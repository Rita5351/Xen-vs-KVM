# Setup 
This chapter outlines the complete experimental testbed configuration required to evaluate Xen and KVM under mixed-criticality workloads. To ensure reliable, predictable, and reproducible latency measurements, the host environment must be strictly tailored for real-time execution. 

The following sections detail the step-by-step preparation of the system, starting with the installation and tuning of the host operating system, the compilation of a fully preemptible Linux kernel (`PREEMPT_RT`), and the deployment of the respective hypervisors. We then detail both hypervisors' configuration, focusing on the differences between the two.

## Kernel configuration and real-time tuning

To establish a baseline for our performance comparison, we also required the standard, non-real-time Linux kernel version 6.18.35. 

* First, we downloaded the official kernel source code from the [Linux Kernel Archive](https://cdn.kernel.org/pub/linux/kernel/).
* We extracted the archive using the following command:
  ```bash
  tar -xzvf ~/Downloads/linux-6.18.35.tar.gz -C ~/
  ```

* Next, we installed the necessary dependencies to build the kernel:
  ```bash
  sudo apt -y install libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf llvm qtcreator qtbase5-dev qt5-qmake cmake
  ```

* We navigated into the Linux build tree and copied the configuration file from the currently running system:
  ```bash
  cd ~/linux-6.18.35
  cp /boot/config-$(uname -r) .config
  ```

* To fix potential configuration issues arising from the kernel version mismatch, we updated the configuration:
  ```bash
  make olddefconfig
  ```

* To streamline the build by compiling only the currently loaded modules, we ran:
  ```bash
  make localmodconfig
  ```

### Patching Linux with PREEMPT_RT
To achieve true real-time determinism after installation, we must move beyond the default `PREEMPT_DYNAMIC` schema. While `PREEMPT_DYNAMIC` allows the kernel to dynamically determine preemption modes (e.g., *none*, *voluntary*, or *full*), it is not designed for real-time workloads and lacks hard guarantees for interrupt latency and thread scheduling.

For the Real-Time kernel, we needed to follow some additional steps:

* We downloaded the matching PREEMPT_RT patch from the [Linux Foundation Real-Time Wiki](https://wiki.linuxfoundation.org/realtime/start) and extracted it:
  ```bash
  gunzip -c ~/Downloads/patch-6.18.35-rt5.patch.gz > ~/patch-6.18.35-rt5.patch
  ```

* Returning to the build tree, we applied the patch and opened the configuration GUI:
  ```bash
  cd ~/linux-6.18.35
  patch -p1 < ../patch-6.18.35-rt5.patch
  make xconfig
  ```

* In the configuration menu, we navigated to General Setup -> Preemption Model and set it to Fully Preemptible Kernel (RT).


* We opened the configuration menu again (`make xconfig`) to manually disable specific features to reduce latency, strictly in the following order:
  * `CONFIG_SCHED_MC_PRIO` (**Processor type and features** -> **Multi-core scheduler support**)
  * `CONFIG_CPU_FREQ` (**Power management and ACPI options** -> **CPU Frequency scaling**)
  * `CONFIG_STACKPROTECTOR` 
  * `CONFIG_APM` 
  * `CONFIG_ACPI_PROCESSOR` (**Power management and ACPI options** -> **ACPI (Advanced Configuration and Power Interface)**)
  * `CONFIG_CPU_IDLE` (**Power management and ACPI options** -> **CPU idle PM support**)
  * **Simultaneous Multi-threading** (if supported by the hardware)

* We also ensured NVMe support was enabled:
  * `CONFIG_BLK_DEV_NVME` (**Device Drivers** -> **NVME Support** -> **NVM Express block device**)

* Under **Processor type and features**, we fine-tuned the settings for our specific hardware architecture and saved the configuration.

### Compiling the kernel 

* For Ubuntu specifically, it is necessary to clear the Canonical certificates (`canonical.pem`) to avoid build failures. From the Linux build tree, we executed:
  ```bash
  sudo scripts/config --disable SYSTEM_TRUSTED_KEYS
  sudo scripts/config --disable SYSTEM_REVOCATION_KEYS
  make olddefconfig
  ```

* Finally, we built and installed the kernel and its modules:
  ```bash
  sudo make -j25
  sudo make modules_install
  sudo make install
  ```

### Hardware Tuning (BIOS/UEFI)

The configurations in this section are highly hardware-specific and will vary depending on the motherboard manufacturer and CPU vendor. To ensure predictable performance and minimize latency spikes for real-time workloads, it is crucial to disable dynamic frequency scaling and deep power-saving states directly at the firmware level. 

Below are the specific configuration steps applied to our testbed, which features an MSI motherboard and an AMD processor:

* **Disable Precision Boost Overdrive (PBO):** Navigate to `Overclocking` -> `Advanced CPU Configuration` -> `AMD Overclocking` and set **Precision Boost Overdrive** to **Disabled**.

* **Disable CPU Boost and Sleep States:** Navigate to `Overclocking` -> `Advanced CPU Configuration` -> `AMD CBS` and set both **Core Performance Boost** and **Global C-state Control** to **Disabled**.

* **Set a Fixed CPU Frequency:** In the main `Overclocking` menu, change the **CPU Ratio** from `Auto` to a fixed value of **44.00**. This forces the processor to run at a constant clock speed, preventing the latency overhead associated with dynamic frequency transitions during the experiments.


### OS-level isolation

Given the presence of some counterintuitive results, we decided to configure the operating system to adopt additional isolation mechanisms, aiming to identify the possible cause of such behaviors by minimizing the variables introduced by the OS scheduler.

#### Isolation and Configuration Steps
The isolation was implemented at the operating system level through various techniques, including:

* **Kernel scheduling isolation (`isolcpus`):** Use the `isolcpus=` boot parameter to prevent the scheduler from assigning tasks to a specific set of CPUs, thereby avoiding general SMP balancing.
* **Kernel house-keeping noise (`nohz_full`):** Address kernel house-keeping noise by appending `nohz_full=` to enable Tickless Mode, which reduces OS overhead on those selected CPUs.
* **RCU callback offloading (`rcu_nocbs`):** To further minimize latencies imposed by memory allocators in `softirq` contexts, apply RCU callback offloading to dedicated kernel threads using the `rcu_nocbs=` parameter.
* **IRQ affinity:** Configure IRQ affinity to ensure hardware interrupts are kept away from our isolated cores as much as possible.

The isolation was applied to both the host and the virtualized environment. The host system was configured to avoid scheduling tasks on the physical CPUs dedicated to running the virtual machines. Concurrently, the guest system was also configured so that the virtual machine's scheduler could not assign tasks to the cores reserved for real-time applications.

The following is an example of OS-level isolation we adopted in one of the KVM experiments. On the host, we fully isolated **CPU22** and **CPU23** on our 24-core system, configuring GRUB by adding a custom boot entry in `/etc/grub.d/40_custom`:

```text
menuentry 'Ubuntu 24.04 (6.18.35-rt5-full)'{
        echo 'Loading Linux 6.18.35-rt5 with NO_HZ, ISOLCPUS, RCU_NOCBS and no IRQ_AFFINITY on [22, 23]'
        linux   /boot/vmlinuz-6.18.35-rt5 root=UUID=8e001ea3-a450-434d-bfab-ee2e6f61c6a2 ro  nohz_full=22-23 isolcpus=22-23 rcu_nocbs=22-23 irqaffinity=0-21 quiet splash $vt_handoff
        echo    'Loading initial ramdisk ...'
        initrd  /boot/initrd.img-6.18.35-rt5
}
```

Similarly, on the guest we isolated **CPU1** with the following configuration:

```text
menuentry 'Ubuntu 24.04 (6.18.35-rt5-full)'{
        echo 'Loading Linux 6.18.35-rt5 with NO_HZ, ISOLCPUS, RCU_NOCBS and no IRQ_AFFINITY on 1'
        linux   /boot/vmlinuz-6.18.35-rt5 root=UUID=1fe78ac9-040a-4fe5-b3a8-8715d38d692e ro  nohz_full=1 isolcpus=1 rcu_nocbs=1 irqaffinity=0 quiet splash $vt_handoff
        echo    'Loading initial ramdisk ...'
        initrd  /boot/initrd.img-6.18.35-rt5
}
```


## KVM
Being effectively treated as a Type-2 hypervisor, KVM sits on top of an already booted operating system. The host OS manages it similarly to a user-space application, where the virtual CPUs (vCPUs) are scheduled as standard host processes. Consequently, the installation process is as straightforward as running the following command:

```bash
sudo apt -y install bridge-utils cpu-checker libvirt-clients libvirt-daemon qemu-system qemu-kvm virt-manager numad
```

We installed QEMU emulator version 8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.17)

In order to apply the OS-level isolation techniques on the pinned configuration, we modified the `/etc/grub.d/40_custom` file adding the entries in the [GRUB host configuration](KVM/grub_cfg/40_custom_host).

Once the installation was complete, we provisioned the following guest Virtual Machines with the same hardware specifications:

| Name | ubuntu24.04 | ubuntu24.04-pinned |
|---|---|---|
| **vCPUs:** | 2 | 2 |
| **RAM:** | 4 GB | 4 GB |
| **Isolation techniques** | Memory locking, CPU pass-through | CPU pinning, memory locking, CPU pass-through, OS-level isolation |
| **Configuration file** | [ubuntu24.04.xml](KVM/vms/ubuntu24.04.xml) | [ubuntu24.04-pinned.xml](KVM/vms/ubuntu24.04-pinned.xml) |

We installed both the 6.18.35 and the 6.18.35-rt5 kernels in the same manner as on the host, with the exception that we did not enable the NVMe block device support, since we will be using VirtIO. For simplicity reasons, the two VMs share the same virtual drive.

In order to apply the OS-level isolation techniques on the pinned configuration, we modified the `/etc/grub.d/40_custom` file adding the entries in the [GRUB guest configuration](KVM/grub_cfg/40_custom_guest).

We ensured the VM vCPUs always had the required resources available and could not be preempted by other tasks by setting the `vcpusched` mode of both vCPUs to `SCHED_FIFO` with priority 98.

```xml
<vcpusched vcpus='0' scheduler='fifo' priority='98'/>
<vcpusched vcpus='1' scheduler='fifo' priority='98'/>
```

We enabled memory locking to prevent swapping:

```xml
<memoryBacking>
  <locked/>
</memoryBacking>
```

We ensured CPU pass-through and correct topology mapping:

```xml
<cpu mode='host-passthrough' check='none'>
  <topology sockets='1' dies='1' cores='2' threads='1'/>
</cpu>
```

In the pinned configuration, we applied CPU pinning to make the vCPU threads run exactly on the isolated cores:

```xml
<vcpu placement='static'>2</vcpu>
<cputune>
  <vcpupin vcpu='0' cpuset='22'/>
  <vcpupin vcpu='1' cpuset='23'/> 
  <emulatorpin cpuset='0-21'/>
  <iothreadpin iothread='1' cpuset='0-21'/>
</cputune>
```

### TACLe Benchmark

We provisioned the following guest Virtual Machines to run the TACLe benchmarks:

| Name | ubuntu24.04-tacle | ubuntu24.04-tacle-pinned |
|---|---|---|
| **vCPUs:** | 2 | 2 |
| **RAM:** | 4 GB | 4 GB |
| **Isolation techniques** | Memory locking, CPU pass-through | CPU pinning, memory locking, CPU pass-through, OS-level isolation |
| **Configuration file** | [ubuntu24.04-tacle.xml](KVM/vms/ubuntu24.04-tacle.xml) | [ubuntu24.04-tacle-pinned.xml](KVM/vms/ubuntu24.04-tacle-pinned.xml) |

We configured them the same way we did for the `ubuntu24.04` and `ubuntu24.04-pinned` VMs respectively, with the exception of the pinning layout of the emulation and I/O threads. These four also share the same virtual drive, since only one of them will be turned on at a time.

For the noisy guests, we provisioned similar VMs, but with different specs and no real-time vCPU priority assigned:

| Name | ubuntu24.04-noise-small | ubuntu24.04-noise-big | ubuntu24.04-noise-big-pinned |
|---|---|---|---|
| **vCPUs:** | 2 | 16 | 16 |
| **RAM:** | 4 GB | 16 GB | 16 GB |
| **Isolation techniques** | Memory locking, CPU pass-through | Memory locking, CPU pass-through | CPU pinning, memory locking, CPU pass-through |
| **Configuration file** | [ubuntu24.04-noise-small.xml](KVM/vms/ubuntu24.04-noise-small.xml) | [ubuntu24.04-noise-big.xml](KVM/vms/ubuntu24.04-noise-big.xml) | [ubuntu24.04-noise-big-pinned.xml](KVM/vms/ubuntu24.04-noise-big-pinned.xml) |

These three also share a different virtual drive, that does not require any modification but the installation of `stress-ng`:

```bash
sudo apt -y install stress-ng
```

## Xen

We installed the Xen hypervisor 4.17.3 via the `xen-hypervisor-amd64` package. This process automatically generated the necessary GRUB bootloader entries to boot the Ubuntu system as **Dom0** (the privileged management domain). 

```bash
sudo apt -y install xen-hypervisor-amd64
```

During our initial boot tests, we encountered severe instability with the Graphical User Interface (GUI). Specifically, the `nouveau` open-source drivers—often relied upon for NVIDIA GPU compatibility—failed to initialize correctly on our testbed. Further investigation suggested that graphical drivers generally exhibit poor stability when running under Xen Dom0, a behavior observed across different hardware configurations. To bypass this limitation, we opted for a headless setup and managed the host via SSH.

To streamline the provisioning of subsequent DomUs, we installed the `xen-tools` package:

```bash
sudo apt -y install xen-tools
```

Since our guests required dedicated block storage, we resized the existing LVM (Logical Volume Manager) partition hosting the Ubuntu installation to carve out a new logical volume exclusively dedicated to the VMs. We performed this using the following steps:

```bash
sudo lvreduce --resizefs --size -65G /dev/ubuntu-vg/root
sudo lvcreate -L 65G -n ubuntu-24.04-domU ubuntu-vg
```

To speed up the setup of the DomU, we decided to clone the Dom0 partition and assign it a new UUID:

```bash
sudo dd if=/dev/nvme0n1p4 of=/dev/ubuntu-vg/ubuntu-24.04-domU status=progress
sudo e2fsck -f /dev/ubuntu-vg/ubuntu-24.04-domU
sudo tune2fs -U random /dev/ubuntu-vg/ubuntu-24.04-domU
```

We designed different configuration files to provision our DomU instances, with the same hardware specifications. The differences between the configurations are the underlying kernel used to boot them and how vCPU allocation is performed.

| Name | ubuntu-24.04-linux-6.18.35-nrt-hvm | ubuntu-24.04-linux-6.18.35-nrt-hvm-pinned | ubuntu-24.04-linux-6.18.35-rt5-hvm | ubuntu-24.04-linux-6.18.35-rt5-hvm-pinned |
|---|---|---|---|---|
| **vCPUs:** | 2 | 2 | 2 | 2 |
| **RAM:** | 4 GB | 4 GB | 4 GB | 4 GB |
| **Isolation techniques** | None | CPU pinning | None | CPU pinning |
| **Configuration file** | [ubuntu-24.04-linux-6.18.35-nrt-hvm.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-nrt-hvm.conf) | [ubuntu-24.04-linux-6.18.35-nrt-hvm-pinned.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-nrt-hvm-pinned.conf) | [ubuntu-24.04-linux-6.18.35-rt5-hvm.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-rt5-hvm.conf) | [ubuntu-24.04-linux-6.18.35-rt5-hvm-pinned.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-rt5-hvm-pinned.conf) |

These different configurations share the same LVM partition, as only one of them will be turned on at a time.

### Problems with PREEMPT_RT

During the initial setup phase, we attempted to boot Xen using the same real-time kernel—compiled with the previously described instructions—as the Dom0 kernel. We tested various kernel versions across different Linux distributions and experimented with several combinations of the tuning parameters mentioned earlier (specifically: `CONFIG_SCHED_MC_PRIO`, `CONFIG_CPU_FREQ`, `CONFIG_STACKPROTECTOR`, `CONFIG_APM`, `CONFIG_ACPI_PROCESSOR`, and `CONFIG_CPU_IDLE`). 

Furthermore, we applied a wide array of Xen and kernel command-line boot parameters that are traditionally recommended for resolving boot hangs and hardware initialization issues. However, none of these mitigations proved successful.

We also ensured that all the necessary configuration flags required to run the kernel as a Xen Dom0 were strictly enabled. We tried:

* `swiotlb=35536,force`
* `iommu=pt`
* `console=hvc0`
* `console=tty0`
* `earlyprintk=xen`
* `apci=off noapic pci=nomsi`
* `noirqbalance`
* `nomodeset`

Despite these extensive troubleshooting efforts, we observed that enabling the "Fully Preemptible Kernel (RT)" option consistently caused severe boot incompatibilities with the Xen hypervisor. The boot sequence systematically stalled even before the initialization of the logging daemons (such as `systemd-journald`). 

Coupled with the graphical driver issues discussed previously, debugging this behavior proved to be a formidable challenge. The system most likely dropped into an `initramfs` recovery shell, which remained completely inaccessible to us in our headless setup. 

Consequently, we decided to leave the "Fully Preemptible Kernel" option disabled for the Dom0 kernel. Instead, we opted for the "Low-Latency" scheduling model, which guaranteed a reliable boot process while still offering better responsiveness compared to the standard generic kernel.

### Resource partitioning and NULL-scheduler

In order to compare the effects of the scheduler choice on Xen, we swapped the default Credit2 scheduler with a pinned configuration, effectively using an offline scheduler. This is done to assess the current effects of the issues identified by the previous analyses of Abeni and Faggioli, such as the priority inversion via QEMU and the `TIMER_SLOP` limitation. In order to do so, we changed the Dom0 GRUB boot configuration at `/etc/grub.d/40_custom` adding the entries shown in [this GRUB configuration file](Xen/grub_cfg/40_custom).

This configuration restricts Xen to using only the first 22 pCPUs for Dom0. Also, we configured the pinned guests to use only the pCPUs 22 and 23, so that they would have two dedicated cores with no interference from the Dom0.

To be absolutely certain of the vCPU to pCPU fixed mapping, we also executed the following commands after the VM booted:

```bash
sudo xl vcpu-pin ubuntu-24.04-linux-6.18.35-rt5 0 22
sudo xl vcpu-pin ubuntu-24.04-linux-6.18.35-rt5 1 23
```

### TACLe Benchmark

For the TACLe benchmarks, we used the Low-Latency Dom0 and Real-Time DomU setup, and pinned Dom0 to only use the first four pCPUs, leaving the others to both the noisy guest and the benchmark guest. This is to separate the cores dedicated to the privileged domain from the other guests, ensuring that only stress generated by the benchmarks and the noisy VM is reflected in the results.

We designed the following configurations to run the TACLe benchmarks:

| Name | ubuntu-24.04-linux-6.18.35-rt5-hvm-tacle | ubuntu-24.04-linux-6.18.35-rt5-hvm-tacle-pinned |
|---|---|---|
| **vCPUs:** | 2 | 2 |
| **RAM:** | 4 GB | 4 GB |
| **Isolation techniques** | CPU scheduling range (4-23) | CPU pinning |
| **Configuration file** | [ubuntu-24.04-linux-6.18.35-rt5-hvm-tacle.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-rt5-hvm-tacle.conf) | [ubuntu-24.04-linux-6.18.35-rt5-hvm-tacle-pinned.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-rt5-hvm-tacle-pinned.conf) |

The only difference between these configurations and the previous ones is the range the vCPUs will be scheduled in. These too share the same LVM partition assigned to the other DomUs.

For the noisy guests, we defined similar configurations, but with different specs:

| Name | ubuntu-24.04-linux-6.18.35-nrt-hvm-noisyguest-small | ubuntu-24.04-linux-6.18.35-nrt-hvm-noisyguest-big | ubuntu-24.04-linux-6.18.35-nrt-hvm-noisyguest-big-pinned |
|---|---|---|---|
| **vCPUs:** | 2 | 16 | 16 |
| **RAM:** | 4 GB | 16 GB | 16 GB |
| **Isolation techniques** | CPU scheduling range (4-23) | CPU scheduling range (4-23) | CPU pinning |
| **Configuration file** | [ubuntu-24.04-linux-6.18.35-nrt-hvm-noisyguest-small.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-nrt-hvm-noisyguest-small.conf) | [ubuntu-24.04-linux-6.18.35-nrt-hvm-noisyguest-big.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-nrt-hvm-noisyguest-big.conf) | [ubuntu-24.04-linux-6.18.35-nrt-hvm-noisyguest-big-pinned.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-nrt-hvm-noisyguest-big-pinned.conf) |

These three also share a different LVM partition, that does not require any modification but the installation of `stress-ng`:

```bash
sudo apt -y install stress-ng
```

#### TACLe and stress on Dom0

There is also a variation of the above configuration, where the stress is generated on Dom0 itself. In this case, there is no need to limit the scheduling range of the DomU. The configuration file is [this one](Xen/domains/ubuntu-24.04-linux-6.18.35-rt5-hvm-tacle-dom0noise.conf). The pinned configuration, by definition, does not change.

### PV and PVH DomUs

To test different virtualization technologies, we created some PV and PVH configuration variants of the previous real-time DomUs. As we will discuss in the Xen analysis section, the PV DomUs don't support `PREEMPT_RT` patched kernels with the Fully Preemptible Kernel option enabled (in a similar fashion to Dom0, it being a PV domain too), thus we used the Low-Latency variant of the kernel for these configurations:

| Name | ubuntu-24.04-linux-6.18.35-rt5-ll-pv | ubuntu-24.04-linux-6.18.35-rt5-ll-pv-pinned | ubuntu-24.04-linux-6.18.35-rt5-pvh | ubuntu-24.04-linux-6.18.35-rt5-pvh-pinned |
|---|---|---|---|---|
| **vCPUs:** | 2 | 2 | 2 | 2 |
| **RAM:** | 4 GB | 4 GB | 4 GB | 4 GB |
| **Isolation techniques** | None | CPU pinning | None | CPU pinning |
| **Configuration file** | [ubuntu-24.04-linux-6.18.35-rt5-ll-pv.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-rt5-ll-pv.conf) | [ubuntu-24.04-linux-6.18.35-rt5-ll-pv-pinned.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-rt5-ll-pv-pinned.conf) | [ubuntu-24.04-linux-6.18.35-rt5-pvh.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-rt5-pvh.conf) | [ubuntu-24.04-linux-6.18.35-rt5-pvh-pinned.conf](Xen/domains/ubuntu-24.04-linux-6.18.35-rt5-pvh-pinned.conf) |

All these configurations use the same LVM partition as the other HVM configurations, and do not require any other specific setup.

## Benchmark automation

In order to streamline the testing procedure, a series of supplementary configuration steps were required. Since these procedures apply identically across both virtualization platforms, the following terminology will be used for simplicity: the term **Host** will refer collectively to the KVM Host and the Xen Dom0, while the term **Guest** will denote both the KVM virtual machine and the Xen DomU.

First, we installed `openssh-server` and `expect` on the Host to orchestrate the benchmarks from a remote machine and interact with the Guest OS via the `xl` and `virsh` consoles.

```bash
sudo apt -y install openssh-server expect
```

To enable passwordless SSH access, we generated an SSH key pair on the orchestrator machine and appended the public key to the `authorized_keys` file on the Host:

```bash
ssh-keygen -t ed25519 -C "xen-vs-kvm-orchestrator"
ssh-copy-id matt@192.168.1.166
```

To facilitate operations requiring root privileges without manual intervention, we added the following rule to the `/etc/sudoers` file on the Host and Guests using `visudo`:

```text
matt ALL=(ALL) NOPASSWD: ALL
```

To automatically boot on the appropriate kernel with the correct settings, we modified the GRUB configuration in `/etc/default/grub` on the Host and KVM Guests:

```text
GRUB_DEFAULT=saved
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=5
```

For the KVM Guests, we enabled the serial console by enabling the corresponding `systemctl` service:

```bash
sudo systemctl enable --now serial-getty@ttyS0.service
```
