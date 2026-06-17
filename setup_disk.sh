#!/usr/bin/env bash

# ==============================================================================
# Disk setup script
# The main purpose is to partition disk both for emu68 and AmigaOS 
# 
# The partitioning is based on "partitions.config" file. It create a new MBR
# structure with 2 partitions
#   - part 1 : fat32, dedicated to emu68 (which is autoamtically installed
#   - part 2 : 0x76, contains Amiga RDB partitions which are formated
# ==============================================================================

set -e

__DEPENDENCIES__=("wget" "unzip" "sed" "partprobe" "mount" "umount" "curl" "sudo")
CLEAN_UP=false

source main.config
source functions.sh

usage() {
    echo "Usage: $0 --disk [DEVICE] --kickstart [ROM_PATH] [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  -d, --disk        Path to disk device (e.g., /dev/sdc)"
    echo "  -k, --kickstart   Path to Amiga Kickstart ROM file"
    echo ""
    echo "Options:"
    echo "  -c, --config      Path to custom config.txt"
    echo "  -l, --cmdline     Path to custom cmdline.txt"
    echo "  --clean-on-close  Remove downloads and extractions after completion"
    echo "  -h, --help        Display this help message"
    echo ""
    echo "Note that this script requires root privileges via sudo to run certain commands."
    exit 1
}


# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--disk)          DISK_PATH="$2";                     shift 2 ;;
        -k|--kickstart)     KICKSTART_PATH=$(readlink -f "$2"); shift 2 ;;
        -c|--config)        CUSTOM_CONFIG=$(readlink -f "$2");  shift 2 ;;
        -l|--cmdline)       CUSTOM_CMDLINE=$(readlink -f "$2"); shift 2 ;;
        --clean-on-close)   CLEAN_UP=true;                      shift ;;
        -h|--help) usage ;;
        *) shift ;;
    esac
done

# Basic Validations
[[ -z "$DISK_PATH"          ]] && usage
[[ -z "$KICKSTART_PATH"     ]] && usage
[[ ! -f "$KICKSTART_PATH"   ]] && log_error "Kickstart file not found."

# ensure all needed programs are presents
check_dependencies

# Workspace preparation
mkdir -p "$TMP_SETUP_DIR/emu68_files"
cp contribs/ps32lite-stealth-firmware.gz "$TMP_SETUP_DIR/emu68_files/"
cp contribs/pfs3aio "$TMP_SETUP_DIR/"
cd "$TMP_SETUP_DIR"

# Download hst imager if not yet done
get_hst_tool "hst.imager"

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

# initialize disc and create Amiga partitions
log_info "Initializing disk and creating partitions..."
sudo $HST_BIN script generated_partitions.config > /dev/null
if [[ $? -ne 0 ]]; then
    log_error "could not initialize disk with : $HST_BIN script generated_partitions.config"
fi
log_success "Disk partitioned and RDB initialized."

# Check for custom files for emu68
log_info "Setting up EMU68 boot partition..."
[[ -n "$CUSTOM_CONFIG" ]] && cp "$CUSTOM_CONFIG" emu68_files/config.txt
[[ -n "$CUSTOM_CMDLINE" ]] && cp "$CUSTOM_CMDLINE" emu68_files/cmdline.txt
cp "$KICKSTART_PATH" emu68_files/kick.rom

# mount the just created emu68 partition 
mkdir -p "$MOUNT_POINT"
sudo partprobe "$DISK_PATH"
sleep 2 
sudo mount "${DISK_PATH}1" "$MOUNT_POINT" || log_error "Failed to mount ${DISK_PATH}1"

# copy emu68 files to partition
log_info "Copying files to ${DISK_PATH}1..."
sudo cp -r emu68_files/* "$MOUNT_POINT/"
sudo sync

sudo umount "$MOUNT_POINT"
log_success "Emu68 installation complete."


# Cleanup if needed
if [ "$CLEAN_UP" = true ]; then
    log_info "Cleaning up temporary extraction files..."
    rm -rf "$TMP_SETUP_DIR"
fi

log_info "Process finished successfully."