# KVM
This documentation describes the detailed procedure to configure an automated test at the boot of the virtual machine. The system allows forcing the boot with a specific kernel via GRUB and running `cyclictest` automatically for a single session of 5 minutes, disabling the automation once completed.

### 1. Boot Kernel Configuration on GRUB (One-time)

To ensure the accuracy and consistency of deterministic tests, it is necessary to lock the boot loader onto a specific installed version of the Linux kernel.

#### Step 1.1: List available kernel entries
Identify the exact identification string of the desired kernel by analyzing the GRUB configuration:

```bash
awk -F\' '/menuentry / {print $2}' /boot/grub/grub.cfg
```

*Note: If the kernel is located inside a submenu (e.g., "Advanced options for Ubuntu"), the syntax to use for the configuration file will be `SubmenuName>KernelSpecificationEntry`.*

#### Step 1.2: Modify GRUB parameters
Open the main GRUB configuration file for editing:

```bash
sudo nano /etc/default/grub
```

Replace the `GRUB_DEFAULT` directive by setting the path extracted in the previous step (enclosed in quotes). For example:

```text
GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 6.18.35"
```

#### Step 1.3: Update the boot loader
Release the new configuration to make it persistent on the next boot:

```bash
sudo update-grub
```

---

### 2. Implementation of the Control and Test Script

The Bash script invokes `cyclictest` for a 5-minute duration, redirects the results to a log file, and disables the service upon completion to prevent execution on subsequent normal boots.

#### Step 2.1: Script creation
Create a new executable file in the system path dedicated to local scripts:

```bash
sudo nano /usr/local/bin/run_cyclictest.sh
```

#### Step 2.2: Script code (`run_cyclictest.sh`)
Paste the following code inside the file:

```bash
#!/bin/bash

# Paths configuration
LOG_DIR="/var/log/cyclictest_results"

# Ensure the log directory exists
mkdir -p "$LOG_DIR"

# Wait for system to fully settle before starting the test
sleep 30

# Execute cyclictest with Real-Time priority for 5 minutes
sudo cyclictest --mlockall --priority=99 --threads=1 --affinity=1 --interval=50 --duration 5m -H 1000 --histfile="$LOG_DIR/results_hist.log"

# Termination condition: remove the service to prevent running on future reboots
systemctl disable cyclictest-autorun.service
```

#### Step 2.3: Assign execution permissions
Configure the correct POSIX permissions to allow systemd to invoke the script:

```bash
sudo chmod +x /usr/local/bin/run_cyclictest.sh
```

---

### 3. Configuration of the Systemd Unit Service

To ensure the script is executed immediately after the boot phase and in a non-interactive context, a `oneshot` type systemd service is implemented.

#### Step 3.1: Unit file creation
Create the service descriptor within the system units directory:

```bash
sudo nano /etc/systemd/system/cyclictest-autorun.service
```

#### Step 3.2: Service structure (`cyclictest-autorun.service`)
Configure the unit with the following directives:

```ini
[Unit]
Description=Cyclictest Automation 5-Min Run
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/run_cyclictest.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

---

### 4. Enabling and Executing the Flow

Once the components are defined, it is necessary to notify the service manager of the changes and enable the automatic startup of the test.

#### Step 4.1: Reload the systemd daemon
```bash
sudo systemctl daemon-reload
```

#### Step 4.2: Enable the service at boot
```bash
sudo systemctl enable cyclictest-autorun.service
```

#### Step 4.3: Triggering the test
To start the automated 5-minute test, perform a manual reboot of the KVM virtual machine:

```bash
sudo reboot
```

After the system boots, it will wait 30 seconds and then run the test for exactly 5 minutes. At the end of the process, the results will be available in `/var/log/cyclictest_results/results_hist.log`, the service will automatically disable itself, and the system will remain stably booted on the set kernel.

![Baseline Performance - KVM ](KVM/plot/result_1.png)

## NON-REAL-TIME HOST AND NON-REAL-TIME GUEST

This section presents an analysis of a single, extended 5-minute `cyclictest` run conducted in a standard environment, featuring a Non-Real-Time guest Linux kernel hosted on a Non-Real-Time host system. The objective is to establish a performance baseline and assess system determinism in the absence of real-time optimizations, such as the `PREEMPT_RT` patch or a real-time tuned host hypervisor.

### Distribution Analysis and Nominal Performance
Analysis of the histogram log reveals significant consistency during nominal execution over the 5-minute test period. The statistical mode (the most frequent latency value) was anchored firmly at 6 µs. The average latency was equally stable, measuring exactly 7 µs across the entire continuous execution. Additionally, the minimum recorded latency was extremely low, bottoming out at 5 µs. This performance indicates that under nominal conditions, without background load or anomalous preemption, the baseline overhead introduced by the default virtualization layer and host kernel scheduler is remarkably low.

### Worst-Case Execution Time (WCET) and Lack of Determinism
The fundamental limitation of this general-purpose configuration is revealed by the Worst-Case Execution Time (WCET) data, which continues to demonstrate high variability and unpredictable latency spikes. Across the 5-minute continuous execution, the absolute maximum latency recorded was 602 µs, a severe, stochastic deviation from the average.

### Conclusions on Standard Environments
These latency spikes—the "long tails" observed in the distribution logs—are characteristic of general-purpose software stacks. In this ecosystem, the hypervisor operates without strict real-time constraints and may preempt the Virtual CPU (VCPU) to serve host-level tasks; simultaneously, the guest kernel is subject to non-preemptible critical sections and non-deferrable hardware interrupts. Consequently, while nominal and average performance metrics are excellent, the Non-RT guest on a Non-RT host environment is susceptible to unpredictable delays and cannot guarantee the rigid, reliable upper bounds required for safety-critical control applications.

## NON-REAL-TIME HOST AND REAL-TIME GUEST
This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a hybrid environment, configured with a Real-Time optimized guest hosted on a Standard Linux Kernel Host. The goal of this analysis is to evaluate if the guest's internal real-time scheduling can maintain determinism during sustained workloads when the underlying host hypervisor lacks real-time optimizations.

### Nominal Performance and Average Latency
The data collected confirm that optimization at the Host hypervisor level guarantees excellent efficiency in the average case. The average latency value is extremely stable, resting at 8 µs for the duration of the 5-minute test. Furthermore, the absolute minimum latency dropped down to 4 µs. This behavior indicates that the Real-Time host allocates VCPU resources to the guest promptly and with minimal virtualization overhead under normal operating conditions.

### Worst-Case Execution Time (WCET) Analysis
Despite the high baseline efficiency of the underlying infrastructure, the analysis of the Worst-Case Execution Time (WCET) reveals a severe lack of determinism under sustained testing. The recorded maximum latency reached an extreme peak of 6114 µs (over 6 milliseconds), and other 3 over-milliseconds spikes. This data indicates that while the system performs well nominally, it is subject to rare but catastrophic scheduling delays that shatter any real-time guarantees.

### Conclusions on the Hybrid Environment
The empirical observation of this sustained 5-minute test demonstrates conclusively that the exclusive optimization of the virtualization infrastructure (Hypervisor/Host) is not able to stem anomalous latencies if the guest operating system is not equally optimized. The critical peak of over 6 milliseconds is a direct symptom of the internal architecture of the standard kernel. The absence of the `PREEMPT_RT` patch leaves the guest vulnerable to delays induced by the host's non-preemptible critical sections (such as spinlocks), non-deferrable hardware interrupts, and unbounded priority inversion phenomena.

Therefore, to obtain reliable determinism in control contexts, the use of an RT Guest proves not to be a sufficient condition.

## REAL-TIME HOST AND NON-REAL-TIME GUEST
This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a hybrid environment, configured with a  Standard Linux Guest hosted on a Real-Time `PREEMPT_RT` patched Host. The goal of this analysis is to verify whether the use of a deterministic Host hypervisor is sufficient to guarantee strict temporal constraints during sustained workloads when the guest operating system remains general-purpose.

### Nominal Performance and Average Latency
The data collected confirms exceptional baseline efficiency. The average latency value is strictly maintained at 7 µs for the entire duration of the 5-minute test. Furthermore, the absolute minimum latency recorded was 5 µs. The histogram distribution reveals a massive concentration around the mode, with over 92% of execution cycles completing in exactly 7 µs. This behavior indicates that the `PREEMPT_RT` patch effectively minimizes internal scheduling jitter, processing tasks extremely efficiently when the Virtual CPU (VCPU) is active.

### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) reveals highly stable and deterministic behavior during this sustained test. The absolute maximum latency recorded reached a peak of only 93 µs. This data demonstrates a complete absence of the severe, prolonged hypervisor-induced preemption spikes that typically characterize standard host environments.

### Conclusions on the Hybrid Environment
The empirical observation of this sustained 5-minute test demonstrates that optimizing the Host OS with a `PREEMPT_RT` kernel yielded remarkably robust determinism, even while running on a Non-Real-Time Guest. By successfully bounding the WCET strictly under 100 µs (peaking at 93 µs) and entirely avoiding latency overflows, the guest managed to maintain a highly predictable execution environment.

## REAL-TIME HOST AND REAL-TIME GUEST (FULL RT STACK)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a "Full RT" environment, where a `PREEMPT_RT` patched Linux guest kernel is hosted on a Real-Time optimized Host. The objective of this configuration is to validate the effectiveness of an end-to-end real-time stack in mitigating virtualization overhead and establishing a strict, deterministic upper bound for execution latency during a sustained workload.

### Nominal Performance and Average Latency
The experimental data collected demonstrates unparalleled stability under sustained nominal conditions. The average latency metric is exceptionally consistent, locked at 8 µs for the duration of the test. The absolute minimum latency recorded was 7 µs. The histogram distribution highlights this extreme efficiency, showing that the vast majority of execution cycles—over 92% of samples—completed in exactly 8 µs. This indicates that when the Virtual CPU (VCPU) is active, the `PREEMPT_RT` patch successfully manages thread scheduling and interrupt handling with virtually zero internal jitter, effectively mirroring bare-metal performance for standard task cycles.

### Worst-Case Execution Time (WCET) Analysis
The transition to a Full RT stack demonstrates a definitive improvement in worst-case performance, completely neutralizing the severe stochastic latency spikes observed in non-optimized configurations. Throughout the entire 5-minute sustained test, the absolute maximum latency (Worst-Case Execution Time) was strictly bounded at just 81 µs. The "long tail" of the distribution—characteristic of hypervisor-induced preemption and unoptimized kernel locks—has been entirely eliminated. The system demonstrates a robust, flawless ability to remain within deterministic bounds, drastically reducing the magnitude of any scheduling delays.

### Conclusions on the Full RT Architecture
The empirical observation of this sustained test provides conclusive evidence regarding the requirements for deterministic virtualization:

*   **End-to-End Determinism:** Achieving hard real-time guarantees is an end-to-end property, and the combination of the `PREEMPT_RT` Guest kernel and a Real-Time Host successfully prevents hypervisor-induced preemption.
*   **Absolute Stability:** The system maintained a strict upper bound of 81 µs over nearly 6 million consecutive execution cycles.
*   **Zero Overflows:** The complete absence of histogram overflows confirms that the system never experienced uncontrolled latency spikes during the prolonged execution.
*   **Viability for Critical Systems:** This "Full RT" configuration establishes a highly predictable WCET, proving that with proper infrastructure tuning, virtualized environments can reliably support safety-critical control applications that previously required dedicated bare-metal hardware.