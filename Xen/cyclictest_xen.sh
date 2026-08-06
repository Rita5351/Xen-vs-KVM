#!/bin/bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================

DOM0_IP="192.168.1.166"
DOM0_USER="matt"
DOMU_USER="matt"
DOMU_PASS="YOUR_DOMU_PASSWORD"

# Local directory where results are collected
RESULTS_DIR="./results"

# DomU virtual disk device (as seen on Dom0) and the mount point used to
# retrieve cyclictest output files after the guest has been destroyed.
DOMU_DISK_DEV="/dev/dm-1"
DOMU_MOUNT_POINT="/mnt/domU"

# Seconds to wait inside DomU after login before starting cyclictest
DOMU_PREWARM_TIME=15

# GRUB Entries — exact strings from /etc/grub.d/40_custom
declare -A KERNELS=(
    ["NRT"]="Xen 4.17-amd64 Linux 6.18.35 Dom0 22 vCPUs"
    ["NRT-pinned"]="Xen 4.17-amd64 Linux 6.18.35 Dom0 22 vCPUs and pinning"
    ["LL"]="Xen 4.17-amd64 Linux 6.18.35-rt5-ll Dom0 22 vCPUs"
    ["LL-pinned"]="Xen 4.17-amd64 Linux 6.18.35-rt5-ll Dom0 22 vCPUs and pinning"
)

# Guest configurations: associative array  key -> "guest_name /path/to/guest.conf"
# guest_name must match the 'name' field inside the .conf file (used by xl)
declare -A GUESTS=(
    ["guest-nrt-hvm"]="ubuntu-24.04-linux-6.18.35 /etc/xen/ubuntu-24.04-linux-6.18.35-nrt-hvm.conf"
    ["guest-nrt-pinned-hvm"]="ubuntu-24.04-linux-6.18.35 /etc/xen/ubuntu-24.04-linux-6.18.35-nrt-hvm-pinned.conf"
    ["guest-rt5-hvm"]="ubuntu-24.04-linux-6.18.35-rt5 /etc/xen/ubuntu-24.04-linux-6.18.35-rt5-hvm.conf"
    ["guest-rt5-pinned-hvm"]="ubuntu-24.04-linux-6.18.35-rt5 /etc/xen/ubuntu-24.04-linux-6.18.35-rt5-hvm-pinned.conf"
)

# Ordered list of kernels to iterate (controls experiment order)
KERNEL_ORDER=("NRT" "NRT-pinned" "LL" "LL-pinned")

# Per-kernel guest list: only matching pairs are tested.
# Normal kernels run with non-pinned guests; pinned kernels with pinned guests.
declare -A KERNEL_GUEST_MAP=(
    ["NRT"]="guest-nrt-hvm guest-rt5-hvm"
    ["NRT-pinned"]="guest-nrt-pinned-hvm guest-rt5-pinned-hvm"
    ["LL"]="guest-nrt-hvm guest-rt5-hvm"
    ["LL-pinned"]="guest-nrt-pinned-hvm guest-rt5-pinned-hvm"
)

# Order of stressor scenarios to run for each guest
STRESSOR_ORDER=("baseline" "stresshost" "stresshost_maxprioqemu")

# ---------------------------------------------------------------------------
# Host stress-ng stressors (CPU and VM as separate processes).
# Used in scenarios 2 and 3.
# ---------------------------------------------------------------------------
DOM0_STRESS_CMDs=(
    "nohup sudo stress-ng --cpu 22 --timeout 0 > /dev/null 2>&1 &"
    "nohup sudo stress-ng --vm 12 --vm-bytes 2G --timeout 0 > /dev/null 2>&1 &"
)

# cyclictest parameters (run inside DomU)
CYCLICTEST_DURATION="5m"
CYCLICTEST_PRIORITY=99
CYCLICTEST_INTERVAL=50          # microseconds
CYCLICTEST_HISTSIZE=1000        # microseconds histogram max
CYCLICTEST_THREADS=1
CYCLICTEST_AFFINITY=1

