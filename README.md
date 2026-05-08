# Emu68-boostrap : Easy Amiga disk creation for emu68 

[![Logo](logo.png)]()

This toolchain provides a headless, Linux-native alternative to **emu68-imager**. It is designed for users who need a powerful, scriptable way to prepare SD cards or disk images for Amiga systems (including Emu68/PiStorm) without a graphical interface.

Everything is customizable:
* **Partition scheme**: Define exactly how your disk is structured.
* **Emu68 config files**: Full control over your PiStorm/Emu68 setup.
* **Software payload**: Choose exactly what to install on your Amiga partitions.

## Overview

Installation of Amiga software (including AmigaOS) is managed by a basic package mechanism consisting of a **package list** and **package description files**. 
* The **list** identifies the archives to install (LHA, ZIP, or ADF). 
* The **description file** (`.desc`) specifies where to copy each file from the archive to any Amiga partition.

While package description files can be generated automatically, they usually allow for fine-tuned customization. Base packages are already available for **AmigaOS 3.2 and its Updates**.

## Typical Usage

### 1. Partition the Disk
Initialize the RDB partitions, set up the filesystem, and provide the required Kickstart ROM.
```bash
sudo ./setup_disk.sh -d /dev/sdc -k A1200.47.115.rom
```

### 2. Deploy Amiga OS
Install AmigaOS 3.2 and some system addons. In this example, we map the Amiga volume label "Workbench" to the physical device name "SDH0" defined in the RDB.
Off course you have to provide your own ADF files of Amiga OS 3.2 and updates that must be copie respectively in `AmigaOS_ADF` and `AmigaOSUpdate_ADF` directories
```bash
sudo ./package.sh -d /dev/sdc -m SDH0=Workbench -i OS32,addons
```

## Repository Structure
| Path                  | git ignore    | usage                                                 |
| :---                  | :---          | :---                                                  |
| .continue             | no            | configuration files for AI coding help                |  
| AmigaOS_ADF           | yes           | Amiga OS ADF files must be copied here                |
| AmigaOSUpdate_ADF     | yes           | Amiga OS Update ADF files must be copied here         |
| contribs              | no            | contains distribuable binaries used by the toolchain  |
| custom                | yes           | should contains any non free softwares                |
| packages              | no            | contains packages list and description for install    |
| function.sh           | no            | kind of framework used by all the scripts             |
| generate_package.sh   | no            | see below : tries to generate package description     |
| LICENCE               | no            | read it :)                                            |
| logo.png              | no            | thank you chatGPT                                     |
| main.config           | no            | global parameters common to all scripts               |
| package.sh            | no            | see below : install packages on amiga partitions      |
| partitions.config     | no            | example of partition scheme used by setup_disk.sh     |
| README.md             | no            | you're reading it                                     |
| setup_disk.sh         | no            | see below : initialize disk for PiStorm               |


## Full documentation

### Initialize disk and Amiga partitions with `setup_disk.sh`

This script is responsible for the low-level preparation of the storage medium. It automates the creation of a hybrid partition structure compatible with both the host hardware (via MBR) and the Amiga environment (via RDB).

**Key actions:**
* **Hybrid Partitioning**: Creates an MBR table with two primary partitions:
    1. **FAT32 Partition**: Dedicated to Emu68 firmware and boot files.
    2. **Type 0x76 Partition**: A container for the Amiga Rigid Disk Block (RDB), which allows for native Amiga partitions (Workbench, Data, etc.).
* **Dynamic Configuration**: The partitioning process relies on a `partitions.config` file using the **hst.imager** script format. 
    > **Note**: The placeholder `[PATH_TO_DISK]` within this file is automatically replaced at runtime by the disk path provided in the arguments.
* **Emu68 Installation**: Downloads the latest firmware, installs the provided Kickstart ROM, and handles optional custom `config.txt` or `cmdline.txt` files.
* **Filesystem Setup**: Prepares the RDB structure and installs necessary Amiga filesystems like `pfs3aio`.

#### Arguments & Options

| Argument | Long Format | Description |
| :--- | :--- | :--- |
| `-d` | `--disk` | **Required**. Path to the disk device (e.g., `/dev/sdc`). |
| `-k` | `--kickstart` | **Required**. Path to the Amiga Kickstart ROM file. |
| `-c` | `--config` | Path to a custom `config.txt` for Emu68. |
| `-l` | `--cmdline` | Path to a custom `cmdline.txt` for Emu68. |
| | `--clean-on-close` | Removes temporary downloads and extractions after completion. |
| `-h` | `--help` | Displays the help message. |

#### Usage Example
```bash
sudo ./setup_disk.sh -d /dev/sdc -k ./roms/kick32.rom --clean-on-close
```

