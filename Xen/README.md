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


sudo cyclictest --mlockall --priority=99 --threads=1 --affinity=1 --interval=50 --duration 5m -H 1000 --histfile="results_ll_rt.log"
```

## NON-REAL-TIME KERNEL AND NON-REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. The objective of this analysis is to evaluate the baseline latency, virtualization overhead, and scheduling patterns provided by Xen's general-purpose scheduler during a sustained workload.

### Nominal Performance and Average Latency
The data collected reveals a noticeable baseline overhead introduced by the virtualization layer. The average latency remained stable at 32 µs throughout the test duration. While the absolute minimum latency recorded was 3 µs, the results demonstrate a wide variance in nominal execution times. Unlike highly optimized deterministic systems, the Credit2 scheduler tends to produce a broad spread of execution latencies.

### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) indicates that the Credit2 scheduler provides a reasonably bounded execution environment, though it does not appear strictly deterministic. Over the 5-minute continuous test, the absolute maximum latency recorded was 369 µs. The data shows that while longer delays can occur, the system generally manages to avoid the catastrophic, multi-millisecond preemption spikes often seen in entirely unoptimized environments.

### Observations on the Xen Credit2 Environment
The empirical observation of this sustained test provides initial insights into the behavior of the Xen hypervisor when using the Credit2 scheduler:

* **Bounded but Variable Latency:** The system bounded the WCET to 369 µs, which suggests that Credit2 can limit unbounded latency starvation to a certain extent.
* **Average Jitter:** The average latency of 32 µs and the broad spread of execution times highlight the inherent jitter introduced by fair-share scheduling algorithms.
* **Suitability:** This configuration appears capable of handling general-purpose workloads. However, the 369 µs peak suggests that further configuration might be needed if stricter real-time constraints are required.

## NON-REAL-TIME KERNEL AND REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. The configuration features a standard (Non-Real-Time) Linux Dom0 and a `PREEMPT_RT` patched DomU. The objective is to observe how effectively the guest's internal scheduling can manage execution times despite the privileged domain having a general-purpose scheduler.

### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead heavily influences average execution times. The average latency recorded was 33 µs. While the absolute minimum latency was low at just 3 µs, the data continues to show a broad spread of overall execution times.

### Worst-Case Execution Time (WCET) Analysis
Despite the average jitter introduced by the hypervisor, the analysis of the Worst-Case Execution Time (WCET) demonstrates improved stability at the upper bounds. Over the entire 5-minute sustained test, the absolute maximum latency was capped at 74 µs. This indicates that the system avoided the more severe preemption spikes typically found in unoptimized environments.

### Observations on the Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the behaviour of the RT DomU with a Non-RT Dom0 and the Credit2 scheduler:

* **Bounded WCET:** By capping the absolute maximum latency at 74 µs, the `PREEMPT_RT` guest kernel showed potential in establishing a more predictable upper bound.
* **Hypervisor-Induced Jitter:** The average latency of 33 µs and the wide variance of nominal samples suggest that the Credit2 scheduler introduces inherent jitter that guest-side optimizations cannot entirely remove.
* **Internal Determinism:** In this hybrid configuration, the guest-level real-time optimizations appeared to help maintain tighter temporal constraints, offering a potential solution for applications sensitive to large latency spikes.

## LOW LATENCY KERNEL AND NON-REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. For this specific test, the Dom0 operating system was configured with a "Low Latency" kernel while the DomU maintained a Non-Real-Time (NRT) kernel, to evaluate the effects of a modified Dom0 on the latency of the other guests.

### Nominal Performance and Average Latency
The data collected confirms the consistent baseline behavior of the Xen Credit2 scheduler. The average latency remained at 32 µs throughout the entire 5-minute test. The absolute minimum latency achieved was 3 µs. Similar to previous Credit2 tests, there is a broad spread of nominal execution times.

### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) suggests tangible benefits from the baseline configuration. Over the sustained execution, the absolute maximum latency was bounded at 152 µs. This result indicates that the low-latency optimizations within the Dom0 likely helped mitigate severe preemption spikes. While the maximum peak of 152 µs is higher than what a patched RT kernel of the DomU might achieve, it indicates an improved stability provided by a low-latency Dom0.

### Observations on the Low Latency Xen Environment
The empirical observation of this sustained test provides insights into the capabilities of a Low Latency Dom0 running with a NRT DomU and Credit2:

* **Predictable Upper Bounds:** The Low Latency kernel tuning bounded the WCET to 152 µs during the test.
* **Persistent Hypervisor Jitter:** The average latency of 32 µs and the broad spread of nominal samples confirm that the hypervisor's scheduler likely dictates the baseline jitter.
* **Suitability:** This configuration presents a potential middle-ground, appearing to offer improved predictability compared to a standard kernel without the complexity of maintaining a full `PREEMPT_RT` patch.

## LOW LATENCY KERNEL AND REAL-TIME VM (CREDIT2 SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the default Credit2 scheduler. This specific configuration features a Low Latency kernel Dom0 and a Real-Time DomU.

### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead continues to influence average execution times. The average latency recorded was 32 µs. While the absolute minimum latency was 3 µs, the recorded cycles completed across a wide band of times. This variance is characteristic of the Xen Credit2 scheduler, which is designed to optimize for workload fairness rather than microsecond-level precision.

### Worst-Case Execution Time (WCET) Analysis
Despite the general average jitter, the analysis of the Worst-Case Execution Time (WCET) demonstrates stability at the upper limits. Over the entire 5-minute sustained test, the absolute maximum latency was capped at 71 µs. This indicates an absence of the severe preemption delays that typically affect standard virtual environments, suggesting that the guest OS optimizations effectively managed internal critical sections.

### Observations on the Low Latency RT Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the behaviour of a RT DomU with a Low Latency Dom0 and the Credit2 scheduler:

* **Bounded WCET:** By capping the absolute maximum latency at 71 µs, the guest kernel appeared highly effective at establishing a deterministic upper bound.
* **Hypervisor-Induced Jitter:** The average latency of 32 µs confirms that the Credit2 scheduler introduces inherent, unavoidable jitter.
* **Effective Internal Determinism:** The guest-level optimizations seemed sufficient to maintain relatively tight temporal constraints, avoiding large latency spikes despite the general-purpose hypervisor layer.

## Emulating the Null Scheduler via Static vCPU Pinning

Following the initial performance analyses with the default Xen configuration, an attempt was made to replace the Credit2 scheduler with the Null Scheduler to evaluate a purely static, offline scheduling approach. However, this reconfiguration proved unsuccessful. The deployed Xen hypervisor rejected the modification, defaulting back to the Credit2 scheduler despite the explicit inclusion of the Null Scheduler boot parameters. Furthermore, subsequent attempts to dynamically construct a dedicated CPU-POOL at runtime resulted in system errors. This limitation is likely attributable to the experimental status of the Null Scheduler in Xen version 4.17.3, rendering it unavailable or unsupported within the specific software stack utilized for this study.

To circumvent this hypervisor limitation and achieve an operational state strictly equivalent to an offline scheduler, a rigid static configuration was implemented. This methodology involved explicitly reducing the number of virtual CPUs (vCPUs) allocated to the privileged domain (Dom0) and enforcing strict vCPU-to-pCPU pinning. Concurrently, the exact number of vCPUs assigned to the guest domain (DomU) was fixed and equally pinned to dedicated physical cores. 

By enforcing this absolute isolation, the active scheduling algorithms are entirely bypassed in practice. The hypervisor's decision-making process is minimized, effectively restricting it to statically mapping tasks to their exclusively designated physical CPUs, thereby mimicking the exact deterministic behavior expected from the Null Scheduler. Some other latent effects, such as some residual latency, may still be present, caused by the way the Credit2 scheduler is implemented.

## NON-REAL-TIME KERNEL AND NON-REAL-TIME VM (NULL SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the Null scheduler. The objective of this analysis is to evaluate the baseline latency, virtualization overhead, and scheduling patterns provided by Xen's static, dedicated CPU allocation scheduler during a sustained workload.

### Nominal Performance and Average Latency
The data collected reveals a noticeable baseline overhead introduced by the virtualization layer. The average latency remained stable at 32 µs throughout the test duration. While the absolute minimum latency recorded was 3 µs, the results demonstrate a wide variance in nominal execution times.

### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) indicates that the Null scheduler provides a far more strictly bounded execution environment compared to general-purpose algorithms. Over the 5-minute continuous test, the absolute maximum latency recorded was bounded at 179 µs. The data shows that by avoiding complex fair-share preemption, the system completely avoids catastrophic, multi-millisecond preemption spikes.

### Observations on the Xen Null Environment
The empirical observation of this sustained test provides insights into the behavior of the Xen hypervisor when using the Null scheduler:

* **Improved Upper Bound:** The system bounded the WCET to 179 µs, which demonstrates that the static resource allocation of the Null scheduler significantly reduces unbounded latency starvation.
* **Average Jitter:** The average latency of 32 µs highlights that the baseline virtualization jitter remains, despite the absence of a dynamic scheduling algorithm.
* **Suitability:** This configuration demonstrates much better predictability for latency-sensitive tasks than standard schedulers, offering a much lower peak latency.

## NON-REAL-TIME KERNEL AND REAL-TIME VM (NULL SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the Null scheduler. The configuration features a standard (Non-Real-Time) Linux Dom0 and a `PREEMPT_RT` patched DomU. The objective is to observe how effectively the guest's internal scheduling can manage execution times when provided with a dedicated, non-preempted virtual CPU by the hypervisor.

### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead heavily influences average execution times. The average latency recorded was 33 µs. The absolute minimum latency achieved was very low at just 3 µs.

### Worst-Case Execution Time (WCET) Analysis
Despite the average jitter introduced by the hypervisor, the analysis of the Worst-Case Execution Time (WCET) demonstrates excellent stability at the upper bounds. Over the entire 5-minute sustained test, the absolute maximum latency was capped at 65 µs. This indicates that the system avoided preemption spikes and handled critical sections with high determinism.

### Observations on the Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the behaviour of the RT DomU with a Non-RT Dom0 and the Null scheduler:

* **Bounded WCET:** By tightly capping the absolute maximum latency at 65 µs, the `PREEMPT_RT` guest kernel showed high effectiveness in establishing a highly predictable upper bound.
* **Hypervisor-Induced Jitter:** The average latency of 33 µs suggests that the inherent virtualization layer jitter cannot be entirely removed by guest-side optimizations.
* **Internal Determinism:** In this hybrid configuration, the guest-level real-time optimizations successfully maintained strict temporal constraints, heavily benefiting from the static CPU assignment of the Null scheduler.

## LOW LATENCY KERNEL AND NON-REAL-TIME VM (NULL SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the Null scheduler. For this specific test, the Dom0 operating system was configured with a "Low Latency" kernel while the DomU maintained a Non-Real-Time (NRT) kernel, to evaluate the effects of a modified Dom0 on guest latencies.

### Nominal Performance and Average Latency
The data collected confirms the consistent baseline behavior of the Xen infrastructure. The average latency remained at 32 µs throughout the entire 5-minute test. The absolute minimum latency achieved was 3 µs. 

### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) suggests tangible benefits from this configuration. Over the sustained execution, the absolute maximum latency was bounded at 137 µs. This result indicates that the low-latency optimizations within the Dom0, paired with the Null scheduler, helped to further mitigate severe preemption spikes compared to a standard Dom0 kernel.

### Observations on the Low Latency Xen Environment
The empirical observation of this sustained test provides insights into the capabilities of a Low Latency Dom0 running with a NRT DomU and the Null scheduler:

* **Predictable Upper Bounds:** The Low Latency kernel tuning bounded the WCET to 137 µs during the test.
* **Persistent Hypervisor Jitter:** The average latency of 32 µs confirms that the baseline virtualization overhead dictates the nominal jitter.
* **Suitability:** This configuration presents a solid improvement in maximum latency over the strictly NRT environment (reducing the peak from 179 µs down to 137 µs), offering enhanced predictability without patching the guest.

## LOW LATENCY KERNEL AND REAL-TIME VM (NULL SCHEDULER)

This section analyzes the results obtained from a single, prolonged 5-minute execution of the `cyclictest` tool in a Xen virtualized environment utilizing the Null scheduler. This specific configuration features a Low Latency kernel Dom0 and a Real-Time (`PREEMPT_RT`) DomU.

### Nominal Performance and Average Latency
The data collected reveals that the baseline virtualization overhead continues to define the average execution times. The average latency recorded was 32 µs. The absolute minimum latency was recorded at 3 µs. 

### Worst-Case Execution Time (WCET) Analysis
The analysis of the Worst-Case Execution Time (WCET) demonstrates immense stability at the upper limits. Over the entire 5-minute sustained test, the absolute maximum latency was strictly capped at 67 µs. This indicates a complete absence of the severe preemption delays that typically affect standard virtual environments.

### Observations on the Low Latency RT Hybrid Xen Environment
The empirical observation of this sustained test provides insights into the behaviour of a RT DomU with a Low Latency Dom0 and the Null scheduler:

* **Bounded WCET:** By capping the absolute maximum latency at 67 µs, the guest kernel proved highly effective at establishing a deterministic upper bound when isolated on a dedicated virtual CPU.
* **Hypervisor-Induced Jitter:** The consistent average latency of 32 µs confirms that the underlying virtualization architecture introduces inherent, unavoidable jitter.
* **Effective Internal Determinism:** The guest-level optimizations are sufficient to maintain extremely tight temporal constraints. The maximum latency performance remains robust and stable, mirroring the results achieved with a standard Dom0 (67 µs versus 65 µs).

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

## Da rivedere
### Empirical Results

A thorough data analysis of the provided cyclictest histograms reveals the following key findings:

* **Absence of Priority Inversion Spikes**: In older versions of Xen suffering from the QEMU starvation issue, the expected symptom would be a pronounced "heavy tail" in the histogram, indicating extreme, unbounded latencies where the DomU was blocked waiting for Dom0. The empirical data across all results_null_hvm_pinned_* logs demonstrates no such extreme outliers in the default priority configurations.
* **Latency Distribution Parity**: The latency distributions between the default configurations and their mitigated counterparts are virtually identical.
* **Consistent Upper Bounds**: The maximum recorded latencies (Worst-Case Execution Time) in the standard configurations are directly comparable to those in the maximum priority configurations. Across both the Low-Latency (LL) and Non-Real-Time (NRT) Dom0 environments, elevating QEMU's priority did not tighten the worst-case temporal bounds.

Based on the experimental data, the priority inversion problem previously documented in Section 6.2 of the Abeni and Faggioli research seems to be non-existent in this modern Xen deployment. Changing the Device Model priority yields no beneficial effect for the latency bounds of real-time tasks inside the DomU.

This behavior indicates that modern Xen HVM implementations successfully decouple essential local timer and interrupt deliveries from the QEMU Device Model. Because CPU-bound real-time workloads (like cyclictest) primarily exercise timer wakeups rather than complex I/O, the DomU can accurately maintain its temporal constraints utilizing hardware virtualization extensions alone. Therefore, manually elevating the priority of the Dom0 QEMU process is unnecessary for maintaining real-time determinism in contemporary Xen environments.