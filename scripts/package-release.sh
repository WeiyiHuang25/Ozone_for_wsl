#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )) || [[ ! $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Usage: %s vMAJOR.MINOR.PATCH QtGui.so SEGGER_Qt487_Src.7z\n' "$0" >&2
    exit 2
fi

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=$1
library=$(realpath -- "$2")
source_archive=$(realpath -- "$3")
printf '%s  %s\n' 09a32c0d0292c128f91f045ac129b0418d99f2936a6e08b22797f72d73e5f6bd \
    "$source_archive" | sha256sum --check
readelf -h "$library" | grep -q 'Machine:.*X86-64'
readelf -d "$library" | grep -q 'SONAME.*\[libQtGui.so.4\]'

stem="ozone-wslg-$version"
binary="$stem-ubuntu26.04-x86_64"
source="$stem-qt-source"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p -- "$work/$binary" "$work/$source/vendor" "$repo/dist"

install -m 755 -- "$repo/release/install.sh" "$repo/release/ozone-wslg" "$work/$binary/"
install -m 644 -- "$repo/release/README.md" "$repo/LICENSE.LGPLv21" "$work/$binary/"
install -m 644 -- "$library" "$work/$binary/libQtGui.so.4.8.7"
printf '%s\n' "$version" >"$work/$binary/VERSION"

cp -a -- "$repo/patches" "$repo/scripts" "$repo/README.md" "$repo/LICENSE.LGPLv21" "$work/$source/"
cp -- "$source_archive" "$work/$source/vendor/SEGGER_Qt487_Src.7z"

tar -C "$work" -czf "$repo/dist/$binary.tar.gz" "$binary"
tar -C "$work" -cf - "$source" | gzip -1 >"$repo/dist/$source.tar.gz"
cd -- "$repo/dist"
sha256sum "$binary.tar.gz" "$source.tar.gz" >SHA256SUMS
cat SHA256SUMS