### Install Amiga software with `package.sh`

This script handles the high-speed deployment of software to the Amiga partitions. Instead of copying files one by one (which is extremely slow on RDB structures), it reconstructs the entire file tree in a local **staging area** on Linux before performing a bulk transfer to the disk.

**Key features:**
* **Flexible Sourcing**: Supports local archives or direct downloads via HTTP/HTTPS.
* **Smart Extraction**: Automatically handles `.lha`, `.zip`, and `.adf` files, including `.z` decompression (gunzip).
* **Encoding Bridge**: Converts package descriptions and filenames from Linux (UTF-8) to Amiga (ISO-8859-1) to ensure accents and special characters appear correctly on the Workbench.
* **Volume Mapping**: Allows you to map virtual Amiga volume names (e.g., `Workbench:`) to physical RDB device names (e.g., `SDH0`) defined on your disk.
* **Bulk Transfer**: Uses **hst.imager** to copy entire directories to the RDB partitions in seconds rather than minutes.

#### Layered Package System
The deployment follows a **top-down priority** based on your package list. Software are installed in the exact order specified in the `.list` file, overwriting any existing files in the staging area.

**Standardized Repository**: By default, the script looks into `packages` directory where `.list` files and their associated `.desc` folders (of the same name) are stored.
* **Multi-Package Installation**: You can chain multiple package sets (e.g., `OS32,Addons`) in a single command. They will be processed in the order provided.
* **Customizable & Layered**: You can easily add or reorder software. For example, installing a "GlowIcons" package after the main OS will automatically overwrite the standard icons in the staging area.
* **Pre-configured Packages**: Several ready-to-use sets are available in the `packages` folder:
    * **OS32**: AmigaOS 3.2 & Update 3.2.3.
    * **emu68tools**: Specific utilities for PiStorm users.
    * **addons**: SysInfo, KingCON, and other essential tools.

> **Note**: any `.user-startup` file will be injected in system partition `S/User-startup` and will automatically be surounded `;BEGIN <package name>` and `;END <package name>`

### Arguments & Options

| Argument | Long Format | Description |
| :--- | :--- | :--- |
| **`-i`** | **`--install`** | **Required (or -l/-p)**. Names of packages to install (e.g., `OS32,Addons`). Matches `.list` files and directories in the `packages/` folder. |
| `-l` | `--package-list` | **Manual Mode**. Path to a specific `.list` file. |
| `-p` | `--packages-path`| **Manual Mode**. Directory containing the associated `.desc` files. |
| `-d` | `--disk` | **Required**. Path to the physical disk (e.g., `/dev/sdc`). |
| `-m` | `--mapping` | Map an RDB Device to a Volume Name (e.g., `-m SDH0=Workbench`). Can be used multiple times. |
| | `--clean-on-close` | Removes downloads and extraction folders after completion. |
| `-h` | `--help` | Displays the help message. |

> **Warning**: The `--install` argument is mutually exclusive with `--package-list` and `--packages-path`.

#### Usage Example
**Standard Usage (Automated):**
Install the OS 3.2 base followed by the Addons pack using the standardized repository:
```bash
sudo ./package.sh -d /dev/sdc --install OS32,Addons -m SDH0=Workbench
```
**Custom package file (Manual):**
```bash
sudo ./package.sh -d /dev/sdc -l my-own-packages.list -p my-own-packages-folder -m SDH0=Workbench 
```

### Generate packages description files with `generate_package.sh`

This script is the companion tool for creating the `.desc` files required by the deployment process. It automates the indexing of archives and attempts to intelligently map where files should be installed on the Amiga partitions. This provides with a simple yyet efficient way to build and share reproductable installations without sharing a heavy binary image.

**Key features:**
* **AmigaOS 3.2 Specialized Logic**: Includes dedicated rules for processing official AmigaOS 3.2 and Update ADFs. It mimics the behavior of the original Commodore/Hyperion install scripts (e.g., remapping `Startup-HardDrive` to `S:Startup-Sequence`, copying Backdrops to Presets, etc.).
* **Generic Rule Engine**: For non-OS archives, the script applies a "best-guess" logic to place files in standard Amiga locations (e.g., `.library` to `Libs:`, `.device` to `Devs:`).
* **Multi-Format Support**: Can parse and index `.lha`, `.zip`, and `.adf` archives.
* **Smart Remapping**: Automatically detects and handles compressed `.z` files, stripping the extension for the destination path.

> **Note**: While the specialized OS 3.2 logic is pretty accurate, the generic output for third-party software often serves as a template and **requires manual adjustment** to ensure perfect placement.

#### Arguments & Options

