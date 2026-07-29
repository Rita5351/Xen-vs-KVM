# Xen
This section describes the detailed procedure to configure a consistent test cycle for the virtual machine. The system allows accessing the system with SSH and running the `cyclictest` utility to evaluate scheduling latency.

### 1. Accessing Dom0 via SSH
To launch a shell on the Dom0 administrative domain, a remote connection was established from a secondary machine. This approach allows for the remote execution of commands as if operating locally, which is a necessary step since in our setup the system running the Xen hypervisor lacked a Graphical User Interface (GUI).

#### Step 1.1: Establishing the remote connection
Execute the following command to access Dom0 from the secondary machine:

```bash
ssh unina@192.168.1.166
```

#### Step 1.2: Guest domain creation
Subsequently, a guest virtual machine (DomU) was initialized based on the configuration specified during the setup phase by executing the following command:

```bash
sudo xl create -c /etc/xen/ubuntu-24.04-linux-6.18.35.conf
```

#### Step 1.3: Executing the cyclictest utility
Finally, the `cyclictest` tool was executed to measure system latency, employing the identical parameters previously defined for the KVM testing environment:

```bash
sudo cyclictest --mlockall --priority=99 --threads=1 --affinity=1 --interval=50 --duration 5m -H 1000 --histfile="results_ll_rt.log"
```
## BASELINE PERFORMANCE ANALYSIS WITH CREDIT2 SCHEDULER

This section presents a detailed analysis of execution latencies measured within a virtualized environment based on the Xen bare-metal (Type-1) hypervisor. The primary objective is to evaluate the system's behavior and the virtualization overhead utilizing the default general-purpose scheduler, Credit2. This establishes a fundamental performance baseline before exploring more restrictive static configurations, such as vCPU pinning or the adoption of the NULL scheduler.

To quantify response times, the jitter interval, and the Worst-Case Execution Time (WCET), the `cyclictest` tool was employed through continuous 5-minute executions. The investigation explores the impact on system determinism and stability by cross-referencing four different kernel combinations between the privileged control domain (Dom0) and the unprivileged user domain (DomU):

*   **Non-Real-Time (NRT) Dom0 and NRT DomU:** to measure standard system behavior in the total absence of real-time optimizations.
*   **Non-Real-Time (NRT) Dom0 and Real-Time (RT) DomU:** to evaluate the effectiveness of internal scheduling optimizations within the DomU when the system relies on a non-deterministic control domain.
*   **Low Latency (LL) Dom0 and Non-Real-Time (NRT) DomU:** to analyze the impact of a latency-optimized Dom0 on the performance and preemption spikes of a standard DomU.
*   **Low Latency (LL) Dom0 and Real-Time (RT) DomU:** to observe the maximum level of temporal predictability achievable operating with the most responsive kernels, while maintaining the dynamic infrastructure of the Credit2 scheduler.

The analyses in the following paragraphs offer a comprehensive overview of the limitations of fair-share scheduling and the effectiveness of the various kernels in mitigating latency spikes within their respective domains.

![Baseline Performance - Credit2 Scheduler (No Noise)](tests/plots/svg/xen_nonoise.svg)

### NON-REAL-TIME KERNEL AND NON-REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. The objective of this analysis is to evaluate the baseline latency, virtualization overhead, and scheduling patterns provided by Xen's general-purpose scheduler during a sustained workload.

#### Nominal Performance and Average Latency
The data collected reveals a noticeable baseline overhead introduced by the virtualization layer. The average latency remained stable at 32 µs throughout the test duration. While the absolute minimum latency recorded was 3 µs, the results demonstrate a wide variance in nominal execution times. Unlike highly optimized deterministic systems, the Credit2 scheduler tends to produce a broad spread of execution latencies.

#### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) indicates that the Credit2 scheduler provides a reasonably bounded execution environment, though it does not appear strictly deterministic. Over the 5-minute continuous test, the absolute maximum latency recorded was 369 µs. The data shows that while longer delays can occur, the system generally manages to avoid the catastrophic, multi-millisecond preemption spikes often seen in entirely unoptimized environments.

#### Observations on the Xen Credit2 Environment
The empirical observation of this sustained test provides initial insights into the behavior of the Xen hypervisor when using the Credit2 scheduler:

* **Bounded but Variable Latency:** The system bounded the WCET to 369 µs, which suggests that Credit2 can limit unbounded latency starvation to a certain extent.
* **Average Jitter:** The average latency of 32 µs and the broad spread of execution times highlight the inherent jitter introduced by fair-share scheduling algorithms.
* **Suitability:** This configuration appears capable of handling general-purpose workloads. However, the 369 µs peak suggests that further configuration might be needed if stricter real-time constraints are required.


### NON-REAL-TIME KERNEL AND REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. The configuration features a standard (Non-Real-Time) Linux Dom0 and a `PREEMPT_RT` patched DomU. The objective is to observe how effectively the guest's internal scheduling can manage execution times despite the privileged domain having a general-purpose scheduler.

#### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead heavily influences average execution times. The average latency recorded was 33 µs. While the absolute minimum latency was low at just 3 µs, the data continues to show a broad spread of overall execution times.

#### Worst-Case Execution Time (WCET) Analysis
Despite the average jitter introduced by the hypervisor, the analysis of the Worst-Case Execution Time (WCET) demonstrates improved stability at the upper bounds. Over the entire 5-minute sustained test, the absolute maximum latency was capped at 74 µs. This indicates that the system avoided the more severe preemption spikes typically found in unoptimized environments.

#### Observations on the Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the behaviour of the RT DomU with a Non-RT Dom0 and the Credit2 scheduler:

* **Bounded WCET:** By capping the absolute maximum latency at 74 µs, the `PREEMPT_RT` guest kernel showed potential in establishing a more predictable upper bound.
* **Hypervisor-Induced Jitter:** The average latency of 33 µs and the wide variance of nominal samples suggest that the Credit2 scheduler introduces inherent jitter that guest-side optimizations cannot entirely remove.
* **Internal Determinism:** In this hybrid configuration, the guest-level real-time optimizations appeared to help maintain tighter temporal constraints, offering a potential solution for applications sensitive to large latency spikes.

### LOW LATENCY KERNEL AND NON-REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. For this specific test, the Dom0 operating system was configured with a "Low Latency" kernel while the DomU maintained a Non-Real-Time (NRT) kernel, to evaluate the effects of a modified Dom0 on the latency of the other guests.

#### Nominal Performance and Average Latency
The data collected confirms the consistent baseline behavior of the Xen Credit2 scheduler. The average latency remained at 32 µs throughout the entire 5-minute test. The absolute minimum latency achieved was 3 µs. Similar to previous Credit2 tests, there is a broad spread of nominal execution times.

#### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) suggests tangible benefits from the baseline configuration. Over the sustained execution, the absolute maximum latency was bounded at 152 µs. This result indicates that the low-latency optimizations within the Dom0 likely helped mitigate severe preemption spikes. While the maximum peak of 152 µs is higher than what a patched RT kernel of the DomU might achieve, it indicates an improved stability provided by a low-latency Dom0.

#### Observations on the Low Latency Xen Environment
The empirical observation of this sustained test provides insights into the capabilities of a Low Latency Dom0 running with a NRT DomU and Credit2:

* **Predictable Upper Bounds:** The Low Latency kernel tuning bounded the WCET to 152 µs during the test.
* **Persistent Hypervisor Jitter:** The average latency of 32 µs and the broad spread of nominal samples confirm that the hypervisor's scheduler likely dictates the baseline jitter.
* **Suitability:** This configuration presents a potential middle-ground, appearing to offer improved predictability compared to a standard kernel without the complexity of maintaining a full `PREEMPT_RT` patch.

### LOW LATENCY KERNEL AND REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. This specific configuration features a Low Latency kernel Dom0 and a Real-Time DomU.

#### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead continues to influence average execution times. The average latency recorded was 32 µs. While the absolute minimum latency was 3 µs, the recorded cycles completed across a wide band of times. This variance is characteristic of the Xen Credit2 scheduler, which is designed to optimize for workload fairness rather than microsecond-level precision.

