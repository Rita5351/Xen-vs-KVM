#!/bin/bash

# ==============================================================================
# KVM CYCLICTEST ORCHESTRATION SCRIPT
#
# Runs cyclictest inside a KVM guest across multiple Host × Guest kernel
# combinations and three stress scenarios:
#   1. Baseline          — no host stress
#   2. Host stress       — CPU + VM stress-ng on the host
#   3. Isolated + stress — isolated VM variant + CPU + VM stress-ng on the host
#
# Kernel combinations tested: NRT-NRT, NRT-RT, RT-NRT, RT-RT
# Counterpart script : ../Xen/cyclictest_xen.sh
# Results land in   : $RESULTS_DIR
# ==============================================================================

# ==============================================================================
# CONFIGURATION
# ==============================================================================

HOST_IP="192.168.1.166"       # KVM host reachable via SSH
HOST_USER="matt"

GUEST_USER="matt"
GUEST_PASS="YOUR_GUEST_PASSWORD"

# Local directory where results are collected on the orchestrator
RESULTS_DIR="./results"

# Seconds to wait inside the guest after login before starting cyclictest
GUEST_PREWARM_TIME=15

# Seconds to wait for the guest to fully boot after 'virsh start' or after
# rebooting to a new kernel before connecting via virsh console.
GUEST_SETTLE_TIME=60

# ---------------------------------------------------------------------------
# Host GRUB entries (exact strings from /etc/grub.d/40_custom on the host).
# The host is rebooted once per host-kernel change.
# ---------------------------------------------------------------------------
declare -A HOST_KERNELS=(
    ["NRT"]="Advanced options for Ubuntu>Ubuntu, with Linux 6.18.35"
    ["RT"]="Advanced options for Ubuntu>Ubuntu, with Linux 6.18.35-rt5"
    ["NRT-isolated"]="Ubuntu 24.04 (6.18.35 isolated)"
    ["RT-isolated"]="Ubuntu 24.04 (6.18.35-rt5 isolated)"
)

# ---------------------------------------------------------------------------
# Guest GRUB entries (exact strings from the guest's GRUB menu).
# The guest is rebooted via grub-reboot + sudo reboot (over virsh console).
# ---------------------------------------------------------------------------
declare -A GUEST_KERNELS=(
    ["NRT"]="Advanced options for Ubuntu>Ubuntu, with Linux 6.18.35"
    ["RT"]="Advanced options for Ubuntu>Ubuntu, with Linux 6.18.35-rt5"
    ["NRT-isolated"]="Ubuntu 24.04 (6.18.35 isolated)"
    ["RT-isolated"]="Ubuntu 24.04 (6.18.35-rt5 isolated)"
)

# ---------------------------------------------------------------------------
# Combination sets.
#
# STANDARD_COMBINATIONS : used for scenarios 1 (baseline) and 2 (host stress).
#   Standard NRT/RT kernels on both host and guest; VM_STANDARD domain.
#
# ISOLATED_COMBINATIONS : used for scenario 3 (isolated + host stress).
#   Isolated/pinned kernels on both host and guest; VM_ISOLATED domain.
#
# Each entry is "HOST_KERNEL_KEY:GUEST_KERNEL_KEY".
# ---------------------------------------------------------------------------
STANDARD_COMBINATIONS=(
    "NRT:NRT"
    "NRT:RT"
    "RT:NRT"
    "RT:RT"
)

ISOLATED_COMBINATIONS=(
    "NRT-isolated:NRT-isolated"
    "NRT-isolated:RT-isolated"
    "RT-isolated:NRT-isolated"
    "RT-isolated:RT-isolated"
)

# ---------------------------------------------------------------------------
# KVM domain names (as known to virsh on the host).
# ---------------------------------------------------------------------------
VM_STANDARD="ubuntu24.04"          # standard (non-isolated) guest domain
VM_ISOLATED="ubuntu24.04-pinned" # isolated guest domain (same disk, different QEMU config)

# ---------------------------------------------------------------------------
# Host stress-ng stressors (CPU and VM as separate processes).
# Used in scenarios 2 and 3.
# ---------------------------------------------------------------------------
HOST_STRESS_CMDS=(
    "nohup sudo stress-ng --cpu 22 --timeout 0 > /dev/null 2>&1 &"
    "nohup sudo stress-ng --vm 12 --vm-bytes 2G --timeout 0 > /dev/null 2>&1 &"
)