# How long (seconds) to wait after 'xl create' before launching cyclictest
GUEST_SETTLE_TIME=30

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
    log "FATAL: $*" >&2
    exit 1
}

# Wait for Dom0 to reboot and become reachable again.
wait_for_reboot() {
    log "Waiting for Dom0 ($DOM0_IP) to go offline..."
    sleep 15
    while ping -c 1 -W 1 "$DOM0_IP" &>/dev/null; do sleep 2; done
    log "Dom0 is offline. Waiting for it to come back..."
    until ping -c 1 -W 1 "$DOM0_IP" &>/dev/null; do sleep 5; done
    log "Dom0 is reachable. Giving Xen services 10 s to settle..."
    sleep 10
    # Wait until SSH is actually responsive (sshd may still be starting)
    until ssh -o ConnectTimeout=5 -o BatchMode=yes \
              "$DOM0_USER@$DOM0_IP" "true" 2>/dev/null; do
        log "  SSH not yet ready, retrying in 5 s..."
        sleep 5
    done
    log "Dom0 SSH is ready."
}

# Drop page/dentry/inode caches on Dom0 and synchronise disk buffers.
drop_dom0_caches() {
    log "Dropping Dom0 caches..."
    ssh "$DOM0_USER@$DOM0_IP" "sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null"
}

# Kill all stress-ng processes on Dom0.
kill_stressors() {
    log "Killing all stress-ng processes on Dom0..."
    ssh "$DOM0_USER@$DOM0_IP" \
        "sudo pkill -f stress-ng; sleep 2; sudo pkill -9 -f stress-ng 2>/dev/null; true"
}

# Start the stress-ng stressors on Dom0.
start_dom0_stressors() {
    log "Starting stress-ng stressors on Dom0 (cpu + vm)..."
    for cmd in "${DOM0_STRESS_CMDs[@]}"; do
        ssh "$DOM0_USER@$DOM0_IP" "$cmd"
    done
    sleep 2
}

# ---------------------------------------------------------------------------
# Set FIFO real-time priority 98 on the QEMU Device Model process for a DomU.
# This prevents the QEMU emulator threads from being preempted by Dom0 tasks.
# $1 = domain name
# ---------------------------------------------------------------------------
set_qemu_dm_rt_priority() {
    local domain="$1"
    log "Setting QEMU Device Model threads of '$domain' to FIFO priority 98..."
    ssh "$DOM0_USER@$DOM0_IP" bash <<EOF
# Find the PID of the QEMU device model for this domain.
# The most robust way is via Xenstore.
domid=\$(sudo xl domid '$domain' 2>/dev/null)
if [[ -n "\$domid" ]]; then
    qemu_pid=\$(sudo xenstore-read "/local/domain/\$domid/image/device-model-pid" 2>/dev/null)
fi

if [[ -z "\$qemu_pid" ]]; then
    echo "WARN: could not find QEMU PID in Xenstore for '$domain'; trying pgrep fallback."
    qemu_pid=\$(pgrep -f "qemu.*$domain" | head -1)
fi

if [[ -z "\$qemu_pid" ]]; then
    echo "WARN: could not find QEMU PID; skipping priority assignment."
    exit 0
fi

# Apply FIFO 98 to the main process and all its threads.
sudo chrt -f -a -p 98 "\$qemu_pid" && echo "  chrt OK (PID \$qemu_pid)" \\
    || echo "  WARN: chrt failed for PID \$qemu_pid"
EOF
}

# Create a DomU and wait for it to settle.
# Retries xl create up to 3 times with a 15 s delay to ride out transient
# xenbr0 unavailability (NetworkManager briefly reconfigures the bridge after
# a VIF is detached on destroy, causing the next create to fail intermittently).
# Returns non-zero if all attempts fail.
# $1 = guest config path
start_guest() {
    local cfg="$1"
    local max_attempts=3
    local retry_delay=15

    for (( attempt=1; attempt<=max_attempts; attempt++ )); do
        log "Creating DomU from config: $cfg (attempt $attempt/$max_attempts)"
        if ssh "$DOM0_USER@$DOM0_IP" "sudo xl create '$cfg'"; then
            log "Waiting ${GUEST_SETTLE_TIME} s for DomU to boot..."
            sleep "$GUEST_SETTLE_TIME"
            return 0
        fi
        if (( attempt < max_attempts )); then
            log "  xl create failed — waiting ${retry_delay} s before retry..."
            sleep "$retry_delay"
        fi
    done

    log "  ERROR: xl create failed after $max_attempts attempts — skipping this run."
    return 1
}