#### Worst-Case Execution Time (WCET) Analysis
Despite the general average jitter, the analysis of the Worst-Case Execution Time (WCET) demonstrates stability at the upper limits. Over the entire 5-minute sustained test, the absolute maximum latency was capped at 71 µs. This indicates an absence of the severe preemption delays that typically affect standard virtual environments, suggesting that the guest OS optimizations effectively managed internal critical sections.

#### Observations on the Low Latency RT Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the behaviour of a RT DomU with a Low Latency Dom0 and the Credit2 scheduler:

* **Bounded WCET:** By capping the absolute maximum latency at 71 µs, the guest kernel appeared highly effective at establishing a deterministic upper bound.
* **Hypervisor-Induced Jitter:** The average latency of 32 µs confirms that the Credit2 scheduler introduces inherent, unavoidable jitter.
* **Effective Internal Determinism:** The guest-level optimizations seemed sufficient to maintain relatively tight temporal constraints, avoiding large latency spikes despite the general-purpose hypervisor layer.

## Impact of the Stress Workload on Latencies

To evaluate system robustness and trigger potentially higher latencies, the testing methodology involves introducing an additional load, defined as a "stress workload". In the case of the Xen hypervisor, this stress workload is executed in the background within the privileged Dom0, utilizing the general-purpose `SCHED_OTHER` scheduling policy alongside the default Credit2 scheduler. 

Experimental analysis has shown that adding this load to Dom0 does not produce a linear degradation of performance; rather, it reveals complex behaviors that depend strictly on the type of guest kernel and the virtualization technology employed:

* **Persistent Virtualization Overhead:** Across every tested configuration, the average latency remains rigidly fixed at 35 µs. This demonstrates that the Xen hypervisor and the Credit2 scheduler introduce an inherent, structural baseline jitter that cannot be bypassed by domain-level kernel optimizations alone.
* **Efficacy of Guest-Level Real-Time Optimizations:** Equipping the DomU with a Real-Time kernel successfully shields its critical sections, even when the system is under stress. Regardless of whether Dom0 is standard or optimized, an RT DomU consistently limits the Worst-Case Execution Time, capping maximum preemption spikes at 177 µs and 209 µs, respectively.
* **Anomalous Impact of Low Latency Dom0 Tuning:** Modifying the Dom0 does not universally improve system determinism. Surprisingly, pairing a Low Latency Dom0 with a standard Non-Real-Time DomU yielded the poorest predictability of the test suite, resulting in severe latency spikes up to 526 µs. This indicates that Dom0 tuning without corresponding DomU optimization does not actually improve worst-case response times.

In this section, we reproduce these stress experiments and analyze the detailed results to quantify the determinism achievable under the Credit2 scheduler.

![Performance under Stress Workload - Credit2 Scheduler](tests/plots/svg/xen_backgroundnoise.svg)
 
### NON-REAL-TIME HOST KERNEL AND NON-REAL-TIME GUEST KERNEL (CREDIT2 SCHEDULER)
 
This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. The objective of this analysis is to evaluate the baseline latency, virtualization overhead, and scheduling patterns provided by Xen's general-purpose scheduler during a sustained workload.
 
#### Nominal Performance and Average Latency

The data collected reveals a noticeable baseline overhead introduced by the virtualization layer. The average latency remained stable at 35 µs throughout the test duration. While the absolute minimum latency recorded was 3 µs, the results demonstrate a wide variance in nominal execution times. Unlike highly optimized deterministic systems, the Credit2 scheduler tends to produce a broad spread of execution latencies.
 
#### Worst-Case Execution Time (WCET) Analysis

The analysis of the Worst-Case Execution Time (WCET) indicates that the Credit2 scheduler provides a reasonably bounded execution environment, though it does not appear strictly deterministic. Over the 5-minute continuous test, the absolute maximum latency recorded was 239 µs. The data shows that while longer delays can occur, the system generally manages to avoid the catastrophic, multi-millisecond preemption spikes often seen in entirely unoptimized environments.
 
#### Observations on the Xen Credit2 Environment

The empirical observation of this sustained test provides initial insights into the behavior of the Xen hypervisor when using the Credit2 scheduler:
 
* **Bounded but Variable Latency:** The system bounded the WCET to 239 µs, which suggests that Credit2 can limit unbounded latency starvation to a certain extent.

* **Average Jitter:** The average latency of 35 µs and the broad spread of execution times highlight the inherent jitter introduced by fair-share scheduling algorithms.

* **Suitability:** This configuration appears capable of handling general-purpose workloads. However, the 239 µs peak suggests that further configuration might be needed if stricter real-time constraints are required.


### NON-REAL-TIME HOST KERNEL AND REAL-TIME GUEST KERNEL (CREDIT2 SCHEDULER)
 
This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. The configuration features a standard (Non-Real-Time) Linux Dom0 and a `PREEMPT_RT` patched DomU. The objective is to observe how effectively the guest's internal scheduling can manage execution times despite the privileged domain having a general-purpose scheduler.
 
#### Nominal Performance and Average Latency

The data collected reveals that the baseline virtualization overhead heavily influences average execution times. The average latency recorded was 35 µs. While the absolute minimum latency was low at just 3 µs, the data continues to show a broad spread of overall execution times.
 
#### Worst-Case Execution Time (WCET) Analysis

Despite the average jitter introduced by the hypervisor, the analysis of the Worst-Case Execution Time (WCET) demonstrates improved stability at the upper bounds compared to a pure NRT setup. Over the entire 5-minute sustained test, the absolute maximum latency was capped at 177 µs. This indicates that the system avoided the more severe preemption spikes typically found in entirely unoptimized environments.
 
#### Observations on the Hybrid Xen Environment

The empirical observation of this sustained test provides insights into the behaviour of the RT DomU with a Non-RT Dom0 and the Credit2 scheduler:
 
* **Bounded WCET:** By capping the absolute maximum latency at 177 µs, the `PREEMPT_RT` guest kernel showed potential in establishing a more predictable upper bound.

* **Hypervisor-Induced Jitter:** The average latency of 35 µs and the wide variance of nominal samples suggest that the Credit2 scheduler introduces inherent jitter that guest-side optimizations cannot entirely remove.

* **Internal Determinism:** In this hybrid configuration, the guest-level real-time optimizations appeared to help maintain tighter temporal constraints, offering a potential solution for applications sensitive to large latency spikes.
 
### LOW LATENCY HOST KERNEL AND NON-REAL-TIME GUEST KERNEL (CREDIT2 SCHEDULER)
 
This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. For this specific test, the Dom0 operating system was configured with a "Low Latency" kernel while the DomU maintained a Non-Real-Time (NRT) kernel, to evaluate the effects of a modified Dom0 on the latency of the other guests.
 
#### Nominal Performance and Average Latency

The data collected confirms the consistent baseline behavior of the Xen Credit2 scheduler. The average latency remained at 35 µs throughout the entire 5-minute test. The absolute minimum latency achieved was 3 µs. Similar to previous Credit2 tests, there is a broad spread of nominal execution times.
 
#### Worst-Case Execution Time (WCET) Analysis

The analysis of the Worst-Case Execution Time (WCET) highlights significant deviations from expected stability. Over the sustained execution, the absolute maximum latency spiked to 526 µs. This result indicates that low-latency optimizations within Dom0, when paired with an NRT DomU, can occasionally introduce severe preemption delays far exceeding the standard NRT baseline.
 
#### Observations on the Low Latency Xen Environment

The empirical observation of this sustained test provides insights into the capabilities of a Low Latency Dom0 running with a NRT DomU and Credit2:
 
* **Variable Upper Bounds:** The Low Latency kernel tuning resulted in a bounded WCET of 526 µs during the test, revealing notable latency spikes.

* **Persistent Hypervisor Jitter:** The average latency of 35 µs and the broad spread of nominal samples confirm that the hypervisor's scheduler likely dictates the baseline jitter.

* **Suitability:** This configuration introduces unpredictable maximum latencies, suggesting that a Low Latency Dom0 without a corresponding RT guest may negatively impact worst-case response times.
 
