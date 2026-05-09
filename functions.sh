#!/bin/bash

# ==============================================================================
#
# This file contains common functions used in all scripts
# 
# ==============================================================================

# USER_MAP: Maps Volume Labels (Workbench) to Device Names (SDH0)
# RDB_MAP:  Maps Device Names (SDH0) to RDB Indices (1) via disk scan
declare -A USER_MAP
declare -A RDB_MAP

# loggers
log_info() { echo -e "[\e[34mINFO \e[0m] $1"; }
log_success() { echo -e "[\e[32m OK  \e[0m] $1"; }
log_error() { echo -e "[\e[31mERROR\e[0m] $1"; exit 1; }
log_warn() { echo -e "[\e[33mWARN \e[0m] $1"; }


# check dependencies based on a special variable.
# __DEPENDENCIES__ must be defined on host script
check_dependencies() {
    if [[ -v $__DEPENDENCIES__ ]]; then

        for cmd in "${deps[@]}"; do
            if ! command -v "$cmd" &> /dev/null; then
                log_error "Required command '$cmd' not found. Please install it."
            fi
        done

    fi
}


# download hst-imager if not already present in contribs folder
# it only keeps the hst.imager executable, zip file is deleted
# depends on config variable HST_IMAGER_REPO
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
    rm ./contribs/hst-imager.zip

    log_success "./contribs/hst.imager ($suffix) is ready."
}


# given a source path and a package name (eg. my_software.lha)
# it tries set the target path according to Amiga "standards"
# The "SYS:" partition is hardcoded to "Workbench:"
get_generic_destination() {
    local src_path="$1"
    local pkg_name="$2"
    local dest_base=""
    local relative_path=""

    # 1. Special Case: Catalogs (must go to Locale/Catalogs/)
    if [[ "$src_path" =~ (.*)/Catalogs/(.*) ]]; then
        relative_path="${BASH_REMATCH[2]}"
        echo "Workbench:Locale/Catalogs/${relative_path}"

    # 2. Standard System Directories (C, S, L, Libs, etc.)
    elif [[ "$src_path" =~ (.*)/(c|C|s|S|l|L|LIBS|Libs|libs|Classes|Fonts|Locale|Docs|Storage)/(.*) ]]; then
        dest_base="${BASH_REMATCH[2]}"
        relative_path="${BASH_REMATCH[3]}"
        echo "Workbench:${dest_base}/${relative_path}"
        
    # 3. Devs and Prefs (including Preferences redirection)
    elif [[ "$src_path" =~ (.*)/(DEVS|Devs|devs|Prefs|Preferences)/(.*) ]]; then
        dest_base="${BASH_REMATCH[2]}"
        [[ "$dest_base" == "Preferences" ]] && dest_base="Prefs"
        relative_path="${BASH_REMATCH[3]}"
        echo "Workbench:${dest_base}/${relative_path}"

    # 4. Fallback by File Extension
    elif [[ "$src_path" == *.library ]]; then
        echo "Workbench:Libs/$(basename "$src_path")"
    elif [[ "$src_path" == *.device ]]; then
        echo "Workbench:Devs/$(basename "$src_path")"
    elif [[ "$src_path" == *.guide* ]]; then
        echo "Workbench:Docs/$(basename "$src_path")"
    elif [[ "$src_path" == *.doc* ]]; then
        echo "Workbench:Docs/$(basename "$src_path")"
    elif [[ "$src_path" == *handler* ]]; then
        echo "Workbench:L/$(basename "$src_path")"

    # 5. Default: Apps/<PackageName>/...
    else
        echo "Apps:${src_path}"
    fi
}


# Create and return a mapping between RDB parition number and their name 
# eg. 1 => SDH0, 2=> SDH1, etc.
# It allows to easily match formated disk names with partition names 
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
        log_error "No RDB partitions found on ${disk}/mbr/2 (did you run setup_disk.sh ?)."
    fi
}


# Convert an Amiga path to hst.image compatible path 
# eg. SDH0:Prefs/Presets may become /dev/sdc/mbr/2/rdb/1/Prefs/Presets
# Used in conjunction with build_rdb_cache
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