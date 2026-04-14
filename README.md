# PicoCalc Pi Zero 2 Setup Guide

Complete setup guide for using a PicoCalc with ILI9488 4" TFT display on Raspberry Pi Zero 2W.

---

## Table of Contents

1. [Hardware Connection](#hardware-connection)
2. [Choose Your OS & Method](#choose-your-os--method)
3. [Method A: Trixie (Bookworm-based, 32-bit) — Recommended](#method-a-trixie-bookworm-based-32-bit--recommended)
4. [Method B: Bullseye (Legacy, 32-bit)](#method-b-bullseye-legacy-32-bit)
5. [Keyboard Driver](#keyboard-driver)
6. [Audio Setup](#audio-setup)
7. [Troubleshooting](#troubleshooting)

---

## Hardware Connection

Connect your PicoCalc to the Raspberry Pi Zero 2 using the following pins:

| **PicoCalc Pin** | **Raspberry Pi Pin** | **Pi Pin Number** |
|------------------|----------------------|-------------------|
| **VDD**          | 5V                   | Pin 2 or Pin 4    |
| **GND**          | Ground               | Pin 6             |
| **LCD_DC**       | GPIO 24              | Pin 18            |
| **LCD_RST**      | GPIO 25              | Pin 22            |
| **SPI1_CS**      | GPIO 8               | Pin 24            |
| **SPI1_TX**      | GPIO 10              | Pin 19            |
| **SPI1_SCK**     | GPIO 11              | Pin 23            |
| **I2C1_SDA**     | GPIO 2               | Pin 3             |
| **I2C1_SCL**     | GPIO 3               | Pin 5             |
| **PWM_R**        | GPIO 13              | Pin 33            |
| **PWM_L**        | GPIO 12              | Pin 32            |

> **⚠️ Important:** The Pico Connectors on `clockwork_Mainboard_V2.0_Schematic` are **Left-Right flipped!** Double-check your connections before powering on.

<img src="pinconnection.png" alt="Pinout Connections" height="400">
<img src="connector.png" alt="Connector Schematic" height="400">

---

## Choose Your OS & Method

| OS Version | Script | Display Driver | Notes |
|------------|--------|----------------|-------|
| **Trixie (32-bit)** | `setup_display_kernel.sh` | Kernel fbtft (native) | ✅ Recommended — no userspace daemon |
| **Trixie (32-bit)** | `setup_display_trixie.sh` | fbcp-ili9341 (userspace) | ⚠️ Requires kernel headers compilation |
| **Bullseye Legacy (32-bit)** | `setup_display.sh` | fbcp-ili9341 (userspace) | Original method |

### What's the difference?

**Kernel fbtft driver** (`setup_display_kernel.sh`):
- Uses the kernel's built-in `fb_ili9488` module
- No background process needed — driver loads at boot
- Lower CPU usage
- Works across kernel updates automatically

**fbcp-ili9341 userspace driver** (`setup_display_trixie.sh` / `setup_display.sh`):
- Compiles a custom userspace binary
- Runs as a background service
- May offer better performance in some cases
- May break on kernel updates and require recompilation

---

## Method A: Trixie (Bookworm-based, 32-bit) — Recommended

### Prerequisites

Flash **Raspberry Pi OS 32-bit with Desktop** (Trixie) to your SD card using Raspberry Pi Imager.

<img src="bullseye_os.png" alt="Raspberry Pi Imager" height="200">

### Step 1: Clone the repository

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/wasdwasd0105/picocalc-pi-zero-2.git
cd picocalc-pi-zero-2
```

### Step 2: Install display driver (kernel-native)

```bash
chmod +x setup_display_kernel.sh
sudo ./setup_display_kernel.sh
```

This script will:
- Enable the SPI interface via `raspi-config`
- Compile and install a custom device tree overlay for the ILI9488 display
- Configure `/boot/firmware/config.txt` with display settings
- Set up kernel module auto-loading
- Reboot your Pi automatically

### Step 3: Install keyboard driver

After reboot, run:

```bash
chmod +x setup_keyboard_trixie.sh
sudo ./setup_keyboard_trixie.sh
```

This script will:
- Install build dependencies (kernel headers, device tree compiler)
- Build the PicoCalc keyboard kernel module
- Install the device tree overlay
- Configure I2C and keyboard overlay in config.txt

Reboot after installation:

```bash
sudo reboot
```

---

## Method B: Bullseye (Legacy, 32-bit)

### Prerequisites

Flash **Raspberry Pi OS (Legacy) 32-bit with Desktop** (Bullseye) to your SD card.

### Step 1: Clone the repository

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/wasdwasd0105/picocalc-pi-zero-2.git
cd picocalc-pi-zero-2
```

### Step 2: Install display driver

```bash
chmod +x setup_display.sh
sudo ./setup_display.sh
```

This script will:
- Enable the SPI interface
- Download and compile `fbcp-ili9341` from source
- Configure `/boot/config.txt` with display settings
- Set up a systemd service for fbcp
- Reboot your Pi automatically

### Step 3: Install keyboard driver

After reboot, run:

```bash
chmod +x setup_keyboard.sh
sudo ./setup_keyboard.sh
```

Reboot after installation:

```bash
sudo reboot
```

---

## Alternative: Trixie with fbcp-ili9341

If you prefer the userspace driver on Trixie instead of the kernel-native approach:

```bash
chmod +x setup_display_trixie.sh
sudo ./setup_display_trixie.sh
```

This version:
- Detects `/boot/firmware/` vs `/boot/` config paths automatically
- Uses a systemd service instead of `rc.local`
- Dynamically detects the correct kernel headers package

Then install the keyboard driver:

```bash
chmod +x setup_keyboard_trixie.sh
sudo ./setup_keyboard_trixie.sh
```

---

## Keyboard Driver

The keyboard driver is a kernel module (`picocalc_kbd.ko`) that handles the I2C-connected keyboard on the PicoCalc. It works with all OS versions.

### Files

| File | Description |
|------|-------------|
| `picocalc_kbd/picocalc_kbd.c` | Kernel module source |
| `picocalc_kbd/dts/picocalc_kbd-overlay.dts` | Device tree overlay source |
| `picocalc_kbd/dts/picocalc_kbd.dtbo` | Pre-compiled overlay |

### After installation

Verify the module is loaded:

```bash
lsmod | grep picocalc_kbd
dmesg | grep picocalc
```

---

## Audio Setup

Audio is routed through the GPIO PWM pins (GPIO 12 and GPIO 13).

Edit your config file:

```bash
sudo nano /boot/firmware/config.txt   # Trixie
# or
sudo nano /boot/config.txt            # Bullseye
```

Add these lines at the end:

```text
dtparam=audio=on
dtoverlay=audremap,pins_12_13
```

Reboot to apply:

```bash
sudo reboot
```

### Verify audio

```bash
aplay -l
speaker-test -c 2 -t wav
```

---

## Troubleshooting

### Display not working

**Check framebuffer devices:**

```bash
ls /dev/fb*
```

You should see `fb0` (HDMI) and `fb1` (TFT).

**Check kernel driver logs:**

```bash
dmesg | grep fbtft
dmesg | grep ili9488
```

**For fbcp-ili9341 method, check service status:**

```bash
sudo systemctl status fbcp-ili9341
cat /var/log/fbcp-ili9341.log
```

**Verify SPI is enabled:**

```bash
raspi-config nonint get_spi
# Should return 0 (enabled)
```

### Keyboard not working

**Check I2C is enabled:**

```bash
raspi-config nonint get_i2c
# Should return 0 (enabled)
```

**Check kernel module:**

```bash
lsmod | grep picocalc_kbd
dmesg | grep picocalc
```

**Check DT overlay loaded:**

```bash
vcgencmd dtoverlay
# Should show picocalc_kbd
```

### Config file path confusion

| OS Version | Config Path | Overlays Path |
|------------|-------------|---------------|
| Trixie | `/boot/firmware/config.txt` | `/boot/firmware/overlays/` |
| Bullseye | `/boot/config.txt` | `/boot/overlays/` |

All scripts auto-detect the correct paths.

### Display rotation

If the display orientation is wrong, edit the device tree overlay in `setup_display_kernel.sh` and change the `rotate` value:

- `0` = 0° (landscape)
- `90` = 90° (portrait)
- `180` = 180° (landscape, flipped)
- `270` = 270° (portrait, flipped) — **default for PicoCalc**

Then re-run the script.

### Performance tuning

For the kernel fbtft driver, you can adjust SPI speed in the device tree overlay. Default is 32MHz. Some displays support up to 48MHz:

```dts
spi-max-frequency = <48000000>;
```

For fbcp-ili9341, adjust `SPI_BUS_CLOCK_DIVISOR` in the cmake command (lower = faster).

---

## Credits

- **Original fbcp-ili9341 fork:** [wasdwasd0105/fbcp-ili9341-picocalc](https://github.com/wasdwasd0105/fbcp-ili9341-picocalc)
- **4" ILI9488 script reference:** [AdamoMD/4inchILI9488RpiScript](https://github.com/adamomd/4inchILI9488RpiScript/)
- **PicoCalc hardware:** Clockwork Pi

---

## License

See original repository for licensing information.
