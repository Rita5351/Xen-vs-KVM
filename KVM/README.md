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

    # Execute cyclictest with Real-Time priority (Modify parameters if necessary)
    # Example parameters: -t1 (1 thread), -p 99 (max RT priority), -n (clock_nanosleep), -D 1m (duration 1 minute)
    cyclictest -t1 -p 99 -n -i 10000 -m -D 1m > "$LOG_DIR/result_${NEXT_RUN}.txt"

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

## NON-REAL-TIME KERNEL

## KERNEL NON REAL TIME

## MODIFICHE HW
Vado in overclocking \Advanced cpu \ AMD OVERCLOCKING \PRECISION BOOST OVERDRIVE DISABLED

Vado in overclocking \Advanced cpu\ AMD CBS e disattiviamo core performance boost e global C-state Control


Vado in Overclocking e metto CPU RATIO 44.00 invece di Auto 
