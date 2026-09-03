#!/bin/bash

# ==============================================================================
# KVM TACLE BENCHMARK ORCHESTRATION SCRIPT
#
# Runs TACLe benchmarks inside a KVM guest (ubuntu24.04-tacle) across four
# experiment configurations, each pairing the TACLe VM with a noisy VM that
# optionally runs stress-ng inside it.
#
# Host kernel: "Ubuntu 24.04 (6.18.35-rt5 TACLe)"
#   Boot params: nohz_full=4-23 rcu_nocbs=4-23 irqaffinity=0-3
#   NO isolcpus — the load balancer is kept alive so VMs can float on 4-23.
#   Host user-space is confined to CPUs 0-3 via systemd CPUAffinity=0-3
#   set in /etc/systemd/system.conf (applied at boot; no restore needed).
#
# CPU layout
#   CPUs 0-3  : host OS + QEMU emulator/IO threads
#   CPUs 4-23 : VM vCPU pool (floating, balanced by the Linux scheduler)
#   CPUs 22-23: also used by the pinned TACLe VM (tacle-pinned)
#
# Experiment configurations (CONFIG_ORDER)
#   baseline         — TACLe VM (float) + small noisy VM (float), no stress
#   small_noise      — TACLe VM (float) + small noisy VM (float), small stress
#   big_noise        — TACLe VM (float) + big   noisy VM (float), big   stress
#   big_noise_pinned — TACLe VM (pinned 22-23) + big pinned noisy VM, big stress
#
# Result retrieval
#   The TACLe VM has a virtiofs share (/mnt/virtio_fs on host, tag 'mount').
#   Benchmarks write histfiles to /home/GUEST_USER/ inside the VM, then copy
#   them to /mnt/shared (virtiofs) before the VM is stopped.  The orchestrator
#   then scp-s from HOST_IP:/mnt/virtio_fs/<histfile>.
#
# Counterpart scripts
#   Xen version : tacle_xen.sh
#   cyclictest  : cyclictest_kvm.sh
# ==============================================================================

# ==============================================================================
# CONFIGURATION
# ==============================================================================

HOST_IP="192.168.1.166"
HOST_USER="matt"

GUEST_USER="matt"
GUEST_PASS="YOUR_GUEST_PASSWORD"

# Local directory where results are collected on the orchestrator
RESULTS_DIR="./results_tacle"

# Seconds to wait inside the TACLe guest after login before starting a benchmark
GUEST_PREWARM_TIME=15

# Seconds to wait after 'virsh start' before the guest console is usable
GUEST_SETTLE_TIME=60
NOISY_GUEST_SETTLE_TIME=60

# GRUB entry for the host — exact string from /etc/grub.d/40_custom on the host
# Kernel params: nohz_full=4-23 rcu_nocbs=4-23 irqaffinity=0-3 (no isolcpus)
GRUB_ENTRY="Ubuntu 24.04 (6.18.35-rt5 TACLe)"

# ---------------------------------------------------------------------------
# TACLe VM configurations (virsh domain names)
# ---------------------------------------------------------------------------
VM_TACLE="ubuntu24.04-tacle"               # floating on CPUs 4-23
VM_TACLE_PINNED="ubuntu24.04-tacle-pinned" # pinned to CPUs 22-23

# ---------------------------------------------------------------------------
# Noisy VM configurations (virsh domain names)
# ---------------------------------------------------------------------------
VM_NOISE_SMALL="ubuntu24.04-noise-small"           # 2 vCPUs, floating 4-23
VM_NOISE_BIG="ubuntu24.04-noise-big"               # 16 vCPUs, floating 4-23
VM_NOISE_BIG_PINNED="ubuntu24.04-noise-big-pinned" # 16 vCPUs, pinned 6-22

# ---------------------------------------------------------------------------
# Experiment configurations
# ---------------------------------------------------------------------------
CONFIG_ORDER=("baseline" "small_noise" "big_noise" "big_noise_pinned")

# TACLe VM to use for each configuration
declare -A CONF_TACLE_VM=(
    ["baseline"]="$VM_TACLE"
    ["small_noise"]="$VM_TACLE"
    ["big_noise"]="$VM_TACLE"
    ["big_noise_pinned"]="$VM_TACLE_PINNED"
)

# Noisy VM to use for each configuration
declare -A CONF_NOISY_VM=(
    ["baseline"]="$VM_NOISE_SMALL"
    ["small_noise"]="$VM_NOISE_SMALL"
    ["big_noise"]="$VM_NOISE_BIG"
    ["big_noise_pinned"]="$VM_NOISE_BIG_PINNED"
)

# Pipe-separated stress commands to run INSIDE the noisy VM.
# Empty string means no stress (baseline).
declare -A CONF_STRESS=(
    ["baseline"]=""
    ["small_noise"]="nohup sudo stress-ng --cpu 2 --timeout 0 > /dev/null 2>&1 &|nohup sudo stress-ng --vm 4 --vm-bytes 1G --timeout 0 > /dev/null 2>&1 &"
    ["big_noise"]="nohup sudo stress-ng --cpu 16 --timeout 0 > /dev/null 2>&1 &|nohup sudo stress-ng --vm 16 --vm-bytes 1G --timeout 0 > /dev/null 2>&1 &"
    ["big_noise_pinned"]="nohup sudo stress-ng --cpu 16 --timeout 0 > /dev/null 2>&1 &|nohup sudo stress-ng --vm 16 --vm-bytes 1G --timeout 0 > /dev/null 2>&1 &"
)

# ---------------------------------------------------------------------------
# TACLe benchmarks
# ---------------------------------------------------------------------------
TACLE_DIR="/home/${GUEST_USER}/custom_tests"

declare -A TACLE_BENCHMARKS=(
    ["huff_enc"]="sudo ./huff_enc --mlockall -N --priority=99 --affinity=1 --loops=1000000 --histogram=1000000 --histfile=results_huffenc.log > /dev/null 2>&1"
    ["matrix1"]="sudo ./matrix1 --mlockall -N --priority=99 --affinity=1 --loops=1000000 --histogram=1000000 --histfile=results_matrix1.log > /dev/null 2>&1"
    ["lift"]="sudo ./lift --mlockall -N --priority=99 --affinity=1 --loops=1000000 --histogram=1000000 --histfile=results_lift.log > /dev/null 2>&1"
    ["test3"]="sudo ./test3 --mlockall --priority=99 --affinity=1 --loops=10000 --histogram=1000000 --histfile=results_test3.log > /dev/null 2>&1"
    ["debie"]="sudo ./debie --mlockall --priority=99 --affinity=1 --loops=10000 --histogram=1000000 --histfile=results_debie.log > /dev/null 2>&1"
)

BENCHMARK_ORDER=("huff_enc" "matrix1" "lift" "test3" "debie")

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
# Wait for the KVM host to reboot and become SSH-reachable.
# ---------------------------------------------------------------------------
wait_for_host_reboot() {
    log "Waiting for host ($HOST_IP) to go offline..."
    sleep 15
    while ping -c 1 -W 1 "$HOST_IP" &>/dev/null; do sleep 2; done
    log "Host is offline. Waiting for it to come back..."
    until ping -c 1 -W 1 "$HOST_IP" &>/dev/null; do sleep 5; done
    log "Host is reachable. Waiting for SSH..."
    sleep 10
    until ssh -o ConnectTimeout=5 -o BatchMode=yes \
              "$HOST_USER@$HOST_IP" "true" 2>/dev/null; do
        log "  SSH not yet ready, retrying in 5 s..."
        sleep 5
    done
    log "Host SSH is ready."
}

# ---------------------------------------------------------------------------
# Drop page cache on the host.
# ---------------------------------------------------------------------------
drop_host_caches() {
    log "Dropping host caches..."
    ssh "$HOST_USER@$HOST_IP" "sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null"
}

# ---------------------------------------------------------------------------
# Start a virsh domain and wait for it to settle.
# Retries up to 3 times to handle transient failures.
# $1 = domain name
# $2 = settle time in seconds (default: GUEST_SETTLE_TIME)
# ---------------------------------------------------------------------------
start_vm() {
    local domain="$1"
    local settle="${2:-$GUEST_SETTLE_TIME}"
    local max_attempts=3
    local retry_delay=15

    for (( attempt=1; attempt<=max_attempts; attempt++ )); do
        log "Starting VM '$domain' (attempt $attempt/$max_attempts)..."
        if ssh "$HOST_USER@$HOST_IP" "virsh -c qemu:///system start '$domain'"; then
            log "Waiting ${settle} s for VM to boot..."
            sleep "$settle"
            return 0
        fi
        if (( attempt < max_attempts )); then
            log "  virsh start failed — waiting ${retry_delay} s before retry..."
            sleep "$retry_delay"
        fi
    done

    log "  ERROR: virsh start '$domain' failed after $max_attempts attempts."
    return 1
}

