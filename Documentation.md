# Full documentation for Emu68-Boostrap

- [Full documentation for Emu68-Boostrap](#full-documentation-for-emu68-boostrap)
  - [Initialize disk and Amiga partitions](#initialize-disk-and-amiga-partitions)
    - [Arguments \& Options](#arguments--options)
    - [Usage Example](#usage-example)
  - [Install Amiga software](#install-amiga-software)
    - [Layered Package System](#layered-package-system)
    - [Icons operations with ".icons" files](#icons-operations-with-icons-files)
      - [Icon types](#icon-types)
    - [Arguments \& Options](#arguments--options-1)
    - [Usage Example](#usage-example-1)
  - [Create packages](#create-packages)
    - [Arguments \& Options](#arguments--options-2)
    - [Usage Example](#usage-example-2)
  - [Configuration Formats](#configuration-formats)
    - [Package List File](#package-list-file)
  - [Package Description](#package-description)


## Initialize disk and Amiga partitions

The `setup_disk.sh` script is responsible for the low-level preparation of the storage medium. It automates the creation of a hybrid partition structure compatible with both the host hardware (via MBR) and the Amiga environment (via RDB).

**Key actions:**

- **Hybrid Partitioning**: Creates an MBR table with two primary partitions:
    1. **FAT32 Partition**: Dedicated to Emu68 firmware and boot files.
    2. **Type 0x76 Partition**: A container for the Amiga Rigid Disk Block (RDB), which allows for native Amiga partitions (Workbench, Data, etc.).
- **Dynamic Configuration**: The partitioning process relies on a `partitions.config` file using the **hst.imager** script format.

    > **Note**: The placeholder `[PATH_TO_DISK]` within this file is automatically replaced at runtime by the disk path provided in the arguments.

- **Emu68 Installation**: Downloads the latest firmware, installs the provided Kickstart ROM, and handles optional custom `config.txt` or `cmdline.txt` files.
- **Filesystem Setup**: Prepares the RDB structure and installs necessary Amiga filesystems like `pfs3aio`.

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
sudo ./setup_disk.sh -d /dev/sdc -k ./roms/kick32.rom --clean-on-close
```

## Install Amiga software

The `package.sh` script handles the high-speed deployment of software to the Amiga partitions. Instead of copying files one by one (which is extremely slow on RDB structures), it reconstructs the entire file tree in a local **staging area** on Linux before performing a bulk transfer to the disk.

**Key features:**

- **Flexible Sourcing**: Supports local archives or direct downloads via HTTP/HTTPS.
- **Smart Extraction**: Automatically handles `.lha`, `.zip`, and `.adf` files, including `.z` decompression (gunzip).
- **Encoding Bridge**: Converts package descriptions and filenames from Linux (UTF-8) to Amiga (ISO-8859-1) to ensure accents and special characters appear correctly on the Workbench.
- **Volume Mapping**: Allows you to map virtual Amiga volume names (e.g., `Workbench:`) to physical RDB device names (e.g., `SDH0`) defined on your disk.
- **Bulk Transfer**: Uses **hst.imager** to copy entire directories to the RDB partitions in seconds rather than minutes.

### Layered Package System

The deployment follows a **top-down priority** based on your package list. Software are installed in the exact order specified in the `.list` file, overwriting any existing files in the staging area.

**Standardized Repository**: By default, the script looks into `packages` directory where `.list` files and their associated `.desc` folders (of the same name) are stored.

- **Multi-Package Installation**: You can chain multiple package sets (e.g., `OS32,Addons`) in a single command. They will be processed in the order provided.
- **Customizable & Layered**: You can easily add or reorder software. For example, installing a "GlowIcons" package after the main OS will automatically overwrite the standard icons in the staging area.
- **Pre-configured Packages**: Several ready-to-use sets are available in the `packages` folder:
  - **OS32**: AmigaOS 3.2 & Update 3.2.3.
  - **emu68tools**: Specific utilities for PiStorm users.
  - **addons**: SysInfo, MUI, and other "essential" tools for modern Amiga.

> **Note**: any `.user-startup` file will be injected in system partition `S/User-startup` and will automatically be surounded `;BEGIN <package name>` and `;END <package name>`

### Icons operations with ".icons" files

Any package can be associated with a ".icons" file which contains orders passed through to hst.amiga command. The goal is to change icon type and positions in the staging area. It allows to customize any icons before copying files to the final destination.

**The file format is basicaly :**

```bash
<Amiga style path to the .info file> <hst.amiga icon order> <hst.amiga command arguments>
```

**Example :**
If you have a package with the following `StandardGlowIcons.desc` to copy a specific disk icon to the workbench partition:

```bash
"StandardGlowIcons/Drives/Harddrive/AmigaHDisk.info" "Workbench:disk.info"
```

You can then use the following `StandardGlowIcons.icons` file to set the icon type to `1` (`disk`) and fix its position to `0,50` on the workbench window

```bash
"Workbench:disk.info"   update -t 1 -x 0 -y 50
```

#### Icon types

* **1**: disk
* **2**: drawer
* **3**: tool
* **4**: project
* **5**: trashcan
* **7**: kickstart
* **8**: appicon

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

## Create packages

The `generate_package.sh` script is the companion tool for creating the `.desc` files required by the deployment process. It automates the indexing of archives and attempts to intelligently map where files should be installed on the Amiga partitions. This provides with a simple yet efficient way to build and share reproductable installations without sharing a heavy binary image.

**Key features:**

- **AmigaOS 3.2 Specialized Logic**: Includes dedicated rules for processing official AmigaOS 3.2 and Update ADFs. It mimics the behavior of the original Commodore/Hyperion install scripts (e.g., remapping `Startup-HardDrive` to `S:Startup-Sequence`, copying Backdrops to Presets, etc.).
- **Generic Rule Engine**: For non-OS archives, the script applies a "best-guess" logic to place files in standard Amiga locations (e.g., `.library` to `Libs:`, `.device` to `Devs:`).
- **Multi-Format Support**: Can parse and index `.lha`, `.zip`, `.iso` and `.adf` archives.
- **Smart Remapping**: Automatically detects and handles compressed `.z` files, stripping the extension for the destination path.

> **Note**: While the specialized OS 3.2 logic is pretty accurate, the generic output for third-party software often serves as a template and **requires manual adjustment** to ensure perfect placement.

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
./gen_package_desc.sh -l packages-OS32.list -p packages-OS32
```

## Configuration Formats

The toolchain uses two types of simple text files to manage software installation.

### Package List File

A package list is a simple text file that defines **what** to install. It is a simple space-separated or tab-separated file which name ends with `.list` by convention.

**Format:**
`PackageName` `SourcePathOrUrl`

- **PackageName**: The name of the package. It must match a corresponding `.desc` file in your descriptions directory.
- **SourcePathOrUrl**: Can be a local path to an archive (`.lha`, `.zip`, `.iso` or `.adf`) or a direct `http/https` URL.
- Lines starting with `#` are ignored (comments)
- If a source path url ends with "!", the first encoutered ADF file inside the archive will be used instead of the archive itself.

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

## Package Description

The description file defines **where** to copy the files from an archive. A description file ends with `.desc`. Each package mentioned in the `.list` file **must** have a corresponding `.desc` file in the descriptions directory (e.g., `SysInfo.desc`).
Any file present in the archive but not listed in a ".desc" file will be ignored and thus not copied.

**Format:**

`"SourcePathInArchive"` `"AmigaDestination"`

- **SourcePathInArchive**: The internal path of the file or directory inside the archive.
- **AmigaDestination**: The destination path on the Amiga, formatted as `Volume:Path/To/Target`.
- **Encapsulation**: It is highly recommended to wrap both paths in **double quotes** `"` to handle spaces and special characters.

**Key Features:**

- **Path Sanitization**: The script automatically removes trailing slashes and redundant quotes to prevent "directory-in-directory" nesting errors.
- **Automatic Decompression**: Files ending in `.z` or `.Z` (common in AmigaOS updates) are automatically decompressed using `gunzip` during the staging process.
- **Recursive Copy**: If the source path is a directory, its entire content is merged into the destination.
- **Ordering**: Files are processed in the order they appear in the `.desc` file.

**Example (`SysInfo.desc`):**

```text
"SysInfo"                "Workbench:Tools/SysInfo"
"SysInfo.info"           "Workbench:Tools/SysInfo.info"
"Docs/SysInfo.guide"     "Workbench:Help/SysInfo.guide"
```
