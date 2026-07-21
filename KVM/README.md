# KVM
This documentation describes the detailed procedure to configure an automated test at the boot of the virtual machine. The system allows forcing the boot with a specific kernel via GRUB and running `cyclictest` automatically for a single session of 5 minutes, disabling the automation once completed.

## 1. Implementation of the Control and Test Script

The Bash script invokes `cyclictest` for a 5-minute duration, redirects the results to a log file, and disables the service upon completion to prevent execution on subsequent normal boots.

### Step 1.1: Script creation
Create a new executable file in the system path dedicated to local scripts:

```bash
sudo nano /usr/local/bin/run_cyclictest.sh
```

### Step 1.2: Script code (`run_cyclictest.sh`)
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

### Step 1.3: Assign execution permissions
Configure the correct POSIX permissions to allow systemd to invoke the script:

```bash
sudo chmod +x /usr/local/bin/run_cyclictest.sh
```

---

## 2. Configuration of the Systemd Unit Service

To ensure the script is executed immediately after the boot phase and in a non-interactive context, a `oneshot` type systemd service is implemented.

### Step 2.1: Unit file creation
Create the service descriptor within the system units directory:

```bash
sudo nano /etc/systemd/system/cyclictest-autorun.service
```

### Step 2.2: Service structure (`cyclictest-autorun.service`)
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

## 3. Enabling and Executing the Flow

Once the components are defined, it is necessary to notify the service manager of the changes and enable the automatic startup of the test.

### Step 3.1: Reload the systemd daemon
```bash
sudo systemctl daemon-reload
```

### Step 3.2: Enable the service at boot
```bash
sudo systemctl enable cyclictest-autorun.service
```

### Step 3.3: Triggering the test
To start the automated 5-minute test, perform a manual reboot of the KVM virtual machine:

```bash
sudo reboot
```

After the system boots, it will wait 30 seconds and then run the test for exactly 5 minutes. At the end of the process, the results will be available in `/var/log/cyclictest_results/results_hist.log`, the service will automatically disable itself, and the system will remain stably booted on the set kernel.

## BASELINE PERFORMANCE ANALYSIS IN KVM ENVIRONMENTS

This section presents a detailed analysis of execution latencies measured within a virtualized environment based on the Kernel-based Virtual Machine (KVM) hypervisor. The primary objective is to establish a performance baseline and evaluate the system's behavior, determinism, and virtualization overhead under standard scheduling policies before introducing more advanced or restrictive tuning configurations.

To quantify response times, internal jitter, and the Worst-Case Execution Time (WCET), the `cyclictest` tool was employed through continuous 5-minute baseline executions. The investigation explores the impact on system stability and temporal predictability by cross-referencing four distinct kernel combinations between the underlying Host infrastructure and the Guest virtual machine:

* **Non-Real-Time (NRT) Host and Non-Real-Time (NRT) Guest:** to measure standard system behavior and baseline virtualization overhead in the total absence of real-time optimizations.
* **Non-Real-Time (NRT) Host and Real-Time (RT) Guest:** to evaluate the effectiveness of internal scheduling optimizations within the guest when the underlying hypervisor lacks deterministic guarantees.
* **Real-Time (RT) Host and Non-Real-Time (NRT) Guest:** to analyze the impact of a determinism-optimized host on the performance, preemption spikes, and overall execution stability of a standard, general-purpose guest.
* **Real-Time (RT) Host and Real-Time (RT) Guest (Full RT Stack):** to observe the maximum level of temporal predictability achievable by aligning both the host infrastructure and the guest operating system with the `PREEMPT_RT` patch.

The analyses in the following paragraphs offer a comprehensive overview of the latency profiles characteristic of each configuration, detailing the limitations of general-purpose environments and validating the effectiveness of an end-to-end real-time stack for mitigating virtualization overhead.

![Baseline Performance - KVM ](tests/plot/svg/kvm_nonoise.svg)

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

## Impact of the Stress Workload on Latencies

To evaluate system robustness and trigger potentially higher latencies, the testing methodology involves introducing an additional load, defined as a "stress workload." In the case of the KVM hypervisor, this stress workload is executed in the background directly on the Host operating system, simulating heavy external contention that competes for CPU time and system resources.

Experimental analysis of the KVM infrastructure reveals that adding this background load produces severe performance degradation across the board. Unlike the complex, configuration-dependent behaviors observed in other hypervisors, the stress workload on KVM exposes fundamental architectural vulnerabilities in maintaining determinism:

* **Catastrophic Failure in Unoptimized and Hybrid Stacks:** Introducing host-level stress immediately shatters the determinism of standard and hybrid configurations. Whether using a fully Non-Real-Time (NRT) stack or attempting partial optimization (an RT Guest on an NRT Host, or an NRT Guest on an RT Host), the system experiences catastrophic scheduling delays. Maximum latencies in these configurations routinely spike between 44 and 51 milliseconds, indicating massive host-induced starvation and lock contention.
* **The Illusion of Guest-Only Optimization:** Counter-intuitively, equipping the Guest with a Real-Time kernel while the Host remains NRT yielded the highest variability and the worst absolute latency spikes (over 51 milliseconds) of the dataset. This proves that an optimized guest scheduler is entirely powerless to protect time-sensitive threads if the underlying Host hypervisor is vulnerable to non-deterministic preemption.
* **Chronic Instability of the Full RT Stack:** Even when utilizing an end-to-end "Full RT" stack (RT Host and RT Guest) with optimal prioritization parameters, the KVM environment fails to guarantee strict real-time bounds under stress. While the Full RT stack successfully suppresses the catastrophic 50-millisecond delays (bounding the absolute maximum latency to approximately 9.8 milliseconds), it suffers from a massive frequency of significant scheduling stalls, evidenced by hundreds of over-millisecond latency overflows.

