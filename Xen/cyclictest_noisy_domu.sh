#!/bin/bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================

DOM0_IP="192.168.1.166"
DOM0_USER="matt"
DOMU_USER="matt"
DOMU_PASS="YOUR_DOMU_PASSWORD"

# Local directory where results are collected
RESULTS_DIR="./results_noisy_domu"

# DomU virtual disk device (regular guest) and mount point for result retrieval.
# Must be free (i.e. regular guest destroyed) before mounting.
DOMU_DISK_DEV="/dev/dm-1"
DOMU_MOUNT_POINT="/mnt/domU"

# Seconds to wait inside the regular DomU after login before starting cyclictest
DOMU_PREWARM_TIME=15

# Seconds to wait after 'xl create' for the regular guest before connecting
GUEST_SETTLE_TIME=30

# Seconds to wait after 'xl create' for the noisy guest.
# This VM boots very slowly due to spinlock contention; increase if needed.
NOISY_GUEST_SETTLE_TIME=300

# ---------------------------------------------------------------------------
# GRUB entries — Dom0 runs the rt5-ll kernel with 4 vCPUs, idle (no Dom0 load)
# ---------------------------------------------------------------------------
declare -A KERNELS=(
    ["LL-4vcpu"]="Xen 4.17-amd64 Linux 6.18.35-rt5-ll Dom0 4 vCPUs"
    ["LL-4vcpu-pinned"]="Xen 4.17-amd64 Linux 6.18.35-rt5-ll Dom0 4 vCPUs and pinning"
)

KERNEL_ORDER=("LL-4vcpu" "LL-4vcpu-pinned")

# ---------------------------------------------------------------------------
# Noisy DomU — always present during cyclictest runs.
# One noisy guest is booted per Dom0 kernel configuration and kept alive while
# all regular guests run.  It runs stress-ng inside itself.
# ---------------------------------------------------------------------------

# Per-kernel noisy guest: key -> "domain_name /path/to/conf"
declare -A NOISY_GUESTS=(
    ["LL-4vcpu"]="ubuntu-24.04-linux-6.18.35-noisyguest-big /etc/xen/ubuntu-24.04-linux-6.18-35-nrt-hvm-noisyguest-big.conf"
    ["LL-4vcpu-pinned"]="ubuntu-24.04-linux-6.18.35-noisyguest-big /etc/xen/ubuntu-24.04-linux-6.18-35-nrt-hvm-noisyguest-big-pinned.conf"
)

# stress-ng commands to run inside the noisy DomU.
# Kept as separate processes so CPU and VM stressors run independently.
NOISY_STRESS_CMDS=(
    "nohup sudo stress-ng --cpu 16 --timeout 0 > /dev/null 2>&1 &"
    "nohup sudo stress-ng --vm 16 --vm-bytes 1G --timeout 0 > /dev/null 2>&1 &"
)

# ---------------------------------------------------------------------------
# Regular guest configurations (running cyclictest)
# key -> "domain_name /path/to/conf"
# ---------------------------------------------------------------------------
declare -A GUESTS=(
    ["guest-nrt-hvm"]="ubuntu-24.04-linux-6.18.35 /etc/xen/ubuntu-24.04-linux-6.18-35-nrt-hvm.conf"
    ["guest-nrt-pinned-hvm"]="ubuntu-24.04-linux-6.18.35 /etc/xen/ubuntu-24.04-linux-6.18-35-nrt-hvm-pinned.conf"
    ["guest-rt5-hvm"]="ubuntu-24.04-linux-6.18.35-rt5 /etc/xen/ubuntu-24.04-linux-6.18-35-rt5-hvm.conf"
    ["guest-rt5-pinned-hvm"]="ubuntu-24.04-linux-6.18.35-rt5 /etc/xen/ubuntu-24.04-linux-6.18-35-rt5-hvm-pinned.conf"
)

# Per-kernel regular guest list (pinning must match Dom0 and the noisy guest)
declare -A KERNEL_GUEST_MAP=(
    ["LL-4vcpu"]="guest-nrt-hvm guest-rt5-hvm"
    ["LL-4vcpu-pinned"]="guest-nrt-pinned-hvm guest-rt5-pinned-hvm"
)

# ---------------------------------------------------------------------------
# cyclictest parameters (run inside the regular DomU)
# ---------------------------------------------------------------------------
CYCLICTEST_DURATION="5m"
CYCLICTEST_PRIORITY=99
CYCLICTEST_INTERVAL=50      # microseconds
CYCLICTEST_HISTSIZE=1000    # microseconds histogram max
CYCLICTEST_THREADS=1
CYCLICTEST_AFFINITY=1

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

