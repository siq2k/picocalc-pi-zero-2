#!/bin/bash
set -e

MODULE_NAME=picocalc_kbd
SRC_DIR=./picocalc_kbd
DTBO_DIR=./picocalc_kbd/dts
KO_FILE=${MODULE_NAME}.ko
DTBO_FILE=${MODULE_NAME}.dtbo

# Detect config.txt path (Trixie uses /boot/firmware/, older uses /boot/)
if [ -d "/boot/firmware" ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
    echo "Detected Trixie-style boot path: /boot/firmware/"
else
    CONFIG_FILE="/boot/config.txt"
    echo "Detected legacy boot path: /boot/"
fi

echo "🔧 Step 1: Installing dependencies..."
sudo apt update

# Detect correct kernel headers package for this OS version
HEADERS_PKG=""
if dpkg -l raspberrypi-kernel-headers 2>/dev/null | grep -q "^ii"; then
    HEADERS_PKG="raspberrypi-kernel-headers"
    echo "Found installed: raspberrypi-kernel-headers"
elif dpkg -l raspberrypi-kernel 2>/dev/null | grep -q "^ii"; then
    HEADERS_PKG="raspberrypi-kernel"
    echo "Found installed: raspberrypi-kernel"
elif apt-cache search raspberrypi-kernel-headers 2>/dev/null | grep -q "raspberrypi-kernel-headers"; then
    HEADERS_PKG="raspberrypi-kernel-headers"
    echo "Will install: raspberrypi-kernel-headers"
else
    HEADERS_PKG="raspberrypi-kernel"
    echo "Will install: raspberrypi-kernel (fallback)"
fi

sudo apt install -y \
    build-essential \
    ${HEADERS_PKG} \
    device-tree-compiler \
    git

echo "🔧 Step 2: Building kernel module in ${SRC_DIR}..."
make -C /lib/modules/$(uname -r)/build M=$(realpath ${SRC_DIR}) modules

echo "📁 Step 3: Installing kernel module to system..."
sudo mkdir -p /lib/modules/$(uname -r)/extra
sudo cp ${SRC_DIR}/${KO_FILE} /lib/modules/$(uname -r)/extra/
sudo depmod

echo "📄 Step 4: Installing DTBO to /boot/overlays/..."
# Create overlays directory if it doesn't exist (path may vary)
if [ -d "/boot/firmware/overlays" ]; then
    OVERLAYS_DIR="/boot/firmware/overlays"
else
    OVERLAYS_DIR="/boot/overlays"
    sudo mkdir -p "$OVERLAYS_DIR"
fi
echo "Installing DTBO to: ${OVERLAYS_DIR}"
sudo cp ${DTBO_DIR}/${DTBO_FILE} "${OVERLAYS_DIR}/"

echo "📝 Step 5: Updating config.txt..."

# Helper function to add config lines if not present
add_config_line() {
    local line="$1"
    if ! grep -q "^${line}" "$CONFIG_FILE"; then
        # Prepend to config file
        sudo sed -i "1i ${line}" "$CONFIG_FILE"
        echo "Added: ${line}"
    else
        echo "Already present: ${line}"
    fi
}

add_config_line "dtoverlay=${MODULE_NAME}"
add_config_line "dtparam=i2c_arm=on"

# Remove duplicates in config.txt
echo "Cleaning up duplicate entries in config.txt..."
sudo awk '!seen[$0]++' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
sudo mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo "✅ Installation complete."
echo "🔁 Reboot now to activate the driver:"
echo "    sudo reboot"
