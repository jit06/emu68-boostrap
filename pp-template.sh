#!/usr/bin/env bash

# ==============================================================================
#
# Post-processing template script. Serves as basic documentation / how to.
# Helper functions assume that the Workbench partition is named "Workbench"
# 
# ==============================================================================

# Available variables
# ===================
# STAGING_ROOT : path to the root of the staging directory. It contains one folder per partition (eg. "Workbench", "Apps", etc.)
# HSTA_BIN : path to the hst-amiga executable
# HST_BIN : path to the hst-imager executable

# Available base functions
# ========================
# log_info()
# log_success()
# log_error()
# log_warn()

# Available helper functions
# ==========================
# enable_commodity(name) : copy given commodity from Tools/Commodities to WBStartup
# enable_dosdriver(name) : copy given dosdriver from Storage/DOSDrivers to Devs/DOSDrivers
# enable_monitor(name) : copy given monitor from Storage/Monitors to Devs/Monitors
# set_tooltypes(icon_path, tooltypes_string) : replace icon tooltypes with the given one
# use_deficon(icon_path, def_icon) : replace (or create) given icon file with given system default 
# set_icon(icon_path, icon_args) : call hst.amiga icon update on icon with given arguments

enable_commodity "ClickToFront"
enable_commodity "MouseBlanker"

enable_commodity "ScreenTime"
set_tooltypes "workbench/WBStartup/ScreenTime.info" \
"DONOTWAIT
CX_POPUP=NO
FORMAT=%a %d %b %H:%M"

enable_commodity "FKey"
set_tooltypes "workbench/WBStartup/FKey.info" \
"«F10» INSERT Workbench:Tools/SnoopDos
«F2» INSERT Workbench:System/Tasko_v1.0/Tasko
DONOTWAIT
CX_POPUP=NO
CX_POPKEY=ctrl alt f
CX_PRIORITY=0"

enable_dosdriver "CD0"
enable_dosdriver "PC0"

enable_monitor "NTSC"

use_deficon "workbench/Network.info" "def_drawer"
use_deficon "workbench/Network/MiamiDX.info" "def_drawer"
use_deficon "workbench/Network/NetSurf.info" "def_drawer"
use_deficon "workbench/Network/iBrowse.info" "def_drawer"
use_deficon "workbench/Network/Yam.info" "def_drawer"
use_deficon "workbench/Network/AWeb.info" "def_drawer"
use_deficon "workbench/Tools/IconMixer.info" "def_drawer"
use_deficon "workbench/System/WBDock.info" "def_drawer"
use_deficon "workbench/System/MUI.info" "def_drawer"