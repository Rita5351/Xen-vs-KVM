# Xen

This documentation describes the detailed procedure to configure an automated test cycle at the boot of the Xen virtual machine (DomU). The system allows forcing the boot with a specific kernel via GRUB, running `cyclictest` for a preset number of iterations, and automatically rebooting the machine at the end of each session, disabling the cycle once completed.

### 1. Boot Kernel Configuration on GRUB (One-time)

To ensure the accuracy and consistency of deterministic tests within the Xen environment, it is necessary to lock the boot loader of the guest machine onto a specific installed version of the Linux kernel (e.g., the `PREEMPT_RT` patched kernel).

#### Step 1.1: List available kernel entries
Identify the exact identification string of the desired kernel by analyzing the GRUB configuration inside the Xen Guest:
