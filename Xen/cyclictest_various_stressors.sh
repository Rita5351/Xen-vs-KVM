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
    ["guest-nrt-hvm"]="ubuntu-24.04-linux-6.18.35 /etc/xen/ubuntu-24.04-linux-6.18-35-nrt-hvm.conf"
    ["guest-nrt-pinned-hvm"]="ubuntu-24.04-linux-6.18.35 /etc/xen/ubuntu-24.04-linux-6.18-35-nrt-hvm-pinned.conf"
    ["guest-rt5-hvm"]="ubuntu-24.04-linux-6.18.35-rt5 /etc/xen/ubuntu-24.04-linux-6.18-35-rt5-hvm.conf"
    ["guest-rt5-pinned-hvm"]="ubuntu-24.04-linux-6.18.35-rt5 /etc/xen/ubuntu-24.04-linux-6.18-35-rt5-hvm-pinned.conf"
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

# ---------------------------------------------------------------------------
# Stressor definitions
#
# ALWAYS_ON_STRESSORS : launched at the start of every guest experiment and
#                       kept alive for all four stressor scenarios.
# SEQUENTIAL_STRESSORS: launched one at a time for each scenario; killed and
#                       caches are dropped between scenarios.
# ---------------------------------------------------------------------------

# cpu + vm run continuously during all scenarios
ALWAYS_ON_STRESSORS=(
    "nohup sudo stress-ng --cpu 22 --timeout 0 > /dev/null 2>&1 &"
    "nohup sudo stress-ng --vm 12 --vm-bytes 2G --timeout 0 > /dev/null 2>&1 &"
)

# These run one at a time alongside the always-on stressors.
# "baseline" means no extra stressor (cpu + vm only).
declare -A SEQUENTIAL_STRESSORS=(
    ["baseline"]=""
    ["cache"]="nohup sudo stress-ng --cache 0 --timeout 0 > /dev/null 2>&1 &"
    ["interrupts"]="nohup sudo stress-ng --interrupts --timeout 0 > /dev/null 2>&1 &"
    ["rawsock"]="nohup sudo stress-ng --rawsock 22 --timeout 0 > /dev/null 2>&1 &"
)

STRESSOR_ORDER=("baseline" "cache" "interrupts" "rawsock")

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

# Start the always-on stressors on Dom0.
start_always_on_stressors() {
    log "Starting always-on stressors (cpu + vm)..."
    for cmd in "${ALWAYS_ON_STRESSORS[@]}"; do
        ssh "$DOM0_USER@$DOM0_IP" "$cmd"
    done
    sleep 2
}

# Start a single sequential stressor (or nothing for 'baseline').
# $1 = stressor label
start_sequential_stressor() {
    local label="$1"
    local cmd="${SEQUENTIAL_STRESSORS[$label]}"
    if [[ -n "$cmd" ]]; then
        log "Starting sequential stressor: $label"
        ssh "$DOM0_USER@$DOM0_IP" "$cmd"
        sleep 2
    else
        log "No extra sequential stressor (baseline scenario)."
    fi
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

        # Start always-on stressors once at the beginning of this guest's
        # experiment block (they will be restarted after each scenario cleanup)
        start_always_on_stressors

        # -----------------------------------------------------------
        # Stressor scenario loop
        # -----------------------------------------------------------
        for stressor_label in "${STRESSOR_ORDER[@]}"; do

            log "  -- Stressor scenario: $stressor_label --"

            # Start the sequential stressor for this scenario
            start_sequential_stressor "$stressor_label"

            # Boot the DomU and let it settle; skip on xl create failure
            if ! start_guest "$guest_cfg"; then
                # Best-effort cleanup in case xl left a partial domain behind
                destroy_guest "$guest_name"
                kill_stressors
                drop_dom0_caches
                sleep 5
                continue
            fi

            # Build descriptive names for this run
            result_tag="${kernel_label}__${guest_key}__stressor-${stressor_label}"
            remote_base="cyclictest_${result_tag}"
            local_outfile="${RESULTS_DIR}/${result_tag}"

            # Run cyclictest inside the DomU
            run_cyclictest_in_domu "$guest_name" "$remote_base" "$local_outfile"

            # Shut down the DomU before mounting its disk
            destroy_guest "$guest_name"

            # Mount the DomU disk on Dom0, retrieve result files, unmount
            collect_domu_results "$remote_base" "$local_outfile"

            # Kill ALL stress-ng (both always-on and sequential), drop caches
            kill_stressors
            drop_dom0_caches
            sleep 5

            # If more stressor scenarios remain for this guest, restart the
            # always-on stressors so they are running for the next scenario.
            stressor_idx=0
            for s in "${STRESSOR_ORDER[@]}"; do
                [[ "$s" == "$stressor_label" ]] && break
                (( stressor_idx++ ))
            done
            if (( stressor_idx < ${#STRESSOR_ORDER[@]} - 1 )); then
                start_always_on_stressors
            fi

        done  # stressor scenario loop

        # Final cleanup after all scenarios for this guest
        kill_stressors
        drop_dom0_caches
        sleep 5

    done  # guest config loop

    log "All guests tested under kernel '$kernel_label'."

done  # kernel loop

log "================================================================"
log " All experiments completed."
log " Results are in: $RESULTS_DIR"
log "================================================================"