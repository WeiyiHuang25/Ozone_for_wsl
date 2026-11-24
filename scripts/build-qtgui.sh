#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
    printf 'Usage: %s /path/to/extracted/qt-source\n' "$0" >&2
    exit 2
fi

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_tree=$(realpath -- "$1")
if [[ ! -f "$source_tree/configure" || ! -d "$source_tree/mkspecs/linux-g++-64" ]]; then
    printf 'Expected the extracted SEGGER Qt 4.8.7 source tree.\n' >&2
    exit 2
fi

export OZONE_QT_CXX
OZONE_QT_CXX=$(command -v g++)
mkdir -p -- "$repo/build"
work=$(mktemp -d "$repo/build/qt4.XXXXXX")
qt="$work/source"
build="$work/build"
mkdir -- "$qt" "$build" "$work/bin"
cp -a -- "$source_tree/." "$qt/"
printf 'Build directory: %s\n' "$work"

python3 - "$qt" <<'PY'
from pathlib import Path
import stat
import sys

source = Path(sys.argv[1])
patch_targets = {
    source / "src/corelib/global/qglobal.h",
    source / "src/gui/kernel/qwidget_x11.cpp",
}
for path in source.rglob("*"):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open("rb") as stream:
        script = stream.read(2) == b"#!"
    if script or path in patch_targets or path.name in {"configure", "Makefile"} or (
        path.suffix in {".conf", ".mk", ".prf", ".pri", ".pro", ".sh"}
    ):
        original = path.read_bytes()
        normalized = original.replace(b"\r\n", b"\n")
        if original != normalized:
            path.write_bytes(normalized)
        if script:
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
PY

for diff in "$repo"/patches/*.patch; do
    patch --directory "$qt" --strip 1 --batch --forward --input "$diff"
done

cat >"$work/bin/g++" <<'SH'
#!/usr/bin/env bash
exec "$OZONE_QT_CXX" -std=gnu++98 "$@"
SH
chmod +x "$work/bin/g++"
export PATH="$work/bin:$PATH"
export CXXFLAGS="-std=gnu++98 ${CXXFLAGS:-}"

sdk_flags=()
if [[ -n ${QT4_SDK:-} ]]; then
    sdk=$(realpath -- "$QT4_SDK")
    sdk_lib="$sdk/lib/x86_64-linux-gnu"
    export C_INCLUDE_PATH="$sdk/include${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"
    export CPLUS_INCLUDE_PATH="$sdk/include${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
    export LIBRARY_PATH="$sdk_lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
    export PKG_CONFIG_PATH="$sdk_lib/pkgconfig:$sdk/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    sdk_flags=(-I "$sdk/include" -I "$sdk/include/freetype2" -L "$sdk_lib")
fi

cd -- "$build"
bash "$qt/configure" \
    -prefix "$work/install" -platform linux-g++-64 -nomake examples -nomake demos -nomake \
    docs -nomake translations -nomake tests -nomake tools -opensource -confirm-license \
    -shared -no-fast -largefile -no-system-proxies -exceptions -no-accessibility -stl \
    -no-sql-db2 -no-sql-ibase -no-sql-mysql -no-sql-odbc -no-sql-psql -no-sql-sqlite \
    -no-sql-sqlite2 -no-sql-sqlite_symbian -no-sql-tds -no-qt3support -no-xmlpatterns \
    -no-multimedia -no-audio-backend -no-phonon -no-phonon-backend -no-webkit -no-script \
    -no-scripttools -no-declarative -no-declarative-debug -graphicssystem raster \
    -no-mmx -no-3dnow -no-sse -no-sse2 -no-neon -little-endian -no-libmng -no-libtiff \
    -qt-zlib -qt-libpng -qt-libjpeg -no-openssl -no-nis -no-cups -iconv \
    -no-dbus -no-opengl -no-openvg -release -no-svg -no-gif -no-xml \
    -no-javascript-jit -no-sse3 -no-ssse3 -no-sse4.1 -no-sse4.2 -no-avx -no-rpath \
    -no-optimized-qmake -pch -no-separate-debug-info -no-nas-sound -sm -no-xshape \
    -no-xvideo -no-xsync -no-xinerama -xcursor -xfixes -xrandr -xrender -no-mitshm \
    -fontconfig -no-xinput -xkb -no-glib -silent "${sdk_flags[@]}" >"$work/configure.log" 2>&1 || {
        tail -n 35 "$work/configure.log" >&2
        exit 1
    }

make -j"${JOBS:-$(nproc)}" -C src sub-gui-make_first >"$work/build.log" 2>&1 || {
    tail -n 35 "$work/build.log" >&2
    exit 1
}

library="$build/lib/libQtGui.so.4.8.7"
test -f "$library"
printf 'QtGui: %s\n' "$library"
