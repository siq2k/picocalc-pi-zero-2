#!/bin/bash

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo ./setup_display_kernel.sh"
   exit 1
fi

# Introduction and confirmation
clear
echo "TFT 4\" Kernel-Native Setup Script for ILI9488 on PicoCalc with Pi Zero 2"
echo "Uses the kernel's built-in fbtft driver (no fbcp required)"
echo "Tested for TFT 4\" displays with dimensions 480x320."
echo
echo "This process will:"
echo "  - Enable SPI interface"
echo "  - Configure the kernel fbtft driver via device tree overlay"
echo "  - Update config.txt with display settings"
echo
echo "At the end of the process, your Raspberry Pi will automatically reboot."
echo
read -p "Do you authorize this process and accept full responsibility for any changes? (Y/N): " user_input
if [[ "$user_input" != "Y" && "$user_input" != "y" ]]; then
    echo "No changes have been made. Process aborted."
    exit 0
fi

# Ensure locale settings
export LANGUAGE="en_GB.UTF-8"
export LC_ALL="en_GB.UTF-8"
export LC_CTYPE="en_GB.UTF-8"
export LANG="en_GB.UTF-8"

# Detect config.txt path (Trixie uses /boot/firmware/, older uses /boot/)
if [ -d "/boot/firmware" ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
    echo "Detected Trixie-style boot path: /boot/firmware/"
else
    CONFIG_FILE="/boot/config.txt"
    echo "Detected legacy boot path: /boot/"
fi

# Enable SPI using raspi-config
echo "Enabling SPI interface using raspi-config..."
raspi-config nonint do_spi 0

# Prompt before modifying config.txt
echo
echo "The script will now modify the Raspberry Pi configuration file (config.txt)."
echo "Existing lines that are changed will be commented with a note."
read -p "Do you accept these changes and wish to proceed? (Y/N): " config_input
if [[ "$config_input" != "Y" && "$config_input" != "y" ]]; then
    echo "No changes have been made to the configuration file. Process aborted."
    exit 0
fi

update_config() {
    local key=$1
    local value=$2

    # Check if the key already exists (commented or uncommented)
    if grep -q "^[#]*$key" "$CONFIG_FILE"; then
        # Uncomment and update value if necessary
        sed -i "s/^#[[:space:]]*$key/$key/" "$CONFIG_FILE"
        if [ -n "$value" ]; then
            sed -i "s|^$key.*|$key=$value|" "$CONFIG_FILE"
        fi
    else
        # Add the line if it doesn't exist
        if [ -z "$value" ]; then
            echo "$key" >> "$CONFIG_FILE"
        else
            echo "$key=$value" >> "$CONFIG_FILE"
        fi
    fi
}

remove_duplicates() {
    local file=$1
    awk '!seen[$0]++' "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
}

# Comment the line max_framebuffers=2 if it exists (fbtft needs framebuffer)
if grep -q "^max_framebuffers=2" "$CONFIG_FILE"; then
    sed -i "s|^max_framebuffers=2|#max_framebuffers=2 (commented for fbtft installation on $(date +%m/%d/%Y))|" "$CONFIG_FILE"
fi

# Comment [pi4] section overrides that may conflict
sed -i '/^\[pi4\]/s/^/#/' "$CONFIG_FILE"

# Add required configuration lines
echo "# Modifications for ILI9488 kernel fbtft driver implemented on $(date +%m/%d/%Y)" >> "$CONFIG_FILE"

# Enable SPI with correct parameters
update_config "dtparam" "spi=on"

# Force HDMI output for framebuffer (so fbcp not needed)
update_config "hdmi_force_hotplug" "1"
update_config "hdmi_cvt" "480 320 60 1 0 0 0"
update_config "hdmi_group" "2"
update_config "hdmi_mode" "87"
update_config "gpu_mem" "128"

# Create custom device tree overlay for ILI9488
echo "Compiling custom ILI9488 device tree overlay..."

# Create temporary DTS file
DTS_TEMP=$(mktemp /tmp/ili9488-picocalc-XXXXXX.dts)
DTBO_OUTPUT="/boot/firmware/overlays/ili9488-picocalc.dtbo"

# Detect overlays directory
if [ -d "/boot/firmware/overlays" ]; then
    OVERLAYS_DIR="/boot/firmware/overlays"
else
    OVERLAYS_DIR="/boot/overlays"
    mkdir -p "$OVERLAYS_DIR"
fi
DTBO_OUTPUT="${OVERLAYS_DIR}/ili9488-picocalc.dtbo"

cat > "$DTS_TEMP" <<'DTEOF'
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2835";

    fragment@0 {
        target = <&spi0>;
        __overlay__ {
            status = "okay";

            ili9488@0 {
                compatible = "ilitek,ili9488";
                reg = <0>;
                spi-max-frequency = <32000000>;
                rotate = <270>;
                fps = <30>;
                buswidth = <8>;
                dc-gpios = <&gpio 24 0>;   /* GPIO 24, active high */
                reset-gpios = <&gpio 25 0>; /* GPIO 25, active high */
                debug = <0>;
            };
        };
    };
};
DTEOF

# Compile and install the overlay
if command -v dtc &> /dev/null; then
    dtc -@ -I dts -O dtb -o "$DTBO_OUTPUT" "$DTS_TEMP" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "Successfully compiled ILI9488 DT overlay to: $DTBO_OUTPUT"
        rm -f "$DTS_TEMP"
    else
        echo "Warning: DT compilation failed. Installing dtc..."
        apt install -y device-tree-compiler
        dtc -@ -I dts -O dtb -o "$DTBO_OUTPUT" "$DTS_TEMP"
        if [ $? -eq 0 ]; then
            echo "Successfully compiled ILI9488 DT overlay after installing dtc."
            rm -f "$DTS_TEMP"
        else
            echo "ERROR: Failed to compile device tree overlay."
            echo "You may need to install dtc manually: sudo apt install device-tree-compiler"
            rm -f "$DTS_TEMP"
            exit 1
        fi
    fi
else
    echo "Installing device-tree-compiler..."
    apt install -y device-tree-compiler
    dtc -@ -I dts -O dtb -o "$DTBO_OUTPUT" "$DTS_TEMP"
    if [ $? -eq 0 ]; then
        echo "Successfully compiled ILI9488 DT overlay."
        rm -f "$DTS_TEMP"
    else
        echo "ERROR: Failed to compile device tree overlay."
        rm -f "$DTS_TEMP"
        exit 1
    fi
fi

# Add the custom overlay to config.txt
update_config "dtoverlay" "ili9488-picocalc"

echo "# Kernel fbtft setup complete" >> "$CONFIG_FILE"

# Remove duplicates in config.txt
echo "Removing duplicate lines in config.txt..."
remove_duplicates "$CONFIG_FILE"

# Ensure fbtft modules are loaded
echo "Configuring fbtft kernel modules..."
cat <<'EOT' > /etc/modules-load.d/fbtft.conf
fbtft
fb_ili9488
EOT

# Create udev rule for framebuffer device (optional but helpful)
echo "Creating udev rule for framebuffer device..."
cat <<'EOT' > /etc/udev/rules.d/99-fbtft.rules
SUBSYSTEM=="graphics", KERNEL=="fb1", SYMLINK+="fbtft", MODE="0666"
EOT

udevadm control --reload-rules 2>/dev/null || true

# Finish and force reboot
echo "Finalizing processes..."
sync

echo -e "\nSetup complete. The Raspberry Pi will now reboot."
echo "After reboot, the fbtft driver should load automatically."
echo "You can verify with: ls /dev/fb*  and  dmesg | grep fbtft"
sudo reboot