# ---------------------------------------------------------------------------
# cyclictest parameters (run inside the guest)
# ---------------------------------------------------------------------------
CYCLICTEST_DURATION="5m"
CYCLICTEST_PRIORITY=99
CYCLICTEST_INTERVAL=50      # microseconds
CYCLICTEST_HISTSIZE=1000    # microseconds, histogram max
CYCLICTEST_THREADS=1
CYCLICTEST_AFFINITY=1

# Histfile is written to /home/$GUEST_USER/ (not /tmp which is a tmpfs in
# Ubuntu 24.04 and has no disk backing — file would vanish on guest shutdown).
# Result is retrieved via SSH after the run.

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
# Wait for the guest to boot and display a login prompt on the serial console.
# $1 = domain name
# $2 = timeout in seconds (default 120)
# ---------------------------------------------------------------------------
wait_for_guest_boot() {
    local domain="$1"
    local timeout="${2:-120}"

    log "Waiting up to ${timeout}s for guest '$domain' to show login prompt..."
    ssh "$HOST_USER@$HOST_IP" bash <<REMOTE_EOF
sudo expect << 'EXPECT_SCRIPT'
set timeout ${timeout}
log_user 1
spawn virsh -c qemu:///system console ${domain}
expect "Escape character is"
send "\r"
expect {
    timeout {
        send_user "ERROR: timed out waiting for guest login prompt\n"
        exit 1
    }
    -re {(?:login|Login):\s*$} {
        send "\x1d\x1d"
        expect eof
        exit 0
    }
    -re {[#\$] } {
        send "\x1d\x1d"
        expect eof
        exit 0
    }
}
EXPECT_SCRIPT
REMOTE_EOF
}

# ---------------------------------------------------------------------------
# Start a virsh domain and wait for it to settle.
# Retries up to 3 times to handle transient failures.
# $1 = domain name
# ---------------------------------------------------------------------------
start_vm() {
    local domain="$1"
    local max_attempts=3
    local retry_delay=15

    for (( attempt=1; attempt<=max_attempts; attempt++ )); do
        log "Starting VM '$domain' (attempt $attempt/$max_attempts)..."
        if ssh "$HOST_USER@$HOST_IP" "virsh -c qemu:///system start '$domain'"; then
            log "Waiting ${GUEST_SETTLE_TIME} s for VM to boot..."
            sleep "$GUEST_SETTLE_TIME"
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
# Switch the guest to a different GRUB entry.
# Logs into the running guest via virsh console + expect, runs grub-reboot,
# then reboots.  The caller is responsible for waiting until the guest is
# reachable again afterwards.
# $1 = domain name
# $2 = GRUB entry string (exact, as it appears in the guest's GRUB menu)
# ---------------------------------------------------------------------------
switch_guest_kernel() {
    local domain="$1"
    local grub_entry="$2"

    log "Switching guest '$domain' to kernel: $grub_entry"

    ssh "$HOST_USER@$HOST_IP" bash <<REMOTE_EOF
sudo expect << 'EXPECT_SCRIPT'
# Long timeout for the initial connection in case the VM was just started
set timeout 120
log_user 1

spawn virsh -c qemu:///system console ${domain}
expect "Escape character is"
send "\r"

expect {
    timeout {
        send_user "ERROR: timed out waiting for guest login prompt\n"
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

send "sudo grub-reboot '${grub_entry}'\r"
expect -re {[#\$] }

send "sudo reboot\r"
expect {
    -re {(?:login|Login):\s*$} {}
    eof {}
}
EXPECT_SCRIPT
REMOTE_EOF
}

# ---------------------------------------------------------------------------
# Start host stress-ng stressors (CPU + VM as separate processes).
# ---------------------------------------------------------------------------
start_host_stress() {
    log "Starting host stress-ng stressors..."
    for cmd in "${HOST_STRESS_CMDS[@]}"; do
        ssh "$HOST_USER@$HOST_IP" "$cmd"
    done
    sleep 2
}

# ---------------------------------------------------------------------------
# Kill all stress-ng processes on the host.
# ---------------------------------------------------------------------------
stop_host_stress() {
    log "Killing host stress-ng processes..."
    ssh "$HOST_USER@$HOST_IP" \
        "sudo pkill -f stress-ng; sleep 2; sudo pkill -9 -f stress-ng 2>/dev/null; true"
}

# ---------------------------------------------------------------------------
# Drop page cache on the host.
# ---------------------------------------------------------------------------
drop_host_caches() {
    log "Dropping host caches..."
    ssh "$HOST_USER@$HOST_IP" "sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null"
}

# ---------------------------------------------------------------------------
# Run cyclictest inside the guest (already booted, correct kernel active).
# Logs in via virsh console + expect, runs cyclictest, flushes to disk, and
# extracts the result file via virtiofs mount and scp.
#
# $1  = virsh domain name
# $2  = base name for the result file (no extension)
# $3  = local destination path prefix (no extension)
# ---------------------------------------------------------------------------
run_cyclictest_in_guest() {
    local domain="$1"
    local remote_base="$2"
    local local_outfile="$3"

    local domu_histfile="/home/${GUEST_USER}/${remote_base}.log"

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

    log "Running cyclictest in guest '$domain' (duration: ${CYCLICTEST_DURATION})..."
    
    local duration_sec
    duration_sec=$(echo "${CYCLICTEST_DURATION}" | awk '
        /m$/ { sub(/m$/,""); print $1*60; next }
        /h$/ { sub(/h$/,""); print $1*3600; next }
        /s$/ { sub(/s$/,""); print $1+0; next }
        { print $1+0 }
    ')
    local expect_timeout=$(( GUEST_PREWARM_TIME + duration_sec + 120 ))

    ssh "$HOST_USER@$HOST_IP" bash <<REMOTE_EOF
sudo expect << 'EXPECT_SCRIPT'
set timeout 60
log_user 1

spawn virsh -c qemu:///system console ${domain}
expect "Escape character is"
send "\r"

expect {
    timeout {
        send_user "ERROR: timed out waiting for guest login or shell prompt\n"
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

# Let the guest settle before the measurement
send "sleep ${GUEST_PREWARM_TIME}\r"
expect -re {[#\$] }

# Run cyclictest (console silent during the run to avoid VM-exit storms)
send "${cyclictest_cmd}\r"

set timeout ${expect_timeout}
expect -re {[#\$] }
set timeout 30

# Mount the virtiofs shared directory (tag 'mount') and copy the result over
send "sudo mkdir -p /mnt/shared && sudo mount -t virtiofs mount /mnt/shared\r"
expect -re {[#\$] }

send "sudo cp ${domu_histfile} /mnt/shared/\r"
expect -re {[#\$] }

# Flush page cache to disk
send "sync\r"
expect -re {[#\$] }

send "exit\r"
expect -re {(?:login|Login):\s*$}
# Detach from virsh console
send "\x1d\x1d"
expect eof
EXPECT_SCRIPT
REMOTE_EOF

    local ssh_exit=${PIPESTATUS[0]}
    if [[ $ssh_exit -ne 0 ]]; then
        log "  WARN: ssh expect script failed."
    fi

    mkdir -p "$(dirname "$local_outfile")"
    
    if scp "${HOST_USER}@${HOST_IP}:/mnt/virtio_fs/${remote_base}.log" \
           "${local_outfile}.log" 2>/dev/null; then
        log "  Histogram saved: ${local_outfile}.log"
    else
        log "  WARN: could not retrieve histogram from host virtiofs (/mnt/virtio_fs/${remote_base}.log)"
    fi
}

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

preflight_check() {
    log "Running pre-flight checks..."
    command -v ssh  >/dev/null 2>&1 || die "ssh not found on orchestrator."
    command -v scp  >/dev/null 2>&1 || die "scp not found on orchestrator."
    command -v ping >/dev/null 2>&1 || die "ping not found on orchestrator."
    ping -c 1 -W 3 "$HOST_IP" &>/dev/null || die "KVM host ($HOST_IP) is not reachable."
    ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST_USER@$HOST_IP" \
        "virsh -c qemu:///system list > /dev/null" \
        || die "Cannot reach host via SSH or virsh not available."
    mkdir -p "$RESULTS_DIR"
    log "Pre-flight checks passed."
}

# ==============================================================================
# SCENARIO RUNNER
#
# Runs all kernel combinations for a given scenario.
#
# $1 = scenario label (used in result filenames)
# $2 = virsh domain name to use (VM_STANDARD or VM_ISOLATED)
# $3 = "stress" if host stress-ng should run, "" otherwise
# ==============================================================================

run_scenario() {
    local scenario_label="$1"
    local domain="$2"
    local with_stress="$3"
    local -n combos="$4"   # nameref: caller passes the array name as a string

    log "======================================================================"
    log " SCENARIO: $scenario_label  |  VM: $domain  |  stress: ${with_stress:-none}"
    log "======================================================================"

    # Track the current host kernel to avoid unnecessary reboots
    local current_host_kernel=""

    for combo in "${combos[@]}"; do
        local host_key="${combo%%:*}"
        local guest_key="${combo##*:}"
        local host_grub="${HOST_KERNELS[$host_key]}"
        local guest_grub="${GUEST_KERNELS[$guest_key]}"

        log "----------------------------------------------------------------------"
        log " Combination: host=$host_key  guest=$guest_key"
        log "   host GRUB : $host_grub"
        log "   guest GRUB: $guest_grub"
        log "----------------------------------------------------------------------"

        # ------------------------------------------------------------------
        # Reboot the host if its kernel needs to change
        # ------------------------------------------------------------------
        if [[ "$host_key" != "$current_host_kernel" ]]; then
            log "Switching host to kernel '$host_key'..."
            ssh "$HOST_USER@$HOST_IP" \
                "sudo grub-reboot '${host_grub}' && sudo reboot" || true
            wait_for_host_reboot
            current_host_kernel="$host_key"
        fi

        # ------------------------------------------------------------------
        # Ensure the VM is running (it will be rebooted by the kernel switch)
        # ------------------------------------------------------------------
        if ! ssh "$HOST_USER@$HOST_IP" "virsh -c qemu:///system list --name | grep -q '^${domain}$'"; then
            log "VM '$domain' is not running. Starting it..."
            if ! start_vm "$domain"; then
                log "  ERROR: could not start VM '$domain' — skipping combination."
                continue
            fi
        fi

        # ------------------------------------------------------------------
        # Switch the guest to the target kernel and wait for reboot
        # ------------------------------------------------------------------
        if ! switch_guest_kernel "$domain" "$guest_grub"; then
            log "  ERROR: failed to switch guest kernel — skipping."
            stop_vm "$domain"
            continue
        fi
        
        log "  Waiting for guest to reboot into new kernel..."
        sleep 10   # give the guest a moment to start restarting
        
        if ! wait_for_guest_boot "$domain" 120; then
            log "  ERROR: guest did not show login prompt after kernel switch — skipping."
            stop_vm "$domain"
            continue
        fi
        log "  Guest '$domain' is booted and ready with kernel '$guest_key'."

        # ------------------------------------------------------------------
        # Start host stress-ng if requested
        # ------------------------------------------------------------------
        [[ -n "$with_stress" ]] && start_host_stress

        # ------------------------------------------------------------------
        # Run cyclictest
        # ------------------------------------------------------------------
        local result_tag="${host_key}-host__${guest_key}-guest__${scenario_label}"
        run_cyclictest_in_guest \
            "$domain" \
            "cyclictest_${result_tag}" \
            "${RESULTS_DIR}/${result_tag}"

        # ------------------------------------------------------------------
        # Cleanup after this combination
        # ------------------------------------------------------------------
        [[ -n "$with_stress" ]] && stop_host_stress
        drop_host_caches

        sleep 5

    done  # combination loop

    # Stop the VM at the end of the scenario
    stop_vm "$domain"
}

# ==============================================================================
# MAIN
# ==============================================================================

preflight_check

# Scenario 1: Baseline — no host stress, standard kernels, standard VM
run_scenario "baseline" "$VM_STANDARD" "" STANDARD_COMBINATIONS

# Scenario 2: Host stress — CPU + VM stress-ng, standard kernels, standard VM
run_scenario "host-stress" "$VM_STANDARD" "stress" STANDARD_COMBINATIONS

# Scenario 3: Isolated + host stress — isolated/pinned kernels on both host and
# guest, CPU + VM stress-ng on host, isolated VM domain
run_scenario "isolated-host-stress" "$VM_ISOLATED" "stress" ISOLATED_COMBINATIONS

log "======================================================================"
log " All experiments completed."
log " Results are in: $RESULTS_DIR"
log "======================================================================"
