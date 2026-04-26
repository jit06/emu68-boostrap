#!/bin/bash

# ==============================================================================
# Script Name: deploy_packages.sh
# Description: Deploy Amiga packages to RDB partitions using .desc files
# Author: AI Collaborator
# ==============================================================================

#set -e

# --- Global Variables ---
HST_IMAGER_REPO="henrikstengaard/hst-imager"
TMP_DOWNLOAD_DIR="/tmp/amiga_downloads"
TMP_EXTRACT_DIR="/tmp/amiga_extract"
STAGING_ROOT="/tmp/amiga_staging"
HST_BIN="./contribs/hst.imager"

# USER_MAP: Maps Volume Labels (Workbench) to Device Names (SDH0) via CLI
# RDB_MAP:  Maps Device Names (SDH0) to RDB Indices (1) via disk scan
declare -A USER_MAP
declare -A RDB_MAP

# --- Functions ---

usage() {
    echo "Usage: sudo $0 --package-list [FILE] --packages-path [DIR] --disk [DEVICE] [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  -l, --package-list   Path to the package-list file"
    echo "  -p, --packages-path  Directory containing .desc files"
    echo "  -d, --disk           Path to the physical disk (e.g. /dev/sdc)"
    echo ""
    echo "Options:"
    echo "  -m, --mapping        Map Device to Volume (e.g., --mapping SDH0=Workbench)"
    echo "                       Can be used multiple times."
    echo "  --clean-on-close     Remove downloads and extractions after completion"
    echo "  -h, --help           Display this help"
    exit 1
}

log_info() { echo -e "[\e[34mINFO \e[0m] $1"; }
log_success() { echo -e "[\e[32m OK  \e[0m] $1"; }
log_error() { echo -e "[\e[31mERROR\e[0m] $1"; exit 1; }

check_dependencies() {
    local deps=("wget" "unzip" "lha" "unadf" "readlink" "curl" "sed" "gunzip")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found. Please install it."
        fi
    done
}

get_hst_imager() {
    if [[ -f "$HST_BIN" ]]; then
        log_info "hst.imager already present, skipping download."
        return
    fi

    log_info "Detecting architecture and downloading hst-imager..."
    local arch=$(uname -m)
    local suffix=""

    case "$arch" in
        x86_64)  suffix="linux_x64" ;;
        aarch64) suffix="linux_arm64" ;;
        armv7l)  suffix="linux_arm" ;;
        *) log_error "Unsupported architecture: $arch" ;;
    esac

    local download_url=$(curl -s https://api.github.com/repos/${HST_IMAGER_REPO}/releases/latest \
        | grep "browser_download_url" \
        | grep "$suffix.zip" \
        | cut -d '"' -f 4)

    if [[ -z "$download_url" ]]; then
        log_error "Could not find hst-imager binary for $suffix"
    fi

    mkdir -p ./contribs
    wget -q --show-progress "$download_url" -O ./contribs/hst-imager.zip
    if [[ $? -ne 0 ]]; then
        log_error "Could not download $download_url"
    fi
    unzip -q -o ./contribs/hst-imager.zip -d ./contribs/ hst.imager
    chmod +x ./contribs/hst.imager
    log_success "./contribs/hst.imager ($suffix) is ready."
}

