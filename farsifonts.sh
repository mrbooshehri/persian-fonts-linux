#!/usr/bin/env bash
# Improved Persian fonts installer, based on fzerorubigd/persian-fonts-linux.
set -uo pipefail

FONT_BASE_URL=${PERSIAN_FONTS_BASE_URL:-https://raw.githubusercontent.com/mrbooshehri/persian-fonts-linux/master/fonts}
CATALOG_URL=${PERSIAN_FONTS_CATALOG_URL:-$FONT_BASE_URL/list.txt}
CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/persian-fonts
FONT_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/fonts/persian
CATALOG=$CACHE_DIR/list.txt
DOWNLOADER=auto
SHA256_FILE=${PERSIAN_FONTS_SHA256_FILE:-}
ALL=0; LIST=0; FORCE=0; OFFLINE=0; REFRESH=0
SUCCESS=0; SKIPPED=0; FAILED=0; CHANGED=0

green=''; yellow=''; red=''; reset=''
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; reset=$'\033[0m'; fi
info() { printf '%s\n' "[INFO] $*"; }
ok() { printf '%s%s%s\n' "$green" "[OK] $*" "$reset"; }
warn() { printf '%s%s%s\n' "$yellow" "[WARN] $*" "$reset" >&2; }
err() { printf '%s%s%s\n' "$red" "[ERROR] $*" "$reset" >&2; }
usage() { cat <<'HELP'
Usage: farsifonts.sh [options]
  --all                  Install all fonts without prompting
  --list                 List fonts in the catalog
  --force                Re-download and reinstall selected fonts
  --offline              Use cached catalog and archives only
  --refresh              Refresh the catalog (otherwise use cached copy)
  --downloader TOOL      auto|aria2c|axel|curl|wget
  --sha256 FILE          Verify archives against SHA-256 manifest
  --help                 Show help
Environment:
  PERSIAN_FONTS_CATALOG_URL  Override catalog URL
  PERSIAN_FONTS_BASE_URL     Override repository font directory URL
  XDG_CACHE_HOME, XDG_DATA_HOME
Notes: archives are cached and validated; no sudo is needed.
HELP
}
while (($#)); do
  case $1 in
    --all) ALL=1;; --list) LIST=1;; --force) FORCE=1;; --offline) OFFLINE=1;; --refresh) REFRESH=1;;
    --downloader) [[ $# -ge 2 ]] || { err 'Missing downloader'; exit 2; }; DOWNLOADER=$2; shift;;
    --downloader=*) DOWNLOADER=${1#*=};;
    --sha256) [[ $# -ge 2 ]] || { err "Missing manifest path"; exit 2; }; SHA256_FILE=$2; shift;;
    --sha256=*) SHA256_FILE=${1#*=};;
    axel|wget|aria2c|curl) DOWNLOADER=$1;; # Original positional syntax
    --help|-h) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 2;;
  esac
  shift
done
case $DOWNLOADER in auto|aria2c|axel|curl|wget) ;; *) err "Unsupported downloader: $DOWNLOADER"; exit 2;; esac
if [[ -n $SHA256_FILE ]]; then
  [[ -r $SHA256_FILE ]] && command -v sha256sum >/dev/null || { err "Readable SHA-256 manifest and sha256sum required"; exit 1; }
fi
command -v unzip >/dev/null || { err 'unzip is required'; exit 1; }
command -v fc-cache >/dev/null || warn 'fc-cache not available; font cache cannot be refreshed'
mkdir -p "$CACHE_DIR" "$FONT_DIR" || exit 1

choose_downloader() {
  local candidate
  if [[ $DOWNLOADER != auto ]]; then
    command -v "$DOWNLOADER" >/dev/null || { err "$DOWNLOADER not installed"; return 1; }
    return 0
  fi
  for candidate in aria2c axel curl wget; do
    if command -v "$candidate" >/dev/null; then DOWNLOADER=$candidate; return 0; fi
  done
  err 'Install aria2c, axel, curl, or wget'; return 1
}
# Downloader progress is printed to the terminal; stderr is intentionally not hidden.
# Partial files are retained for resumable tools. A validated completed file is atomically renamed.
download() {
  local url=$1 dest=$2 partial="${2}.part" status=0
  case $DOWNLOADER in
    aria2c) aria2c --continue=true --max-connection-per-server=8 --split=8 --min-split-size=1M \
      --file-allocation=none --summary-interval=1 --console-log-level=warn \
      --dir="$(dirname "$partial")" --out="$(basename "$partial")" "$url" || status=$?;;
    axel) axel -n 8 -a -o "$partial" "$url" || status=$?;;
    curl) curl --fail --location --retry 3 --continue-at - --progress-bar --output "$partial" "$url" || status=$?;;
    wget) wget --continue --show-progress --progress=bar:force -O "$partial" "$url" || status=$?;;
  esac
  ((status == 0)) && [[ -s $partial ]] || return 1
  mv -f -- "$partial" "$dest"
}
verify_checksum() {
  local archive=$1 filename=${1##*/} expected actual
  [[ -n $SHA256_FILE ]] || return 0
  expected=$(awk -v f="$filename" '$2==f || $2=="*"f {print $1; exit}' "$SHA256_FILE")
  [[ $expected =~ ^[[:xdigit:]]{64}$ ]] || { warn "No valid checksum for $filename"; return 1; }
  actual=$(sha256sum -- "$archive") || return 1
  [[ ${actual%% *} == "$expected" ]]
}
valid_archive() {
  local file=$1
  [[ -s $file ]] || return 1
  case ${file,,} in
    *.zip) unzip -tqq "$file" >/dev/null 2>&1;;
    *.ttf|*.otf) [[ -s $file ]] && { ! command -v fc-scan >/dev/null || fc-scan --format '%{family}\n' "$file" 2>/dev/null | grep -q .; };;
    *) return 1;;
  esac
}
# Validate paths in ZIPs before extraction; reject traversal, absolute paths and symlinks.
zip_is_safe() {
  local file=$1 member
  while IFS= read -r member; do
    [[ -n $member ]] || continue
    [[ $member != /* && $member != \\* && $member != *\\* && $member != *:* ]] || return 1
    [[ /$member/ != *'/../'* && /$member/ != *'/./'* ]] || return 1
  done < <(unzip -Z -1 "$file")
  # ZIP entries marked as symbolic links are disallowed.
  if command -v zipinfo >/dev/null; then
    zipinfo -l "$file" | awk 'NR>3 && substr($1,1,1)=="l" {bad=1} END {exit !bad}' && return 1
  fi
  return 0
}

if (( ! OFFLINE )); then
  choose_downloader || exit 1
  info "Downloader: $DOWNLOADER"
fi
# Refresh an older default catalog after switching the source to this repository.
if (( ! OFFLINE && ! REFRESH )) && [[ -z ${PERSIAN_FONTS_CATALOG_URL:-} && -s $CATALOG ]] &&
   ! grep -q '^RFonts|' "$CATALOG"; then
  info 'Cached catalog is outdated; refreshing from the repository'
  REFRESH=1
fi
if [[ ! -s $CATALOG || $REFRESH -eq 1 ]]; then
  if ((OFFLINE)); then err "No cached catalog at $CATALOG"; exit 1; fi
  info 'Fetching font catalog...'
  # Keep an older valid catalog if refresh fails.
  if download "$CATALOG_URL" "$CATALOG.new"; then
    mv -f "$CATALOG.new" "$CATALOG"
  elif [[ ! -s $CATALOG ]]; then
    err 'Catalog download failed'; exit 1
  else
    warn 'Catalog refresh failed; using cached catalog'
  fi
else
  info 'Using cached catalog (pass --refresh to update)'
fi

names=(); files=(); urls=(); descriptions=()
repo_url_for_file() {
  local filename=$1 encoded
  encoded=${filename// /%20}
  printf '%s/%s' "$FONT_BASE_URL" "$encoded"
}
while IFS='|' read -r name filename url description rest || [[ -n ${name:-} ]]; do
  [[ -n ${name:-} && -n ${filename:-} && -n ${url:-} ]] || continue
  # Migrate legacy catalog names to the filename vendored in this repository.
  case ${name,,} in
    xbnilufar|xbniloofar|xb\ niloofar|xb\ nilufar) filename='XB Niloofar.ttf' ;;
  esac
  [[ $name != *'/'* && $name != *'\\'* && $name != '.' && $name != '..' ]] || { warn "Skipping unsafe font name: $name"; continue; }
  [[ $filename == "$(basename -- "$filename")" && $filename != .* && $filename != *\* ]] || { warn "Skipping unsafe filename: $filename"; continue; }
  case ${filename,,} in *.zip|*.ttf|*.otf) ;; *) warn "Skipping unsupported file: $filename"; continue;; esac
  case $url in https://*|http://*) ;; *) warn "Skipping invalid URL for $name"; continue;; esac
  names+=("$name"); files+=("$filename"); urls+=("$(repo_url_for_file "$filename")"); descriptions+=("${description:-}")
done < "$CATALOG"
((${#names[@]})) || { err 'No usable entries in font catalog'; exit 1; }
if ((LIST)); then
  for i in "${!names[@]}"; do printf '%3d) %s — %s\n' "$((i+1))" "${names[i]}" "${descriptions[i]}"; done
  exit 0
fi

install_one() {
  local i=$1 name=${names[$1]} filename=${files[$1]} url=${urls[$1]}
  local archive="$CACHE_DIR/$filename" target="$FONT_DIR/$name" temp path count=0
  info "Processing $name ($filename)"
  if [[ -f $target/.persian-fonts-source && $FORCE -eq 0 && -z $SHA256_FILE ]] && \
     [[ $(cat "$target/.persian-fonts-source") == "$url" ]] && \
     find "$target" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit | grep -q .; then
    ok "Already installed: $name"; ((SKIPPED+=1)); return 0
  fi
  if ((FORCE)) || ! valid_archive "$archive" || ! verify_checksum "$archive"; then
    if ((OFFLINE)); then err "Missing/invalid cached archive: $filename"; ((FAILED+=1)); return 1; fi
    if [[ -f $archive ]]; then warn "Invalid cache; downloading again: $filename"; rm -f -- "$archive" "$archive.part"; fi
    info "Downloading $filename..."
    if ! download "$url" "$archive" || ! valid_archive "$archive" || ! verify_checksum "$archive"; then
      err "Download or validation failed: $filename"; rm -f -- "$archive"; ((FAILED+=1)); return 1
    fi
  else
    ok "Using cached archive: $filename"
  fi
  temp=$(mktemp -d "$FONT_DIR/.install.XXXXXXXX") || { ((FAILED+=1)); return 1; }
  case ${filename,,} in
    *.zip)
      if ! zip_is_safe "$archive" || ! unzip -oq "$archive" -d "$temp"; then
        err "Unsafe or unextractable ZIP: $filename"; rm -rf -- "$temp"; ((FAILED+=1)); return 1
      fi;;
    *.ttf|*.otf) cp -- "$archive" "$temp/$filename" || { rm -rf -- "$temp"; ((FAILED+=1)); return 1; };;
  esac
  count=$(find "$temp" -type f \( -iname '*.ttf' -o -iname '*.otf' \) | wc -l)
  if ((count == 0)); then err "No fonts found in $filename"; rm -rf -- "$temp"; ((FAILED+=1)); return 1; fi
  # Remove unrelated files from archives before installation.
  find "$temp" -type f ! -iname '*.ttf' ! -iname '*.otf' -delete
  printf '%s' "$url" > "$temp/.persian-fonts-source"
  mkdir -p "$target" || { rm -rf -- "$temp"; ((FAILED+=1)); return 1; }
  # Copy new files; preserve other existing files rather than deleting user data.
  cp -a -- "$temp/." "$target/" || { err "Failed installing $name"; rm -rf -- "$temp"; ((FAILED+=1)); return 1; }
  rm -rf -- "$temp"
  ((SUCCESS+=1)); ((CHANGED+=1)); ok "Installed $name ($count font files)"
}

selected=()
if ((ALL)); then
  selected=("${!names[@]}")
else
  printf '\nAvailable fonts:\n'
  for i in "${!names[@]}"; do printf '%3d) %s\n' "$((i+1))" "${names[i]}"; done
  printf '  a) Install all\n  q) Quit\n'
  while :; do
    read -r -p 'Choose a number, a, or q: ' choice || exit 0
    case $choice in
      q|Q) exit 0;;
      a|A) selected=("${!names[@]}"); break;;
      *[!0-9]*|'') warn 'Invalid selection';;
      *) if ((10#$choice >= 1 && 10#$choice <= ${#names[@]})); then
           selected=("$((10#$choice-1))"); break
         else warn 'Out of range'; fi;;
    esac
  done
fi

for j in "${!selected[@]}"; do
  printf '\n[%d/%d] ' "$((j+1))" "${#selected[@]}"
  install_one "${selected[j]}" || true
done
if ((CHANGED)) && command -v fc-cache >/dev/null; then
  info 'Refreshing font cache...'
  fc-cache -f "$FONT_DIR" && ok 'Font cache refreshed' || warn 'fc-cache failed'
fi
printf '\nSummary: installed=%d, already-installed=%d, failed=%d\n' "$SUCCESS" "$SKIPPED" "$FAILED"
((FAILED == 0))
