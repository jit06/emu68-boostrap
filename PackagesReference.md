# Package reference for Emu68-Boostrap

The following document serves as rules for creating and modifying a package. Feel free to propose new ones or add new software in existing packages.

>Note: I created [adf2zip](https://github.com/jit06/adf2zip), a companion tool that automates the extraction, reconstruction, and repackaging of applications which employs complex storage techniques to fit data onto fewer floppies (lha inside ADF, splitted files, etc.).

## Supported Language

By convention or simplicity (who said lazyness ?), no catalogs nor locale files are installed. All packages relies on the original english language

## Naming convention

- a package name is lowercase, except "OS"
- desc file and associated software follow thw following convention: `<name><version with dot>`
- if a software is distributed with mutiple file (eg. ADF), the name ends with the part number (eg `1`, `2`, etc)
- desc file describing an ISO image ends with `CD`

## Package organization

| Package File  | Description        |
|---------------|-----------------|
| addons   | Various OS addons which are installed in the `Workbench` partition        |
| emu68tools | Tools and drivers to manage emu68 on a PiStorm          |
| games     | Amiga games with native HDD compatibility and no WHDload slave        |
| graphics  | Graphical applications such as DPaint. Some entries rely on commercial files that you must put into the `custon` directory        |
| ibrowse   | Dedicated to iBrowse v2.58 that you must provide your own copy in the `custom` directory        |
| music     | Music making and playing software, like ProTracker AGA, DA Player, etc.        |
| office    | Office related software like Final Calc or Final Writer 97        |
| optical   | Software often needed with a CDRom drive or CD Recorder         |
| OS32      | Amiga OS 3.2 and updates. You must provide your own ADF files in the dedicated directories        |
| pcgames   | PC games ported to Amiga like Doom or Quake        |
| picasso96 | RTG drivers and tools for both UAE and PiStorm        |
| pimyretro | Custom package to apply settings used on my own A1200        |
| whdload   | WHDload official "light" package, kickstarts, RTB files and iGame interface         |
| whdlmedias | Games and Demos assets as used by iGame        |
| whdlgames | Selection of whdload games        |