In this section, we will present the detailed experiments conducted under these stress conditions and analyze the resulting execution logs.

![Performance under stress workload- KVM at maximum priority](tests/plot/svg/kvm_backgroundnoise.svg)

## NON REAL-TIME HOST AND NON REAL-TIME GUEST -STRESS HOST

This section presents an analysis of the first `cyclictest` execution log conducted on a KVM host under stress conditions. The objective is to evaluate the system's scheduling behavior and latency bounds when subjected to external load.

### Distribution Analysis and Nominal Performance
Analysis of the histogram log reveals that the system maintains a reasonable baseline under stress. Over the test duration, the average latency recorded was 13 µs. The statistical mode (the most frequent latency) was concentrated at 14 µs, with a significant number of cycles also completing at 13 µs. The absolute minimum recorded latency dropped to an impressive 5 µs. This indicates that when the CPU is not actively dealing with stress-induced contention, the base virtualization and scheduling overhead remains low.

### Worst-Case Execution Time (WCET) and Lack of Determinism
The impact of the stress workload becomes severely apparent when analyzing the Worst-Case Execution Time (WCET). The absolute maximum latency recorded during this run was an extreme 44,409 µs (over 44 milliseconds). Furthermore, the log reports 11 histogram overflows (latencies exceeding the 1000 µs tracking threshold). 

### Conclusions
The presence of 44-millisecond latency spikes clearly demonstrates that this environment lacks determinism. Under stress, the host OS experiences massive scheduling delays, likely due to lock contention, non-preemptible critical sections, or starvation of the test threads. This configuration cannot guarantee the strict upper bounds required for real-time applications.

## NON REAL-TIME HOST AND REAL-TIME GUEST -STRESS HOST

This section analyzes the results obtained from the second `cyclictest` execution, also run under stressed conditions on the KVM host infrastructure. 

### Nominal Performance and Average Latency
The nominal performance mirrors the first log closely, confirming a consistent baseline efficiency even under load. The average latency was precisely 13 µs, and the minimum latency was 5 µs. Interestingly, the distribution shows a dual-peak behavior, with the highest concentration at 13 µs (the mode), but with another massive spike of cycles completing at 7 µs.

### Worst-Case Execution Time (WCET) Analysis
This specific execution experienced the highest variability and worst latency spikes of the entire dataset. The absolute maximum latency reached an exorbitant 51,069 µs (over 51 milliseconds). The severity of the instability is further highlighted by the 26 histogram overflows, more than double the number seen in the first log. 

### Conclusions 
The empirical observation of this run conclusively shows that the stress workload induces chaotic, non-deterministic preemption. A 51-millisecond delay represents a catastrophic failure for any safety-critical system. The KVM host in this state is entirely unsuitable for bounded real-time execution, as the scheduler cannot adequately protect time-sensitive threads from background stress.

## REAL-TIME HOST AND NON REAL-TIME GUEST -STRESS HOST

This section examines the third prolonged execution of the `cyclictest` tool on the stressed KVM host environment, validating the patterns observed in previous iterations.

### Nominal Performance and Average Latency
The data collected confirms a stable nominal execution path. The average latency metric remained locked at 13 µs, while the minimum latency reached the lowest point among the first three runs, hitting 3 µs. The histogram shows a massive concentration of execution cycles completing in exactly 13 µs, indicating that when the scheduler is unimpeded, it processes tasks with high consistency.

### Worst-Case Execution Time (WCET) Analysis
Despite the strong nominal performance, the WCET remains unacceptable for real-time standards. The maximum latency peaked at 50,257 µs (over 50 milliseconds). The system registered 11 histogram overflows, indicating multiple occurrences of severe scheduling stalls exceeding one millisecond.

### Conclusions
This run confirms that while the system can occasionally achieve extremely fast task dispatching (3 µs min), it is completely vulnerable to unpredictable, systemic delays. The 50-millisecond peak re-emphasizes that background stress can effectively starve tasks for dozens of milliseconds, a fatal condition for latency-sensitive applications.

## REAL-TIME HOST AND REAL-TIME GUEST -STRESS HOST

This section presents an analysis of the provided `cyclictest` execution log conducted on a KVM environment under stress conditions. The objective is to evaluate the system's scheduling determinism and latency bounds when subjected to external load.

### Distribution Analysis and Nominal Performance
Analysis of the histogram log reveals a highly efficient baseline performance under nominal execution. The statistical mode (the most frequent latency) is sharply concentrated at 7 µs, representing over 1.7 million completed cycles. The average latency metric is remarkably stable at 11 µs, and the absolute minimum recorded latency is exceptionally low at 4 µs. This indicates that most of the time, the virtualization overhead is minimal.

### Worst-Case Execution Time (WCET) Analysis
Despite the excellent average case, the analysis of the Worst-Case Execution Time (WCET) reveals severe scheduling instability induced by the stress workload. The absolute maximum latency recorded reached 9,829 µs (nearly 9.8 milliseconds). Even more critically, the log reports an overwhelming 283 histogram overflows (latencies exceeding the 1000 µs tracking threshold). This represents a massive frequency of significant scheduling stalls compared to typical runs.

### Conclusions
The empirical observation of this execution demonstrates severe latency instability, which is particularly critical given the system's strict configuration. Despite this optimal prioritization, the system still suffered from chronic and significant delays.

These high latencies indicate that the delays are originating from deeper, non-preemptible sources escaping the guest's control. Consequently, this configuration proves that merely applying the maximum scheduler priority is fundamentally insufficient to guarantee the strict, reliable upper bounds required for safety-critical real-time applications.