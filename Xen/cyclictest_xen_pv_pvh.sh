#!/bin/bash

# ==============================================================================
# XEN PV/PVH CYCLICTEST ORCHESTRATION SCRIPT
#
# Runs cyclictest inside PV and PVH DomU guests across 8 configurations:
#
#   Dom0 kernel : Xen 4.17-amd64 + Linux 6.18.35-rt5-ll (LL, fixed)
#   DomU types  : PV  (guest runs vmlinuz-6.18.35-rt5-ll)
#                 PVH (guest runs vmlinuz-6.18.35-rt5)
#   Schedulers  : credit2 (non-pinned GRUB entry, default Xen scheduler)
#                 null    (pinned GRUB entry, sched=null + dom0_vcpus_pin)
#   Stress      : baseline (no stress) | stressdom0 (stress-ng CPU+VM on Dom0)
#
# 8 runs total (scheduler × vmtype × stress):
#   credit2_pv_nopin_ll_ll
#   credit2_pv_nopin_ll_ll_stressdom0
#   credit2_pvh_nopin_ll_rt
#   credit2_pvh_nopin_ll_rt_stressdom0
#   null_pv_pinned_ll_ll
#   null_pv_pinned_ll_ll_stressdom0
#   null_pvh_pinned_ll_rt
#   null_pvh_pinned_ll_rt_stressdom0
#
# Result filenames follow the existing tests_pv_pvh/ naming convention.
# ==============================================================================

# ==============================================================================
# CONFIGURATION
# ==============================================================================

DOM0_IP="192.168.1.166"
DOM0_USER="matt"
DOMU_USER="matt"
DOMU_PASS="YOUR_DOMU_PASSWORD"

# Local directory where results are collected on the orchestrator
RESULTS_DIR="./results_pv_pvh"

# DomU virtual disk device (as seen on Dom0) and the mount point used to
# retrieve cyclictest output files after the guest has been destroyed.
DOMU_DISK_DEV="/dev/ubuntu-vg/ubuntu-24.04-domU"
DOMU_MOUNT_POINT="/mnt/domU"

# Seconds to wait inside DomU after login before starting cyclictest
DOMU_PREWARM_TIME=15

# ---------------------------------------------------------------------------
# Dom0 GRUB entries (exact strings from /etc/grub.d/40_custom on Dom0).
# Both boot the LL (6.18.35-rt5-ll) Dom0 kernel with 4 vCPUs.
#   LL      → credit2 scheduler, no pinning
#   LL-pinned → null scheduler + dom0_vcpus_pin
# ---------------------------------------------------------------------------
declare -A DOM0_KERNELS=(
    ["LL"]="Xen 4.17-amd64 Linux 6.18.35-rt5-ll Dom0 4 vCPUs"
    ["LL-pinned"]="Xen 4.17-amd64 Linux 6.18.35-rt5-ll Dom0 4 vCPUs and pinning"
)

# ---------------------------------------------------------------------------
# Guest configurations: key -> "guest_name /path/to/guest.conf"
# guest_name must match the 'name' field inside the .conf file.
# All four guests share the same disk image; the conf file selects the
# guest kernel and type (PV vs PVH).
# ---------------------------------------------------------------------------
declare -A GUESTS=(
    ["pv-nopin"]="ubuntu-24.04-linux-6.18.35-rt5 /etc/xen/ubuntu-24.04-linux-6.18.35-rt5-ll-pv.conf"
    ["pv-pinned"]="ubuntu-24.04-linux-6.18.35-rt5 /etc/xen/ubuntu-24.04-linux-6.18.35-rt5-ll-pv-pinned.conf"
    ["pvh-nopin"]="ubuntu-24.04-linux-6.18.35-rt5 /etc/xen/ubuntu-24.04-linux-6.18.35-rt5-pvh.conf"
    ["pvh-pinned"]="ubuntu-24.04-linux-6.18.35-rt5 /etc/xen/ubuntu-24.04-linux-6.18.35-rt5-pvh-pinned.conf"
)