| Argument | Long Format | Description |
| :--- | :--- | :--- |
| `-l` | `--package-list` | **Required**. Path to the file listing packages and their sources. |
| `-p` | `--packages-path`| **Required**. Directory where the generated `.desc` files will be saved. |
| | `--clean-on-close` | Removes temporary downloads after the generation process. |
| `-h` | `--help` | Displays the help message. |

#### Usage Example
(re)generate descriptions files for Amiga OS 3.2 ADF files listed in packages-OS32.list
```bash
./gen_package_desc.sh -l packages-OS32.list -p packages-OS32
```

## Configuration Formats

The toolchain uses two types of simple text files to manage software installation.

### 1. Package List File (`.list`)
The package list defines **what** to install. It is a simple space-separated or tab-separated file.

**Format:**
`PackageName` `SourcePathOrUrl`

* **PackageName**: The name of the package. It must match a corresponding `.desc` file in your descriptions directory.
* **SourcePathOrUrl**: Can be a local path to an archive (`.lha`, `.zip`, `.adf`) or a direct `http/https` URL.
* Lines starting with `#` are ignored.

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

### 2. Package Description File (`.desc`)

The description file defines **where** to copy the files from an archive. Each package mentioned in the `.list` file **must** have a corresponding `.desc` file in the descriptions directory (e.g., `SysInfo.desc`).
Any file present in the archive but not listed in a ".desc" file will be ignored and thus not copied.

**Format:**
`"SourcePathInArchive"` `"AmigaDestination"`

* **SourcePathInArchive**: The internal path of the file or directory inside the archive.
* **AmigaDestination**: The destination path on the Amiga, formatted as `Volume:Path/To/Target`.
* **Encapsulation**: It is highly recommended to wrap both paths in **double quotes** `"` to handle spaces and special characters.

**Key Features:**
* **Path Sanitization**: The script automatically removes trailing slashes and redundant quotes to prevent "directory-in-directory" nesting errors.
* **Automatic Decompression**: Files ending in `.z` or `.Z` (common in AmigaOS updates) are automatically decompressed using `gunzip` during the staging process.
* **Recursive Copy**: If the source path is a directory, its entire content is merged into the destination.
* **Ordering**: Files are processed in the order they appear in the `.desc` file.

**Example (`SysInfo.desc`):**
```text
"SysInfo"                "Workbench:Tools/SysInfo"
"SysInfo.info"           "Workbench:Tools/SysInfo.info"
"Docs/SysInfo.guide"     "Workbench:Help/SysInfo.guide"
```

## Dependencies

The toolchain distinguishes between system-level prerequisites and components that are automatically managed by the scripts.

### 1. System Prerequisites (Hard Dependencies)
These must be installed on your Linux host before running any script. They are essential for archive manipulation, encoding conversion, and disk management.

| Tool | Purpose | Source / Project |
| :--- | :--- | :--- |
| **wget** / **curl** | Downloading remote components and packages. | [Wget](https://www.gnu.org/software/wget/) / [Curl](https://curl.se/) |
| **lha** | Extracting Amiga `.lha` archives. | [GitHub](https://github.com/jca02266/lha) |
| **unadf** | Extracting files from Amiga Disk Files (`.adf`). | [unADF](http://lclevy.free.fr/adflib/) |
| **unzip** | Extracting firmware and tool archives. | [Info-ZIP](http://infozip.sourceforge.net/) |
| **gunzip** | Decompressing `.z` files from Amiga archives. | [GNU Gzip](https://www.gnu.org/software/gzip/) |
| **iconv** | Handling UTF-8 to ISO-8859-1 filename conversion. | [GNU libiconv](https://www.gnu.org/software/libiconv/) |
| **partprobe** | Updating the kernel partition table (RDB/MBR). | [GNU Parted](https://www.gnu.org/software/parted/) |
| **sed** | Path sanitization and configuration generation. | [GNU sed](https://www.gnu.org/software/sed/) |

### 2. Auto-managed Components (Soft Dependencies)

To ensure compatibility and ease of use, the following components are **automatically downloaded and configured** by the scripts. You do not need to install these manually:

* **hst.imager**: The core engine used for RDB partitioning, scripting, and high-speed filesystem transfers. The script fetches the latest version if it's not present in your path.
    * [Project Link](https://github.com/henrikstengaard/hst.imager)
* **Emu68 Firmware**: The latest release of the Emu68 firmware is automatically fetched from its official repository during the disk setup phase to populate the boot partition.
    * [Project Link](https://github.com/michalsc/Emu68)
* **Amiga Filesystems**: **pfs3aio** is bundled to be automatically installed into the RDB (Rigid Disk Block) for optimal partition performance.
    * [PFS3aio Reference](https://aminet.net/package/disk/misc/pfs3aio)
