#!/bin/bash

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo ./setup_display_trixie.sh"
   exit 1
fi

# Introduction and confirmation
clear
echo "TFT 4\" Setup Script for ILI9488 on PicoCalc with Pi Zero 2"
echo "Compatible with Raspberry Pi OS Trixie (32-bit)"
echo "Tested for TFT 4\" displays with dimensions 320x320."
echo "This process involves modifying system files, downloading files, and installing dependencies."
echo "These changes may affect the functionality of your Raspberry Pi."
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

# Begin setup
echo "Starting TFT setup..."

# Update system and install dependencies
echo "Updating the system and installing dependencies..."
apt update && apt upgrade -y
apt install -y cmake git build-essential nano

# Configure fbcp-ili9341
echo "Downloading and configuring fbcp-ili9341..."
if [ ! -d "fbcp-ili9341-picocalc" ]; then
    git clone https://github.com/wasdwasd0105/fbcp-ili9341-picocalc.git
fi
cd fbcp-ili9341-picocalc
mkdir -p build
cd build
rm -rf *
cmake -DUSE_GPU=ON -DSPI_BUS_CLOCK_DIVISOR=12 \
      -DGPIO_TFT_DATA_CONTROL=24 -DGPIO_TFT_RESET_PIN=25 \
      -DILI9488=ON -DUSE_DMA_TRANSFERS=ON -DDMA_TX_CHANNEL=10 -DDMA_RX_CHANNEL=11 -DSTATISTICS=0 ..
make -j$(nproc)
sudo install fbcp-ili9341 /usr/local/bin/

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
    # Retain line breaks and remove duplicate lines
    awk '!seen[$0]++' "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
}

# Comment the line max_framebuffers=2 if it exists
if grep -q "^max_framebuffers=2" "$CONFIG_FILE"; then
    sed -i "s|^max_framebuffers=2|#max_framebuffers=2 (line commented for TFT ILI9488 installation on $(date +%m/%d/%Y))|" "$CONFIG_FILE"
fi

# Comment the dtoverlay=vc4-kms-v3d line (required for fbcp to work)
if grep -q "^dtoverlay=vc4-kms-v3d" "$CONFIG_FILE"; then
    sed -i "s|^dtoverlay=vc4-kms-v3d|#dtoverlay=vc4-kms-v3d (line commented for TFT ILI9488 installation on $(date +%m/%d/%Y))|" "$CONFIG_FILE"
fi

# Comment [pi4] section overrides that may conflict
sudo sed -i '/^\[pi4\]/s/^/#/' "$CONFIG_FILE"

# Add required configuration lines
echo "#Modifications for ILI9488 installation implemented by the script on $(date +%m/%d/%Y)" >> "$CONFIG_FILE"
update_config "dtoverlay" "spi0-0cs"
update_config "dtparam" "spi=on"
update_config "hdmi_force_hotplug" "1"
update_config "hdmi_cvt" "320 320 60 1 0 0 0"
update_config "hdmi_group" "2"
update_config "hdmi_mode" "87"
update_config "gpu_mem" "128"
echo "# Utilized for TFT ILI9488 setup script by AdamoMD" >> "$CONFIG_FILE"
echo "# https://github.com/adamomd/4inchILI9488RpiScript/" >> "$CONFIG_FILE"
echo "# Feel free to send feedback and suggestions." >> "$CONFIG_FILE"

# Remove duplicates in config.txt
echo "Removing duplicate lines in config.txt..."
remove_duplicates "$CONFIG_FILE"

# Create systemd service for fbcp-ili9341 (replaces rc.local approach)
echo "Creating systemd service for fbcp-ili9341..."
cat <<'EOT' > /etc/systemd/system/fbcp-ili9341.service
[Unit]
Description=Framebuffer copy for ILI9488 TFT display
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/fbcp-ili9341
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/fbcp-ili9341.log
StandardError=append:/var/log/fbcp-ili9341.log

[Install]
WantedBy=multi-user.target
EOT

chmod 644 /etc/systemd/system/fbcp-ili9341.service
systemctl daemon-reload
systemctl enable fbcp-ili9341.service

# Configure sudoers for fbcp-ili9341
echo "Setting permissions in sudoers..."
VISUDO_FILE="/etc/sudoers.d/fbcp-ili9341"
if [ ! -f "$VISUDO_FILE" ]; then
    echo "ALL ALL=(ALL) NOPASSWD: /usr/local/bin/fbcp-ili9341" > "$VISUDO_FILE"
    chmod 440 "$VISUDO_FILE"
fi

# Set binary permissions
echo "Configuring permissions for fbcp-ili9341..."
chmod u+s /usr/local/bin/fbcp-ili9341

# Remove duplicates in rc.local if it exists (legacy cleanup)
RC_LOCAL="/etc/rc.local"
if [ -f "$RC_LOCAL" ]; then
    echo "Removing duplicate lines in rc.local..."
    remove_duplicates "$RC_LOCAL"
fi

# Finish and force reboot
echo "Finalizing processes..."
killall -9 fbcp-ili9341 2>/dev/null || true
sync

echo -e "\nSetup complete. The Raspberry Pi will now reboot."
sudo reboot