# ---------------------------------------------------------------------------
# Experiment matrix: ordered list of (dom0_kernel_key, guest_key) pairs.
# Each entry also carries a result-file tag matching the tests_pv_pvh/ naming:
#   {scheduler}_{vmtype}_{pin}_{dom0kern}_{guestkern}
# ---------------------------------------------------------------------------
# Format: "DOM0_KEY:GUEST_KEY:RESULT_TAG"
EXPERIMENT_ORDER=(
    "LL:pv-nopin:credit2_pv_nopin_ll_ll"
    "LL:pvh-nopin:credit2_pvh_nopin_ll_rt"
    "LL-pinned:pv-pinned:null_pv_pinned_ll_ll"
    "LL-pinned:pvh-pinned:null_pvh_pinned_ll_rt"
)

# Stress scenarios to run for each experiment
STRESSOR_ORDER=("baseline" "stressdom0")

# ---------------------------------------------------------------------------
# Dom0 stress-ng stressors (CPU and VM as separate processes).
# ---------------------------------------------------------------------------
DOM0_STRESS_CMDS=(
    "nohup sudo stress-ng --cpu 22 --timeout 0 > /dev/null 2>&1 &"
    "nohup sudo stress-ng --vm 12 --vm-bytes 2G --timeout 0 > /dev/null 2>&1 &"
)

# ---------------------------------------------------------------------------
# cyclictest parameters (run inside DomU)
# ---------------------------------------------------------------------------
CYCLICTEST_DURATION="5m"
CYCLICTEST_PRIORITY=99
CYCLICTEST_INTERVAL=50      # microseconds
CYCLICTEST_HISTSIZE=1000    # microseconds, histogram max
CYCLICTEST_THREADS=1
CYCLICTEST_AFFINITY=1

# How long (seconds) to wait after 'xl create' before connecting to the console
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

# ---------------------------------------------------------------------------
# Wait for Dom0 to reboot and become SSH-reachable.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Drop page/dentry/inode caches on Dom0 and synchronise disk buffers.
# ---------------------------------------------------------------------------
drop_dom0_caches() {
    log "Dropping Dom0 caches..."
    ssh "$DOM0_USER@$DOM0_IP" "sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null"
}

# ---------------------------------------------------------------------------
# Start stress-ng stressors on Dom0.
# ---------------------------------------------------------------------------
start_dom0_stressors() {
    log "Starting stress-ng stressors on Dom0 (cpu + vm)..."
    for cmd in "${DOM0_STRESS_CMDS[@]}"; do
        ssh "$DOM0_USER@$DOM0_IP" "$cmd"
    done
    sleep 2
}

# ---------------------------------------------------------------------------
# Kill all stress-ng processes on Dom0.
# ---------------------------------------------------------------------------
kill_dom0_stressors() {
    log "Killing all stress-ng processes on Dom0..."
    ssh "$DOM0_USER@$DOM0_IP" \
        "sudo pkill -f stress-ng; sleep 2; sudo pkill -9 -f stress-ng 2>/dev/null; true"
}

# ---------------------------------------------------------------------------
# Create a DomU and wait for it to settle.
# Retries up to 3 times to handle transient failures.
# $1 = guest config path
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Destroy a DomU by name.
# $1 = domain name as known to xl
# ---------------------------------------------------------------------------
destroy_guest() {
    local name="$1"
    log "Destroying DomU: $name"
    if ssh "$DOM0_USER@$DOM0_IP" "sudo xl domid '$name' > /dev/null 2>&1"; then
        if ! ssh "$DOM0_USER@$DOM0_IP" "sudo xl destroy '$name'"; then
            log "  WARN: xl destroy '$name' reported an error (domain may already be gone)."
        fi
    else
        log "  INFO: DomU '$name' is not running; nothing to destroy."
    fi
    sleep 3
}

