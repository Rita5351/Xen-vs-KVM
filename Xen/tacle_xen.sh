#!/bin/bash

# ==============================================================================
# XEN TACLE BENCHMARK ORCHESTRATION SCRIPT
#
# Runs TACLe benchmarks inside a Xen HVM DomU (TACLe variant) while a noisy
# DomU creates interference. Four experiment configurations:
#   baseline         — TACLe VM (float) + small noisy VM, no stress
#   small_noise      — TACLe VM + small noisy VM + light stress inside noisy VM
#   big_noise        — TACLe VM + big noisy VM + heavy stress inside noisy VM
#   big_noise_pinned — both VMs pinned + heavy stress inside noisy VM
#
# Dom0 kernel fixed to LL-RT (6.18.35-rt5-ll, 4 vCPUs + pinning).
# Counterpart script : ../KVM/tacle_kvm.sh
# Results land in   : $RESULTS_DIR
# ==============================================================================

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

# GRUB Entry — exact string from /etc/grub.d/40_custom
GRUB_ENTRY="Xen 4.17-amd64 Linux 6.18.35-rt5-ll Dom0 4 vCPUs and pinning"

# ---------------------------------------------------------------------------
# Regular guest configurations (running TACLe)
# ---------------------------------------------------------------------------
declare -A GUESTS=(
    ["guest-rt5-tacle-hvm"]="ubuntu-24.04-linux-6.18.35-rt5-tacle /etc/xen/ubuntu-24.04-linux-6.18-35-rt5-hvm-tacle.conf"
    ["guest-rt5-tacle-hvm-pinned"]="ubuntu-24.04-linux-6.18.35-rt5-tacle /etc/xen/ubuntu-24.04-linux-6.18-35-rt5-hvm-tacle-pinned.conf"
)

# ---------------------------------------------------------------------------
# Noisy guest configurations
# ---------------------------------------------------------------------------
declare -A NOISY_GUESTS=(
    ["noisyguest-small"]="ubuntu-24.04-linux-6.18.35-noisyguest-small /etc/xen/ubuntu-24.04-linux-6.18-35-nrt-hvm-noisyguest-small.conf"
    ["noisyguest-big"]="ubuntu-24.04-linux-6.18.35-noisyguest-big /etc/xen/ubuntu-24.04-linux-6.18-35-nrt-hvm-noisyguest-big.conf"
    ["noisyguest-big-pinned"]="ubuntu-24.04-linux-6.18.35-noisyguest-big /etc/xen/ubuntu-24.04-linux-6.18-35-nrt-hvm-noisyguest-big-pinned.conf"
)

# ---------------------------------------------------------------------------
# Experiment configurations
# ---------------------------------------------------------------------------
CONFIG_ORDER=("baseline" "small_noise" "big_noise" "big_noise_pinned")

declare -A CONF_DOMU=(
    ["baseline"]="guest-rt5-tacle-hvm"
    ["small_noise"]="guest-rt5-tacle-hvm"
    ["big_noise"]="guest-rt5-tacle-hvm"
    ["big_noise_pinned"]="guest-rt5-tacle-hvm-pinned"
)

declare -A CONF_NOISY=(
    ["baseline"]="noisyguest-small"
    ["small_noise"]="noisyguest-small"
    ["big_noise"]="noisyguest-big"
    ["big_noise_pinned"]="noisyguest-big-pinned"
)

# Pipe-separated stress commands to run inside the noisy guest.
declare -A CONF_STRESS=(
    ["baseline"]=""
    ["small_noise"]="nohup sudo stress-ng --cpu 2 --timeout 0 > /dev/null 2>&1 &|nohup sudo stress-ng --vm 4 --vm-bytes 1G --timeout 0 > /dev/null 2>&1 &"
    ["big_noise"]="nohup sudo stress-ng --cpu 16 --timeout 0 > /dev/null 2>&1 &|nohup sudo stress-ng --vm 16 --vm-bytes 1G --timeout 0 > /dev/null 2>&1 &"
    ["big_noise_pinned"]="nohup sudo stress-ng --cpu 16 --timeout 0 > /dev/null 2>&1 &|nohup sudo stress-ng --vm 16 --vm-bytes 1G --timeout 0 > /dev/null 2>&1 &"
)

# ---------------------------------------------------------------------------
# TACLe benchmarks
# ---------------------------------------------------------------------------
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
NOISY_GUEST_SETTLE_TIME=30

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

# Read the domain name declared inside a Xen config file (on Dom0).
# $1 = conf file path
get_guest_name() {
    local cfg="$1"
    ssh "$DOM0_USER@$DOM0_IP" \
        "grep -oP '(?<=name\s*=\s*\")[^\"]+' '$cfg' | head -1" 2>/dev/null
}

