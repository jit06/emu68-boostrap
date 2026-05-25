#!/usr/bin/env bash

# ==============================================================================
# Package description generator
# The main purpose is create ".desc" files used by deploy_package.sh 
# This script support zip, adf and lha files
# 
# The script has a dedicated logic to make proper AmigaOS 3.2 ".desc" files in
# order to generate a working OS like the original install script would have done
#
# For any other file, the generator tries to respect Amiga standards like copying
# ".library" file to SYS:Libs, ".device" to SYS:Devs, etc.
# Most of the time generic ".desc" files must be manualy adjusted
# ==============================================================================

set -e

__DEPENDENCIES__=("wget" "unzip" "lha" "unadf" "readlink", "isoinfo")
CLEAN_UP=false

source main.config
source functions.sh


usage() {
    echo "Usage: $0 --package-list [FILE] --packages-path [DIR]"
    echo ""
    echo "Required:"
    echo "  -l, --package-list   Path to the file listing packages and sources"
    echo "  -p, --packages-path  Directory where .desc files should be created"
    echo "Options:"
    echo "  --clean-on-close  Remove downloads and extractions after completion"
    exit 1
}


# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--package-list)  LIST_PATH=$(readlink -f "$2");      shift 2 ;;
        -p|--packages-path) PKG_DEST_DIR=$(readlink -f "$2");   shift 2 ;;
        -h|--help) usage ;;
        *) shift ;;
    esac
done

# Basic Validations
[[ -z "$LIST_PATH" || -z "$PKG_DEST_DIR" ]] && usage

# ensure all needed programs are presents
check_dependencies

# Workspace preparation
mkdir -p "$PKG_DEST_DIR"
mkdir -p "$TMP_DOWNLOAD_DIR"