# ---------------------------------------------------------------------------
# Run cyclictest inside a DomU via xl console + expect.
# $1 = domain name (for xl console)
# $2 = base name for the result file (no extension)
# $3 = local destination path prefix (no extension)
# ---------------------------------------------------------------------------
run_cyclictest_in_domu() {
    local guest_name="$1"
    local remote_base="$2"
    local local_outfile="$3"

    # Write the histfile to /home/$DOMU_USER/ (not /tmp — Ubuntu 24.04 mounts
    # /tmp as tmpfs with no disk backing; file would be lost on xl destroy).
    local domu_histfile="/home/${DOMU_USER}/${remote_base}.log"

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
    -re {[#$] } {
        # Already at a shell prompt — nothing to do
    }
}

# Give the DomU time to finish settling
send "sleep ${DOMU_PREWARM_TIME}\r"
expect -re {[#$] }

# Run cyclictest (output silenced to avoid VM-exit storms on the serial console)
send "${cyclictest_cmd}\r"

set timeout ${expect_timeout}
expect -re {[#$] }
set timeout 30

# Flush dirty pages to disk BEFORE logging out so the histfile is fully
# written to the block device before xl destroy kills the DomU kernel.
send "sync\r"
expect -re {[#$] }

send "exit\r"
expect -re {(?:login|Login):\s*$}
send "\x1d"
expect eof
EXPECT_SCRIPT
REMOTE_EOF
}

# ---------------------------------------------------------------------------
# Mount the DomU disk on Dom0, copy the result file to the orchestrator,
# then unmount. Must be called AFTER destroy_guest so the disk is free.
#
# $1 = remote_base (base name of the histfile, no extension)
# $2 = local destination path prefix (no extension)
# ---------------------------------------------------------------------------
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
        "command -v stress-ng > /dev/null && sudo xl list > /dev/null" \
        || die "Cannot reach Dom0 via SSH, or stress-ng/xl not available."
    mkdir -p "$RESULTS_DIR"
    log "Pre-flight checks passed."
}

# ==============================================================================
# MAIN ORCHESTRATION LOOP
# ==============================================================================

preflight_check

# Track current Dom0 kernel to avoid unnecessary reboots
current_dom0_kernel=""

for experiment in "${EXPERIMENT_ORDER[@]}"; do
    dom0_key="${experiment%%:*}"
    rest="${experiment#*:}"
    guest_key="${rest%%:*}"
    result_tag="${rest##*:}"

    dom0_grub="${DOM0_KERNELS[$dom0_key]}"
    read -r guest_name guest_cfg <<< "${GUESTS[$guest_key]}"

    log "================================================================"
    log " Experiment: $result_tag"
    log "   Dom0 kernel : $dom0_key  ($dom0_grub)"
    log "   Guest       : $guest_key  ($guest_cfg)"
    log "================================================================"

    # ------------------------------------------------------------------
    # Reboot Dom0 if its kernel needs to change
    # ------------------------------------------------------------------
    if [[ "$dom0_key" != "$current_dom0_kernel" ]]; then
        log "Switching Dom0 to kernel '$dom0_key'..."
        ssh "$DOM0_USER@$DOM0_IP" \
            "sudo grub-reboot '${dom0_grub}' && sudo reboot" || true
        wait_for_reboot
        current_dom0_kernel="$dom0_key"
    fi

    # ------------------------------------------------------------------
    # Stress scenario loop
    # ------------------------------------------------------------------
    for stressor_label in "${STRESSOR_ORDER[@]}"; do

        log "--------------------------------------------------------------"
        log "  Stressor: $stressor_label"
        log "--------------------------------------------------------------"

        if ! start_guest "$guest_cfg"; then
            log "  ERROR: could not start guest '$guest_name' — skipping."
            continue
        fi

        if [[ "$stressor_label" == "stressdom0" ]]; then
            start_dom0_stressors
        fi

        # Build result names
        if [[ "$stressor_label" == "baseline" ]]; then
            run_tag="${result_tag}"
        else
            run_tag="${result_tag}_${stressor_label}"
        fi
        remote_base="results_${run_tag}"
        local_outfile="${RESULTS_DIR}/${remote_base}"

        run_cyclictest_in_domu "$guest_name" "$remote_base" "$local_outfile"

        if [[ "$stressor_label" == "stressdom0" ]]; then
            kill_dom0_stressors
        fi

        destroy_guest "$guest_name"
        collect_domu_results "$remote_base" "$local_outfile"

        drop_dom0_caches
        sleep 5

    done  # stressor loop

    log "All stress scenarios done for experiment '$result_tag'."

done  # experiment loop

log "================================================================"
log " All experiments completed."
log " Results are in: $RESULTS_DIR"
log "================================================================"