build_rdb_cache() {
    local disk="$1"
    log_info "Scanning disk RDB for device names..."

    local rdb_info=$($HST_BIN rdb info "${disk}/mbr/2")
    
    local in_partition_section=false

    while read -r line; do
        # 1. Detect start of the correct section
        if [[ "$line" =~ "Partitions:" ]]; then
            in_partition_section=true
            continue
        fi

        # 2. Detect end of the section (to stop parsing)
        if [[ "$line" =~ "Partition table overview" ]]; then
            in_partition_section=false
        fi

        # 3. Only process lines if we are inside the toggle range
        if [ "$in_partition_section" = true ]; then
            # Matches the format: index | Name | Size | ...
            # Specifically looks for the index and the Name between the first two pipes
            if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]*\|[[:space:]]*([^[:space:]|]+)[[:space:]]*\| ]]; then
                local idx="${BASH_REMATCH[1]}"
                local dev_name="${BASH_REMATCH[2],,}" 
                RDB_MAP["$dev_name"]="$idx"
                log_info "RDB Discovery: Device '$dev_name' is at index $idx"
            fi
        fi
    done <<< "$rdb_info"

    if [[ ${#RDB_MAP[@]} -eq 0 ]]; then
        log_error "No RDB partitions found on ${disk}/mbr/2. Please check hst.imager output."
    fi
}

get_rdb_path() {
    local full_amiga_path="$1"
    local disk="$2"
    
    local volume="${full_amiga_path%%:*}"
    local volume_lc="${volume,,}"
    local sub_path="${full_amiga_path#*:}"
    
    # 1. Look for user mapping (Volume Label -> Device Name)
    local dev_name="${USER_MAP[$volume_lc]}"
    
    # 2. Fallback: if no mapping, assume the .desc used the Device Name directly
    if [[ -z "$dev_name" ]]; then
        dev_name="$volume_lc"
    fi

    # 3. Look for technical index (Device Name -> Index)
    local part_idx="${RDB_MAP[$dev_name]}"

    if [[ -z "$part_idx" ]]; then
        log_error "Volume/Device '$volume' could not be resolved. Check your --mapping or RDB setup."
    fi

    # Return hst.imager format: [DISK]/mbr/2/rdb/[IDX]/[PATH]
    echo "${disk}/mbr/2/rdb/${part_idx}/${sub_path}"
}

# --- Argument Parsing ---

CLEAN_UP=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--package-list) LIST_PATH=$(readlink -f "$2"); shift 2 ;;
        -p|--packages-path) DESC_DIR=$(readlink -f "$2"); shift 2 ;;
        -d|--disk) DISK_DEVICE="$2"; shift 2 ;;
        -m|--mapping)
            IFS="=" read -r dev vol <<< "$2"
            USER_MAP["${vol,,}"]="${dev,,}"
            log_info "Mapping registered: Volume '${vol,,}' will use Device '${dev,,}'"
            shift 2 ;;
        --clean-on-close) CLEAN_UP=true; shift ;;
        -h|--help) usage ;;
        *) shift ;;
    esac
done

# Basic Validations
[[ -z "$LIST_PATH" || -z "$DESC_DIR" || -z "$DISK_DEVICE" ]] && usage
[[ $(id -u) -ne 0 ]] && log_error "This script must be run as root (sudo)."

check_dependencies
get_hst_imager

# Initialize disk cache
build_rdb_cache "$DISK_DEVICE"

# --- Phase 1: Verification & Pre-download ---

log_info "Phase 1: Verifying components and downloading missing archives..."
mkdir -p "$TMP_DOWNLOAD_DIR" "$TMP_EXTRACT_DIR"
declare -A PKG_SOURCES

