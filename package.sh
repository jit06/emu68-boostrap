#!/bin/bash

# ==============================================================================
# Package deployment script
# The main purpose is to copy files to Amiga RDB Partitions according to packages 
# 
# The copy is based on 
#   - a "PackageList" file which describes source materials (local or http) 
#   - a "PackageDesc" file that defines where sources must be copied
# ==============================================================================

#set -e

__DEPENDENCIES__=("wget" "unzip" "lha" "unadf" "readlink" "curl" "sed" "gunzip")
CLEAN_UP=false

source main.config
source functions.sh

usage() {
    echo "Usage: sudo $0 --disk [DEVICE] [OPTIONS]"
    echo ""
    echo "Required (choose one):"
    echo "  -i, --install        Names of packages to install (e.g. OS32,Addons)"
    echo "  OR"
    echo "  -l, --package-list   Path to a custom package-list file"
    echo "  -p, --packages-path  Directory containing associated .desc files"
    echo ""
    echo "Required:"
    echo "  -d, --disk           Path to the physical disk (e.g. /dev/sdc)"
    echo ""
    echo "Options:"
    echo "  -m, --mapping        Map Device to Volume (e.g., --mapping SDH0=Workbench)"
    echo "  --clean-on-close     Remove downloads and extractions after completion"
    echo "  -h, --help           Display this help"
    exit 1
}


# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--install)       INSTALL_ITEMS="$2";             shift 2 ;;
        -l|--package-list)  LIST_PATH=$(readlink -f "$2");  shift 2 ;;
        -p|--packages-path) DESC_DIR=$(readlink -f "$2");   shift 2 ;;
        -d|--disk)          DISK_DEVICE="$2";               shift 2 ;;
        --clean-on-close)   CLEAN_UP=true;                  shift ;;
        -m|--mapping)
            IFS="=" read -r dev vol <<< "$2"
            USER_MAP["${vol,,}"]="${dev,,}"
            log_info "Mapping registered: Volume '${vol,,}' will use Device '${dev,,}'"
            shift 2 ;;
        -h|--help) usage ;;
        *) shift ;;
    esac
done

# Basic Validations
[[ -z "$DISK_DEVICE" ]] && usage
[[ -n "$INSTALL_ITEMS" && (-n "$LIST_PATH" || -n "$DESC_DIR") ]] && log_error "Cannot use --install with --package-list or --packages-path"
[[ -z "$INSTALL_ITEMS" && ( -z "$LIST_PATH" || -z "$DESC_DIR" ) ]] && usage
[[ $(id -u) -ne 0 ]] && log_error "This script must be run as root (sudo)."

# ensure all needed programs are presents
check_dependencies

# Download hst imager if not yet done
get_hst_imager 

# Initialize RDB index cache
build_rdb_cache "$DISK_DEVICE"

# Prepare task list
declare -a TASKS
if [[ -n "$INSTALL_ITEMS" ]]; then
    IFS=',' read -ra ADDR <<< "$INSTALL_ITEMS"
    for item in "${ADDR[@]}"; do
        TASKS+=("${PACKAGES_BASE_DIR}/${item}.list|${PACKAGES_BASE_DIR}/${item}")
    done
else
    TASKS+=("$LIST_PATH|$DESC_DIR")
fi


# Download all needed packages and check that every package has a ".desc" file 
log_info "Verifying components and downloading missing archives..."
mkdir -p "$TMP_DOWNLOAD_DIR" "$TMP_EXTRACT_DIR"
declare -A PKG_SOURCES

