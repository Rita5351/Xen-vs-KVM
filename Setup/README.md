# Setup 
This chapter outlines the complete experimental testbed configuration required to evaluate Xen and KVM under mixed-criticality workloads. To ensure reliable, predictable, and reproducible latency measurements, the host environment must be strictly tailored for real-time execution. 

The following sections detail the step-by-step preparation of the system, starting with the installation and tuning of the host operating system, the compilation of a fully preemptible Linux kernel (`PREEMPT_RT`), and the deployment of the respective hypervisors. We then detail both hypervisors' configuration, focusing on the differences between the two.

### Installing the Baseline (Non-RT) Kernel

To establish a baseline for our performance comparison, we also required the standard, non-real-time Linux kernel version 6.12.89. For convenience and to streamline the deployment, we utilized the **Ubuntu Mainline Kernel Installer** graphical utility to fetch the necessary packages. 

Once the packages were retrieved, we installed and loaded the new kernel by executing the following commands:

```bash
sudo add apt-repository ppa:cappelikan/ppa
sudo apt update
sudo apt install mainline
```

## Patching Linux with PREEMPT_RT

* First, we downloaded the official kernel source code from the [Linux Kernel Archive](https://cdn.kernel.org/pub/linux/kernel/).
* We extracted the archive using the following command:
  ```bash
  tar -xzvf ~/Downloads/linux-6.12.89.tar.gz -C ~/
  ```

* Next, we installed the necessary dependencies to build the kernel:
  ```bash
  sudo apt install libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf llvm qtcreator qtbase5-dev qt5-qmake cmake
  ```

* We navigated into the Linux build tree and copied the configuration file from the currently running system:
  ```bash
  cd ~/linux-6.12.89
  cp /boot/config-$(uname -r) .config
  ```

* To fix potential configuration issues arising from the kernel version mismatch, we updated the configuration:
  ```bash
  make olddefconfig
  ```

* Subsequently, we downloaded the matching PREEMPT_RT patch from the [Linux Foundation Real-Time Wiki](https://wiki.linuxfoundation.org/realtime/start) and extracted it:
  ```bash
  gunzip -c ~/Downloads/patch-6.12.89-rt18.patch.gz > ~/patch-6.12.89-rt18.patch
  ```

* Returning to the build tree, we applied the patch and opened the configuration GUI:
  ```bash
  cd ~/linux-6.12.89
  patch -p1 < ../patch-6.12.89-rt18.patch
  make xconfig
  ```

* In the configuration menu, we navigated to General Setup -> Preemption Model and set it to Fully Preemptible Kernel (RT).

* To streamline the build by compiling only the currently loaded modules, we ran:
  ```bash
  make localmodconfig
  ```

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

* For Ubuntu specifically, it is necessary to clear the Canonical certificates (`canonical.pem`) to avoid build failures. From the Linux build tree, we executed:
  ```bash
  sudo scripts/config --disable SYSTEM_TRUSTED_KEYS
  sudo scripts/config --disable SYSTEM_REVOCATION_KEYS
  make olddefconfig
  ```

* Under **Processor type and features**, we fine-tuned the settings for our specific hardware architecture and saved the configuration.

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

### Achieving True Real-Timeliness

To achieve true real-timeliness after installation, we must move beyond the default `PREEMPT_DYNAMIC` schema. While `PREEMPT_DYNAMIC` allows the kernel to dynamically determine preemption modes (e.g., *none*, *voluntary*, or *full*), it is not designed for real-time workloads and lacks hard guarantees for interrupt latency and thread scheduling.

#### Isolation and Configuration Steps

* **Kernel scheduling isolation (`isolcpus`):** Use the `isolcpus=` boot parameter to prevent the scheduler from assigning tasks to a specific set of CPUs, thereby avoiding general SMP balancing.
* **Kernel house-keeping noise (`nohz_full`):** Address kernel house-keeping noise by appending `nohz_full=` to enable Tickless Mode, which reduces OS overhead on those selected CPUs.
* **RCU callback offloading (`rcu_nocbs`):** To further minimize latencies imposed by memory allocators in `softirq` contexts, apply RCU callback offloading to dedicated kernel threads using the `rcu_nocbs=` parameter.
* **IRQ affinity:** Configure IRQ affinity to ensure hardware interrupts are kept away from our isolated cores as much as possible.

## KVM
Being effectively treated as a Type-2 hypervisor, KVM sits on top of an already booted operating system. The host OS manages it similarly to a user-space application, where the virtual CPUs (vCPUs) are scheduled as standard host processes. Consequently, the installation process is as straightforward as running the following command:

```bash
sudo apt -y install bridge-utils cpu-checker libvirt-clients libvirt-daemon qemu-system qemu-kvm virt-manager
```

Once the installation was complete, we provisioned the guest Virtual Machine with the following hardware specifications:

* **vCPUs:** 2
* **RAM:** 4 GB
* **Storage:** 25 GB virtual hard disk

We installed both the 6.12.89 and the 6.12.89-rt18 kernels in the same manner as on the host, with the exception that we did not enable the NVMe block device support, since we will be using VirtIO.

### Modifying the Bootloader (GRUB)

On the host, we fully isolated **CPU22** and **CPU23** on our 24-core system, configuring GRUB by adding a custom boot entry in `/etc/grub.d/40_custom`:

```text
menuentry 'Ubuntu 24.04 (6.12.89-rt18-full)'{
        echo 'Loading Linux 6.12.89-rt18 with NO_HZ, ISOLCPUS, RCU_NOCBS and no IRQ_AFFINITY on [22, 23]'
        linux   /boot/vmlinuz-6.12.89-rt18 root=UUID=8e001ea3-a450-434d-bfab-ee2e6f61c6a2 ro  nohz_full=22-23 isolcpus=22-23 rcu_nocbs=22-23 irqaffinity=0-21 quiet splash $vt_handoff
        echo    'Loading initial ramdisk ...'
        initrd  /boot/initrd.img-6.12.89-rt18
}
 ```

Similarly, on the guest we isolated **CPU1** with the following configuration:

```text
menuentry 'Ubuntu 24.04 (6.12.89-rt18-full)'{
        echo 'Loading Linux 6.12.89-rt18 with NO_HZ, ISOLCPUS, RCU_NOCBS and no IRQ_AFFINITY on 1'
        linux   /boot/vmlinuz-6.12.89-rt18 root=UUID=1fe78ac9-040a-4fe5-b3a8-8715d38d692e ro  nohz_full=1 isolcpus=1 rcu_nocbs=1 irqaffinity=0 quiet splash $vt_handoff
        echo    'Loading initial ramdisk ...'
        initrd  /boot/initrd.img-6.12.89-rt18
}
 ```

### Tweaking the VM
Furthermore, we appended specific parameters to the XML configuration to ensure stable and predictable VM behaviour:

1. We applied CPU pinning to make the vCPU threads only run on the isolated cores, while banishing emulator and I/O threads to the general-purpose cores:

   ```xml
    <vcpu placement='static'>2</vcpu>
    <cputune>
      <vcpupin vcpu='0' cpuset='22'/>
      <vcpupin vcpu='1' cpuset='23'/> 
      <emulatorpin cpuset='0-21'/>
      <iothreadpin iothread='1' cpuset='0-21'/>
    </cputune>
   ```

2. We enabled memory locking to prevent swapping:
   ```xml
    <memoryBacking>
      <locked/>
    </memoryBacking>
   ```

3. We ensured CPU pass-through and correct topology mapping:
   ```xml
    <cpu mode='host-passthrough' check='none'>
      <topology sockets='1' dies='1' cores='2' threads='1'/>
    </cpu>
   ```

## XEN
Abbiamo installato Xen attraverso XEN-HYPERVISOR-AMD64.
Questo aggiunge delle voci nel menù di avvio di GRUB per avviare ubuntu come dom0 usando Xen.
Dato che l'interfaccia grafica non è disponibile (anche su hw differenti non cambia), è stato necessario riconfigurare un demone SSH sull'host. Abbiamo eseguito il comando
sudo apt install openssh - server 
Abbiamo poi modificato il file di configurazione per accettare connessioni dalla rete locale.
Al seguito del restart, avvio su xen e 