### LOW LATENCY HOST KERNEL AND REAL-TIME GUEST KERNEL (CREDIT2 SCHEDULER)
 
This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. This specific configuration features a Low Latency kernel Dom0 and a Real-Time DomU.
 
#### Nominal Performance and Average Latency

The data collected reveals that the baseline virtualization overhead continues to influence average execution times. The average latency recorded was 35 µs. While the absolute minimum latency was 3 µs, the recorded cycles completed across a wide band of times. This variance is characteristic of the Xen Credit2 scheduler, which is designed to optimize for workload fairness rather than microsecond-level precision.
 
#### Worst-Case Execution Time (WCET) Analysis

Despite the general average jitter, the analysis of the Worst-Case Execution Time (WCET) demonstrates relative stability at the upper limits. Over the entire 5-minute sustained test, the absolute maximum latency was capped at 209 µs. This indicates that while guest OS optimizations managed internal critical sections, hypervisor-level delays still persist.
 
#### Observations on the Low Latency RT Hybrid Xen Environment

The empirical observation of this sustained test provides insights into the behaviour of a RT DomU with a Low Latency Dom0 and the Credit2 scheduler:
 
* **Bounded WCET:** By capping the absolute maximum latency at 209 µs, the guest kernel managed to reign in the severe spikes seen in the NRT guest configuration.

* **Hypervisor-Induced Jitter:** The average latency of 35 µs confirms that the Credit2 scheduler introduces inherent, unavoidable jitter.

* **Effective Internal Determinism:** The guest-level optimizations seemed sufficient to maintain temporal constraints within a 209 µs window, managing large latency spikes despite the general-purpose hypervisor layer.
 
## BASELINE PERFORMANCE ANALYSIS WITH STATIC vCPU PINNING

This section advances the performance investigation by introducing a static configuration utilizing virtual CPU (vCPU) pinning. During previous evaluations, the introduction of a background stress workload in Dom0 resulted in a significant degradation of Xen execution latencies. This prompted a targeted investigation to determine whether these high latencies were a fundamental issue caused by the hypervisor scheduler or if they stemmed from the Device Model being preempted by the stress workload. 

To isolate the root cause, this phase reproduces the experimental methodology outlined in the 2019 study by Abeni and Faggioli, aiming to verify the behavior of these specific components across newer versions of the hypervisor. Building upon the baseline established in the previous section, this phase evaluates the impact of strictly isolating workloads. By restricting vCPU migration and pinning domains to dedicated physical cores, this approach mitigates the inherent jitter of dynamic scheduling and serves as a practical alternative to deploying the NULL scheduler.

Maintaining the established testing methodology, `cyclictest` is executed across the same four combinations of non-deterministic (NRT) and optimized (Low Latency/`PREEMPT_RT`) kernels for both the privileged control domain (Dom0) and the unprivileged user domain (DomU). The following analyses aim to quantify the extent to which static hardware allocation can mitigate the Worst-Case Execution Times (WCET) and stabilize the average latency observed during stress workloads, ultimately confirming whether the Device Model or the scheduler dictates the severe latency spikes.

### Emulating the Null Scheduler via Static vCPU Pinning

Following the initial performance analyses with the default Xen configuration, an attempt was made to replace the Credit2 scheduler with the Null Scheduler to evaluate a purely static, offline scheduling approach. However, this reconfiguration proved unsuccessful. The deployed Xen hypervisor rejected the modification, defaulting back to the Credit2 scheduler despite the explicit inclusion of the Null Scheduler boot parameters. Furthermore, subsequent attempts to dynamically construct a dedicated CPU-POOL at runtime resulted in system errors. This limitation is likely attributable to the experimental status of the Null Scheduler in Xen version 4.17.3, rendering it unavailable or unsupported within the specific software stack utilized for this study.

To circumvent this hypervisor limitation and achieve an operational state strictly equivalent to an offline scheduler, a rigid static configuration was implemented. This methodology involved explicitly reducing the number of virtual CPUs (vCPUs) allocated to the privileged domain (Dom0) and enforcing strict vCPU-to-pCPU pinning. Concurrently, the exact number of vCPUs assigned to the guest domain (DomU) was fixed and equally pinned to dedicated physical cores. 

By enforcing this absolute isolation, the active scheduling algorithms are entirely bypassed in practice. The hypervisor's decision-making process is minimized, effectively restricting it to statically mapping tasks to their exclusively designated physical CPUs, thereby mimicking the exact deterministic behavior expected from the Null Scheduler. Some other latent effects, such as some residual latency, may still be present, caused by the way the Credit2 scheduler is implemented.

![Baseline Performance - Static vCPU Pinning/Null Scheduler (No Noise)](tests/plots/svg/xen_null_nonoise.svg)

### NON-REAL-TIME KERNEL AND NON-REAL-TIME VM (NULL SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the Null scheduler. The objective of this analysis is to evaluate the baseline latency, virtualization overhead, and scheduling patterns provided by Xen's static, dedicated CPU allocation scheduler during a sustained workload.

#### Nominal Performance and Average Latency
The data collected reveals a noticeable baseline overhead introduced by the virtualization layer. The average latency remained stable at 32 µs throughout the test duration. While the absolute minimum latency recorded was 3 µs, the results demonstrate a wide variance in nominal execution times.

#### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) indicates that the Null scheduler provides a far more strictly bounded execution environment compared to general-purpose algorithms. Over the 5-minute continuous test, the absolute maximum latency recorded was bounded at 179 µs. The data shows that by avoiding complex fair-share preemption, the system completely avoids catastrophic, multi-millisecond preemption spikes.

#### Observations on the Xen Null Environment
The empirical observation of this sustained test provides insights into the behavior of the Xen hypervisor when using the Null scheduler:

* **Improved Upper Bound:** The system bounded the WCET to 179 µs, which demonstrates that the static resource allocation of the Null scheduler significantly reduces unbounded latency starvation.
* **Average Jitter:** The average latency of 32 µs highlights that the baseline virtualization jitter remains, despite the absence of a dynamic scheduling algorithm.
* **Suitability:** This configuration demonstrates much better predictability for latency-sensitive tasks than standard schedulers, offering a much lower peak latency.

### NON-REAL-TIME KERNEL AND REAL-TIME VM (NULL SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the Null scheduler. The configuration features a standard (Non-Real-Time) Linux Dom0 and a `PREEMPT_RT` patched DomU. The objective is to observe how effectively the guest's internal scheduling can manage execution times when provided with a dedicated, non-preempted virtual CPU by the hypervisor.

#### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead heavily influences average execution times. The average latency recorded was 33 µs. The absolute minimum latency achieved was very low at just 3 µs.

#### Worst-Case Execution Time (WCET) Analysis
Despite the average jitter introduced by the hypervisor, the analysis of the Worst-Case Execution Time (WCET) demonstrates excellent stability at the upper bounds. Over the entire 5-minute sustained test, the absolute maximum latency was capped at 65 µs. This indicates that the system avoided preemption spikes and handled critical sections with high determinism.

#### Observations on the Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the behaviour of the RT DomU with a Non-RT Dom0 and the Null scheduler:

* **Bounded WCET:** By tightly capping the absolute maximum latency at 65 µs, the `PREEMPT_RT` guest kernel showed high effectiveness in establishing a highly predictable upper bound.
* **Hypervisor-Induced Jitter:** The average latency of 33 µs suggests that the inherent virtualization layer jitter cannot be entirely removed by guest-side optimizations.
* **Internal Determinism:** In this hybrid configuration, the guest-level real-time optimizations successfully maintained strict temporal constraints, heavily benefiting from the static CPU assignment of the Null scheduler.

### LOW LATENCY KERNEL AND NON-REAL-TIME VM (NULL SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the Null scheduler. For this specific test, the Dom0 operating system was configured with a "Low Latency" kernel while the DomU maintained a Non-Real-Time (NRT) kernel, to evaluate the effects of a modified Dom0 on guest latencies.

