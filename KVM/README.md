# KVM
This documentation describes the detailed procedure to configure an automated test cycle at the boot of the virtual machine. The system allows forcing the boot with a specific kernel via GRUB, running `cyclictest` for a preset number of iterations (30 cycles), and automatically rebooting the machine at the end of each session, disabling the cycle once completed.


### Boot Kernel Configuration on GRUB (One-time)

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
GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 5.15.0-88-generic"
```

#### Step 1.3: Update the boot loader
Release the new configuration to make it persistent on the next boot:

```bash
sudo update-grub
```

---

### 2. Implementation of the Control and Test Script

The Bash script manages the automation state through a persistent counter file, invokes `cyclictest` redirecting the results to a unique log file for each iteration, and launches the reboot command until the thirtieth execution is reached.

#### Step 2.1: Script creation
Create a new executable file in the system path dedicated to local scripts:

```bash
sudo nano /usr/local/bin/run_cyclictest.sh
```

#### Step 2.2: Script code (`run_cyclictest.sh`)
Paste the following code inside the file:

```bash
#!/bin/bash

# Paths and limits configuration
LOG_DIR="/var/log/cyclictest_results"
COUNT_FILE="$LOG_DIR/run_count.txt"
MAX_RUNS=30

# Ensure the log directory exists
mkdir -p "$LOG_DIR"

# State counter initialization
if [ ! -f "$COUNT_FILE" ]; then
    echo 0 > "$COUNT_FILE"
fi

CURRENT_RUN=$(cat "$COUNT_FILE")

if [ "$CURRENT_RUN" -lt "$MAX_RUNS" ]; then
    # Increment counter for the current iteration
    NEXT_RUN=$((CURRENT_RUN + 1))
    echo "$NEXT_RUN" > "$COUNT_FILE"
    sleep 30

    # Execute cyclictest with Real-Time priority (Modify parameters if necessary)
    # Example parameters: -t1 (1 thread), -p 99 (max RT priority), -n (clock_nanosleep), -D 1m (duration 1 minute)
    sudo cyclictest --mlockall --priority=99 --threads=1 --affinity=1 --interval=50 --duration 1m -H 1000 --histfile="$LOG_DIR/results_hit_${NEXT_RUN}.log"

    # Force reboot for the next cycle
    reboot
else
    # Termination condition: remove the service to prevent infinite loops
    systemctl disable cyclictest-reboot.service
    echo "30-test cycle successfully completed. Automation disabled." > "$LOG_DIR/final_status.txt"
fi
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
sudo nano /etc/systemd/system/cyclictest-reboot.service
```

#### Step 3.2: Service structure (`cyclictest-reboot.service`)
Configure the unit with the following directives:

```ini
[Unit]
Description=Cyclictest Automation and Reboot Loop
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

Once the components are defined, it is necessary to notify the service manager of the changes and enable the automatic startup of the test chain.

#### Step 4.1: Reload the systemd daemon
```bash
sudo systemctl daemon-reload
```

#### Step 4.2: Enable the service at boot
```bash
sudo systemctl enable cyclictest-reboot.service
```

#### Step 4.3: Triggering the first cycle
To start the automated sequence of the 30 tests, perform the first manual reboot of the KVM virtual machine:

```bash
sudo reboot
```

At the end of the thirtieth cycle, the incremental logs will be available in `/var/log/cyclictest_results/` and the system will remain stably booted on the set kernel, awaiting interaction.

## NO-REAL-TIME KERNEL AND NO REAL-TIME VM
This section presents an analysis of 30 consecutive `cyclictest` runs conducted in a standard environment, featuring a Non-Real-Time Linux kernel hosted on a Non-Real-Time Virtual Machine. The objective is to establish a performance baseline and assess system determinism in the absence of real-time optimizations, such as the PREEMPT_RT patch or a real-time tuned hypervisor.

### Distribution Analysis and Nominal Performance
Analysis of the histogram logs across all 30 test runs reveals significant consistency during nominal execution. In every measurement, the statistical mode (the most frequent latency value) remained firmly anchored at 8 µs. For instance, the final iteration (Run 30) recorded the 8 µs latency 887,458 times. Average latencies were equally stable, consistently measuring 8 µs across the majority of the analyzed runs, including runs 2, 12, 15, and 30. This performance indicates that under nominal conditions, without background load or anomalous preemption, the overhead introduced by the default virtualization layer and host kernel scheduler is remarkably low.

