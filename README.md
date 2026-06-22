# Xen-vs-KVM
Xen vs KVM under Mixed-Criticality Workloads: an  Experimental Characterization

This repo contains the configurations, scripts, raw data, and the final experimental report for the A6 Project on hypervisor characterization.

*DISCLAIMER*: **all configurations, scripts, and isolation setups used in this project are generated for the sole scope of this academic project. They are NOT intended to be deployed in production environments.**

## Course information

Professor: Marcello Cinque

Academic Year: 2025-26

Students: Rita Marino, Matteo Arnese

## Contents

* [Overview](#overview)
* [Tasks and Methodology](#tasks-and-methodology)
  * [1. Baseline Campaign and Reproduction](#1-baseline-campaign-and-reproduction)
  * [2. Guest-type Comparison](#2-guest-type-comparison)
  * [3. Unikraft Unikernels as Alternative Guests](#3-unikraft-unikernels-as-alternative-guests)
* [Required Tools](#required-tools)
* [Reading Material](#reading-material)
* [Repository Structure & Deliverables](#repository-structure--deliverables)

---

## Overview

This project characterizes how the two general-purpose hypervisors covered in the course, **Xen** and **KVM**, behave when used to host mixed-criticality workloads on commodity hardware. 

We designed and ran a measurement campaign on both hypervisors using the same workloads and stressors to quantify the impact of:
* Main isolation mechanisms (vCPU pinning, host-side `isolcpus` / `nohz_full`, IRQ steering, cache and memory-bandwidth partitioning via Intel RDT).
* Guest type selection (HVM, PV, PVH for Xen; full Linux guest vs Unikraft unikernel for both hypervisors).

The experimental analyses of Abeni and Faggioli (2019, 2020) serve as a methodological anchor. This project reproduces their main findings on the current software stack (Linux 6.x, mainline `PREEMPT_RT`, recent Xen, modern Intel/AMD CPUs) and extends the analysis to include real benchmark workloads (TACLe), memory-bandwidth partitioning, and unikernels.

---

## Tasks and Methodology

### 1. Baseline Campaign and Reproduction
* **Setup:** Configured Xen and KVM on the same host with a single Linux guest configuration (vCPUs, memory, `PREEMPT_RT` kernel; HVM for Xen initially).
* **Reproduction:** Replicated key experiments from Abeni & Faggioli (2019, 2020):
  * Executed `cyclictest` in the guest with various host/guest kernel combinations, both with and without a background stress workload (`stress-ng`) in Dom0 / KVM host.
  * Evaluated the effect of the QEMU Device Model priority on Xen HVM (priority-inversion experiment).
  * Analyzed the effect of the Xen scheduler choice (using `null` vs default `Credit` scheduler).
* **Extension:** Ran **TACLe Benchmarks** in a "critical" guest alongside `stress-ng` in a co-located "noisy" guest. 
* **Isolation:** Applied and visualized the effects of vCPU pinning, `isolcpus`, and IRQ steering.

### 2. Guest-type Comparison
* Extended the Xen study to all three guest types: **HVM, PV, and PVH** to measure their dramatic effects on latency.
* Ran the campaign for each isolation method individually and in meaningful combinations to identify which configuration yields the best performance and why.

### 3. Unikraft Unikernels as Alternative Guests
* Built a **Unikraft unikernel** hosting the critical workload (TACLe Benchmarks on Unikraft's minimal scheduler).
* Booted the unikernel as a guest on both KVM and Xen.
* **Comparison:** Evaluated the unikernel against the full Linux `PREEMPT_RT` guest in terms of baseline latency, sensitivity to noisy neighbors, boot time, and resource footprint.

---

## Required Tools

* A development PC with Intel virtualization support (VT-x) and modern RDT features.
* Standard Linux tooling.
* **Hypervisors:** Xen, KVM.
* **Benchmarking & Stress Tools:** `cyclictest`, TACLe Benchmarks, `stress-ng`, `memguard`.
* The Unikraft build environment.

---

## Reading Material

The experimental campaign design is directly compared against the setups detailed in these anchor papers:
* L. Abeni, D. Faggioli, *An Experimental Analysis of the Xen and KVM Latencies*, IEEE ISORC 2019. [DOI: 10.1109/ISORC.2019.00014](https://doi.org/10.1109/ISORC.2019.00014)
* L. Abeni, D. Faggioli, *Using Xen and KVM as real-time hypervisors*, Journal of Systems Architecture, vol. 106, 2020. [DOI: 10.1016/j.sysarc.2020.101709](https://doi.org/10.1016/j.sysarc.2020.101709)
* [Unikraft Documentation](https://unikraft.org/docs)
* Kuenzer et al., *Unikraft: Fast, Specialized Unikernels the Easy Way*, EuroSys 2021.
* M. Cinque, L. De Simone, D. Ottaviano, *Temporal isolation assessment in virtualized safety-critical mixed-criticality systems: A case study on Xen hypervisor*, The Journal of Systems and Software, vol. 216, 112147, 2024. [DOI: 10.1016/j.jss.2024.112147](https://doi.org/10.1016/j.jss.2024.112147)
* L. Abeni, *Virtualized real-time workloads in containers and virtual machines*, Journal of Systems Architecture, vol. 154, 103238, 2024. [DOI: 10.1016/j.sysarc.2024.103238](https://doi.org/10.1016/j.sysarc.2024.103238)
---