#### Nominal Performance and Average Latency
The data collected confirms the consistent baseline behavior of the Xen infrastructure. The average latency remained at 32 µs throughout the entire 5-minute test. The absolute minimum latency achieved was 3 µs. 

#### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) suggests tangible benefits from this configuration. Over the sustained execution, the absolute maximum latency was bounded at 137 µs. This result indicates that the low-latency optimizations within the Dom0, paired with the Null scheduler, helped to further mitigate severe preemption spikes compared to a standard Dom0 kernel.

#### Observations on the Low Latency Xen Environment
The empirical observation of this sustained test provides insights into the capabilities of a Low Latency Dom0 running with a NRT DomU and the Null scheduler:

* **Predictable Upper Bounds:** The Low Latency kernel tuning bounded the WCET to 137 µs during the test.
* **Persistent Hypervisor Jitter:** The average latency of 32 µs confirms that the baseline virtualization overhead dictates the nominal jitter.
* **Suitability:** This configuration presents a solid improvement in maximum latency over the strictly NRT environment (reducing the peak from 179 µs down to 137 µs), offering enhanced predictability without patching the guest.

### LOW LATENCY KERNEL AND REAL-TIME VM (NULL SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the Null scheduler. This specific configuration features a Low Latency kernel Dom0 and a Real-Time (`PREEMPT_RT`) DomU.

#### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead continues to define the average execution times. The average latency recorded was 32 µs. The absolute minimum latency was recorded at 3 µs. 

#### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) demonstrates immense stability at the upper limits. Over the entire 5-minute sustained test, the absolute maximum latency was strictly capped at 67 µs. This indicates a complete absence of the severe preemption delays that typically affect standard virtual environments.

#### Observations on the Low Latency RT Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the behaviour of a RT DomU with a Low Latency Dom0 and the Null scheduler:

* **Bounded WCET:** By capping the absolute maximum latency at 67 µs, the guest kernel proved highly effective at establishing a deterministic upper bound when isolated on a dedicated virtual CPU.
* **Hypervisor-Induced Jitter:** The consistent average latency of 32 µs confirms that the underlying virtualization architecture introduces inherent, unavoidable jitter.
* **Effective Internal Determinism:** The guest-level optimizations are sufficient to maintain extremely tight temporal constraints. The maximum latency performance remains robust and stable, mirroring the results achieved with a standard Dom0 (67 µs versus 65 µs).

## Impact of the Stress Workload on Latencies with vCPU PINNING

To evaluate system determinism and upper latency bounds under severe conditions, the testing methodology involves executing a continuous 5-minute `cyclictest` probe while introducing a background stress workload within the privileged control domain, Dom0. Across all experiments, the Xen hypervisor is configured with static vCPU pinning—acting as a Null scheduler—to restrict vCPU migration and provide dedicated physical cores to the unprivileged domain, DomU.

Experimental analysis demonstrates that while isolating resources via static pinning establishes a baseline of predictability, the system's Worst-Case Execution Time (WCET) is not uniform; rather, it reveals behaviors that depend strictly on the specific combination of kernel optimizations applied across the domains:

* **Efficacy of DomU Real-Time Patches:** Applying `PREEMPT_RT` patches to the DomU drastically reduces maximum latency spikes, even when the control domain is under stress. While an unoptimized DomU suffers from stress-induced delays peaking at 443 µs, an RT-optimized DomU successfully shields its critical sections, capping the WCET to 76 µs even when paired with an unoptimized Dom0.
* **Impact of Dom0 Kernel Tuning:** The kernel configuration of the control domain plays a vital role in mitigating severe preemption events. Upgrading Dom0 to a Low Latency kernel significantly improves overall system bounds, cutting the maximum latency for a standard DomU by more than half (from 443 µs to 179 µs) and pushing an RT DomU to the tightest recorded bound of 65 µs.
* **Persistent Virtualization Overhead:** Despite the dramatic improvements in maximum latency achieved through kernel patches and core pinning, the average latency remains rigidly fixed at approximately 32–33 µs across every tested configuration. This phenomenon indicates that the baseline jitter introduced by the Xen hypervisor layer is a structural constant that cannot be bypassed by domain-level scheduling optimizations alone.

In this section, we will analyze the detailed results of these specific configurations to quantify the determinism and virtualization overhead achievable in a statically pinned Xen architecture.

![Performance under Stress - Static Pinning (Default QEMU Priority)](tests/plots/svg/xen_null_backgroundnoise.svg)

### NON-REAL-TIME KERNEL AND NON-REAL-TIME VM (NULL SCHEDULER)
 
This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the static pinning configuration acting as a Null scheduler. The configuration features a standard (Non-Real-Time) Linux Dom0 and a Non-Real-Time DomU. The objective of this analysis is to evaluate the latency and virtualization overhead under stress conditions when both domains lack real-time optimizations.
 
#### Nominal Performance and Average Latency
The data collected reveals a noticeable baseline overhead introduced by the virtualization layer. The average latency remained stable at 32 µs throughout the test duration. While the absolute minimum latency recorded was 3 µs, the results demonstrate a variance in nominal execution times.
 
#### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) indicates that static vCPU pinning provides a more bounded execution environment compared to dynamic scheduling. Over the 5-minute continuous test, the absolute maximum latency recorded was bounded at 443 µs. Although this value represents a peak due to the `stressdom0` workload on an unoptimized kernel, the system manages to avoid the catastrophic, multi-millisecond preemption spikes often seen in entirely unpinned, dynamic environments.
 
#### Observations on the Xen Pinned Environment
The empirical observation of this sustained test provides insights into the behavior of the Xen hypervisor with static pinning:
* **Bounded but Elevated Latency:** The system bounded the WCET to 443 µs, indicating that while pinning restricts vCPU migration, the unoptimized Dom0 under stress still incurs significant delays.
* **Average Jitter:** The average latency of 32 µs highlights the inherent jitter introduced by the hypervisor layer itself.
* **Suitability:** This configuration limits unbounded latency starvation, but the 443 µs peak suggests it is insufficient for strict real-time constraints under heavy workloads.
 
### NON-REAL-TIME KERNEL AND REAL-TIME VM (NULL SCHEDULER)
 
This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool utilizing static vCPU pinning. The configuration features a standard (Non-Real-Time) Linux Dom0 and a `PREEMPT_RT` patched DomU. The objective is to observe how effectively the DomU's internal scheduling can manage execution times when provided with a dedicated physical core, despite the control domain lacking real-time optimizations and operating under stress.
 
#### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead heavily influences average execution times. The average latency recorded was 33 µs. The absolute minimum latency achieved was very low at just 3 µs.
 
#### Worst-Case Execution Time (WCET) Analysis
Despite the average jitter introduced by the hypervisor, the analysis of the Worst-Case Execution Time (WCET) demonstrates excellent stability at the upper bounds. Over the entire 5-minute sustained test, the absolute maximum latency was strictly capped at 76 µs. This indicates that the combination of DomU optimizations and static pinning successfully shielded the critical sections from the stress workload affecting Dom0.
 
#### Observations on the Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the behaviour of the RT DomU with a Non-RT Dom0 and static pinning:
* **Bounded WCET:** By tightly capping the absolute maximum latency at 76 µs, the `PREEMPT_RT` DomU kernel showed high effectiveness in establishing a highly predictable upper bound.
* **Hypervisor-Induced Jitter:** The average latency of 33 µs suggests that the inherent virtualization layer jitter cannot be entirely removed by DomU-side optimizations alone.
* **Internal Determinism:** In this hybrid configuration, the DomU-level real-time optimizations successfully maintained strict temporal constraints, heavily benefiting from the dedicated physical CPU assignment.
 
### LOW LATENCY KERNEL AND NON-REAL-TIME VM (NULL SCHEDULER)
 
This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool utilizing static vCPU pinning. For this specific test, the Dom0 operating system was configured with a Low Latency kernel while the DomU maintained a Non-Real-Time (NRT) kernel, evaluating the effects of a modified Dom0 on DomU latencies under stress.
 