### Worst-Case Execution Time (WCET) and Lack of Determinism
The fundamental limitation of this configuration is revealed by the Worst-Case Execution Time (WCET) data, which shows high variability and unpredictable latency spikes. Across the 30 runs, maximum latencies varied significantly, ranging from a relative low of 290 µs in Run 12, to extreme values that exceeded the millisecond threshold, such as the 1180 µs spike observed in Run 15. Other runs confirmed this instability, exhibiting substantial peaks such as 742 µs in Run 2 and 681 µs in Run 30.

### Conclusions on Standard Environments
These severe latency spikes—the "long tails" observed in the distribution logs—are characteristic of general-purpose software stacks. In this ecosystem, the hypervisor operates without real-time constraints and may preempt the Virtual CPU (VCPU) to serve host-level tasks; simultaneously, the guest kernel is subject to non-preemptible critical sections and non-deferrable hardware interrupts. Consequently, while nominal and average performance metrics are excellent, the Non-RT kernel on a Non-RT VM environment cannot guarantee the rigid, reliable upper bounds required for safety-critical control applications.

## NO REAL-TIME KERNEL AND REAL TIME VM

This section analyzes the overall results obtained from 30 executions of the `cyclictest` tool in a hybrid environment, configured with a Standard Linux Kernel (Non-Real-Time) hosted on a Virtual Machine optimized for Real-Time. The goal of the analysis is to isolate latency responsibilities, verifying whether the use of a deterministic Hypervisor is sufficient to guarantee the respect of temporal constraints when the guest operating system remains general-purpose.

### Nominal Performance and Average Latency
The data collected over the 30 runs confirm that optimization at the Hypervisor level guarantees excellent efficiency in the average case. The average latency values are extremely stable between 8 µs and 9 µs across all measurements. Furthermore, the absolute minimum latencies frequently drop down to 4 µs (as observed in Runs 23, 25, 27, and 29). This behavior indicates that the Real-Time VM allocates VCPU resources to the guest promptly and with minimal virtualization overhead.

### Worst-Case Execution Time (WCET) Analysis
Despite the optimization of the underlying infrastructure, the analysis of the Worst-Case Execution Time (WCET) reveals a persistent lack of determinism. The recorded maximum latencies exhibit high variability. Although some tests contain the maximums to lower values (e.g., 376 µs in Run 15, 394 µs in Run 30, or 406 µs in Run 3), the majority of the samplings record severe peaks over 650 µs, often settling above 700 µs (e.g., Runs 10, 13, 22, 26, and 27). 

The most critical issues are highlighted in Run 28, which reaches 912 µs, and particularly in Run 17, where the system records an isolated and extreme maximum peak of **1812 µs**.

### Conclusions on the Hybrid Environment
The empirical observation of these 30 runs demonstrates that the exclusive optimization of the virtualization infrastructure (Hypervisor/Host) is not able to stem anomalous latencies if the guest operating system is not equally optimized. The critical peak of over 1.8 milliseconds is a direct symptom of the internal architecture of the standard kernel: the absence of the PREEMPT_RT patch leaves the guest vulnerable to delays induced by non-preemptible critical sections (spinlocks), non-deferrable hardware interrupts, and unbounded priority inversion phenomena. 

Therefore, to obtain reliable determinism in control contexts, the use of an RT Host proves not to be a sufficient condition.

## REAL-TIME KERNEL AND NO REAL-TIME VM

This section provides a synthesis of the performance evaluation conducted over 30 measurement cycles (Runs 1–30). The objective was to determine the feasibility of achieving real-time determinism in a virtualized environment where the Guest OS utilizes a `PREEMPT_RT` patched kernel, while the Host remains a non-real-time infrastructure.

### Summary of Nominal Performance
The analysis of the distribution histograms across all 30 runs demonstrates a high degree of consistency in nominal operating conditions. 
* The mode of the latency distribution is consistently observed between 8 µs and 9 µs. 
* This stability indicates that the PREEMPT_RT patch effectively minimizes internal scheduling jitter and task latency when the Virtual CPU (VCPU) is active and granted execution time.
* The minimum observed latencies remain near 6–7 µs throughout the entire testing campaign.