# Create a DomU and wait for it to settle.
# $1 = guest config path
# $2 = settle time in seconds (default: GUEST_SETTLE_TIME)
start_guest() {
    local cfg="$1"
    local settle="${2:-$GUEST_SETTLE_TIME}"
    local max_attempts=3
    local retry_delay=15

    for (( attempt=1; attempt<=max_attempts; attempt++ )); do
        log "Creating DomU from config: $cfg (attempt $attempt/$max_attempts)"
        if ssh "$DOM0_USER@$DOM0_IP" "sudo xl create '$cfg'"; then
            log "Waiting ${settle} s for DomU to boot..."
            sleep "$settle"
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

# Log into the noisy DomU via xl console and start stress-ng in the background.
# $1 = domain name of the noisy guest
# $2 = pipe-separated stress commands
launch_noisy_domu_stress() {
    local guest_name="$1"
    local stress_cmds="$2"

    if [ -z "$stress_cmds" ]; then
        log "No stress commands to run for noisy DomU '${guest_name}'."
        return 0
    fi

    log "Logging into noisy DomU '${guest_name}' to start stress-ng..."

    local login_timeout=$(( NOISY_GUEST_SETTLE_TIME + 270 ))
    local stress_tcl_block=""
    
    IFS='|' read -ra cmds <<< "$stress_cmds"
    for cmd in "${cmds[@]}"; do
        stress_tcl_block+="send \"${cmd}\\r\"\nset timeout 30\nexpect -re {[#\$] }\n"
    done

    ssh "$DOM0_USER@$DOM0_IP" bash <<REMOTE_EOF
sudo expect << 'EXPECT_SCRIPT'
set timeout ${login_timeout}
log_user 1

spawn sudo xl console ${guest_name}

# Poke the console to surface whatever prompt is waiting
send "\r"

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

$(printf '%b' "${stress_tcl_block}")

# Log out
send "exit\r"
expect -re {(?:login|Login):\s*$}
send "\x1d"
expect eof
EXPECT_SCRIPT
REMOTE_EOF
}

# Run a single TACLe benchmark inside a DomU via xl console + expect.
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

log "================================================================"
log " Ensuring Dom0 is booted into the correct kernel..."
log "================================================================"
log "Setting grub-reboot to '${GRUB_ENTRY}' and rebooting Dom0..."
ssh "$DOM0_USER@$DOM0_IP" "sudo grub-reboot '${GRUB_ENTRY}' && sudo reboot" || true
wait_for_reboot

for config in "${CONFIG_ORDER[@]}"; do
    domu_key="${CONF_DOMU[$config]}"
    noisy_key="${CONF_NOISY[$config]}"
    stress_cmds="${CONF_STRESS[$config]}"
    
    log "================================================================"
    log " Starting experiment config: $config"
    log "================================================================"

    # Boot the noisy guest
    read -r noisy_name noisy_cfg <<< "${NOISY_GUESTS[$noisy_key]}"
    log "----------------------------------------------------------------"
    log " Booting noisy DomU: $noisy_name"
    log "   conf : $noisy_cfg"
    log "   settle time : ${NOISY_GUEST_SETTLE_TIME} s"
    log "----------------------------------------------------------------"
    
    if ! start_guest "$noisy_cfg" "$NOISY_GUEST_SETTLE_TIME"; then
        log "ERROR: could not boot noisy DomU for config '$config'. Skipping."
        continue
    fi

    launch_noisy_domu_stress "$noisy_name" "$stress_cmds"

    read -r guest_name guest_cfg <<< "${GUESTS[$domu_key]}"

    # Benchmark loop
    for bench_label in "${BENCHMARK_ORDER[@]}"; do
        bench_cmd="${TACLE_BENCHMARKS[$bench_label]}"
        histfile_basename=$(echo "$bench_cmd" | grep -oP '(?<=--histfile=)\S+')

        log "  -- Benchmark: $bench_label (Config: $config) --"

        if ! start_guest "$guest_cfg" "$GUEST_SETTLE_TIME"; then
            destroy_guest "$guest_name"
            drop_dom0_caches
            sleep 5
            continue
        fi

        run_benchmark_in_domu "$guest_name" "$bench_label" "$bench_cmd"

        destroy_guest "$guest_name"

        local_outfile="${RESULTS_DIR}/${config}__${bench_label}.log"
        collect_benchmark_result "$histfile_basename" "$local_outfile"

        drop_dom0_caches
        sleep 5
    done

    log "Destroying noisy DomU: $noisy_name"
    destroy_guest "$noisy_name"
    drop_dom0_caches
    sleep 5

done

log "================================================================"
log " All experiments completed."
log " Results are in: $RESULTS_DIR"
log "================================================================"