#### Nominal Performance and Average Latency
The data collected confirms the consistent baseline behavior of the Xen infrastructure. The average latency remained at 32 µs throughout the entire 5-minute test. The absolute minimum latency achieved was 3 µs.
 
#### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) suggests tangible benefits from this configuration. Over the sustained execution, the absolute maximum latency was bounded at 179 µs. This result indicates that the low-latency optimizations within the Dom0, paired with static pinning, helped to significantly mitigate severe preemption spikes compared to a standard Dom0 kernel (reducing the peak from 443 µs to 179 µs).
 
#### Observations on the Low Latency Xen Environment
The empirical observation of this sustained test provides insights into the capabilities of a Low Latency Dom0 running with a NRT DomU and static pinning:
* **Predictable Upper Bounds:** The Low Latency kernel tuning bounded the WCET to 179 µs during the test.
* **Persistent Hypervisor Jitter:** The average latency of 32 µs confirms that the baseline virtualization overhead dictates the nominal jitter.
* **Suitability:** This configuration presents a solid improvement in maximum latency over the strictly NRT environment, offering enhanced predictability without requiring a fully patched RT DomU.
 
### LOW LATENCY KERNEL AND REAL-TIME VM (NULL SCHEDULER)
 
This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing static vCPU pinning. This specific configuration features a Low Latency kernel Dom0 and a Real-Time (`PREEMPT_RT`) DomU, evaluated under stress conditions.
 
#### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead continues to define the average execution times. The average latency recorded was 33 µs. The absolute minimum latency was recorded at 3 µs.
 
#### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) demonstrates immense stability at the upper limits. Over the entire 5-minute sustained test, the absolute maximum latency was strictly capped at 65 µs. This indicates a complete absence of the severe preemption delays that typically affect standard virtual environments, representing the most optimized bounding in this test suite.
 
#### Observations on the Low Latency RT Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the behaviour of a RT DomU with a Low Latency Dom0 and static pinning:
* **Bounded WCET:** By capping the absolute maximum latency at 65 µs, the DomU kernel proved highly effective at establishing a deterministic upper bound when isolated on a dedicated physical core.
* **Hypervisor-Induced Jitter:** The consistent average latency of 33 µs confirms that the underlying virtualization architecture introduces inherent, unavoidable jitter, irrespective of kernel patches.
* **Effective Internal Determinism:** The DomU-level optimizations, combined with the Low Latency Dom0, are sufficient to maintain extremely tight temporal constraints, providing robust and stable maximum latency performance.


## Analysis of Device Model priority inversion in modern Xen

In earlier research evaluating the real-time capabilities of hypervisors, a notable priority inversion issue was identified within the Xen architecture. The problem stems from the architectural dependency of Hardware Virtual Machine (HVM) guests on the Device Model. In Xen, when creating an HVM guest that requires a Device Model, this model is typically an instance of QEMU that executes as a standard process inside Domain 0 (Dom0). Because Dom0 is scheduled alongside other virtual machines by the hypervisor, a low-privilege QEMU process on Dom0 could be preempted when Dom0 is placed under heavy computational stress. Consequently, a Real-Time (RT) DomU waiting for the QEMU Device Model could suffer from unbounded latency, compromising its real-time execution guarantees.

To investigate whether this architectural bottleneck persists in modern versions of Xen, a series of experiments were conducted. The objective is to determine if elevating the QEMU process to a maximum Real-Time priority (FIFO scheduler with priority 99) mitigates preemption and improves the latency bounds of the DomU compared to the default Xen configuration.

To reproduce and analyze the aforementioned priority inversion on a modern Xen version, the environment was configured with strict resource partitioning.

* **CPU Pinning**: Dom0 was pinned to the first 22 physical CPUs (pCPUs), while the Hardware Virtual Machine (HVM) DomU was pinned to the last 2 pCPUs.
* **Host Stress**: To simulate heavy load and induce potential starvation in Dom0, stress-ng was executed with the following parameters:
  ```bash
  stress-ng --cpu 22 --vm 12 --vm-bytes 2G --timeout 10m
  ```
* **Kernel Configurations**: Tests were run across the usual four permutations of Dom0 and DomU kernels.
* **QEMU Priority Mitigation**: For each kernel combination, a baseline test (default QEMU priority) was compared against a mitigated test (`maxprioqemu`), wherein the QEMU Device Model process in Dom0 was explicitly set to the `SCHED_FIFO` policy with a priority of 99.

![Performance under Stress - Credit2 Scheduler (Max QEMU Priority)](tests/plots/svg/xen_null_backgroundnoise_maxprioqemu.svg)


### Empirical Results

A thorough data analysis of the provided cyclictest histograms reveals the following key findings:

* **Absence of Priority Inversion Spikes**: In older versions of Xen suffering from the QEMU starvation issue, the expected symptom would be a pronounced "heavy tail" in the histogram, indicating extreme, unbounded latencies where the DomU was blocked waiting for Dom0. The empirical data across all results_null_hvm_pinned_* logs demonstrates no such extreme outliers in the default priority configurations.
* **Latency Distribution Parity**: The latency distributions between the default configurations and their mitigated counterparts are virtually identical.
* **Consistent Upper Bounds**: The maximum recorded latencies (Worst-Case Execution Time) in the standard configurations are directly comparable to those in the maximum priority configurations. Across both the Low-Latency (LL) and Non-Real-Time (NRT) Dom0 environments, elevating QEMU's priority did not tighten the worst-case temporal bounds.

Based on the experimental data, the priority inversion problem previously documented in Section 6.2 of the Abeni and Faggioli research seems to be non-existent in this modern Xen deployment. Changing the Device Model priority yields no beneficial effect for the latency bounds of real-time tasks inside the DomU.

With further experiments, we confirmed that changing the priority of the QEMU process does not improve latency even when using the Credit2 scheduler.

![Performance under Stress - Static Pinning (Max QEMU Priority)](tests/plots/svg/xen_backgroundnoise_maxprioqemu.svg)

This behavior indicates that modern Xen HVM implementations successfully decouple essential local timer and interrupt deliveries from the QEMU Device Model. Because CPU-bound real-time workloads (like cyclictest) primarily exercise timer wakeups rather than complex I/O, the DomU can accurately maintain its temporal constraints utilizing hardware virtualization extensions alone. Therefore, manually elevating the priority of the Dom0 QEMU process is unnecessary for maintaining real-time determinism in contemporary Xen environments.

---
Following the detailed analysis of each individual scenario, the table below provides a consolidated overview of the Worst-Case Execution Time (WCET) measurements. It allows for a direct comparison across all four Dom0-DomU kernel configurations (**NRT-NRT**, **NRT-RT**, **LL-NRT**, and **LL-RT**) under the four tested scheduling and load conditions: standard dynamic execution (**BASELINE**), execution under heavy system load within Dom0 (**STRESS WORKLOAD**), execution with static core isolation (**vCPU PINNING BASELINE**), and isolated execution under heavy load (**vCPU PINNING STRESS WORKLOAD**).

| Configurazione | NRT-NRT | NRT-RT | LL-NRT | LL-RT |
|---|---|---|---|---|
| **BASELINE** | 369 | 74 | 152 | 71 |
| **STRESS WORLOAD** | 239 | 177 | 526 | 209 |
| **vCPU PINNING BASELINE** | 137 | 67 | 179 | 65 |
| **vCPU PINNING STRESS WORKLOAD** | 443 | 76 | 410 | 163 |

## TACLe Benchmark

This section of the documentation illustrates the rationale behind the selection of the benchmarks extracted from the **TACLeBench** version 1.9 suite and the methodology adopted for their execution within our architecture. The goal is to provide a heterogeneous workload to accurately validate execution latencies and performance stability in environments with strict real-time requirements.

### 1. Benchmark Selection

We selected a representative program for each of the main TACLeBench categories, ensuring optimal coverage of the different execution patterns.

