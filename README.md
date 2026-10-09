# Persian Fonts for Linux

This repository provides a safe command-line installer for Persian fonts. It
caches the catalog and downloaded archives, validates ZIP and font files,
supports offline installation, and does not require `sudo`.

Repository: <https://github.com/mrbooshehri/persian-fonts-linux>

## Installation

Clone the repository and run the installer:

```shell
git clone https://github.com/mrbooshehri/persian-fonts-linux.git
cd persian-fonts-linux
./farsifonts.sh --all
```

The historical `zfarsifonts.sh` command remains available as a compatibility
entry point and uses the same installer:

```shell
./zfarsifonts.sh --list
```

You can also run the installer directly from this repository:

```shell
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mrbooshehri/persian-fonts-linux/master/farsifonts.sh)"
```

## Options

```text
--all                  Install all fonts without prompting
--list                 List fonts in the catalog
--force                Re-download and reinstall selected fonts
--offline              Use only the cached catalog and archives
--refresh              Refresh the catalog
--downloader TOOL      auto, aria2c, axel, curl, or wget
--sha256 FILE          Verify archives with a SHA-256 manifest
```

The installer stores its cache under `${XDG_CACHE_HOME:-$HOME/.cache}/persian-fonts`
and installs fonts under `${XDG_DATA_HOME:-$HOME/.local/share}/fonts/persian`.
Set `XDG_CACHE_HOME`, `XDG_DATA_HOME`, or
`PERSIAN_FONTS_CATALOG_URL` to customize these locations.
By default, the catalog and font downloads come from this repository's
`master/fonts` directory. Set `PERSIAN_FONTS_BASE_URL` to use another font
directory.

## Bundled font files

The [`fonts/`](fonts/) directory contains the catalog's validated font
archives and font files for local use, mirroring the available installer set.

## Available fonts

Vazir, FarsiFonts, BFonts, IranianSans, IranNastaliq, FPF, Lalezar, XBZar,
XBNilufar, XBKhoramshahr, XBKayhan, XBYaghout, XBRiyaz, XBRoya, XBShafigh,
XBShafighKurd, XBShafighUzbek, XBShiraz, XBSols, XBTitr, XBTabriz, XBTraffic,
XBVahid, XBVosta, XBYermook, XBYas, XBZiba, Tahoma, Samim, Shabnam, Sahel,
VazirCode, Tanha, Nahid, Parastoo, and RFonts.

## XePersian

In a TeX file, include:

```tex
\usepackage{xepersian}
\usepackage{fontspec}
\settextfont[Scale=1]{IranNastaliq}
\setlatintextfont[Scale=1]{TeX Gyre Termes}
```

Then compile it with:

```shell
xelatex <TeX file>
```