# ---------------------------------------------------------------------------
# Destroy (force-stop) a virsh domain.
# $1 = domain name
# ---------------------------------------------------------------------------
stop_vm() {
    local domain="$1"
    log "Stopping VM '$domain'..."
    if ssh "$HOST_USER@$HOST_IP" "virsh -c qemu:///system list --name | grep -q '^${domain}$'"; then
        if ! ssh "$HOST_USER@$HOST_IP" "virsh -c qemu:///system destroy '$domain'"; then
            log "  WARN: virsh destroy '$domain' reported an error."
        fi
    else
        log "  INFO: VM '$domain' is not running; nothing to stop."
    fi
    sleep 3
}

# ---------------------------------------------------------------------------
# Log into the noisy VM via virsh console + expect and launch stress-ng
# in the background inside that VM.
#
# $1 = noisy VM virsh domain name
# $2 = pipe-separated stress commands to run inside the VM
# ---------------------------------------------------------------------------
launch_noisy_vm_stress() {
    local domain="$1"
    local stress_cmds="$2"

    if [ -z "$stress_cmds" ]; then
        log "No stress commands to run for noisy VM '${domain}'."
        return 0
    fi

    log "Logging into noisy VM '${domain}' to start stress-ng..."

    local login_timeout=$(( NOISY_GUEST_SETTLE_TIME + 270 ))
    local stress_tcl_block=""

    IFS='|' read -ra cmds <<< "$stress_cmds"
    for cmd in "${cmds[@]}"; do
        stress_tcl_block+="send \"${cmd}\\r\"\nset timeout 30\nexpect -re {[#\$] }\n"
    done

    ssh "$HOST_USER@$HOST_IP" bash <<REMOTE_EOF
sudo expect << 'EXPECT_SCRIPT'
set timeout ${login_timeout}
log_user 1

spawn virsh -c qemu:///system console ${domain}
expect "Escape character is"
send "\r"

expect {
    timeout {
        send_user "ERROR: timed out waiting for noisy VM login prompt\n"
        exit 1
    }
    -re {(?:login|Login):\s*$} {
        send "${GUEST_USER}\r"
        expect -re {(?:password|Password):\s*$}
        send "${GUEST_PASS}\r"
        expect -re {[#\$] }
    }
    -re {[#\$] } {}
}

$(printf '%b' "${stress_tcl_block}")

# Log out
send "exit\r"
expect -re {(?:login|Login):\s*$}
send "\x1d\x1d"
expect eof
EXPECT_SCRIPT
REMOTE_EOF
}

# ---------------------------------------------------------------------------
# Run a single TACLe benchmark inside the TACLe VM via virsh console + expect.
# The benchmark writes a histfile to TACLE_DIR inside the VM, then the script
# copies it to the virtiofs share (/mnt/shared inside the VM == /mnt/virtio_fs
# on the host) so the orchestrator can scp it afterwards.
#
# $1 = TACLe VM virsh domain name
# $2 = benchmark label (for logging)
# $3 = benchmark command (run from TACLE_DIR; must include --histfile=...)
# ---------------------------------------------------------------------------
run_benchmark_in_vm() {
    local domain="$1"
    local bench_label="$2"
    local bench_cmd="$3"

    local full_cmd="cd ${TACLE_DIR} && ${bench_cmd}"

    # Extract the histfile basename from the bench command
    local histfile_basename
    histfile_basename=$(echo "$bench_cmd" | grep -oP '(?<=--histfile=)\S+')

    log "Running benchmark '${bench_label}' in VM '${domain}'..."

    # Generous timeout: prewarm + up to 30 min for the benchmark + 60 s margin
    local expect_timeout=$(( GUEST_PREWARM_TIME + 1860 ))

    ssh "$HOST_USER@$HOST_IP" bash <<REMOTE_EOF
sudo expect << 'EXPECT_SCRIPT'
set timeout 60
log_user 1

spawn virsh -c qemu:///system console ${domain}
expect "Escape character is"
send "\r"

# Wait for either a login prompt or an already-open shell prompt.
expect {
    timeout {
        send_user "ERROR: timed out waiting for login or shell prompt\n"
        exit 1
    }
    -re {(?:login|Login):\s*$} {
        send "${GUEST_USER}\r"
        expect -re {(?:password|Password):\s*$}
        send "${GUEST_PASS}\r"
        expect -re {[#$] }
    }
    -re {[#$] } {
        # Already at a shell prompt — nothing to do
    }
}

# Give the VM time to finish settling before the benchmark
send "sleep ${GUEST_PREWARM_TIME}\r"
expect -re {[#$] }

# Run the benchmark (all output silenced to keep the serial console idle)
send "${full_cmd}\r"

# Wait for the benchmark to complete (generous timeout)
set timeout ${expect_timeout}
expect -re {[#$] }
set timeout 30

# Flush dirty pages to disk before copying
send "sync\r"
expect -re {[#$] }

# Copy the histfile to the virtiofs share so the orchestrator can retrieve it
send "sudo mkdir -p /mnt/shared && sudo mount -t virtiofs mount /mnt/shared 2>/dev/null; true\r"
expect -re {[#$] }

send "sudo cp ${TACLE_DIR}/${histfile_basename} /mnt/shared/\r"
expect -re {[#$] }

send "sync\r"
expect -re {[#$] }

# Log out
send "exit\r"
expect -re {(?:login|Login):\s*$}
send "\x1d\x1d"
expect eof
EXPECT_SCRIPT
REMOTE_EOF
}

# ---------------------------------------------------------------------------
# Retrieve the benchmark histfile from the host virtiofs mount point and save
# it locally on the orchestrator.
#
# $1 = histfile basename (as written by the benchmark via --histfile=)
# $2 = local destination file path (including final filename, with extension)
# ---------------------------------------------------------------------------
collect_benchmark_result() {
    local histfile_basename="$1"
    local local_outfile="$2"

    mkdir -p "$(dirname "$local_outfile")"

    if scp "${HOST_USER}@${HOST_IP}:/mnt/virtio_fs/${histfile_basename}" \
           "${local_outfile}" 2>/dev/null; then
        log "  Result saved: $local_outfile"
    else
        log "  WARN: histfile not found at /mnt/virtio_fs/${histfile_basename} on host."
        log "        Verify that the benchmark ran and the virtiofs copy succeeded."
    fi
}

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

preflight_check() {
    log "Running pre-flight checks..."
    command -v ssh  >/dev/null 2>&1 || die "ssh not found on orchestrator."
    command -v scp  >/dev/null 2>&1 || die "scp not found on orchestrator."
    command -v ping >/dev/null 2>&1 || die "ping not found on orchestrator.\n"
    ping -c 1 -W 3 "$HOST_IP" &>/dev/null || die "KVM host ($HOST_IP) is not reachable."
    ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST_USER@$HOST_IP" \
        "virsh -c qemu:///system list > /dev/null" \
        || die "Cannot reach host via SSH or virsh not available."
    mkdir -p "$RESULTS_DIR"
    log "Pre-flight checks passed."
}

# ==============================================================================
# MAIN ORCHESTRATION LOOP
# ==============================================================================

preflight_check

# ---------------------------------------------------------------------------
# Confine host user-space to CPUs 0-3 via systemd cgroups.
# We add CPUAffinity=0-3 to /etc/systemd/system.conf on the host BEFORE
# rebooting so that the setting is in place the moment PID 1 starts under
# the new kernel.  This keeps the Linux load balancer alive on CPUs 4-23
# (needed for the floating VM placement) while preventing host daemons from
# wandering onto the VM pool.
# The line is removed and systemd is re-executed at the end of the campaign
# to restore normal scheduling without requiring another reboot.
# ---------------------------------------------------------------------------
log "================================================================"
log " Ensuring host is booted into the TACLe kernel..."
log "================================================================"

log "Setting CPUAffinity=0-3 in /etc/systemd/system.conf on host..."
ssh "$HOST_USER@$HOST_IP" bash <<'REMOTE_EOF'
    cfg=/etc/systemd/system.conf
    # Remove any pre-existing CPUAffinity line, then append our own.
    sudo sed -i '/^CPUAffinity=/d' "$cfg"
    echo 'CPUAffinity=0-3' | sudo tee -a "$cfg" > /dev/null
    echo "  CPUAffinity=0-3 written to $cfg"
REMOTE_EOF

log "Setting grub-reboot to '${GRUB_ENTRY}' and rebooting host..."
ssh "$HOST_USER@$HOST_IP" "sudo grub-reboot '${GRUB_ENTRY}' && sudo reboot" || true
wait_for_host_reboot

for config in "${CONFIG_ORDER[@]}"; do
    tacle_domain="${CONF_TACLE_VM[$config]}"
    noisy_domain="${CONF_NOISY_VM[$config]}"
    stress_cmds="${CONF_STRESS[$config]}"

    log "================================================================"
    log " Starting experiment config: $config"
    log "   TACLe VM : $tacle_domain"
    log "   Noisy VM : $noisy_domain"
    log "================================================================"

    # -----------------------------------------------------------------------
    # Boot the noisy VM and (optionally) start stress inside it
    # -----------------------------------------------------------------------
    log "----------------------------------------------------------------"
    log " Booting noisy VM: $noisy_domain"
    log "   settle time : ${NOISY_GUEST_SETTLE_TIME} s"
    log "----------------------------------------------------------------"

    if ! start_vm "$noisy_domain" "$NOISY_GUEST_SETTLE_TIME"; then
        log "ERROR: could not boot noisy VM for config '$config'. Skipping entire config."
        continue
    fi

    launch_noisy_vm_stress "$noisy_domain" "$stress_cmds"

    # -----------------------------------------------------------------------
    # Benchmark loop — start the TACLe VM fresh for each benchmark
    # -----------------------------------------------------------------------
    for bench_label in "${BENCHMARK_ORDER[@]}"; do
        bench_cmd="${TACLE_BENCHMARKS[$bench_label]}"
        histfile_basename=$(echo "$bench_cmd" | grep -oP '(?<=--histfile=)\S+')

        log "  -- Benchmark: $bench_label (Config: $config) --"

        if ! start_vm "$tacle_domain" "$GUEST_SETTLE_TIME"; then
            log "  ERROR: could not start TACLe VM — skipping benchmark '$bench_label'."
            drop_host_caches
            sleep 5
            continue
        fi

        run_benchmark_in_vm "$tacle_domain" "$bench_label" "$bench_cmd"

        stop_vm "$tacle_domain"

        local_outfile="${RESULTS_DIR}/${config}__${bench_label}.log"
        collect_benchmark_result "$histfile_basename" "$local_outfile"

        drop_host_caches
        sleep 5
    done

    # -----------------------------------------------------------------------
    # Tear down the noisy VM after all benchmarks for this config are done
    # -----------------------------------------------------------------------
    log "Stopping noisy VM: $noisy_domain"
    stop_vm "$noisy_domain"
    drop_host_caches
    sleep 5

done

log "================================================================"
log " All experiments completed."
log " Results are in: $RESULTS_DIR"
log "================================================================"

# ---------------------------------------------------------------------------
# Restore normal host scheduling: remove CPUAffinity from system.conf and
# re-execute systemd so the change takes effect immediately without a reboot.
# After this point the host's load balancer will schedule services freely
# across all CPUs again.
# ---------------------------------------------------------------------------
log "Restoring host systemd CPUAffinity (removing CPUAffinity=0-3)..."
ssh "$HOST_USER@$HOST_IP" bash <<'REMOTE_EOF'
    cfg=/etc/systemd/system.conf
    sudo sed -i '/^CPUAffinity=0-3$/d' "$cfg"
    echo "  CPUAffinity line removed from $cfg"
    # daemon-reexec re-executes PID 1 in-place with the updated config;
    # running services are NOT restarted, but new cgroup affinity is applied.
    sudo systemctl daemon-reexec
    echo "  systemd daemon-reexec completed — normal scheduling restored."
REMOTE_EOF
log "Host scheduling restored."