* **Kernel Benchmark (`matrix1`):** Isolates the most computationally intensive portions of code to evaluate raw CPU performance and cache efficiency.
* **Sequential Benchmark (`huff_enc`):** Evaluates sequential processing and memory access patterns. Data compression (325 SLOC, David Bourgin) is excellent for measuring latency variations in single-threaded execution.
* **Test Benchmark (`test3`):** An artificial stress test for WCET (Worst-Case Execution Time, 4235 SLOC, Universität des Saarlandes) analysis. It pushes the execution engine to its limits to measure time safety margins and system robustness.
* **Parallel Benchmark (`Debie`):** Aerospace observation tool (6615 SLOC, Tidorum Ltd) consisting of 8 tasks. Essential for testing synchronization mechanisms and preemption in multi-tasking scenarios.
* **Application Benchmark (`lift`):** An elevator controller (361 SLOC, Martin Schoeberl). Verifies that the latency metrics from synthetic tests guarantee stability in a real cyber-physical control application.

### 2. Execution Methodology and Test Scenarios

To rigorously analyze the system's behavior and the impact of the virtualization architecture, **all 5 selected benchmarks were executed on the LL-RT (Low-Latency Dom0, Real-Time DomU) configuration**.

For each benchmark, we defined a test matrix composed of four operational scenarios. In all baseline configurations, **4 vCPUs were assigned to Dom0**. The analyzed variables concern the introduction of a stress load (noise) of varying size originating from another DomU and the application of vCPU pinning (crucial for avoiding context migrations and stabilizing latencies).

To ensure strict real-time conditions and accurate latency measurements, the execution procedure was carefully standardized across all test scenarios. The process involved specific compilation flags, scheduler modifications, and rigid execution parameters designed to eliminate typical operating system interference.

**Compilation and Preparation**
Each of the benchmarks were modified to support automatically changing scheduling priority and repeated executions (the source code is available in this repository). We then compiled them using `-O2` optimizations and linked with the necessary POSIX real-time and threading libraries:

```bash
gcc -O2 -o test3 test3.c -lpthread -lrt

```

**Benchmark Execution Parameters**
The TACLe benchmarks were executed via the command line with a strict set of arguments to maintain deterministic behavior. The fundamental flags applied across the tests included:

* `--mlockall`: Locks the process's memory pages directly into RAM, preventing any unpredictable latency spikes caused by page faults or disk swapping.
* `--priority=99`: Enforces the highest real-time priority internally for the benchmark's execution thread.
* `--affinity=1`: Applies CPU pinning, locking the execution strictly to CPU core 1. This is a critical step to prevent costly context migrations across different processor cores.

Below are the exact execution commands utilized for the targeted benchmarks:

```bash
# Executing test3 (pseudo-cyclictest) for 10,000 loops and outputting a latency histogram
sudo ./test3 --mlockall --priority=99 --affinity=1 --loops=10000 --histogram=1000000 --histfile=results/results_test3_baseline.log
```

**Noise Generation Strategy**
To evaluate the architectural robustness and jitter expansion during the noisy scenarios, interference was artificially injected into the system. This was achieved using `stress-ng` to spawn multiple aggressive workers, intentionally taxing the CPU cores and the virtual memory subsystem to simulate severe cache thrashing and scheduling pressure:

```bash
stress-ng --cpu 16 --vm 16 --vm-bytes 1G --timeout 10m

```

**Domain configuration**
To clearly understand the extent of the interference of a different DomU stress workload on the critical guest, we designed two test scenarios:

* **Small Noise**: a small DomU with just 2 vCPUs and 4 GB of RAM. This would introduce a small amount of noise, thus testing if at least some isolation is provided.
* **Big Noise**: a more beefy DomU configuration with 16 vCPUs and 16 GB of RAM. In this case, the interference introduced is more severe, pushing the limits of the isolation mechanism.
* **Big Noise with pinning**: the same of the previous setup but with added static vCPU pinning. This would determine how much the scheduling algorithm affects the isolation of the domains.

### TACLeBench Baseline Execution Analysis

Establishing this baseline is a critical first step for comparing the determinism and worst-case execution time (WCET) latencies, a Type 1 hypervisor utilizing Dom0 and DomU architectures. The following analysis evaluates the raw execution logs to quantify system determinism before introducing vCPU pinning.

#### Baseline Latency Summary

| Benchmark | Total Loops | Min Latency (μs) | Avg Latency (μs) | Max Latency (μs) | Absolute Jitter (Max - Min) |
| --- | --- | --- | --- | --- | --- |
| **DEBIE** | 10,000 | 23,921 | 27,175 | 31,048 | 7,127 μs |
| **huffenc** | 1,000,000 | 15 | 16 | 35 | 20 μs |
| **lift** | 1,000,000 | 19 | 19 | 85 | 66 μs |
| **matrix1** | 1,000,000 | 0 | 0 | 9 | 9 μs |
| **test3** | 10,000 | 8,286 | 8,328 | 8,414 | 128 μs |

#### Workload-Specific Behavior

**DEBIE**

* The DEBIE benchmark represents the heaviest and most unpredictable workload in the dataset, with a massive spread between the minimum (23,921 µs) and maximum (31,048 µs) execution times.
* The absolute jitter of over 7 milliseconds indicates significant preemption, cache misses, or scheduling overhead during execution.
* This high variability makes DEBIE an excellent candidate for stress-testing how well future DomU or virtualized configurations handle long-running, computationally complex real-time tasks.

**Huffenc**

* The `huffenc` benchmark represents a short-lived task executed 1,000,000 times.
* It shows excellent stability with an average latency of 16 µs and a worst-case peak of 35 µs.
* The absolute jitter is strictly bounded at 20 µs, derived from a minimum latency of 15 µs.

**Lift**

* The `lift` benchmark exhibits highly deterministic behavior on this baseline, with the average latency (19 µs) sitting exactly on the minimum latency (19 µs) across one million loops.
* The maximum latency peak of 85 µs represents a rare outlier.
* The vast majority of executions cluster tightly at 19-20 µs, showing that the unisolated baseline scheduler handles this specific workload with high predictability.

**Matrix1**

* The `matrix1` execution is extremely lightweight, registering a 0 µs average latency, which indicates that standard execution times fall below the microsecond resolution threshold of the testing configuration.
* The absolute worst-case execution time caps at just 9 µs.
* Because this benchmark is practically instantaneous, it is almost entirely cache-bound and will be highly sensitive to hypervisor memory management disruptions.

**Test3**

* The `test3` benchmark represents a heavier execution profile containing 10,000 loops, an average latency of 8,328 µs, and a maximum of 8,414 µs.
* The tighter jitter (128 µs) relative to its extended execution time suggests a steady computational loop that is less affected by micro-interruptions compared to the highly variable DEBIE benchmark.

#### Real-Time Systems Assessment

This baseline demonstrates a standard, unisolated environment where lightweight tasks (`matrix1`, `lift`, `huffenc`) execute with near-perfect determinism, while heavier tasks (`DEBIE`) suffer from severe scheduling jitter. The outliers observed in `lift` (85 µs) and `huffenc` (35 µs) are the specific OS noise artifacts that isolation mechanisms aim to eliminate. When transferring these workloads to virtualized setups, tracking the expansion of these maximum latency tails will directly quantify the scheduling interference introduced by the virtualization layer.

### TACLeBench Small Noise Execution Analysis

This phase of testing evaluates the determinism and worst-case execution time (WCET) latencies of KVM and Xen (a Type 1 hypervisor utilizing Dom0 and DomU architectures) under a "Small Noise" configuration. The following analysis interprets the execution logs to quantify how minor system disturbances impact the predictability of the hypervisor scheduling.

#### Small Noise Latency Summary

| Benchmark | Total Loops | Min Latency (μs) | Avg Latency (μs) | Max Latency (μs) | Absolute Jitter (Max - Min) |
| --- | --- | --- | --- | --- | --- |
| **DEBIE** | 10,000 | 23,873 | 27,118 | 31,022 | 7,149 μs |
| **huffenc** | 1,000,000 | 15 | 16 | 35 | 20 μs |
| **lift** | 1,000,000 | 19 | 19 | 36 | 17 μs |
| **matrix1** | 1,000,000 | 0 | 0 | 8 | 8 μs |
| **test3** | 10,000 | 8,286 | 8,331 | 8,885 | 599 μs |