while read -r pkg_name pkg_source || [[ -n "$pkg_name" ]]; do
    [[ -z "$pkg_name" || "$pkg_name" =~ ^# ]] && continue

    # init .desc file
    log_info "Processing: $pkg_name..."
    DESC_FILE="$PKG_DEST_DIR/${pkg_name}.desc"
    > "$DESC_FILE"

    # Download if necessary
    local_file=""
    if [[ "$pkg_source" =~ ^http ]]; then
        local_file="$TMP_DOWNLOAD_DIR/$(basename "$pkg_source")"
        
        # Handle "!" at the end of the URL to specify searching for an ADF content inside the archive
        use_archive_content=false
        if [[ "$pkg_source" =~ "!" ]]; then
            use_archive_content=true
            # Clean url for download
            pkg_source="${pkg_source%?}"
            # Update local_file to match the original filename in the download directory
            local_file="$TMP_DOWNLOAD_DIR/$(basename "$pkg_source")"
        fi

        if [[ ! -f $local_file ]] ; then
            log_info "Downloading $pkg_name from $pkg_source..."
            wget -q "$pkg_source" -O "$local_file"
            if [[ $? -ne 0 ]]; then
                log_error "Could not download $pkg_source"
            fi
        fi

        if [[ "$use_archive_content" == true ]]; then
            log_info "Treating content of archive as source, searching for ADF file to extract..."
            local_file=$(extract_adf_from_archive "${local_file}")
        fi
    else
        local_file=$(readlink -f "$pkg_source")
        # If the local path ends with '!', assume we want the archive's ADF content.
        use_archive_content=false
        if [[ "$pkg_source" =~ "!" ]]; then
            use_archive_content=true
            # Clean the source path for readlink and other ops
            local_file=$(readlink -f "${pkg_source%?}")
        fi
    fi

    # special handling for ADF file in AmigaOS_ADF directory
    if [[ "$pkg_source" =~ "AmigaOS_ADF" ]]; then
        unadf -r "$local_file" | awk '{print $NF}' | while read -r f; do
            # ignore unadf message (some are on stderr, others on stdout...)
            [[ "$f" == "Warning <"* || "$f" == "Device :"* || "$f" == "Volume :"* ]] && continue

            # ignore non path related info
            [[ "$f" == "" || "$f" == "/" || "$f" == "1" || "$f" =~ "%" || "$f" =~ "Disk.info" ]] && continue
            
            # --- Special logic for backdrops disk : all the content goes to Prefs/Presets
            if [[ "$pkg_name" == *"Backdrops"* ]]; then
                echo "\"$f\" \"Workbench:Prefs/Presets/Backdrops/$f\"" >> "$DESC_FILE"
                continue 
                #src_item=$(echo "$src_raw" | sed 's/^"\(.*\)"$/\1/')
                #dest_amiga=$(echo "$dest_raw" | sed 's/^"\(.*\)"$/\1/')
            fi

            # classes : simplify and keep the root directories
            if [[ "$pkg_name" == *"Classes"* ]]; then
                [[ ! "$f" =~ ^(Devs\/|Classes\/)$ ]] && continue 
            fi

            # DiskDoctor : keep the same file as the official installer
            if [[ "$pkg_name" == *"DiskDoctor"* ]]; then
                [[ ! "$f" =~ ^(C\/DAControl|C\/DiskDoctor|Devs\/trackfile.device)$ ]] && continue 
            fi
            
            # Extras : simplify and keep the root directories as well as some icons
            if [[ "$pkg_name" == *"Extras"* ]]; then
                [[ ! "$f" =~ ^(Prefs\/|System\/|L\/|Tools\/|S/|Prefs.info|System.info|Tools.info)$ ]] && continue 
            fi

            # Fonts : all files must be copied to Fonts directory
            if [[ "$pkg_name" == *"Fonts"* ]]; then
                echo "\"$f\" \"Workbench:Fonts/$f\"" >> "$DESC_FILE"    
                continue 
            fi

             # Install : just keep needed files 
            if [[ "$pkg_name" == *"Install"* ]]; then
                
                # get hardrive startup in the right place
                if [[ "$f" == "Update/Startup-HardDrive" ]]; then
                    echo "\"$f\" \"Workbench:S/Startup-Sequence\"" >> "$DESC_FILE"
                    continue
                fi

                # copy HDTools box 
                if [[ "$f" == "HDTools/HDToolBox" ]]; then
                    echo "\"$f\" \"Workbench:Tools/HDToolBox\"" >> "$DESC_FILE"
                    echo "\"$f.info\" \"Workbench:Tools/HDToolBox.info\"" >> "$DESC_FILE"
                    continue
                fi

                # mimic installer, copy nothing but the following
                [[ ! "$f" =~ ^(Prefs\/Env-Archive\/|Libs\/workbench.library)$ ]] && continue
            fi

            # Locale : only handle countries and fonts
            if [[ "$pkg_name" == *"Locale"* ]]; then
                if [[ "$f" == "Support/Fonts/"?* ]]; then
                    f_dest="${f#Support/}"  
                    f_dest=${f_dest%.*}
                    echo "\"$f\" \"Workbench:$f_dest\"" >> "$DESC_FILE"        
                    continue
                elif [[ "$f" == "Countries/" ]]; then
                    echo "\"$f\" \"Workbench:Locale/Countries/\"" >> "$DESC_FILE"
                    continue
                fi
                continue 
            fi

            # Storage : mimic install script
            if [[ "$pkg_name" == *"Storage"* ]]; then
                if [[ "$f" =~ ^(DOSDrivers\/|Keymaps\/|Monitors\/|Printers\/)$ ]]; then
                    echo "\"$f\" \"Workbench:Storage/$f\"" >> "$DESC_FILE"        
                    continue
                fi
            
                if [[ "$f" == "DefIcons/"?* ]]; then
                    f_dest="${f#DefIcons/}"
                    echo "\"$f\" \"Workbench:Prefs/Env-Archive/Sys/$f_dest\"" >> "$DESC_FILE"        
                    continue
                fi

                if [[ "$f" == "LIBS/"?* ]]; then
                    f_dest="${f#LIBS/}"
                    echo "\"$f\" \"Workbench:Libs/$f_dest\"" >> "$DESC_FILE"        
                    continue
                fi

                if [[ "$f" == "Env-Archive/"?* || "$f" == "Presets/Pointers/"?* ]]; then
                    echo "\"$f\" \"Workbench:Prefs/$f\"" >> "$DESC_FILE"        
                    continue
                fi
            
                [[ ! "$f" =~ ^(WBStartup\/|Classes\/|C\/)$ ]] && continue 
            fi

            # default copy in the same folder / destination
            echo "\"$f\" \"Workbench:$f\"" >> "$DESC_FILE"
        done


    # # special handling for ADF file in AmigaOSUpdate_ADF directory
    elif [[ "$pkg_source" =~ "AmigaOSUpdate_ADF" ]]; then
        unadf -r "$local_file" | awk '{print $NF}' | while read -r f; do
            # ignore unadf message (some are on stderr, others on stdout...)
            [[ "$f" == "Warning <"* || "$f" == "Device :"* || "$f" == "Volume :"* ]] && continue
            
            # ignore non path related info
            [[ "$f" == "" || "$f" == "/" || "$f" == "1" || "$f" =~ "%" || "$f" =~ "Disk.info" || "$f" =~ (\/)$ ]] && continue

            # Update disk has some file to ignore
            if [[ "$pkg_name" == *"Update"* ]]; then
                
                # ignore install process related files
                [[ "$f" =~ ^(Install\/|Install|Installer)$ ]] && continue
                [[ "$f" == *"Install"* || "$f" == *"Patch"* || "$f" == *"T/"* || "$f" == *"IconUpdate"* || "$f" == *"Update/"* ]] && continue

            fi

            # DiskDoctor : only a few files are kept
            if [[ "$pkg_name" == *"DiskDoctor"* ]]; then
                
                # ignore install process related files
                [[ "$f" != "C/DAControl" && "$f" != "C/DiskDoctor" && "$f" != "Devs/trackfile.device" ]] && continue

            fi

            # Gzip handling (.z or .Z)
            if [[ "$f" =~ \.[zZ]$ ]]; then
                # Target name without .z extension
                echo "\"$f\" \"Workbench:${f%.*}\"" >> "$DESC_FILE"
            else
                echo "\"$f\" \"Workbench:$f\"" >> "$DESC_FILE"
            fi
        done

    # Generic packages (non AmigaOS)
    else
        if [[ "$local_file" == *.lha ]];    then process_listing() { lha lq "$local_file" | awk '{print $NF}'; }
        elif [[ "$local_file" == *.zip ]];  then process_listing() { unzip -Z1 "$local_file"; }
        elif [[ "$local_file" == *.adf ]];  then process_listing() { unadf -r "$local_file" | awk '{print $NF}'; }
        # ISO extension handling: list files, remove leading slash, and strip ISO 9660 versioning (;1)
        elif [[ "$local_file" == *.iso ]];  then process_listing() { isoinfo -R -f -i "$local_file" | sed -e 's/^\///' -e 's/;1$//' | iconv -f iso-8859-1 -t utf-8//TRANSLIT; }
        else
            log_warning "Unsupported file type for $pkg_name. Skipping content listing."
            continue
        fi

        process_listing | while read -r src_item; do
            # Clean string and skip directories
            src_item=$(echo "$src_item" | tr -d '\r')
            [[ -z "$src_item" || "$src_item" == */ ]] && continue

            # Skip unadf headers if they appear in stdout
            [[ "$src_item" == "Warning"* || "$src_item" == "Device"* || "$src_item" == "Volume"* ]] && continue

            # ignore non path related info
            [[ "$src_item" == "" || "$src_item" == "/" || "$src_item" == "1" || "$src_item" =~ "%" || "$src_item" =~ "Disk.info" ]] && continue

            dest_item=$(get_generic_destination "$src_item" "$pkg_name")
            echo "\"$src_item\" \"$dest_item\"" >> "$DESC_FILE"
        done
    fi

    log_success "Generated $DESC_FILE"

done < "$LIST_PATH"

# Cleanup if needed
if [ "$CLEAN_UP" = true ]; then
    log_info "Cleaning up temporary extraction files..."
    rm -rf "$TMP_DOWNLOAD_DIR"
fi

log_info "Generation process completed."