# Create a DomU and wait for it to settle.
# Retries xl create up to 3 times with a 15 s delay to ride out transient
# xenbr0 unavailability (NetworkManager briefly reconfigures the bridge after
# a VIF is detached on destroy).
# $1 = guest config path
# $2 = settle time in seconds (default: GUEST_SETTLE_TIME)
start_guest() {
    local cfg="$1"
    local settle="${2:-$GUEST_SETTLE_TIME}"
    local max_attempts=3
    local retry_delay=15

    for (( attempt=1; attempt<=max_attempts; attempt++ )); do
        log "Creating DomU from: $cfg (attempt $attempt/$max_attempts)"
        if ssh "$DOM0_USER@$DOM0_IP" "sudo xl create '$cfg'"; then
            log "Waiting ${settle} s for DomU to settle..."
            sleep "$settle"
            return 0
        fi
        if (( attempt < max_attempts )); then
            log "  xl create failed — waiting ${retry_delay} s before retry..."
            sleep "$retry_delay"
        fi
    done

    log "  ERROR: xl create failed after $max_attempts attempts."
    return 1
}

# Destroy a DomU by name (checks xl domid first to avoid spurious errors).
# $1 = domain name as known to xl
destroy_guest() {
    local name="$1"
    log "Destroying DomU: $name"
    if ssh "$DOM0_USER@$DOM0_IP" "sudo xl domid '$name' > /dev/null 2>&1"; then
        if ! ssh "$DOM0_USER@$DOM0_IP" "sudo xl destroy '$name'"; then
            log "  WARN: xl destroy '$name' reported an error (may already be gone)."
        fi
    else
        log "  INFO: DomU '$name' is not running; nothing to destroy."
    fi
    sleep 3
}