### Worst-Case Execution Time (WCET) and Host Interference
Despite the favorable nominal performance, the presence of statistically significant outliers and histogram overflows confirms that this configuration is inherently non-deterministic.
* Histogram overflows and large latency spikes (reaching values exceeding 300–4000 µs in several instances) indicate severe interruptions by the Host's scheduler.
* These outliers are attributed to hypervisor-induced preemption, where the non-real-time Host suspends the Guest VCPU to handle physical interrupt requests or its own system processes.
* The increased frequency of histogram overflows in the final blocks (Runs 21–30) highlights that while the Guest kernel is "RT-ready," it remains entirely subordinate to the Host's scheduling policies.

### Concluding Remarks on Virtualization Determinism
The consolidated data from all 30 runs supports a clear conclusion: the "RT Guest / Non-RT Host" configuration is insufficient for systems requiring strict Worst-Case Execution Time (WCET) guarantees.
* The PREEMPT_RT patch successfully reduces internal task latency.
* However, the host-level preemption creates a "long tail" in the latency distribution, preventing the establishment of a hard real-time execution bound.
* Consequently, we define this architecture as "soft real-time" at best, suitable for general-purpose workloads, but unsuitable for hard real-time applications requiring predictable performance under all operating conditions.

## REAL-TIME KERNEL AND REAL TIME VM

This section provides a comprehensive analysis of 30 measurement cycles conducted in a "Full RT" environment, where a `PREEMPT_RT` patched Linux kernel is hosted on a Real-Time optimized Virtual Machine. The objective of this configuration is to validate the effectiveness of an end-to-end real-time stack in mitigating virtualization overhead and establishing a strict, deterministic upper bound for execution latency.

### Nominal Performance and Average Latency
The experimental data across all 30 runs indicates unparalleled stability in nominal conditions. Average latency metrics consistently stabilize between 8 µs and 9 µs, with minimum latencies frequently reaching 3 µs to 6 µs. This indicates that the guest kernel is operating with optimal efficiency: when the Virtual CPU (VCPU) is active, the `PREEMPT_RT` patch successfully manages the thread scheduling and interrupt handling with minimal internal jitter, effectively mirroring bare-metal performance for standard task cycles.

### Worst-Case Execution Time (WCET) Analysis
The transition to a Full RT stack demonstrates a significant improvement in worst-case performance compared to the previously tested configurations. While the previous setups were plagued by severe stochastic latency spikes (frequently exceeding 1800 µs and even peaking over 4200 µs), the Full RT stack maintains a much tighter constraint on the Worst-Case Execution Time (WCET). 

Across all 30 runs, the absolute maximum latency recorded was bounded at **448 µs** (observed in Run 11), with the vast majority of the runs maintaining peak latencies well under 150 µs. The "long tail" of the distribution—characteristic of hypervisor-induced preemption—has been effectively neutralized. Although minor outliers persist due to the inherent complexities of virtualized interrupt handling, the system demonstrates a robust ability to remain within deterministic bounds, drastically reducing the frequency and magnitude of scheduling delays.

The majority of test runs exhibit a constrained peak latency, with the "long tail" of the distribution—characteristic of hypervisor-induced preemption—being effectively neutralized. Although minor outliers persist due to the inherent complexities of virtualized interrupt handling, the system demonstrates a robust ability to remain within deterministic bounds, drastically reducing the frequency and magnitude of scheduling delays.

### Conclusions on the Full RT Architecture
The consolidated data from all 30 runs provides conclusive evidence regarding the requirements for deterministic virtualization:

1.  **End-to-End Determinism:** Achieving hard real-time guarantees is an end-to-end property. The optimization of the Guest kernel (`PREEMPT_RT`) is necessary to minimize internal jitter, but it is insufficient without a Real-Time optimized Host to prevent hypervisor-induced preemption of the VCPUs.
2.  **Mitigation of Virtualization Overhead:** By synchronizing the scheduling policies between the Guest and the Host, we effectively eliminate "steal time," allowing the Guest OS to maintain consistent scheduling intervals.
3.  **Viability for Critical Systems:** This "Full RT" configuration establishes a predictable WCET, proving that with proper infrastructure tuning, virtualized environments can reliably support safety-critical control applications that previously required dedicated bare-metal hardware.

The absence of prolonged latency spikes in the Full RT stack confirms its viability as a production-grade architecture for real-time systems.