while read -r pkg_name pkg_source || [[ -n "$pkg_name" ]]; do
    [[ -z "$pkg_name" || "$pkg_name" =~ ^# ]] && continue

    desc_file="${DESC_DIR}/${pkg_name}.desc"
    if [[ ! -f "$desc_file" ]]; then
        log_error "Description file not found for package: $pkg_name"
    fi

    if [[ "$pkg_source" =~ ^http ]]; then
        local_archive="${TMP_DOWNLOAD_DIR}/$(basename "$pkg_source")"
        if [[ ! -f "$local_archive" ]]; then
            log_info "Downloading $pkg_name from $pkg_source..."
            wget -q --show-progress "$pkg_source" -O "$local_archive"
        fi
        PKG_SOURCES["$pkg_name"]="$local_archive"
    else
        abs_source=$(readlink -f "$pkg_source")
        if [[ ! -f "$abs_source" ]]; then
            log_error "Local archive not found: $pkg_source"
        fi
        PKG_SOURCES["$pkg_name"]="$abs_source"
    fi
done < "$LIST_PATH"

log_success "All archives and descriptions are verified."

# --- Phase 2: Deployment ---

# --- Phase 2: Optimized Deployment ---
log_info "Phase 2: Deploying files using local staging..."

STAGING_ROOT="/tmp/amiga_staging"
rm -rf "$STAGING_ROOT" && mkdir -p "$STAGING_ROOT"

# 1. Prepare Local Staging Area
while read -r pkg_name pkg_source || [[ -n "$pkg_name" ]]; do
    [[ -z "$pkg_name" || "$pkg_name" =~ ^# ]] && continue

    archive="${PKG_SOURCES[$pkg_name]}"
    desc_file="${DESC_DIR}/${pkg_name}.desc"
    extract_path="${TMP_EXTRACT_DIR}/${pkg_name}"
    
    log_info "Staging package: $pkg_name"
    mkdir -p "$extract_path"

    # Extraction
    case "${archive,,}" in
        *.lha) lha xqW="$extract_path" "$archive" > /dev/null ;;
        *.zip) unzip -q -o "$archive" -d "$extract_path" ;;
        *.adf) cd "$extract_path" && unadf -w "$archive" &> /dev/null && cd - > /dev/null ;;
    esac

    # Build local tree
    #while IFS=$'\t ' read -r src_raw dest_raw || [[ -n "$src_raw" ]]; do
    iconv -f UTF-8 -t ISO-8859-1 "$desc_file" | while IFS=$'\t ' read -r src_raw dest_raw || [[ -n "$src_raw" ]]; do
        [[ -z "$src_raw" || "$src_raw" =~ ^# ]] && continue

        # remove quotes and trailing slashes if any
        src_item=$(echo "$src_raw" | sed 's/^"\(.*\)"$/\1/; s/\/$//')
        dest_amiga=$(echo "$dest_raw" | sed 's/^"\(.*\)"$/\1/; s/\/$//')
        
        #echo "src=$src_item > dst=$dest_amiga"

        # Get Volume and Subpath
        vol_name="${dest_amiga%%:*}"
        sub_path="${dest_amiga#*:}"

        # Create staging directory for this specific volume
        local_vol_stage="${STAGING_ROOT}/${vol_name,,}"
        if [[ ! -e "${local_vol_stage}/$(dirname "$sub_path")" ]]; then
            mkdir -p "${local_vol_stage}/$(dirname "$sub_path")"
            #echo "mkdir=${local_vol_stage}/$(dirname "$sub_path")"
        fi
        real_src="${extract_path}/${src_item}"
        
        # Handle .z decompression
        if [[ "$src_item" =~ \.[zZ]$ && -f "$real_src" ]]; then
            gunzip -c "$real_src" > "${real_src%.*}" && real_src="${real_src%.*}"
        fi

        # && -e "${local_vol_stage}/${sub_path}"
        if [[ -e "$real_src" ]]; then
            if [[ -d "$real_src" ]] ; then
                sub_path="$(dirname "$sub_path")"
            fi
            
            # Copy to local staging
            cp -rf "$real_src" "${local_vol_stage}/${sub_path}"
            #echo "COPY $real_src TO ${local_vol_stage}/${sub_path}"
        fi
    done < "$desc_file"
done < "$LIST_PATH"

# 2. Bulk Copy to Disk (One call per Volume)
log_info "Performing bulk transfer to disk..."

for vol_dir in "$STAGING_ROOT"/*; do
    if [ -d "$vol_dir" ]; then
        
        vol_label=$(basename "$vol_dir")
        
        # Resolve the RDB path for the root of the volume
        # We pass "Volume:" to get the root partition path
        target_rdb_base=$(get_rdb_path "${vol_label}:" "$DISK_DEVICE")
        
        get_rdb_path "${vol_label}:" "$DISK_DEVICE"
        
        log_info "Transferring all files to Volume: $vol_label..."
        
        # Copy the entire staged content in one go
        # Note: we copy the content of the folder, not the folder itself
        $HST_BIN fs copy "$vol_dir/" "$target_rdb_base" --recursive --force --quiet &> /dev/null

        if [[ $? != 0 ]]; then
            log_error "An error occured while copying files"
        fi
    fi
done

# --- Cleanup ---

if [ "$CLEAN_UP" = true ]; then
    log_info "Cleaning up temporary extraction files..."
    rm -rf "$TMP_EXTRACT_DIR"
    log_info "Cleaning up downloaded archives..."
    rm -rf "$TMP_DOWNLOAD_DIR"
fi

log_success "Deployment process finished."