# Log into the noisy DomU via xl console and start stress-ng in the background.
# Each entry in NOISY_STRESS_CMDS is sent as a separate command so CPU and VM
# stressors run as independent processes.
# The expect timeout covers the full NOISY_GUEST_SETTLE_TIME window in case the
# login prompt appears late during the slow boot.
# $1 = domain name of the noisy guest
launch_noisy_domu_stress() {
    local guest_name="$1"

    log "Logging into noisy DomU '${guest_name}' to start stress-ng..."

    # Allow up to NOISY_GUEST_SETTLE_TIME extra seconds for the login prompt
    # because the VM may still be finishing its slow boot when we connect.
    local login_timeout=$(( NOISY_GUEST_SETTLE_TIME + 60 ))

    # Build a Tcl snippet that sends each stress-ng command in sequence.
    # This runs in bash before the heredoc so the array is expanded here.
    local stress_tcl_block=""
    for cmd in "${NOISY_STRESS_CMDS[@]}"; do
        stress_tcl_block+="send \"${cmd}\\r\"\nset timeout 30\nexpect -re {[#\$] }\n"
    done

    ssh "$DOM0_USER@$DOM0_IP" bash <<REMOTE_EOF
sudo expect << 'EXPECT_SCRIPT'
set timeout ${login_timeout}
log_user 1

spawn sudo xl console ${guest_name}

# Poke the console to surface whatever prompt is waiting
send "\r"

# Wait for a login or shell prompt (long timeout for the slow-booting VM)
expect {
    timeout {
        send_user "ERROR: timed out waiting for noisy DomU login prompt\n"
exit 1
    }
    -re {(?:login|Login):\s*$} {
        send "${DOMU_USER}\r"
        expect -re {(?:password|Password):\s*$}
        send "${DOMU_PASS}\r"
        expect -re {[#\$] }
    }
    -re {[#\$] } {}
}

# Launch each stress-ng stressor (CPU and VM) as a separate background process
$(printf '%b' "${stress_tcl_block}")

# Log out — stressors stay alive because they were daemonized with nohup &
send "exit\r"
expect -re {(?:login|Login):\s*$}
send "\x1d"
expect eof
EXPECT_SCRIPT
REMOTE_EOF
}

# Run cyclictest inside a regular DomU via xl console + expect.
# Histogram is written to /home/$DOMU_USER/ (not /tmp, which is a tmpfs in
# Ubuntu 24.04 and has no disk backing).  A 'sync' is sent before logout to
# flush the kernel page cache to the block device before xl destroy.
# $1 = domain name (for xl console)
# $2 = base name for the result file
# $3 = local destination path prefix
run_cyclictest_in_domu() {
    local guest_name="$1"
    local remote_base="$2"
    local local_outfile="$3"

    local domu_histfile="/home/${DOMU_USER}/${remote_base}.log"

    # All stdout/stderr silenced so nothing flows through the Xen serial console
    # emulator during the run — console VM-exits would inflate measured latencies.
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
    log "  Histogram: ${domu_histfile} (inside DomU)"

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
send "\r"

expect {
    timeout {
        send_user "ERROR: timed out waiting for login or shell prompt\n"
exit 1
    }
    -re {(?:login|Login):\s*$} {
        send "${DOMU_USER}\r"
        expect -re {(?:password|Password):\s*$}
        send "${DOMU_PASS}\r"
        expect -re {[#$] }
    }
    -re {[#$] } {}
}

# Let the DomU settle before the measurement
send "sleep ${DOMU_PREWARM_TIME}\r"
expect -re {[#$] }

# Run cyclictest (console silent during the run)
send "${cyclictest_cmd}\r"

set timeout ${expect_timeout}
expect -re {[#$] }
set timeout 30

# Flush page cache to disk before logout so the histfile is complete on disk
send "sync\r"
expect -re {[#$] }

send "exit\r"
expect -re {(?:login|Login):\s*$}
send "\x1d"
expect eof
EXPECT_SCRIPT
REMOTE_EOF
}

# Mount the regular DomU disk on Dom0, copy the histfile, then unmount.
# Must be called AFTER destroy_guest so the disk is free.
# $1 = base name for the result file
# $2 = local destination path prefix
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
        log "  Histogram saved: ${local_outfile}.log"
    else
        log "  WARN: histogram not found at '${DOMU_MOUNT_POINT}${domu_histfile}' on Dom0."
    fi

    log "Unmounting ${DOMU_MOUNT_POINT} on Dom0..."
    ssh "$DOM0_USER@$DOM0_IP" "sudo umount '${DOMU_MOUNT_POINT}'"
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
        "sudo xl list > /dev/null" \
        || die "Cannot reach Dom0 via SSH or xl not available."
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
    # Boot the noisy DomU and start its load.
    # The noisy guest stays alive for the entire regular-guest loop below.
    # ------------------------------------------------------------------
    read -r noisy_name noisy_cfg <<< "${NOISY_GUESTS[$kernel_label]}"

    log "----------------------------------------------------------------"
    log " Booting noisy DomU: $noisy_name"
    log "   conf : $noisy_cfg"
    log "   settle time : ${NOISY_GUEST_SETTLE_TIME} s (slow boot expected)"
    log "----------------------------------------------------------------"

    if ! start_guest "$noisy_cfg" "$NOISY_GUEST_SETTLE_TIME"; then
        log "ERROR: could not boot noisy DomU for kernel '$kernel_label'. Skipping kernel."
        continue
    fi

    launch_noisy_domu_stress "$noisy_name"

    # ------------------------------------------------------------------
    # Regular guest loop — each guest boots, runs cyclictest, is destroyed
    # ------------------------------------------------------------------
    read -ra kernel_guests <<< "${KERNEL_GUEST_MAP[$kernel_label]}"
    for guest_key in "${kernel_guests[@]}"; do
        read -r guest_name guest_cfg <<< "${GUESTS[$guest_key]}"

        log "----------------------------------------------------------------"
        log " Regular guest : $guest_key"
        log "   name        : $guest_name"
        log "   conf        : $guest_cfg"
        log "----------------------------------------------------------------"

        if ! start_guest "$guest_cfg" "$GUEST_SETTLE_TIME"; then
            log "  xl create failed for '$guest_key' — skipping this run."
            destroy_guest "$guest_name"
            drop_dom0_caches
            sleep 5
            continue
        fi

        result_tag="${kernel_label}__${guest_key}"
        remote_base="cyclictest_${result_tag}"
        local_outfile="${RESULTS_DIR}/${result_tag}"

        run_cyclictest_in_domu "$guest_name" "$remote_base" "$local_outfile"

        destroy_guest "$guest_name"

        collect_domu_results "$remote_base" "$local_outfile"

        drop_dom0_caches
        sleep 5

    done  # regular guest loop

    # ------------------------------------------------------------------
    # All regular guests done — destroy the noisy DomU
    # ------------------------------------------------------------------
    log "Destroying noisy DomU: $noisy_name"
    destroy_guest "$noisy_name"
    drop_dom0_caches
    sleep 5

    log "All regular guests tested under kernel '$kernel_label'."

done  # kernel loop

log "================================================================"
log " All experiments completed."
log " Results are in: $RESULTS_DIR"
log "================================================================"