# Destroy a DomU by name.
# $1 = domain name as known to xl
destroy_guest() {
    local name="$1"
    log "Destroying DomU: $name"

    # Check whether the domain is still known to xl before attempting destroy.
    # This avoids a spurious "failed to destroy" error when xl destroy is called
    # on a domain that has already shut itself down or was never created.
    if ssh "$DOM0_USER@$DOM0_IP" "sudo xl domid '$name' > /dev/null 2>&1"; then
        if ! ssh "$DOM0_USER@$DOM0_IP" "sudo xl destroy '$name'"; then
            log "  WARN: xl destroy '$name' reported an error (domain may already be gone)."
        fi
    else
        log "  INFO: DomU '$name' is not running; nothing to destroy."
    fi
    sleep 3
}

# Run cyclictest inside a DomU via xl console + expect and collect the output.
#
# Cyclictest writes its histogram and log to /tmp inside the DomU's own
# filesystem.  After the guest is destroyed, Dom0 mounts the DomU's virtual
# disk (DOMU_DISK_DEV) at DOMU_MOUNT_POINT, copies the files out, then
# unmounts — no guest-side configuration changes are required.
#
# $1 = domain name (for xl console)
# $2 = base name for result files
# $3 = local destination path prefix for the result files
run_cyclictest_in_domu() {
    local guest_name="$1"
    local remote_base="$2"
    local local_outfile="$3"

    # Path of the histfile inside the DomU.
    # We write to /home/$DOMU_USER/ rather than /tmp/ because Ubuntu 24.04
    # mounts /tmp as a tmpfs (RAM-only, no disk backing).  Files in tmpfs are
    # lost when the DomU is destroyed, so mounting the disk image afterwards
    # would only see an empty /tmp directory.
    local domu_histfile="/home/${DOMU_USER}/${remote_base}.log"

    # Build the cyclictest command that will run inside the DomU.
    # stdout and stderr are sent to /dev/null so that NO output flows through
    # the Xen serial console emulator during the run.  Routing even a single
    # line per millisecond through xl console would cause hypervisor VM-exits
    # on every write and inflate measured latencies by orders of magnitude.
    # The histogram is written directly to the file by cyclictest itself.
    local cyclictest_cmd
    cyclictest_cmd="sudo cyclictest\
 --mlockall\
 --priority=${CYCLICTEST_PRIORITY}\
 --threads=${CYCLICTEST_THREADS}\
 --affinity=${CYCLICTEST_AFFINITY}\
 --interval=${CYCLICTEST_INTERVAL}\
 --duration=${CYCLICTEST_DURATION}\
 -H ${CYCLICTEST_HISTSIZE}\
 --histfile=${domu_histfile}\
 > /dev/null 2>&1"

    log "Running cyclictest in DomU '${guest_name}' (duration: ${CYCLICTEST_DURATION})..."
    log "  Histogram will be at (inside DomU): ${domu_histfile}"

    # -----------------------------------------------------------------------
    # Drive the xl serial console with expect.
    # Key points:
    #  - Shell prompt pattern: match any line ending with "$ ".
    #  - Sleep DOMU_PREWARM_TIME inside the DomU before launching cyclictest.
    #  - After cyclictest finishes, send "exit" then Ctrl+] to detach from the
    #    console (xl console does not produce an EOF on "exit" because the login
    #    manager restarts the prompt).
    # -----------------------------------------------------------------------
    # Calculate a safe expect timeout: prewarm + cyclictest duration + 120 s margin
    local duration_sec
    duration_sec=$(echo "${CYCLICTEST_DURATION}" | awk '
        /m$/ { sub(/m$/,""); print $1*60; next }
        /h$/ { sub(/h$/,""); print $1*3600; next }
        /s$/ { sub(/s$/,""); print $1+0; next }
        { print $1+0 }
    ')
    local expect_timeout=$(( DOMU_PREWARM_TIME + duration_sec + 120 ))

    ssh "$DOM0_USER@$DOM0_IP" bash <<REMOTE_EOF
sudo expect << 'EXPECT_SCRIPT'
set timeout 60
log_user 1

spawn sudo xl console ${guest_name}

# Poke the console to surface whatever prompt is waiting
send "\r"

# Wait for either a login prompt or an already-open shell prompt
expect {
    timeout {
        send_user "ERROR: timed out waiting for login or shell prompt\n"
exit 1
    }
    -re {(?:login|Login):\s*$} {
        send "${DOMU_USER}\r"
        expect -re {(?:password|Password):\s*$}
        send "${DOMU_PASS}\r"
        # Wait for the shell prompt after login.
        # Pattern {[#$] } matches "$ " or "# " without an EOL anchor so it
        # fires immediately when the prompt appears, not after timeout.
        expect -re {[#$] }
    }
    -re {[#$] } {
        # Already at a shell prompt — nothing to do
    }
}

# Give the DomU ${DOMU_PREWARM_TIME} s to finish booting before stressing it
send "sleep ${DOMU_PREWARM_TIME}\r"
expect -re {[#$] }

# Launch cyclictest
send "${cyclictest_cmd}\r"

# Wait for cyclictest to complete (generous timeout)
set timeout ${expect_timeout}
expect -re {[#$] }
set timeout 30

# Flush dirty pages to disk BEFORE logging out so the histfile is fully
# written to the block device before xl destroy kills the DomU kernel.
# Without this, page-cached data is discarded on destroy and the file
# appears as 0 bytes when the disk is mounted on Dom0.
send "sync\r"
expect -re {[#$] }

# Log out of the DomU shell
send "exit\r"

# The console will NOT produce EOF because the getty restarts the login prompt.
# Detach from xl console by sending the escape sequence: Enter then Ctrl+]
expect -re {(?:login|Login):\s*$} {
    # We see the login prompt again — the logout worked.
}
# Send the xl console detach sequence (Ctrl+]) to close the console
send "\x1d"
expect eof
EXPECT_SCRIPT
REMOTE_EOF
}

# Mount the DomU disk on Dom0, copy result files to the orchestrator, unmount.
# Must be called AFTER destroy_guest so the disk is not in use.
#
# $1 = base name for result files (must match what was passed to run_cyclictest_in_domu)
# $2 = local destination path prefix for the result files
collect_domu_results() {
    local remote_base="$1"
    local local_outfile="$2"

    local domu_histfile="/home/${DOMU_USER}/${remote_base}.log"

    log "Mounting DomU disk (${DOMU_DISK_DEV}) at ${DOMU_MOUNT_POINT} on Dom0..."
    ssh "$DOM0_USER@$DOM0_IP" \
        "sudo mkdir -p '${DOMU_MOUNT_POINT}' && sudo mount '${DOMU_DISK_DEV}' '${DOMU_MOUNT_POINT}'"

    mkdir -p "$(dirname "$local_outfile")"

    if scp "$DOM0_USER@$DOM0_IP:${DOMU_MOUNT_POINT}${domu_histfile}" \
           "${local_outfile}.log" 2>/dev/null; then
        log "  Histogram saved : ${local_outfile}.log"
    else
        log "  WARN: histogram not found at '${DOMU_MOUNT_POINT}${domu_histfile}' on Dom0."
    fi

    log "Unmounting ${DOMU_MOUNT_POINT} on Dom0..."
    ssh "$DOM0_USER@$DOM0_IP" \
        "sudo umount '${DOMU_MOUNT_POINT}'"
}

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

preflight_check() {
    log "Running pre-flight checks..."
    command -v ssh  >/dev/null 2>&1 || die "ssh not found on orchestrator."
    command -v scp  >/dev/null 2>&1 || die "scp not found on orchestrator."
    command -v ping >/dev/null 2>&1 || die "ping not found on orchestrator."
    ping -c 1 -W 3 "$DOM0_IP" &>/dev/null || die "Dom0 ($DOM0_IP) is not reachable."
    ssh -o ConnectTimeout=5 -o BatchMode=yes "$DOM0_USER@$DOM0_IP" \
        "command -v stress-ng >/dev/null && sudo xl list >/dev/null" \
        || die "Cannot reach Dom0 via SSH, or stress-ng/xl not available."
    mkdir -p "$RESULTS_DIR"
    log "Pre-flight checks passed."
}

# ==============================================================================
# MAIN ORCHESTRATION LOOP
# ==============================================================================

preflight_check

for kernel_label in "${KERNEL_ORDER[@]}"; do
    grub_entry="${KERNELS[$kernel_label]}"

    log "================================================================"
    log " Switching to kernel config: $kernel_label"
    log "================================================================"

    log "Setting grub-reboot to '${grub_entry}' and rebooting Dom0..."
    ssh "$DOM0_USER@$DOM0_IP" "sudo grub-reboot '${grub_entry}' && sudo reboot" || true
    wait_for_reboot

    # ------------------------------------------------------------------
    # Guest loop — only the guests that match this kernel's pinning style
    # ------------------------------------------------------------------
    read -ra kernel_guests <<< "${KERNEL_GUEST_MAP[$kernel_label]}"
    for guest_key in "${kernel_guests[@]}"; do
        read -r guest_name guest_cfg <<< "${GUESTS[$guest_key]}"

        log "----------------------------------------------------------------"
        log " Guest config : $guest_key"
        log "   name       : $guest_name"
        log "   conf       : $guest_cfg"
        log "----------------------------------------------------------------"

        # -----------------------------------------------------------
        # Stressor scenario loop
        # -----------------------------------------------------------
        for stressor_label in "${STRESSOR_ORDER[@]}"; do

            log "  -- Stressor scenario: $stressor_label --"

            # Boot the DomU for this specific scenario
            if ! start_guest "$guest_cfg"; then
                log "  ERROR: could not start guest '$guest_name' — skipping."
                continue
            fi

            # If it's a pinned configuration, pin the vCPUs manually
            if [[ "$kernel_label" == *"-pinned"* ]]; then
                log "Explicitly pinning vCPU 0 to CPU 22 and vCPU 1 to CPU 23..."
                ssh "$DOM0_USER@$DOM0_IP" "sudo xl vcpu-pin $guest_name 0 22 && sudo xl vcpu-pin $guest_name 1 23" || true
            fi

            if [[ "$stressor_label" == "baseline" ]]; then
                log "No background stress on Dom0."
            elif [[ "$stressor_label" == "stresshost" ]]; then
                start_dom0_stressors
            elif [[ "$stressor_label" == "stresshost_maxprioqemu" ]]; then
                start_dom0_stressors
                set_qemu_dm_rt_priority "$guest_name"
            fi

            # Build descriptive names for this run
            result_tag="${kernel_label}__${guest_key}__${stressor_label}"
            remote_base="cyclictest_${result_tag}"
            local_outfile="${RESULTS_DIR}/${result_tag}"

            # Run cyclictest inside the DomU
            run_cyclictest_in_domu "$guest_name" "$remote_base" "$local_outfile"

            # Clean up stressors after the run
            if [[ "$stressor_label" != "baseline" ]]; then
                kill_stressors
            fi
            
            # Shut down the DomU
            destroy_guest "$guest_name"

            # Retrieve the result for this scenario
            collect_domu_results "$remote_base" "$local_outfile"
            
            sleep 5
            drop_dom0_caches

        done  # stressor scenario loop

        # Final cleanup for this guest
        sleep 5

    done  # guest config loop

    log "All guests tested under kernel '$kernel_label'."

done  # kernel loop

log "================================================================"
log " All experiments completed."
log " Results are in: $RESULTS_DIR"
log "================================================================"