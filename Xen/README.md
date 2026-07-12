# Xen
This documentation describes the detailed procedure to configure an automated test cycle at the boot of the virtual machine. The system allows forcing the boot with a specific kernel via GRUB, running `cyclictest` , and automatically rebooting the machine at the end of each session, disabling the cycle once completed.

### Boot Kernel Configuration on GRUB (One-time)


#### Step 1.1:

#### Step 1.2: 
---

### 2. 

#### Step 2.1: 

#### Step 2.2: 

#### Step 2.3: 
---

### 3. 
#### Step 3.1: 

#### Step 3.2: 

---

### 4. 

#### Step 4.1: 

#### Step 4.2: 
#### Step 4.3: 


## NON REAL-TIME KERNEL NON REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. The objective of this analysis is to evaluate the baseline latency, virtualization overhead, and scheduling patterns provided by Xen's general-purpose scheduler during a sustained workload.

### Nominal Performance and Average Latency
The data collected reveals a noticeable baseline overhead introduced by the virtualization layer. The average latency remained stable at 32 µs throughout the test duration. While the absolute minimum latency recorded was 3 µs, the results demonstrate a wide variance in nominal execution times. Unlike highly optimized deterministic systems, the Credit2 scheduler tends to produce a broad spread of execution latencies.

### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) indicates that the Credit2 scheduler provides a reasonably bounded execution environment, though it does not appear strictly deterministic. Over the 5-minute continuous test, the absolute maximum latency recorded was 369 µs. The data shows that while longer delays can occur, the system generally manages to avoid the catastrophic, multi-millisecond preemption spikes often seen in entirely unoptimized environments.

### Observations on the Xen Credit2 Environment
The empirical observation of this sustained test provides initial insights into the behavior of the Xen hypervisor when using the Credit2 scheduler:

*   **Bounded but Variable Latency:** The system bounded the WCET to 369 µs, which suggests that Credit2 can limit unbounded latency starvation to a certain extent.
*   **Average Jitter:** The average latency of 32 µs and the broad spread of execution times highlight the inherent jitter introduced by fair-share scheduling algorithms.
*   **Suitability:** This configuration appears capable of handling general-purpose workloads. However, the 369 µs peak suggests that further configuration might be needed if stricter real-time constraints are required.

## REAL-TIME KERNEL AND NO REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a hybrid Xen virtualized environment utilizing the default Credit2 scheduler. The configuration features a `PREEMPT_RT` patched Linux Guest hosted on a Standard (Non-Real-Time) Xen Host. The objective is to observe how effectively the guest's internal scheduling can manage execution times when the underlying hypervisor utilizes a general-purpose scheduler.

### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead heavily influences average execution times. The average latency recorded was 33 µs. While the absolute minimum latency was low at just 3 µs, the data continues to show a broad spread of overall execution times.

### Worst-Case Execution Time (WCET) Analysis
Despite the average jitter introduced by the hypervisor, the analysis of the Worst-Case Execution Time (WCET) demonstrates improved stability at the upper bounds. Over the entire 5-minute sustained test, the absolute maximum latency was capped at 74 µs. This indicates that the system avoided the more severe preemption spikes typically found in unoptimized environments.

### Observations on the Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the interaction between an RT Guest and a Non-RT Xen Credit2 Host:

*   **Bounded WCET:** By capping the absolute maximum latency at 74 µs, the `PREEMPT_RT` guest kernel showed potential in establishing a more predictable upper bound.
*   **Hypervisor-Induced Jitter:** The average latency of 33 µs and the wide variance of nominal samples suggest that the Credit2 scheduler introduces inherent jitter that guest-side optimizations cannot entirely remove.
*   **Internal Determinism:** In this hybrid configuration, the guest-level real-time optimizations appeared to help maintain tighter temporal constraints, offering a potential solution for applications sensitive to large latency spikes.

## LOW LATENCY KERNEL AND NON-REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. For this specific test, the Guest operating system was configured with a "Low Latency" Non-Real-Time (NRT) kernel to evaluate its performance under sustained workloads.

### Nominal Performance and Average Latency
The data collected confirms the consistent baseline behavior of the Xen Credit2 scheduler. The average latency remained at 32 µs throughout the entire 5-minute test. The absolute minimum latency achieved was 3 µs. Similar to previous Credit2 tests, there is a broad spread of nominal execution times, highlighting that while the guest is tuned for lower latency, the underlying scheduler still imposes its own balancing logic, resulting in noticeable cycle-to-cycle jitter.

### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) suggests tangible benefits from the "Low Latency" guest kernel tuning. Over the sustained execution, the absolute maximum latency was bounded at 152 µs. This result indicates that the low-latency optimizations within the guest OS likely helped mitigate severe preemption spikes. While the maximum peak of 152 µs is higher than what a fully patched RT kernel might achieve, it indicates a relatively stable upper bound for a non-RT system.

### Observations on the Low Latency Xen Environment
The empirical observation of this sustained test provides insights into the capabilities of a Low Latency NRT Guest running on a Xen Credit2 Host:

*   **Predictable Upper Bounds:** The Low Latency kernel tuning bounded the WCET to 152 µs during the test.
*   **Persistent Hypervisor Jitter:** The average latency of 32 µs and the broad spread of nominal samples confirm that the hypervisor's scheduler likely dictates the baseline jitter.
*   **Suitability:** This configuration presents a potential middle-ground, appearing to offer improved predictability compared to a standard kernel without the complexity of maintaining a full `PREEMPT_RT` patch.

## LOW LATENCY KERNEL AND NON-REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a hybrid Xen virtualized environment utilizing the default Credit2 scheduler. This specific configuration features a "Low Latency RT" Linux Guest hosted on a Standard (Non-Real-Time) Xen Host.

### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead continues to influence average execution times. The average latency recorded was 32 µs. While the absolute minimum latency was 3 µs, the recorded cycles completed across a wide band of times. This variance is characteristic of the Xen Credit2 scheduler, which is designed to optimize for workload fairness rather than microsecond-level precision.

### Worst-Case Execution Time (WCET) Analysis
Despite the general average jitter, the analysis of the Worst-Case Execution Time (WCET) demonstrates stability at the upper limits. Over the entire 5-minute sustained test, the absolute maximum latency was capped at 71 µs. This indicates an absence of the severe preemption delays that typically affect standard virtual environments, suggesting that the guest OS optimizations effectively managed internal critical sections.

### Observations on the Low Latency RT Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the interaction between a Low Latency RT Guest and a Non-RT Xen Credit2 Host:

*   **Bounded WCET:** By capping the absolute maximum latency at 71 µs, the guest kernel appeared highly effective at establishing a deterministic upper bound.
*   **Hypervisor-Induced Jitter:** The average latency of 32 µs confirms that the Credit2 scheduler introduces inherent, unavoidable jitter.
*   **Effective Internal Determinism:** The guest-level optimizations seemed sufficient to maintain relatively tight temporal constraints, avoiding large latency spikes despite the general-purpose hypervisor layer.