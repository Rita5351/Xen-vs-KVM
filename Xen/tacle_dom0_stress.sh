#!/bin/bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================

DOM0_IP="192.168.1.166"
DOM0_USER="matt"
DOMU_USER="matt"
DOMU_PASS="YOUR_DOMU_PASSWORD"

# Local directory where results are collected
RESULTS_DIR="./results_tacle"

# DomU virtual disk device (as seen on Dom0) and the mount point used to
# retrieve benchmark output files after the guest has been destroyed.
DOMU_DISK_DEV="/dev/dm-1"
DOMU_MOUNT_POINT="/mnt/domU"

# Seconds to wait inside DomU after login before starting a benchmark
DOMU_PREWARM_TIME=15

# GRUB Entries — exact strings from /etc/grub.d/40_custom
declare -A KERNELS=(
    ["LL"]="Xen 4.17-amd64 Linux 6.18.35-rt5-ll Dom0 22 vCPUs"
    ["LL-pinned"]="Xen 4.17-amd64 Linux 6.18.35-rt5-ll Dom0 22 vCPUs and pinning"
)

# Guest configurations: associative array  key -> "guest_name /path/to/guest.conf"
# guest_name must match the 'name' field inside the .conf file (used by xl)
declare -A GUESTS=(
    ["guest-rt5-tacle-hvm"]="ubuntu-24.04-linux-6.18.35-rt5-tacle /etc/xen/ubuntu-24.04-linux-6.18-35-rt5-hvm-tacle-dom0noise.conf"
    ["guest-rt5-tacle-hvm-pinned"]="ubuntu-24.04-linux-6.18.35-rt5-tacle /etc/xen/ubuntu-24.04-linux-6.18-35-rt5-hvm-tacle-pinned.conf"
)

# Ordered list of kernels to iterate (controls experiment order)
KERNEL_ORDER=("LL" "LL-pinned")

# Per-kernel guest list: only matching pairs are tested.
# Normal kernels run with non-pinned guests; pinned kernels with pinned guests.
declare -A KERNEL_GUEST_MAP=(
    ["LL"]="guest-rt5-tacle-hvm"
    ["LL-pinned"]="guest-rt5-tacle-hvm-pinned"
)

# ---------------------------------------------------------------------------
# Dom0 stressors — run persistently for the entire guest experiment block.
# ---------------------------------------------------------------------------
DOM0_STRESSORS=(
    "nohup sudo stress-ng --cpu 22 --timeout 0 > /dev/null 2>&1 &"
    "nohup sudo stress-ng --vm 12 --vm-bytes 2G --timeout 0 > /dev/null 2>&1 &"
)

# ---------------------------------------------------------------------------
# TACLe benchmarks
# Format: associative array  label -> command
# Commands are run from TACLE_DIR inside the DomU.
# stdout/stderr are discarded (> /dev/null 2>&1) so nothing flows through
# the Xen serial console emulator during the timed ru---------------------------------------------------------------------------
TACLE_DIR="/home/matt/custom_tests"

declare -A TACLE_BENCHMARKS=(
    ["huff_enc"]="sudo ./huff_enc --mlockall -N --priority=99 --affinity=1 --loops=1000000 --histogram=1000000 --histfile=results_huffenc.log > /dev/null 2>&1"
    ["matrix1"]="sudo ./matrix1 --mlockall -N --priority=99 --affinity=1 --loops=1000000 --histogram=1000000 --histfile=results_matrix1.log > /dev/null 2>&1"
    ["lift"]="sudo ./lift --mlockall -N --priority=99 --affinity=1 --loops=1000000 --histogram=1000000 --histfile=results_lift.log > /dev/null 2>&1"
    ["test3"]="sudo ./test3 --mlockall --priority=99 --affinity=1 --loops=10000 --histogram=1000000 --histfile=results_test3.log > /dev/null 2>&1"
    ["debie"]="sudo ./debie --mlockall --priority=99 --affinity=1 --loops=10000 --histogram=1000000 --histfile=results_debie.log > /dev/null 2>&1"
)

# Ordered list of benchmark labels
BENCHMARK_ORDER=("huff_enc" "matrix1" "lift" "test3" "debie")

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

# Kill all stress-ng processes on Dom0.
kill_stressors() {
    log "Killing all stress-ng processes on Dom0..."
    ssh "$DOM0_USER@$DOM0_IP" \
        "sudo pkill -f stress-ng; sleep 2; sudo pkill -9 -f stress-ng 2>/dev/null; true"
}

# Start the Dom0 stressors (cpu + vm).
start_dom0_stressors() {
    log "Starting Dom0 stressors (cpu + vm)..."
    for cmd in "${DOM0_STRESSORS[@]}"; do
        ssh "$DOM0_USER@$DOM0_IP" "$cmd"
    done
    sleep 2
}

# Read the domain name declared inside a Xen config file (on Dom0).
# $1 = conf file path
get_guest_name() {
    local cfg="$1"
    ssh "$DOM0_USER@$DOM0_IP" \
        "grep -oP '(?<=name\s*=\s*\")[^\"]+' '$cfg' | head -1" 2>/dev/null
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
    if ssh "$DOM0_USER@$DOM0_IP" "sudo xl domid '$name' > /dev/null 2>&1"; then
        if ! ssh "$DOM0_USER@$DOM0_IP" "sudo xl destroy '$name'"; then
            log "  WARN: xl destroy '$name' reported an error (domain may already be gone)."
        fi
    else
        log "  INFO: DomU '$name' is not running; nothing to destroy."
    fi
    sleep 3
}