for task in "${TASKS[@]}"; do
    current_list="${task%%|*}"
    current_desc_dir="${task##*|}"
    
    log_info "Verifying components for list: $(basename "$current_list")"
    while read -r pkg_name pkg_source || [[ -n "$pkg_name" ]]; do
        [[ -z "$pkg_name" || "$pkg_name" =~ ^# ]] && continue

        desc_file="${current_desc_dir}/${pkg_name}.desc"
        [[ ! -f "$desc_file" ]] && log_error "Description file not found: $desc_file"

        # Handle "!" at the end of the URL to specify searching for an ADF content inside the archive
        use_archive_content=false
        if [[ "$pkg_source" =~ "!" ]]; then
            use_archive_content=true
            # Clean url for download
            pkg_source="${pkg_source%?}"
        fi

        if [[ "$pkg_source" =~ ^http ]]; then
            local_archive="${TMP_DOWNLOAD_DIR}/$(basename "$pkg_source")"
            if [[ ! -f "$local_archive" ]]; then
                log_info "Downloading $pkg_name from $pkg_source..."
                wget -q --show-progress "$pkg_source" -O "$local_archive"
            fi

            # handle the case where ADF is in archive
            if [[ "$use_archive_content" == true ]]; then
                log_info "Treating content of archive as source, searching for ADF file to extract..."
                local_archive=$(extract_adf_from_archive "${local_archive}")
            fi

            PKG_SOURCES["$pkg_name"]="$local_archive"
        else
            abs_source=$(readlink -f "$pkg_source")
            [[ ! -f "$abs_source" ]] && log_error "Local archive not found: $pkg_source"
            PKG_SOURCES["$pkg_name"]="$abs_source"
        fi
    done < "$current_list"
done

log_success "All archives and descriptions have been verified."

# map Amiga filesystem localy (staging), then copy everything to Amiga Partitions
log_info "Deploying files to local staging..."

# cleanup staging directory
rm -rf "$STAGING_ROOT" && mkdir -p "$STAGING_ROOT"

# Prepare local staging
for task in "${TASKS[@]}"; do
    current_list="${task%%|*}"
    current_desc_dir="${task##*|}"

    while read -r pkg_name pkg_source || [[ -n "$pkg_name" ]]; do
        [[ -z "$pkg_name" || "$pkg_name" =~ ^# ]] && continue

        archive="${PKG_SOURCES[$pkg_name]}"
        desc_file="${current_desc_dir}/${pkg_name}.desc"
        extract_path="${TMP_EXTRACT_DIR}/${pkg_name}"

        log_info "Staging package: $pkg_name"
        mkdir -p "$extract_path"

        case "${archive,,}" in
            *.lha) lha xqw="$extract_path" "$archive" &> /dev/null ;;
            *.zip) unzip -q -o "$archive" -d "$extract_path" ;;
            *.adf) cd "$extract_path" && unadf -w "$archive" &> /dev/null && cd - > /dev/null ;;
        esac

        # Build local tree ensuring good encoding convertion 
        iconv -f UTF-8 -t ISO-8859-1 "$desc_file" | while read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue

            # Use xargs to properly parse quoted strings with spaces
            eval set -- "$line"
            src_raw="$1"
            dest_raw="$2"

            # remove quotes and trailing slashes if any
            src_item=$(echo "$src_raw" | sed 's/^"\(.*\)"$/\1/; s/\/$//')
            dest_amiga=$(echo "$dest_raw" | sed 's/^"\(.*\)"$/\1/; s/\/$//')
            
            # Get Volume and Subpath
            vol_name="${dest_amiga%%:*}"
            sub_path="${dest_amiga#*:}"

            # Create staging directory for this specific volume
            local_vol_stage="${STAGING_ROOT}/${vol_name,,}"
            if [[ ! -e "${local_vol_stage}/$(dirname "$sub_path")" ]]; then
                mkdir -p "${local_vol_stage}/$(dirname "$sub_path")"
            fi
            
            # check if the final destination exists regardless of the letter case
            existing_path=$(find "$local_vol_stage" -ipath "${local_vol_stage}/${sub_path}" -print -quit)
            if [[ -n "$existing_path" ]]; then
                final_sub_path="${existing_path#$local_vol_stage/}"
            else
                final_sub_path="$sub_path"
            fi

            real_src="${extract_path}/${src_item}"

            # Handle .z decompression
            if [[ "$src_item" =~ \.[zZ]$ && -f "$real_src" ]]; then
                gunzip -c "$real_src" > "${real_src%.*}" && real_src="${real_src%.*}"
            fi

            # if we are about to copy a directory, remove its name from destination not to create "directory in directory"
            if [[ -e "$real_src" ]]; then
                if [[ -d "$real_src" ]] ; then
                    final_sub_path="$(dirname "$final_sub_path")"
                fi
                
                # Do the actual copy to local staging
                cp -rf "$real_src" "${local_vol_stage}/${final_sub_path}"
            fi

        done < "$desc_file"

        # handle ".user-startup" files
        user_startup_src="${desc_file%.desc}.user-startup"
        if [[ -f "$user_startup_src" ]]; then
            # search for s/user-startup file
            target_startup=$(find "$STAGING_ROOT" -ipath "*/s/user-startup" | head -n 1)
            
            if [[ -n "$target_startup" ]]; then
                if ! grep -q ";BEGIN ${pkg_name}" "$target_startup"; then
                    log_info "Injecting user-startup for: $pkg_name"
                    {
                        echo ";BEGIN ${pkg_name}"
                        cat "$user_startup_src"
                        echo ""
                        echo ";END ${pkg_name}"
                        echo ""
                    } >> "$target_startup"
                fi
            else
                log_warn "User-startup file not found in staging. Skipping injection for $pkg_name."
            fi
        fi

    done < "$current_list"
done

exit 0

# Use hst.imager to copy the staging directory of each volume to the corresponding Amiga partition
log_info "Performing bulk transfer to disk..."

for vol_dir in "$STAGING_ROOT"/*; do
    if [ -d "$vol_dir" ]; then
        
        vol_label=$(basename "$vol_dir")
        
        # Resolve the RDB path for the root of the volume
        # We pass "Volume:" to get the root partition path
        target_rdb_base=$(get_rdb_path "${vol_label}:" "$DISK_DEVICE")
        
        get_rdb_path "${vol_label}:" "$DISK_DEVICE"
        
        log_info "Transferring all files to Volume: $vol_label..."
        
        # copy the content of the staging volume directory (but not the folder itself)
        $HST_BIN fs copy "$vol_dir/" "$target_rdb_base" --recursive --force --quiet &> /dev/null

        if [[ $? != 0 ]]; then
            log_error "An error occured while copying files"
        fi
    fi
done

# Cleanup if needed
if [ "$CLEAN_UP" = true ]; then
    log_info "Cleaning up temporary extraction files..."
    rm -rf "$TMP_EXTRACT_DIR"
    log_info "Cleaning up downloaded archives..."
    rm -rf "$TMP_DOWNLOAD_DIR"
fi

log_success "Deployment process finished."