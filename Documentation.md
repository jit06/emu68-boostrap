# Full documentation for Emu68-Boostrap

- [Full documentation for Emu68-Boostrap](#full-documentation-for-emu68-boostrap)
  - [Initialize disk and Amiga partitions](#initialize-disk-and-amiga-partitions)
    - [Arguments \& Options](#arguments--options)
    - [Usage Example](#usage-example)
  - [Install Amiga software](#install-amiga-software)
    - [Layered Package System](#layered-package-system)
    - [Arguments \& Options](#arguments--options-1)
    - [Usage Example](#usage-example-1)
    - [Icons operations with ".icons" files](#icons-operations-with-icons-files)
      - [Icon types reference](#icon-types-reference)
    - [Post processing script](#Post-processing-script)
  - [Creating packages](#creating-packages)
    - [Arguments \& Options](#arguments--options-2)
    - [Usage Example](#usage-example-2)
  - [Configuration Files Format](#configuration-files-format)
    - [Package list file](#package-list-file)
    - [Package Description](#package-description)


## Initialize disk and Amiga partitions

The `setup_disk.sh` script is responsible for the low-level preparation of the storage medium. It automates the creation of a hybrid partition structure compatible with both the host hardware (via MBR) and the Amiga environment (via RDB).

Beware, some integrated sdcard reader (eg. in laptop) expose something like/dev/mmcblk0 but does not support low level IOCTL, making hst-imager unable to create Amiga partitions. 

>**note**: it is possible to use a file instead of a real device.

**Key actions done by the script:**

1. **Hybrid Partitioning**: Creates an MBR table with two primary partitions:
    - **FAT32 Partition**: Dedicated to Emu68 firmware and boot files.
    - **Type 0x76 Partition**: A container for the Amiga Rigid Disk Block (RDB), which allows for native Amiga partitions
        > **Note**: all emu68-boostrap scripts have the same partition naming convention : "Workbench" for the OS and all the addons, "Apps" for applications and "Games" obsviously for games.

2. **Dynamic Configuration**: The partitioning process relies on a `partitions.config` file using the **hst.imager** script format.

    > **Note**: The placeholder `[PATH_TO_DISK]` within this file is automatically replaced at runtime by the disk path provided in the arguments.

3. **Emu68 Installation**: Downloads the latest firmware, installs the provided Kickstart ROM, and handles optional custom `config.txt` or `cmdline.txt` files.

4. **Filesystem Setup**: Prepares the RDB structure and installs necessary Amiga filesystems like `pfs3aio` (the only one tested and provided)

### Arguments & Options

| Argument | Long Format        | Description                                                   |
| :------- | :----------------- | :------------------------------------------------------------ |
| `-d`     | `--disk`           | **Required**. Path to the disk device (e.g., `/dev/sdc`).     |
| `-k`     | `--kickstart`      | **Required**. Path to the Amiga Kickstart ROM file.           |
| `-c`     | `--config`         | Path to a custom `config.txt` for Emu68.                      |
| `-l`     | `--cmdline`        | Path to a custom `cmdline.txt` for Emu68.                     |
|          | `--clean-on-close` | Removes temporary downloads and extractions after completion. |
| `-h`     | `--help`           | Displays the help message.                                    |

### Usage Example

```bash
./setup_disk.sh -d /dev/sdc -k ./roms/kick32.rom --clean-on-close
```

If the device is an image that you want to test with an emulator, you may need to use loop device instead of the file, as it contains a partition scheme.
The example below will generate a 16Gb image, prepare it and create something like `/dev/loop0p1` and `/dev/loop0p2`. The entry /dev/loop0p2 contains the Amiga RDB definition, thus it can be used in an emulator (eg. Amiberry). You may need to use "hardfile" and not "hardrive".

```bash
dd if=/dev/zero of=/path/to/amigadisk.img bs=1M count=16384 
./setup_disk.sh -d /path/to/amigadisk.img -k ./roms/kick32.rom --clean-on-close
sudo losetup -fP /path/to/amigadisk.img 

```

## Install Amiga software

The `package.sh` script handles the deployment of softwares to the Amiga partitions using a sort of package mecanism. Instead of copying files one by one (which is extremely slow on RDB structures), it reconstructs the entire file tree in a local **staging area** on `/tmp` before performing a bulk transfer to the amiga partitions.

**Key features:**

- **Flexible Sourcing**: Supports local archives or direct downloads via HTTP/HTTPS.
- **Smart Extraction**: Automatically handles `.lha`, `.zip`, `.iso` and `.adf` files, including `.z` decompression inside ADF (gunzip).
- **Encoding Bridge**: Converts package descriptions and filenames from Linux (UTF-8) to Amiga (ISO-8859-1) to ensure accents and special characters appear correctly on the Workbench.
- **Volume Mapping**: Allows you to map virtual Amiga volume names (e.g., `Workbench:`) to physical RDB device names (e.g., `SDH0`) defined on your disk.
- **Bulk Transfer**: Uses **hst.imager** to copy entire directories to the RDB corresponding Amiag partitions.

### Layered Package System

The deployment follows a **top-down priority** based on your package list. Software are installed in the exact order specified in the `.list` file, overwriting any existing files in the staging area.

- **Standardized Repository**: By default, the script looks into `packages` directory where `.list` files and their associated folders are stored. Each folder contains one `.desc` file per line in the `.list` file.
- **Multi-Package Installation**: You can chain multiple package sets (e.g., `OS32,Addons`) in a single command. They will be processed in the order provided.
- **Customizable & Layered**: You can easily add or reorder software. For example, installing a "GlowIcons" package after the main OS will automatically overwrite the standard icons in the staging area.
- **Pre-configured Packages**: Several ready-to-use sets are available in the `packages` folder.

### Arguments & Options

| Argument | Long Format        | Description                                                                                                                                   |
| :------- | :----------------- | :-------------------------------------------------------------------------------------------------------------------------------------------- |
| **`-i`** | **`--install`**    | **Required (or -l/-p)**. Names of packages to install (e.g., `OS32,Addons`). Matches `.list` files and directories in the `packages/` folder. |
| `-l`     | `--package-list`   | **Manual Mode**. Path to a specific `.list` file.                                                                                             |
| `-p`     | `--packages-path`  | **Manual Mode**. Directory containing the associated `.desc` files.                                                                           |
| `-d`     | `--disk`           | **Required**. Path to the physical disk (e.g., `/dev/sdc`).                                                                                   |
| `-m`     | `--mapping`        | Map an RDB Device to a Volume Name (e.g., `-m SDH0=Workbench`). Can be used multiple times.                                                   |
|          | `--clean-on-close` | Removes downloads and extraction folders after completion.                                                                                    |
| `-h`     | `--help`           | Displays the help message.                                                                                                                    |

> **Warning**: The `--install` argument is mutually exclusive with `--package-list` and `--packages-path`.

### Usage Example

**Standard Usage (Automated):**
Install the OS 3.2 base followed by the Addons pack using the standardized repository:

```bash
sudo ./package.sh -d /dev/sdc --install OS32,Addons -m SDH0=Workbench
```

**Custom package file (Manual):**

```bash
sudo ./package.sh -d /dev/sdc -l my-own-packages.list -p my-own-packages-folder -m SDH0=Workbench 
```

> **Note 1**: any `.user-startup` file will be injected in system partition `S/User-startup` and will automatically be surrounded by `;BEGIN <package name>` and `;END <package name>`

> **Note 2**: any `.icons` file will be used to set various icons properties like on the real workbench, see next chapter.

### Icons operations with ".icons" files

Any package can be associated with a ".icons" file which contains orders passed through to `hst.amiga` command. The goal is to change various icon informations like type and position in the staging area. It allows to customize any icons before copying files to the final destination.

**The file format is basicaly :**

```bash
<Amiga style path to the .info file> <hst.amiga icon order> <hst.amiga command arguments>
```

**Example :**

giving a package with the following `StandardGlowIcons.desc` that install a specific disk icon to the workbench partition:

```bash
"StandardGlowIcons/Drives/Harddrive/AmigaHDisk.info" "Workbench:disk.info"
```

You can then use the following `StandardGlowIcons.icons` file to set the icon type to `1` (`disk`), set its position to `20,50` and makes it open a window with dimensions 465x164 on position `80`,`50`

```bash
"Workbench:disk.info"   update -t 1 -x 20 -y 50 -dx 80 -dy 50 -dw 465 -dh 165
```

It is also possible to set tooltypes. In that case, the `newmeter.tooltypes` is a simple text file which is on the same directory as the .icons file
```bash
"Workbench:Tools/Commodities/NewMeter.info" tooltypes import newmeter.tooltypes
```

#### Icon types reference

- **1**: disk
- **2**: drawer
- **3**: tool
- **4**: project
- **5**: trashcan
- **7**: kickstart
- **8**: appicon

### Post processing script

The parameters `--post-script` or `-s` of the `package.sh` command allows to do any post processing on the staging area, just before the copy to the final destination. The given script is executed in the staging directory, any Amiga partition are just folders.

The script is also executed with a `context` that provides several variables and functions (defined in `library.sh`) which should be usefull to customise your installation without modifying or creating packages.

Of course, as it is a bash script, you can do whatever you want with it...
An example is given with the file `pp-template.sh`

#### Available variables
**$STAGING_ROOT** : path to the root of the staging directory. It contains one folder per partition (eg. "Workbench", "Apps", etc.)
**$HSTA_BIN** : path to the hst-amiga executable
**$HST_BIN** : path to the hst-imager executable

#### Availabled logging functions
log_info()
log_success()
log_error()
log_warn()

#### Available helper functions
**enable_commodity(name)** : copy given commodity from Tools/Commodities to WBStartup
**enable_dosdriver(name)** : copy given dosdriver from Storage/DOSDrivers to Devs/DOSDrivers
**enable_monitor(name)** : copy given monitor from Storage/Monitors to Devs/Monitors
**set_tooltypes(icon_path, tooltypes_string)** : replace icon tooltypes with the given one
**use_deficon(icon_path, def_icon)** : replace (or create) given icon file with given system default 
**set_icon(icon_path, icon_args)** : call hst.amiga icon update on icon with given arguments


## Creating packages

The `generate_package.sh` script is the companion tool for creating the `.desc` files required by the deployment process. It automates the indexing of archives and attempts to intelligently map where files should be installed on the Amiga partitions. This provides with a simple yet efficient way to build and share reproductable installations without sharing a heavy binary image.

**Key features:**

- **AmigaOS 3.2 Specialized Logic**: Includes dedicated rules for processing official AmigaOS 3.2 and Update ADFs. It mimics the behavior of the original Commodore/Hyperion install scripts (e.g., remapping `Startup-HardDrive` to `S:Startup-Sequence`, copying Backdrops to Presets, etc).
- **Generic Rule Engine**: For non-OS archives, the script applies a "best-guess" logic to place files in standard Amiga locations (e.g., `.library` to `Libs:`, `.device` to `Devs:`).
- **Multi-Format Support**: Can parse and index `.lha`, `.zip`, `.iso` and `.adf` archives.
- **Smart Remapping**: Automatically detects and handles compressed `.z` files inside adf, stripping the extension for the destination path.
- **WHDload game specilized Logic**: install games in a classic tree structure `<first letter>/<game name>`, ready for GUI like `iGame`

> **Note**: While the specialized OS 3.2 and whdload logics are pretty accurate, the generic output for third-party software often serves as a template and **requires manual adjustment** to ensure perfect placement.

### Arguments & Options

| Argument | Long Format        | Description                                                              |
| :------- | :----------------- | :----------------------------------------------------------------------- |
| `-l`     | `--package-list`   | **Required**. Path to the file listing packages and their sources.       |
| `-p`     | `--packages-path`  | **Required**. Directory where the generated `.desc` files will be saved. |
|          | `--clean-on-close` | Removes temporary downloads after the generation process.                |
| `-h`     | `--help`           | Displays the help message.                                               |

### Usage Example

(re)generate descriptions files for Amiga OS 3.2 ADF files listed in packages-OS32.list

```bash
./generate_package.sh -l OS32.list -p packages/OS32/
```

For more defails on files format, please see next chapter.

## Configuration Files Format

The toolchain uses two types of simple text files to manage software installation.

### Package list file

A package list is a text file that defines **what** to install. It is a simple space-separated or tab-separated file which name ends with `.list` by convention.
A list file must match with a corresponding package directory of the same name but **without** the `.list` extention

**Format:**

`PackageName` `SourcePathOrUrl`

- **PackageName**: The name of the package. It must match a corresponding `.desc` file in the package descriptions directory.
- **SourcePathOrUrl**: Can be a local path to an archive (`.lha`, `.zip`, `.iso` or `.adf`) or a direct `http/https` URL.
- Lines starting with `#` are ignored (comments)
- If a source path url ends with `!`, the first encoutered ADF file inside the archive will be used instead of the archive itself.

By convention, contributed commercial free files are stored in the `contribs` folder and any specific archive of your own which is not publicaly downloadable goes in `custom` directory (eg. any commercial software you own).

>**Note**: spaces are not allowed for package name nor source path/URL

**Example:**
Local files in ADF format for Amiga OS 3.2

```text
Workbench32     AmigaOS_ADF/Workbench3.2.adf
Extras32        AmigaOS_ADF/Extras3.2.adf
```

Third Party OS Addons

```text
IDEfix97        https://aminet.net/driver/media/IDEfix97.lha
AmigaTestKit    https://github.com/keirf/amiga-stuff/releases/download/testkit-v1.21/AmigaTestKit-1.21.zip
MUI5            https://github.com/amiga-mui/muidev/releases/download/MUI-5.0-20210831/MUI-5.0-20210831-os3.lha
```

### Package Description

A description file defines **where** to copy the files from an archive. A description file ends with `.desc`. Each package mentioned in the `.list` file **must** have a corresponding `.desc` file in the descriptions directory (e.g., `IDEfix97.desc`).
Any file present in the archive but not listed in a ".desc" file will be ignored.

**Format:**

`"SourcePathInArchive"` `"AmigaDestination"`

- **SourcePathInArchive**: The internal path of the file or directory inside the archive.
- **AmigaDestination**: The destination path on the Amiga, formatted as `Volume:Path/To/Target`.
- **Encapsulation**: It is highly recommended to wrap both paths in **double quotes** `"` to handle spaces and special characters.

**Key Features:**

- **Path Sanitization**: The script automatically removes trailing slashes and redundant quotes to prevent "directory-in-directory" nesting errors.
- **Automatic Decompression**: Files ending in `.z` or `.Z` (common in AmigaOS updates) are automatically decompressed using `gunzip` during the staging process.
- **Recursive Copy**: If the source path is a directory (ends with `/`), its entire content is merged into the destination (that must also ends with `/`).
- **Ordering**: Files are processed in the order they appear in the `.desc` file.

**Example (`SysInfo.desc`):**

```text
"SysInfo"       "Workbench:Tools/SysInfo"
"SysInfo.info"  "Workbench:Tools/SysInfo.info"
"Docs/"         "Workbench:Docs/"
```

Please read the [Packages Reference](PackageReference.md) before sending new ones
