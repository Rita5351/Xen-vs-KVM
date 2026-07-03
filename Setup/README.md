# Setup 
This chapter outlines the complete experimental testbed configuration required to evaluate Xen and KVM under mixed-criticality workloads. To ensure reliable, predictable, and reproducible latency measurements, the host environment must be strictly tailored for real-time execution. 

The following sections detail the step-by-step preparation of the system, starting with the installation and tuning of the host operating system, the compilation of a fully preemptible Linux kernel (`PREEMPT_RT`), and the deployment of the respective hypervisors. We then detail both hypervisors' configuration, focusing on the differences between the two.

## Kernel configuration

To establish a baseline for our performance comparison, we also required the standard, non-real-time Linux kernel version 6.18.35. 

* First, we downloaded the official kernel source code from the [Linux Kernel Archive](https://cdn.kernel.org/pub/linux/kernel/).
* We extracted the archive using the following command:
  ```bash
  tar -xzvf ~/Downloads/linux-6.18.35.tar.gz -C ~/
  ```

* Next, we installed the necessary dependencies to build the kernel:
  ```bash
  sudo apt install libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf llvm qtcreator qtbase5-dev qt5-qmake cmake
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

We installed both the 6.18.35 and the 6.18.35-rt5 kernels in the same manner as on the host, with the exception that we did not enable the NVMe block device support, since we will be using VirtIO.

### Modifying the Bootloader (GRUB)

On the host, we fully isolated **CPU22** and **CPU23** on our 24-core system, configuring GRUB by adding a custom boot entry in `/etc/grub.d/40_custom`:

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

## Xen

### Installation and GUI Troubleshooting

We installed the Xen hypervisor via the `xen-hypervisor-amd64` package. This process automatically generated the necessary GRUB bootloader entries to boot the Ubuntu system as **Dom0** (the privileged management domain). 

During our initial boot tests, we encountered severe instability with the Graphical User Interface (GUI). Specifically, the `nouveau` open-source drivers—often relied upon for NVIDIA GPU compatibility—failed to initialize correctly on our testbed. Further investigation suggested that graphical drivers generally exhibit poor stability when running under Xen Dom0, a behavior observed across different hardware configurations. 

To bypass this limitation, we opted for a headless setup and managed the host via SSH. We installed the SSH daemon:

```bash
sudo apt install openssh-server
```

After modifying the configuration file to accept incoming connections from the local network, we rebooted into the Xen environment and successfully established a remote SSH session. We verified that the hypervisor was functioning correctly by checking its status:

```bash
sudo xl info
```
The output successfully confirmed the Xen hypervisor was active and managing the host.

### Storage Provisioning and Tooling

To streamline the provisioning of subsequent **DomU** (guest) virtual machines, we installed the `xen-tools` package. 

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

### Dom0 Resource Tuning

Before deploying the guests, it is necessary to partition the hardware resources, which are assigned to Dom0 by default. This ensures that dedicated, isolated resources are available for the DomUs. We reduced the Dom0 footprint using the following commands shown [here](Xen/README.md)

### DomU Configuration and Deployment

We designed two distinct configuration files to provision our DomU instances. These guests are configured with the exact same hardware specifications (vCPUs, RAM, Storage) as the KVM virtual machines to guarantee a fair comparison. The only difference between the two configurations is the underlying kernel used to boot them.

The base configuration file is structured as follows:

```conf
# This configures either a HVM, a PVH or a PV guest
type = "hvm"

# Guest name
name = "ubuntu-24.04-linux-6.18.35-rt5"

# Kernel image to boot
kernel = "/boot/vmlinuz-6.18.35-rt5"

# Ramdisk (optional)
ramdisk = "/boot/initrd.img-6.18.35-rt5"

# Kernel command line options (to show output on console)
extra = "root=/dev/xvda console=hvc0"

# Initial memory allocation (4GB)
memory = 4096
maxmem = 4096

# Number of VCPUS (2)
vcpus = 2
maxvcpus = 2

# Network devices
vif = [ 'bridge=xenbr0' ]

# Disk Devices
disk = [ '/dev/ubuntu-vg/ubuntu-24.04-domU,raw,xvda,rw' ]
```

Finally, we instantiated the virtual machine by passing the configuration file to the Xen toolstack:

```bash
sudo xl create -c ubuntu-24.04-linux-6.18.35-rt5-hvm.conf
```
### Problems with PREEMPT_RT

During the initial setup phase, we attempted to boot Xen using the same real-time kernel—compiled with the previously described instructions—as the Dom0 kernel. We tested various kernel versions across different Linux distributions and experimented with several combinations of the tuning parameters mentioned earlier (specifically: `CONFIG_SCHED_MC_PRIO`, `CONFIG_CPU_FREQ`, `CONFIG_STACKPROTECTOR`, `CONFIG_APM`, `CONFIG_ACPI_PROCESSOR`, and `CONFIG_CPU_IDLE`). 

Furthermore, we applied a wide array of Xen and kernel command-line boot parameters that are traditionally recommended for resolving boot hangs and hardware initialization issues. However, none of these mitigations proved successful.

We also ensured that all the necessary configuration flags required to run the kernel as a Xen Dom0 were strictly enabled. We tried:

* `swiotlb=35536,force`
* `iommu=pt`
* `console=hvc0`
* `console=tty0`
* `earlyprintk=ken`
* `apci=off noapic pci=nomsi`
* `noirqbalance`
* `nomodeset`

Despite these extensive troubleshooting efforts, we observed that enabling the "Fully Preemptible Kernel (RT)" option consistently caused severe boot incompatibilities with the Xen hypervisor. The boot sequence systematically stalled even before the initialization of the logging daemons (such as `systemd-journald`). 

Coupled with the graphical driver issues discussed previously, debugging this behavior proved to be a formidable challenge. The system most likely dropped into an `initramfs` recovery shell, which remained completely inaccessible to us in our headless setup. 

Consequently, we decided to leave the "Fully Preemptible Kernel" option disabled for the Dom0 kernel. Instead, we opted for the "Low-Latency" scheduling model, which guaranteed a reliable boot process while still offering better responsiveness compared to the standard generic kernel.
