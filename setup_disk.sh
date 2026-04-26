#!/bin/bash

# ==============================================================================
# Script Name: setup_disk.sh
# Description: Initialize SD Card for PiStorm32-lite / Emu68 using hst-imager
# ==============================================================================

#set -e

# --- Default Variables ---
EMU68_RELEASE_URL="https://github.com/michalsc/Emu68/releases/latest/download/Emu68-pistorm32lite.zip"
HST_IMAGER_REPO="henrikstengaard/hst-imager"
TMP_DIR="/tmp/pistorm_setup"
MOUNT_POINT="/mnt/emu68_boot"

# --- Functions ---

usage() {
    echo "Usage: sudo $0 --disk [DEVICE] --kickstart [ROM_PATH] [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  -d, --disk        Path to disk device (e.g., /dev/sdc)"
    echo "  -k, --kickstart   Path to Amiga Kickstart ROM file"
    echo ""
    echo "Options:"
    echo "  -c, --config      Path to custom config.txt"
    echo "  -l, --cmdline     Path to custom cmdline.txt"
    echo "  -h, --help        Display this help message"
    exit 1
}

log_info() {
    echo -e "[\e[34mINFO \e[0m] $1"
}

log_success() {
    echo -e "[\e[32m OK  \e[0m] $1"
}

log_error() {
    echo -e "[\e[31mERROR\e[0m] $1"
    exit 1
}

check_dependencies() {
    local deps=("wget" "unzip" "sed" "partprobe" "mount" "umount" "curl")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found. Please install it."
        fi
    done
}

get_hst_imager() {
    log_info "Detecting architecture and downloading hst-imager..."
    local arch=$(uname -m)
    local suffix=""

    case "$arch" in
        x86_64)  suffix="linux_x64" ;;
        aarch64) suffix="linux_arm64" ;;
        armv7l)  suffix="linux_arm" ;;
        *) log_error "Unsupported architecture: $arch" ;;
    esac

    # Get the latest download URL for the specific architecture
    local download_url=$(curl -s https://api.github.com/repos/${HST_IMAGER_REPO}/releases/latest \
        | grep "browser_download_url" \
        | grep "$suffix.zip" \
        | cut -d '"' -f 4)

    if [[ -z "$download_url" ]]; then
        log_error "Could not find hst-imager binary for $suffix"
    fi

    wget -q --show-progress "$download_url" -O hst-imager.zip
    if [[ $? -ne 0 ]]; then
        log_error "Could not download $download_url"
    fi
    unzip -q hst-imager.zip hst.imager
    chmod +x hst.imager
    log_success "hst.imager ($suffix) is ready."
}

# --- Argument Parsing ---

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--disk) 
            DISK_PATH="$2"
            shift 2 ;;
        -k|--kickstart) 
            KICKSTART_PATH=$(readlink -f "$2")
            shift 2 ;;
        -c|--config) 
            CUSTOM_CONFIG=$(readlink -f "$2")
            shift 2 ;;
        -l|--cmdline) 
            CUSTOM_CMDLINE=$(readlink -f "$2")
            shift 2 ;;
        -h|--help) 
            usage ;;
        *) 
            shift ;;
    esac
done

# Initial Validations
[[ -z "$DISK_PATH" ]] && usage
[[ -z "$KICKSTART_PATH" ]] && usage
[[ ! -f "$KICKSTART_PATH" ]] && log_error "Kickstart file not found."
[[ $(id -u) -ne 0 ]] && log_error "This script must be run as root (sudo)."

check_dependencies

# Workspace preparation
rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR/emu68_files"
cp contribs/ps32lite-stealth-firmware.gz "$TMP_DIR/emu68_files/"
cp contribs/pfs3aio "$TMP_DIR/"
cd "$TMP_DIR"

# Setup hst.imager
get_hst_imager
HST_BIN="./hst.imager"

# Download Emu68
log_info "Downloading latest Emu68 release..."
wget -q --show-progress "$EMU68_RELEASE_URL" -O emu68.zip
if [[ $? -ne 0 ]]; then
    log_error "Could not download $EMU68_RELEASE_URL"
fi
unzip -q emu68.zip -d emu68_files
log_success "Emu68 downloaded and extracted."

# Prepare Partition Script
log_info "Preparing partition config file for $DISK_PATH..."
if [[ ! -f "$OLDPWD/partitions.config" ]]; then
    log_error "Template partitions.config not found in working directory."
fi
sed "s|\[PATH_TO_DISK\]|$DISK_PATH|g" "$OLDPWD/partitions.config" > generated_partitions.config

# Execute hst.imager
log_info "Initializing disk and creating partitions..."
$HST_BIN script generated_partitions.config > /dev/null
if [[ $? -ne 0 ]]; then
    log_error "could not initialize disk with : $HST_BIN script generated_partitions.config"
fi
log_success "Disk partitioned and RDB initialized."

# Prepare emu68
log_info "Setting up EMU68 boot partition..."
[[ -n "$CUSTOM_CONFIG" ]] && cp "$CUSTOM_CONFIG" emu68_files/config.txt
[[ -n "$CUSTOM_CMDLINE" ]] && cp "$CUSTOM_CMDLINE" emu68_files/cmdline.txt
cp "$KICKSTART_PATH" emu68_files/kick.rom

# mount freshly created emu68 partition 
mkdir -p "$MOUNT_POINT"
partprobe "$DISK_PATH"
sleep 2 
mount "${DISK_PATH}1" "$MOUNT_POINT" || log_error "Failed to mount ${DISK_PATH}1"

# copy emu68 files to partition
log_info "Copying files to ${DISK_PATH}1..."
cp -r emu68_files/* "$MOUNT_POINT/"
sync

umount "$MOUNT_POINT"
log_success "Emu68 installation complete."

# Cleanup
rm -rf "$TMP_DIR"
log_info "Process finished successfully."