#### Workload-Specific Behavior

**DEBIE**

* The DEBIE benchmark remains the heaviest workload, with execution times ranging from a minimum of 23,873 µs to a maximum of 31,022 µs.
* The absolute jitter sits at 7,149 µs, confirming its high sensitivity to preemption and scheduling overhead even in a small noise environment.

**Huffenc**

* The `huffenc` benchmark shows excellent stability across 1,000,000 iterations.
* With an average latency of 16 µs and a worst-case peak of 35 µs, the absolute jitter remains tightly bounded at 20 µs.

**Lift**

* Under the small noise configuration, the `lift` benchmark exhibits highly deterministic behavior, maintaining an average latency of 19 µs.
* The maximum latency peak is only 36 µs, representing a noticeably tighter jitter (17 µs) compared to the unisolated baseline.

**Matrix1**

* The `matrix1` execution remains extremely lightweight and cache-bound, registering a 0 µs average latency.
* The absolute worst-case execution time is capped at an exceptionally low 8 µs.

**Test3**

* The `test3` benchmark executed 10,000 loops with an average latency of 8,331 µs.
* The maximum latency reached 8,885 µs, pushing the absolute jitter to 599 µs. The jitter expansion here is heavily influenced by specific micro-interruptions captured during the run.

#### Real-Time Systems Assessment

Evaluating the small noise scenario reveals that lightweight and highly repetitive tasks (`matrix1`, `lift`, `huffenc`) can maintain extreme determinism, with jitter boundaries narrowing significantly (such as `lift` dropping to a 36 µs max peak). Heavier workloads like `DEBIE` continue to exhibit substantial variance. 

### TACLeBench Big Noise Execution Analysis

This phase of the evaluation investigates the determinism and worst-case execution time (WCET) latencies of a Xen DomU in the presence of another, big-sized DomU affected by significant stress workload. The following analysis examines the execution logs to quantify how significant system disturbances and heavy background noise degrade the predictability of the scheduler prior to applying isolation techniques.

#### Big Noise Latency Summary

| Benchmark | Total Loops | Min Latency (μs) | Avg Latency (μs) | Max Latency (μs) | Absolute Jitter (Max - Min) |
| --- | --- | --- | --- | --- | --- |
| **DEBIE** | 10,000 | 24,627 | 28,196 | 57,314 | 32,687 μs |
| **huffenc** | 1,000,000 | 15 | 19 | 182 | 167 μs |
| **lift** | 1,000,000 | 17 | 20 | 142 | 125 μs |
| **matrix1** | 1,000,000 | 0 | 0 | 45 | 45 μs |
| **test3** | 10,000 | 8,287 | 9,182 | 14,786 | 6,499 μs |

#### Workload-Specific Behavior

**DEBIE**

* Under heavy noise, the DEBIE benchmark suffers massive scheduling disruptions, pushing the worst-case execution time to 57,314 µs.

* The absolute jitter explodes to 32,687 µs, meaning the variance in execution time is larger than the minimum latency itself (24,627 µs).

**Huffenc**

* While the `huffenc` task maintains a relatively stable average latency of 19 µs, the maximum latency spikes dramatically to 182 µs.

* This results in an absolute jitter of 167 µs, showing that even high-frequency, short-lived tasks are heavily preempted in a noisy environment.

**Lift**

* The `lift` benchmark's determinism breaks down under the big noise configuration, expanding to a maximum latency of 142 µs.

* Compared to previous baselines, the average latency rises slightly to 20 µs, but the 125 µs absolute jitter indicates substantial scheduling delays.

**Matrix1**

* Although the average latency remains at 0 µs due to the task's cache-bound, lightweight nature, the maximum latency expands to 45 µs.

* An absolute jitter of 45 µs on a task that typically executes instantaneously highlights severe micro-interruptions and cache thrashing induced by the noise.

**Test3**

* The `test3` benchmark registers an average latency of 9,182 µs and a severe worst-case peak of 14,786 µs.

* The absolute jitter jumps to 6,499 µs, derived from a minimum execution time of 8,287 µs, proving that medium-weight computational loops cannot maintain steady execution states when sharing unisolated CPU resources with heavy noise.

#### Real-Time Systems Assessment

The results of these tests effectively demonstrates the catastrophic loss of determinism across all workloads while the system is under stress because of another DomU. Even ultra-lightweight tasks like `matrix1` and `lift` experience significant latency spikes, while heavy tasks like `DEBIE` become entirely unpredictable. This demostrates the ineffectiveness of the isolation boundaries of the native Xen architecture.

### TACLeBench Big Noise Pinned Execution Analysis

This phase of the evaluation investigates the determinism and worst-case execution time (WCET) latencies of a Xen DomU in the presence of another, big-sized DomU affected by significant stress workload. Because of the poor performance of the unpinned configuration, exhibiting excessively high latencies, CPU pinning was introduced to restrain the interference. The following analysis examines the execution logs to quantify how this pinning mitigates system disturbances.

#### Big Noise Pinned Latency Summary

| Benchmark | Total Loops | Min Latency (μs) | Avg Latency (μs) | Max Latency (μs) | Absolute Jitter (Max - Min) |
| --- | --- | --- | --- | --- | --- |
| **DEBIE** | 10,000 | 24,034 | 27,274 | 41,266 | 17,232 μs |
| **huffenc** | 1,000,000 | 15 | 16 | 42 | 27 μs |
| **lift** | 1,000,000 | 19 | 19 | 43 | 24 μs |
| **matrix1** | 1,000,000 | 0 | 0 | 11 | 11 μs |
| **test3** | 10,000 | 8,632 | 8,701 | 10,037 | 1,405 μs |

#### Workload-Specific Behavior

**DEBIE**

* The DEBIE benchmark ranges from a minimum of 24,034 µs to a maximum of 41,266 µs.
* Pinning the execution restrains the absolute jitter to 17,232 µs, which is a massive improvement over the unpinned big noise scenario, though it remains sensitive to preemption.

**Huffenc**

* The `huffenc` task executes with an average latency of 16 µs and a peak maximum latency of 42 µs.
* CPU pinning effectively bounds the absolute jitter at 27 µs, restoring a high degree of stability to this lightweight loop.

**Lift**

* Under the pinned configuration, the `lift` benchmark regains strict determinism, maintaining an average latency of 19 µs.
* The maximum latency reaches only 43 µs, yielding a tight absolute jitter of 24 µs.

**Matrix1**

* The `matrix1` execution is almost perfectly insulated by the pinning, maintaining a 0 µs average latency and an absolute worst-case execution time of just 11 µs.
* This 11 µs absolute jitter confirms that cache thrashing and severe scheduling interruptions are heavily mitigated.

**Test3**

* The `test3` benchmark registers an average latency of 8,701 µs and a worst-case peak of 10,037 µs.
* With an absolute jitter of 1,405 µs, this computational loop shows a massive recovery in predictability compared to the unpinned execution.

#### Real-Time Systems Assessment

The "Big Noise Pinned" baseline demonstrates the critical importance of CPU pinning when operating in highly congested environments. By binding tasks to specific cores, the hypervisor scheduler prevents the catastrophic latency spikes observed in the unpinned tests. Lightweight tasks (`matrix1`, `lift`, `huffenc`) return to near-baseline determinism, and heavier workloads (`DEBIE`, `test3`) see their jitter margins compressed significantly.


### Max Latency Summary (μs)
To quickly evaluate system stability, the following table exclusively reports the peak values (**Max Latency**). This format allows for an at-a-glance comparison of the Worst-Case Execution Time across the four operational scenarios, directly highlighting the impact of noise and the effectiveness of CPU pinning in containing interference.

| Benchmark | Baseline | Small Noise | Big Noise | Big Noise Pinned |
| --- | --- | --- | --- | --- |
| **DEBIE** | 31,048 | 31,022 | 57,314 | 41,266 |
| **huffenc** | 35 | 35 | 182 | 42 |
| **lift** | 85 | 36 | 142 | 43 |
| **matrix1** | 9 | 8 | 45 | 11 |
| **test3** | 8,414 | 8,885 | 14,786 | 10,037 |

