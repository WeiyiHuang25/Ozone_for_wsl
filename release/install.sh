#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help ]]; then
    printf 'Usage: %s [Ozone installation directory]\n' "$0"
    exit 0
fi
if (( $# > 1 )); then
    printf 'Usage: %s [Ozone installation directory]\n' "$0" >&2
    exit 2
fi
if [[ $(uname -m) != x86_64 ]]; then
    printf '%s\n' 'This release requires x86-64 WSLg.' >&2
    exit 2
fi

package=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
version=$(<"$package/VERSION")
if [[ ! $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' 'Invalid release version.' >&2
    exit 2
fi
candidate="$package/libQtGui.so.4.8.7"
ozone_dir=$(realpath -- "${1:-${OZONE_DIR:-/opt/SEGGER/Ozone_V352}}")
if [[ ! -x "$ozone_dir/Ozone" || ! -r "$ozone_dir/Lib/libQtCore.so.4" ]]; then
    printf 'Install SEGGER Ozone V3.52, then provide its installation directory.\n' >&2
    exit 2
fi
if [[ ! -r "$candidate" ]]; then
    printf '%s\n' 'The release archive is missing QtGui.' >&2
    exit 2
fi

data_root="${XDG_DATA_HOME:-$HOME/.local/share}/ozone-wslg"
bin_dir="${OZONE_WSLG_BIN_DIR:-$HOME/.local/bin}"
mkdir -p -- "$data_root/config" "$data_root/data" "$bin_dir"
data_root=$(realpath -- "$data_root")
bin_dir=$(realpath -- "$bin_dir")
target="$data_root/$version"
shortcut="$bin_dir/ozone-wslg"

if [[ -L "$shortcut" ]]; then
    existing=$(readlink -- "$shortcut")
    if [[ "$existing" != "$data_root/"*/ozone-wslg ]]; then
        printf 'This launcher belongs to another installation: %s\n' "$shortcut" >&2
        exit 1
    fi
elif [[ -e "$shortcut" ]]; then
    printf 'A file already exists at %s\n' "$shortcut" >&2
    exit 1
fi

if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" || ! -x "$target/ozone-wslg" ||
        ! -r "$target/OZONE_DIR" || $(<"$target/OZONE_DIR") != "$ozone_dir" ]] ||
        ! cmp -s -- "$candidate" "$target/Lib/libQtGui.so.4.8.7"; then
        printf 'An incompatible copy already exists at %s\n' "$target" >&2
        exit 1
    fi
else
    stage=$(mktemp -d "$data_root/.install.XXXXXX")
    trap 'rm -rf -- "$stage"' EXIT
    mkdir -- "$stage/Lib"
    install -m 755 -- "$ozone_dir/Ozone" "$stage/Ozone"
    install -m 755 -- "$package/ozone-wslg" "$stage/ozone-wslg"
    install -m 644 -- "$candidate" "$stage/Lib/libQtGui.so.4.8.7"
    printf '%s\n' "$ozone_dir" >"$stage/OZONE_DIR"

    for path in "$ozone_dir"/Lib/*; do
        name=${path##*/}
        case "$name" in libQtGui.so*) continue ;; esac
        ln -s -- "$path" "$stage/Lib/$name"
    done
    for name in libQtGui.so libQtGui.so.4 libQtGui.so.4.8; do
        ln -s -- libQtGui.so.4.8.7 "$stage/Lib/$name"
    done
    for name in Config Doc Plugins Examples Ozone.png ozone-sim; do
        if [[ -e "$ozone_dir/$name" ]]; then
            ln -s -- "$ozone_dir/$name" "$stage/$name"
        fi
    done

    if ! report=$(LD_LIBRARY_PATH="$stage/Lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        ldd -r "$stage/Ozone" 2>&1) ||
        [[ $report == *'not found'* || $report == *'undefined symbol'* ]]; then
        printf '%s\n' "$report" >&2
        exit 1
    fi
    mv -T -- "$stage" "$target"
fi

link_dir=$(mktemp -d "$bin_dir/.ozone-wslg.XXXXXX")
trap 'rmdir -- "$link_dir" 2>/dev/null || true' EXIT
ln -s -- "$target/ozone-wslg" "$link_dir/ozone-wslg"
if ! mv -Tf -- "$link_dir/ozone-wslg" "$shortcut"; then
    rm -f -- "$link_dir/ozone-wslg"
    exit 1
fi
printf 'Launcher: %s\n' "$shortcut"
