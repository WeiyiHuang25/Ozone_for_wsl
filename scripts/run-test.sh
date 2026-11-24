#!/usr/bin/env bash
set -euo pipefail

if (( $# < 1 )); then
    printf 'Usage: %s /path/to/patched/libQtGui.so.4.8.7 [Ozone arguments]\n' "$0" >&2
    exit 2
fi

candidate=$(realpath -- "$1")
shift
install_dir=$(realpath -- "${OZONE_DIR:-/opt/SEGGER/Ozone_V352}")
if [[ ! -r "$candidate" || ! -x "$install_dir/Ozone" || ! -d "$install_dir/Lib" ]]; then
    printf 'Expected a readable QtGui library and an installed Ozone V3.52.\n' >&2
    exit 2
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/ozone-wslg-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT
mkdir -- "$test_root/Lib" "$test_root/config" "$test_root/data"
cp -- "$install_dir/Ozone" "$test_root/Ozone"

for path in "$install_dir"/Lib/*; do
    name=${path##*/}
    case "$name" in
        libQtGui.so*) continue ;;
    esac
    ln -s -- "$path" "$test_root/Lib/$name"
done
for name in libQtGui.so libQtGui.so.4 libQtGui.so.4.8 libQtGui.so.4.8.7; do
    ln -s -- "$candidate" "$test_root/Lib/$name"
done
for name in Config Doc Plugins Examples Ozone.png ozone-sim; do
    if [[ -e "$install_dir/$name" ]]; then
        ln -s -- "$install_dir/$name" "$test_root/$name"
    fi
done

export DISPLAY=${DISPLAY:-:0}
export XDG_CONFIG_HOME="$test_root/config"
export XDG_DATA_HOME="$test_root/data"
export LD_LIBRARY_PATH="$test_root/Lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

"$test_root/Ozone" "$@"
