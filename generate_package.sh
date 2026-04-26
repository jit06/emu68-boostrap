#!/bin/bash

# ==============================================================================
# Script Name: generate_packages.sh
# Description: Generate .desc package files from ADF/LHA/ZIP with hardcoded
#              logic for AmigaOS 3.2 and generic Aminet-style archives.
# ==============================================================================

#set -e

# --- Functions ---

usage() {
    echo "Usage: $0 --package-list [FILE] --packages-path [DIR]"
    echo ""
    echo "Required:"
    echo "  -l, --package-list   Path to the file listing packages and sources"
    echo "  -p, --packages-path  Directory where .desc files will be created"
    exit 1
}

log_info() { echo -e "[\e[34mINFO \e[0m] $1"; }
log_success() { echo -e "[\e[32m OK  \e[0m] $1"; }
log_error() { echo -e "[\e[31mERROR\e[0m] $1"; exit 1; }

check_dependencies() {
    local deps=("wget" "unzip" "lha" "unadf" "readlink")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found. Please install it."
        fi
    done
}

# --- Destination Mapping Logic ---

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

# --- Argument Parsing ---

while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--package-list) LIST_PATH=$(readlink -f "$2"); shift 2 ;;
        -p|--packages-path) PKG_DEST_DIR=$(readlink -f "$2"); shift 2 ;;
        -h|--help) usage ;;
        *) shift ;;
    esac
done

[[ -z "$LIST_PATH" || -z "$PKG_DEST_DIR" ]] && usage
check_dependencies
mkdir -p "$PKG_DEST_DIR"



# --- Main Logic ---

TMP_WORK="/tmp/amiga_pkg_gen"
rm -rf "$TMP_WORK" && mkdir -p "$TMP_WORK"

while read -r pkg_name pkg_source || [[ -n "$pkg_name" ]]; do
    [[ -z "$pkg_name" || "$pkg_name" =~ ^# ]] && continue

    log_info "Processing: $pkg_name..."
    DESC_FILE="$PKG_DEST_DIR/${pkg_name}.desc"
    > "$DESC_FILE"

    # Download if necessary
    local_file=""
    if [[ "$pkg_source" =~ ^http ]]; then
        local_file="$TMP_WORK/$(basename "$pkg_source")"
        wget -q "$pkg_source" -O "$local_file"
        if [[ $? -ne 0 ]]; then
            log_error "Could not download $pkg_source"
        fi
    else
        local_file=$(readlink -f "$pkg_source")
    fi


    # Case 1: AmigaOS_ADF (Base OS)
    if [[ "$pkg_source" =~ "AmigaOS_ADF" ]]; then
        unadf -r "$local_file" | awk '{print $NF}' | while read -r f; do
            # ignore unadf message (some are on stderr, others on stdout...)
            [[ "$f" == "Warning <"* || "$f" == "Device :"* || "$f" == "Volume :"* ]] && continue

            # ignore non path related info
            [[ "$f" == "" || "$f" == "/" || "$f" == "1" || "$f" =~ "%" || "$f" =~ "Disk.info" ]] && continue
            
            # --- Special logic for backdrops disk : all the content goes to Prefs/Presets
            if [[ "$pkg_name" == *"Backdrops"* ]]; then
                echo "\"$f\" \"Workbench:Prefs/Presets/Backdrops/$f\"" >> "$DESC_FILE"
                    continue#src_item=$(echo "$src_raw" | sed 's/^"\(.*\)"$/\1/')
        #dest_amiga=$(echo "$dest_raw" | sed 's/^"\(.*\)"$/\1/')
            fi

            # --- Special logic for classes : simplify and keep the root directories
            if [[ "$pkg_name" == *"Classes"* ]]; then
                [[ ! "$f" =~ ^(Devs\/|Classes\/)$ ]] && continue 
            fi

            # --- Special logic for DiskDoctor : keep the same file as the official installer
            if [[ "$pkg_name" == *"DiskDoctor"* ]]; then
                [[ ! "$f" =~ ^(C\/DAControl|C\/DiskDoctor|Devs\/trackfile.device)$ ]] && continue 
            fi
            
            # --- Special logic for Extras : simplify and keep the root directories and some icons
            if [[ "$pkg_name" == *"Extras"* ]]; then
                [[ ! "$f" =~ ^(Prefs\/|System\/|L\/|Tools\/|S/|Prefs.info|System.info|Tools.info)$ ]] && continue 
            fi

            # --- Special logic for Fonts : all files must be copied to Fonts directory
            if [[ "$pkg_name" == *"Fonts"* ]]; then
                echo "\"$f\" \"Workbench:Fonts/$f\"" >> "$DESC_FILE"    
                continue 
            fi

             # --- Special logic for Install disk : just keep needed files 
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

            # --- Special logic for Locale : only handle countries and fonts
            if [[ "$pkg_name" == *"Locale"* ]]; then
                if [[ "$f" == "Support/Fonts/"?* ]]; then
                    f_dest="${f#Support/}"  
                    f_dest=${f_dest%.*}
                    echo "\"$f\" \"Workbench:$f_dest\"" >> "$DESC_FILE"        
                    continue
                elif [[ "$f" == "Countries/" ]]; then
                    echo "\"$f\" \"Workbench:Locale/\"" >> "$DESC_FILE"
                    continue
                fi
                continue 
            fi

            # --- Special logic for Storage : mimic install script
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

            # General copy for OS files
            echo "\"$f\" \"Workbench:$f\"" >> "$DESC_FILE"
        done


    # Case 2: AmigaOSUpdate_ADF
    elif [[ "$pkg_source" =~ "AmigaOSUpdate_ADF" ]]; then
        unadf -r "$local_file" | awk '{print $NF}' | while read -r f; do
            # ignore unadf message (some are on stderr, others on stdout...)
            [[ "$f" == "Warning <"* || "$f" == "Device :"* || "$f" == "Volume :"* ]] && continue
            
            # ignore non path related info
            [[ "$f" == "" || "$f" == "/" || "$f" == "1" || "$f" =~ "%" || "$f" =~ "Disk.info" || "$f" =~ (\/)$ ]] && continue

            # --- Special logic for Update disk
            if [[ "$pkg_name" == *"Update"* ]]; then
                
                # ignore install process related files
                [[ "$f" =~ ^(Install\/|Install|Installer)$ ]] && continue
                [[ "$f" == *"Install"* || "$f" == *"Patch"* || "$f" == *"T/"* || "$f" == *"IconUpdate"* || "$f" == *"Update/"* ]] && continue

            fi

            # --- Special logic for disk doctor : only a few files are kept
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



    # Case 3: Others (LHA/ZIP/ADF)
    else
        list_cmd=""
        if [[ "$local_file" == *.lha ]]; then list_cmd="lha lq $local_file | awk '{print \$NF}'"
        elif [[ "$local_file" == *.zip ]]; then list_cmd="unzip -Z1 $local_file"
        elif [[ "$local_file" == *.adf ]]; then list_cmd="unadf $local_file -l | awk '{print \$NF}'"
        fi

        # echo "CMD = $list_cmd"

        eval "$list_cmd" | while read -r src_item; do
            # Clean string and skip directories
            src_item=$(echo "$src_item" | tr -d '\r')
            [[ -z "$src_item" || "$src_item" == */ ]] && continue
          
            dest_item=$(get_generic_destination "$src_item" "$pkg_name")
            echo "\"$src_item\" \"$dest_item\"" >> "$DESC_FILE"
        done
    fi

    log_success "Generated $DESC_FILE"

done < "$LIST_PATH"

rm -rf "$TMP_WORK"
log_info "Generation process completed."