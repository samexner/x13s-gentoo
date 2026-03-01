---

# Gentoo Linux on Lenovo ThinkPad X13s (ARM64)

This guide is structured to integrate with the logic of the Gentoo Handbook (AMD64). The reason for using the AMD64 handbook is that the ARM handbook mainly focuses on embedded systems rather than a full desktop environment. This guide details the specific deviations required for the **Lenovo ThinkPad X13s**, specifically regarding its **Snapdragon 8cx Gen 3** (ARM64) architecture, boot process, and kernel requirements.

## 1. Hardware Requirements

Before proceeding, ensure your hardware meets the requirements for the ARM64 architecture.

> **Note:** This installation requires a **secondary ARM64 environment** (or a cross-compiler) to build the initial kernel and Device Tree Blob (DTB), as the standard Gentoo Minimal Installation CD may not boot this device. I use Armbian, but you can use the ironrobin arch ISO or a different one instead.

## 2. Preparing the Disks

The ThinkPad X13s uses **UEFI** and requires a **GPT** partition layout.

### Partitioning Scheme

| Partition | Description | Filesystem | Recommended Size |
| --- | --- | --- | --- |
| `/dev/nvme0n1p1` | **Boot / ESP** | `vfat` (FAT32) | **1024 MiB** (Required for kernel + firmware) |
| `/dev/nvme0n1p2` | **Swap** | `swap` | 8 GiB+ (Adjust for hibernation) |
| `/dev/nvme0n1p3` | **Root** | `xfs` / `ext4` | Remaining space |

**Code Listing 2.1: Creating filesystems**

```bash
mkfs.vfat -F 32 /dev/nvme0n1p1
mkswap /dev/nvme0n1p2
swapon /dev/nvme0n1p2
mkfs.xfs /dev/nvme0n1p3

```

## 3. Installing the Gentoo Installation Files

Mount your partitions and extract the **stage3-arm64** tarball.

**Code Listing 3.1: Mounting partitions**

```bash
mount /dev/nvme0n1p3 /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount /dev/nvme0n1p1 /mnt/gentoo/boot

```

Select a standard ARM64 stage3 tarball (systemd or openrc).

---

## 4. Configuring the Kernel

For the ThinkPad X13s, we will deviate from the standard `emerge gentoo-sources` method. Instead, we will manage the kernel source using **Git**, as detailed in [Leo3418’s guide](https://leo3418.github.io/2022/03/04/gentoo-kernel-git.html). This method allows for easier updates, patch management, and bisecting if regressions occur on this experimental hardware.

### Managing Sources with Git

Instead of downloading a static tarball, clone the specific kernel fork required for the Snapdragon 8cx Gen 3.

**Code Listing 4.1: Cloning the kernel source**

```bash
# Install git if not present
emerge --ask dev-vcs/git

cd /usr/src
# Clone steev's fork, specifically the X13s branch
# We use --depth 1 to save space, but you may omit it for full history
git clone --depth 1 --branch lenovo-x13s-linux-6.19.y https://github.com/steev/linux.git linux-6.19.y

# Symlink to /usr/src/linux
eselect list
eselect set <version>

```

### Automated Installation (Dracut & Installkernel)

To ensure the system boots correctly, we must ensure that **firmware blobs** (specifically for the display and generic Qualcomm subsystems) are included in the initramfs. We will use `sys-kernel/installkernel` to automate the `make install` process and trigger `dracut`.

**Code Listing 4.3: Installing automation tools**

```bash
emerge --ask sys-kernel/installkernel sys-kernel/dracut

```

#### Configuring Installkernel

Configure `installkernel` to automatically generate an initramfs using Dracut and update the systemd-boot loader whenever you install a kernel.

**Code Listing 4.4: /etc/installkernel/installkernel.conf**

```ini
# Create this file if it does not exist
layout=systemd-boot
initramfs_generator=dracut

```

#### Configuring Dracut for Firmware

The X13s requires specific firmware to be available *before* the root filesystem is mounted. We will configure Dracut to force-include these files.

**Code Listing 4.5: /etc/dracut.conf.d/10-x13s-firmware.conf**

```bash
# Force include the Qualcomm firmware directory
# Adjust path if your firmware is organized differently
install_items+=" /lib/firmware/qcom/sc8280xp/LENOVO/21BX/ "

# Force load the display and wifi drivers
add_drivers+=" msm drm_msm ath11k_pci nvme phy_qcom_qmp_pcie pcie_qcom phy_qcom_qmp_ufs ufs_qcom i2c_hid_of i2c_qcom_geni leds_qcom_lpg pwm_bl qrtr pmic_glink_altmode gpio_sbu_mux phy_qcom_qmp_combo gpucc_sc8280xp dispcc_sc8280xp phy_qcom_edp panel_edp "

# If using LVM or LUKS, ensure those modules are also added
# add_dracutmodules+=" lvm crypt "

```

### Building and Installing

With the automation hooks in place, you can now build and install the kernel using standard commands. `make install` will now automatically call Dracut to generate the initrd with your firmware and update the bootloader.

**Code Listing 4.6: Compiling and installing**

```bash
make -j9 hardening.config qcom_laptops.config defconfig all modules_install install dtbs_install

```

When you need to update the kernel in the future, simply run `git pull` in the source directory and repeat **Code Listing 4.6**.


## 5. Configuring the Bootloader

This platform requires `systemd-boot` (or GRUB with specific DTB handling). Additionally, a specialized UEFI driver is required to initialize the co-processors.

### The `qebspil` UEFI Driver

The **Qualcomm Embedded Boot Support Platform Initialization Library (`qebspil`)** driver must be loaded by the bootloader to start the subsystem DSPs (Hexagon) early in the boot process.

**Code Listing 5.1: Installing qebspil**

1. Download or build `qebspilaa64.efi`.
2. Copy it to the systemd drivers directory:
```bash
mkdir -p /boot/EFI/systemd/drivers
cp qebspilaa64.efi /boot/EFI/systemd/drivers/

```


3. Populate the firmware directory on the ESP:
```bash
# The driver looks for firmware in /firmware/ on the ESP
mkdir -p /boot/firmware
cp -r /lib/firmware/qcom /boot/firmware/

```

## 6. System Configuration

### Network Configuration (MAC Address)

The `ath11k` driver may randomize the MAC address on every boot. To enforce a static MAC, use a udev rule.

**Code Listing 6.1: /etc/udev/rules.d/99-mac-address.rules**

```bash
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0006:01:00.0", RUN+="/bin/ip link set dev $name address XX:XX:XX:XX:XX:XX"

```

### Console Fixes

If you experience `Id "f0" respawning too fast` errors, disable the serial console in `/etc/inittab`.

**Code Listing 6.2: Editing /etc/inittab**

```ini
# Comment out the following line:
# f0:12345:respawn:/sbin/agetty 9600 ttyAMA0 vt100

```

---

### References

* `Gentoo Wiki: Lenovo ThinkPad X13s`
* `GitHub: stephan-gh/qebspil`