## PV and PVH DomUs

In their previous work, Abeni and Faggioli concluded that in Xen, virtualization technology played a major role in scheduling latencies due to a priority inversion bug in how the Device Model operated. Specifically, they noted that the QEMU process acting as the DomU DM did not execute with high priority, allowing it to be preempted by the workload.

We previously attempted to reproduce this issue using a newer version of Xen (4.17.3) but did not observe the same trend. We also tried assigning maximum priority to the QEMU process in Dom0, which yielded no noticeable improvement. Consequently, we concluded that this priority inversion bug has been fixed for HVM DomUs.

To further verify this conclusion, we extended our analysis to PV and PVH guests. In this section, we reproduce the most relevant scenarios for guests running on these different virtualization technologies and analyze their resulting behaviors.

### PV DomU and RT Kernel

While configuring the PV guest, we encountered the same issue observed during the [initial setup process](../Setup/README.md#problems-with-preempt_rt). This time, because the output logs were routed to the terminal, we were able to identify the cause. The logs revealed a **soft CPU lockup**, confirming that the issue stemmed from the `PREEMPT_RT` patch. We hypothesize that this failure relates to how the patch modifies low-level mechanisms—such as replacing spinlocks with mutexes—which introduces compatibility issues with paravirtualization. This also explains why the `PREEMPT_RT` patch failed in Dom0, as it is inherently a PV guest. Additionally, we attempted to configure Dom0 as a PVH guest; however, this setup resulted in continuous automatic reboots. Without access to system logs or graphical output to diagnose the root cause, we were unable to troubleshoot the error and ultimately abandoned this configuration. Consequently, for the subsequent tests, we replaced the RT kernel with the Low-Latency kernel in the DomU as well.

![Comparing HVM, PV and PVH guests - Credit2 Scheduler (No Noise)](tests_pv_pvh/plots/svg/xen_guesttypecompare_nonoise.svg)

### LOW LATENCY KERNEL AND REAL-TIME VM (PV DomU)

TODO: ADD

### LOW LATENCY KERNEL AND REAL-TIME VM (PVH DomU)
 
This section analyzes the results obtained from a 5-minute execution of the `cyclictest` utility within a Xen virtualized environment, explicitly assessing a PVH guest. The configuration features a "Low Latency" kernel deployed on the privileged domain (Dom0) and a Real-Time (`PREEMPT_RT`) kernel on the unprivileged user domain (DomU). This test evaluates the baseline performance of the dynamic Credit2 scheduler without static vCPU pinning and without any artificial stress workload applied to Dom0.
 
#### Nominal Performance and Average Latency
The data obtained from the `cyclictest` execution reveals the baseline virtualization overhead and scheduling behavior in an undisturbed, unpinned configuration. The average latency recorded during the test was 32 µs. The absolute minimum latency achieved was 3 µs. The histogram data indicates a broad distribution of execution latencies, demonstrating the variability introduced by dynamic scheduling even in the absence of host-level contention.
 
#### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) provides insight into the system's baseline ability to bound execution delays. Over the duration of the test, the absolute maximum latency recorded was 76 µs. The system successfully avoided any histogram overflows.
 
#### Observations on the Baseline PVH Unpinned Environment
The empirical data collected from this test yields the following observations regarding the behavior of the RT PVH DomU running on a Low Latency Dom0 without vCPU pinning in a quiet environment:
 
*   **Bounded WCET:** The maximum latency was contained at 76 µs, indicating that the combination of the RT guest kernel and the Low Latency host kernel provides a stable upper bound when the host is not under load.
*   **Baseline Jitter:** The average latency of 32 µs and the wide spread of nominal execution times confirm the presence of significant scheduling jitter. This variability highlights the inherent impact of the dynamic Credit2 hypervisor scheduler, even without resource contention from a `stressdom0` workload.

## Impact of the Stress Workload on Different Virtualization Technologies (TODO: REVIEW)

To assess the influence of the underlying virtualization architecture on system determinism, this phase of testing introduces a background stress workload in the privileged domain (Dom0) while executing the `cyclictest` probe within PV and PVH guests. Building upon our earlier findings—which demonstrated that modern Hardware Virtual Machine (HVM) configurations successfully manage latency bounds without suffering from historical QEMU-induced preemption anomalies—this evaluation aims to compare how alternative virtualization models respond to resource contention.

Experimental analysis reveals that moving away from full hardware virtualization fundamentally alters the system dynamics, highlighting key architectural trade-offs when employing PV and PVH configurations:

* **Absence of the Device Model:** Unlike HVM guests, PV and PVH architectures do not rely on a QEMU instance running in Dom0 for hardware emulation. While our previous tests confirmed that modern Xen deployments resolve the historical priority inversion bugs associated with QEMU, evaluating PV and PVH guests allows us to observe system behavior completely isolated from Device Model interactions.
* **Constraints on Kernel Optimization:** While paravirtualization removes the Device Model variable, it introduces strict constraints regarding real-time optimizations. As established during the initial setup, the inherent incompatibility of the `PREEMPT_RT` patch with PV guests necessitated a fallback to a Low Latency kernel. This dynamic fundamentally shifts the performance bottleneck from hypervisor-level interference to guest-level scheduling limitations.
* **Comparative Resilience to Contention:** Evaluating these paravirtualized environments under Dom0 stress provides a direct contrast to the HVM data. Without the ability to deploy a fully preemptible RT kernel in a PV DomU, these tests reveal whether the intrinsically lighter virtualization footprint of PV and PVH architectures can compensate for the lack of rigorous, real-time guest optimizations.

In this section, we present a detailed comparative analysis of these configurations, quantifying the execution latencies of PV and PVH guests under stress to determine their overall viability for predictable, latency-sensitive applications compared to their HVM counterparts.

![Comparing HVM, PV and PVH guests - Credit2 Scheduler (Backgroung Noise)](tests_pv_pvh/plots/svg/xen_guesttypecompare_backgroundnoise.svg)

### LOW LATENCY KERNEL AND REAL-TIME VM (PV DomU)

TODO: ADD

### LOW LATENCY KERNEL AND REAL-TIME VM (PVH DomU)
 
This section details the analysis of a 5-minute execution of the `cyclictest` utility within a Xen virtualized environment, explicitly assessing a PVH guest. The configuration features a "Low Latency" kernel deployed on the privileged domain (Dom0) and a Real-Time (`PREEMPT_RT`) kernel on the unprivileged user domain (DomU). Crucially, this test was conducted without static vCPU pinning and while Dom0 was subjected to a significant background stress workload. The objective is to evaluate the latency characteristics and virtualization overhead introduced by the hypervisor when managing a PVH guest under these specific, unpinned stress conditions.
 
#### Nominal Performance and Average Latency
The data obtained from the `cyclictest` execution reveals the baseline virtualization overhead and scheduling jitter inherent in this unpinned configuration. The average latency recorded during the test was 35 µs. The absolute minimum latency achieved was 3 µs. The histogram data indicates a broad distribution of execution latencies, demonstrating the variability introduced when dynamic scheduling is utilized under host-level contention.
 
#### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) provides insight into the system's ability to bound execution delays under stress. Over the duration of the test, the absolute maximum latency recorded was 157 µs. Furthermore, the system successfully avoided any histogram overflows.
 
#### Observations on the PVH Unpinned Environment
The empirical data collected from this sustained test yields the following observations regarding the behavior of the RT PVH DomU running on a Low Latency Dom0 without vCPU pinning:
 
*   **Bounded WCET:** The maximum latency was contained at 157 µs, indicating that the combination of the RT guest kernel and the Low Latency host kernel provided a degree of stability, preventing the extreme, multi-millisecond spikes that can occur in less optimized configurations.
*   **Hypervisor-Induced Jitter:** The average latency of 35 µs and the wide spread of nominal execution times confirm the presence of significant scheduling jitter. This variability highlights the impact of dynamic hypervisor scheduling and resource contention from the `stressdom0` workload when vCPUs are not statically pinned to dedicated physical cores.
