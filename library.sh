#!/usr/bin/env bash

# ==============================================================================
#
# This file contains helper functions to use in post-processing script
# 
# ==============================================================================

# ==============================================================================
# INTERNALS (Helper functions)
# ==============================================================================

# _enable_storage_item
# Internal helper to copy a file and its companion .info icon from a source 
# directory to a destination directory within the workbench staging root.
_enable_storage_item() {
    local item_name="$1"
    local rel_src_dir="$2"
    local rel_dest_dir="$3"
    local func_caller="$4"

    if [[ -z "$item_name" ]]; then
        log_error "${func_caller}: Missing item name argument."
        return 1
    fi

    local src_dir="${STAGING_ROOT}/workbench/${rel_src_dir}"
    local dest_dir="${STAGING_ROOT}/workbench/${rel_dest_dir}"

    local src_file="${src_dir}/${item_name}"
    local src_icon="${src_file}.info"

    # Verify source file existence
    if [[ ! -f "$src_file" ]]; then
        log_warn "${func_caller}: '${item_name}' not found in source directory: workbench/${rel_src_dir}"
        return 1
    fi

    # Ensure destination directory exists
    mkdir -p "$dest_dir"

    # Copy the main binary/file
    log_info "${func_caller}: Enabling ${item_name} (copying to ${rel_dest_dir})..."
    cp -f "$src_file" "$dest_dir/"

    # Copy the icon file if it exists
    if [[ -f "$src_icon" ]]; then
        cp -f "$src_icon" "$dest_dir/"
    fi
}



# ==============================================================================
# PUBLIC API
# ==============================================================================

# ==============================================================================
# enable_commodity
# Copies a commodity from Tools/Commodities to WBStartup
# Arguments:
#   $1 - name of the commodity file (without the ".info")
enable_commodity() {
    _enable_storage_item "$1" "Tools/Commodities" "WBStartup" "enable_commodity"
}

# ==============================================================================
# enable_dosdriver
# Copies a DOSDriver from Storage/DOSDrivers to Devs/DOSDrivers
# Arguments:
#   $1 - name of the dosdriver file (without the ".info")
enable_dosdriver() {
    _enable_storage_item "$1" "Storage/DOSDrivers" "Devs/DOSDrivers" "enable_dosdriver"
}

# ==============================================================================
# enable_monitor
# Copies a monitor driver from Storage/Monitors to Devs/Monitors
# Arguments:
#   $1 - name of the monitor file (without the ".info")
enable_monitor() {
    _enable_storage_item "$1" "Storage/Monitors" "Devs/Monitors" "enable_monitor"
}


# ==============================================================================
# set_tooltypes
# Replaces the tooltypes of a given icon with the provided tooltypes string.
# Uses hst.amiga icon tooltypes import via a temporary file.
#
# Arguments:
#   $1 - Path to the target icon file inside staging (e.g., "${STAGING_ROOT}/workbench/tools/mytool.info")
#   $2 - Multi-line string containing the new tooltypes
set_tooltypes() {
    local target_icon="$1"
    local tooltypes_string="$2"

    if [[ -z "$target_icon" || -z "$tooltypes_string" ]]; then
        log_error "set_tooltypes: Missing arguments. Usage: set_tooltypes <icon_path> <tooltypes_string>"
        return 1
    fi

    # Ensure the target icon exists in staging
    if [[ ! -f "$target_icon" ]]; then
        log_warn "set_tooltypes: Target icon not found: $target_icon"
        return 1
    fi

    # Create a secured temporary file to hold the tooltypes
    local tmp_tooltypes
    tmp_tooltypes=$(mktemp /tmp/hst_tooltypes.XXXXXX)

    # Write the multi-line string into the file
    # Using printf to properly handle potential newlines and avoid escaping issues
    printf "%s\n" "$tooltypes_string" > "$tmp_tooltypes"

    log_info "Updating tooltypes for icon: $(basename "$target_icon")"

    # Execute hst.amiga to import the tooltypes into the .info file
    # We suppress stdout/stderr to match the quiet approach of your main script
    "$HSTA_BIN" icon tooltypes import "$target_icon" "$tmp_tooltypes" &> /dev/null
    
    local status=$?

    # Clean up the temporary file immediately
    #rm -f "$tmp_tooltypes"

    if [[ $status -ne 0 ]]; then
        log_error "set_tooltypes: hst.amiga failed to import tooltypes to $target_icon"
        return 1
    fi

    return 0
}


# ==============================================================================
# use_deficon
# Replaces (or creates) a target icon file using a system default icon (deficon).
# Default icons are located in "workbench/prefs/env-archive/sys/".
#
# Arguments:
#   $1 - Path to the target icon to create/overwrite (e.g., "${STAGING_ROOT}/workbench/network.info")
#   $2 - Name of the default icon file (e.g., "def_tool.info", "def_drawer.info")
use_deficon() {
    local target_icon="$1"
    local def_icon_name="$2.info"

    if [[ -z "$target_icon" || -z "$def_icon_name" ]]; then
        log_error "use_deficon: Missing arguments. Usage: use_deficon <target_icon_path> <def_icon_name>"
        return 1
    fi

    # Define the repository path for system default icons in staging (lowercase)
    local deficons_dir="${STAGING_ROOT}/workbench/Prefs/Env-Archive/Sys"
    local src_def_icon="${deficons_dir}/${def_icon_name}"

    # Verify that the requested default icon actually exists in your staging
    if [[ ! -f "$src_def_icon" ]]; then
        log_warn "use_deficon: Source default icon not found: $src_def_icon"
        return 1
    fi

    # Ensure the parent directory of the target icon exists
    local target_dir
    target_dir=$(dirname "$target_icon")
    mkdir -p "$target_dir"

    log_info "Applying default icon '${def_icon_name}' to $target_icon..."

    # Copy and rename the default icon to its new destination
    cp -f "$src_def_icon" "$target_icon"
    
    if [[ $? -ne 0 ]]; then
        log_error "use_deficon: Failed to copy default icon to $target_icon"
        return 1
    fi

    return 0
}


# ==============================================================================
# set_icon
# Calls hst.amiga icon update on a specific target icon inside staging
# with custom arguments.
#
# Arguments:
#   $1 - Path to the target icon file inside staging (e.g., "${STAGING_ROOT}/workbench/Tools.info")
#   $2 - String containing the update arguments (e.g., "-t 3" or "--view-modes SortedByName")
set_icon() {
    local target_icon="$1"
    local icon_args="$2"

    if [[ -z "$target_icon" || -z "$icon_args" ]]; then
        log_error "set_icon: Missing arguments. Usage: set_icon <icon_path> <icon_args>"
        return 1
    fi

    # Ensure the target icon exists in staging before trying to modify it
    if [[ ! -f "$target_icon" ]]; then
        log_warn "set_icon: Target icon not found: $target_icon"
        return 1
    fi

    log_info "Updating icon attributes for: $(basename "$target_icon")"

    # We safely split the arguments string into a real Bash array using xargs
    # This respects spaces and quotes inside the argument string perfectly.
    declare -a parsed_args
    eval "parsed_args=($icon_args)"

    # Build the final safe command array
    local cmd_args=("update" "$target_icon" "${parsed_args[@]}")

    # Execute hst.amiga safely using the array expansion
    "$HSTA_BIN" icon "${cmd_args[@]}" &> /dev/null

    if [[ $? -ne 0 ]]; then
        log_error "set_icon: hst.amiga failed to update icon with arguments: $icon_args"
        return 1
    fi

    return 0
}