# Run a single TACLe benchmark inside a DomU via xl console + expect.
# The benchmark writes its histfile to TACLE_DIR inside the DomU.
# stdout/stderr are discarded so nothing flows through the Xen serial console
# emulator during the timed run (which would inflate measured latencies).
#
# $1 = domain name (for xl console)
# $2 = benchmark label (for logging)
# $3 = benchmark command (run from TACLE_DIR; must include --histfile=...)
run_benchmark_in_domu() {
    local guest_name="$1"
    local bench_label="$2"
    local bench_cmd="$3"

    # Full command: cd into TACLE_DIR first, then run the benchmark
    local full_cmd="cd ${TACLE_DIR} && ${bench_cmd}"

    log "Running benchmark '${bench_label}' in DomU '${guest_name}'..."

    # Generous timeout: prewarm + up to 30 min for the benchmark + 60 s margin
    local expect_timeout=$(( DOMU_PREWARM_TIME + 1860 ))

    ssh "$DOM0_USER@$DOM0_IP" bash <<REMOTE_EOF
sudo expect << 'EXPECT_SCRIPT'
set timeout 60
log_user 1

spawn sudo xl console ${guest_name}

# Poke the console to surface whatever prompt is waiting
send "\r"

# Wait for either a login prompt or an already-open shell prompt.
# Pattern {[#$] } matches "$ " or "# " without an EOL anchor so it fires
# immediately when the prompt appears rather than waiting for timeout.
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

# Give the DomU ${DOMU_PREWARM_TIME} s to finish settling before the benchmark
send "sleep ${DOMU_PREWARM_TIME}\r"
expect -re {[#$] }

# Run the benchmark (all output silenced to keep the serial console idle)
send "${full_cmd}\r"

# Wait for the benchmark to complete (generous timeout)
set timeout ${expect_timeout}
expect -re {[#$] }
set timeout 30

# Flush dirty pages to disk BEFORE logging out so the histfile is fully
# written to the block device before xl destroy kills the DomU kernel.
send "sync\r"
expect -re {[#$] }

# Log out of the DomU shell
send "exit\r"

# The console will NOT produce EOF because getty restarts the login prompt.
# Wait for the login prompt to confirm logout, then detach with Ctrl+].
expect -re {(?:login|Login):\s*$}
send "\x1d"
expect eof
EXPECT_SCRIPT
REMOTE_EOF
}

# Mount the DomU disk on Dom0, copy the benchmark histfile to the orchestrator,
# then unmount. Must be called AFTER destroy_guest so the disk is free.
#
# $1 = histfile basename (relative to TACLE_DIR inside the DomU)
# $2 = local destination file path (including final filename)
collect_benchmark_result() {
    local histfile_basename="$1"
    local local_outfile="$2"

    # Full path of the histfile inside the DomU's filesystem
    local domu_histfile="${TACLE_DIR}/${histfile_basename}"

    log "Mounting DomU disk (${DOMU_DISK_DEV}) at ${DOMU_MOUNT_POINT} on Dom0..."
    ssh "$DOM0_USER@$DOM0_IP" \
        "sudo mkdir -p '${DOMU_MOUNT_POINT}' && sudo mount '${DOMU_DISK_DEV}' '${DOMU_MOUNT_POINT}'"

    mkdir -p "$(dirname "$local_outfile")"

    if scp "$DOM0_USER@$DOM0_IP:${DOMU_MOUNT_POINT}${domu_histfile}" \
           "$local_outfile" 2>/dev/null; then
        log "  Result saved : $local_outfile"
    else
        log "  WARN: histfile not found at '${DOMU_MOUNT_POINT}${domu_histfile}' on Dom0."
        log "        Verify TACLE_DIR ('${TACLE_DIR}') is correct and the benchmark ran."
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

        # Start Dom0 stressors for the entire guest experiment block
        start_dom0_stressors

        # --------------------------------------------------------------
        # Benchmark loop — each benchmark gets a fresh DomU boot
        # --------------------------------------------------------------
        for bench_label in "${BENCHMARK_ORDER[@]}"; do
            bench_cmd="${TACLE_BENCHMARKS[$bench_label]}"

            # Extract the histfile basename from the --histfile= argument
            histfile_basename=$(echo "$bench_cmd" | grep -oP '(?<=--histfile=)\S+')

            log "  -- Benchmark: $bench_label --"

            # Boot a fresh DomU; skip this benchmark on xl create failure
            if ! start_guest "$guest_cfg"; then
                # Best-effort cleanup in case xl left a partial domain behind
                destroy_guest "$guest_name"
                drop_dom0_caches
                sleep 5
                continue
            fi

            # Run the benchmark inside the DomU
            run_benchmark_in_domu "$guest_name" "$bench_label" "$bench_cmd"

            # Destroy the DomU before mounting its disk
            destroy_guest "$guest_name"

            # Mount the disk, copy the histfile, unmount
            local_outfile="${RESULTS_DIR}/${kernel_label}__${guest_key}__${bench_label}.log"
            collect_benchmark_result "$histfile_basename" "$local_outfile"

            drop_dom0_caches
            sleep 5

        done  # benchmark loop

        # Tear down Dom0 stressors after all benchmarks for this guest
        kill_stressors
        drop_dom0_caches
        sleep 5

    done  # guest loop

    log "All benchmarks tested under kernel '$kernel_label'."

done  # kernel loop

log "================================================================"
log " All experiments completed."
log " Results are in: $RESULTS_DIR"
log "================================================================"
