#!/bin/bash
# Assembles $INSTALL/PuffletRuntime.app in the layout Pufflet's
# scripts/ci/package-runtime.sh prepare takes as SOURCE_APP:
#   Contents/SharedSupport/wine/{bin,lib/wine,share/wine (with mono, gecko)}
#   Contents/SharedSupport/gstreamer-1.0/  (GStreamer plugins; codesign treats
#     every directory in Frameworks as a bundle, so they can't live there)
#   Contents/Frameworks/*.dylib
#     (no Vulkan ICD manifest: the loader falls back to libMoltenVK.dylib)
#   Contents/SharedSupport/renderer/dxmt/{wine,LICENSE,version}
# which is also the final installed layout, so Pufflet Dev can run it directly.
# Every private library gets an @rpath install name, and each Mach-O an rpath
# to Frameworks relative to itself, so nothing depends on the build prefix.
source "$(dirname "$0")/config.sh"
APP="$INSTALL/PuffletRuntime.app"
C="$APP/Contents"
FW="$C/Frameworks"
W="$C/SharedSupport/wine"

rm -rf "$APP"
mkdir -p "$W/bin" "$FW" "$C/SharedSupport/renderer"

log "wine"
rsync -a --exclude '*.a' --exclude '*.def' "$INSTALL/wine/lib/wine/" "$W/lib/wine/"
rsync -a "$INSTALL/wine/share/wine/" "$W/share/wine/"
cp "$INSTALL/wine/bin/wineserver" "$W/bin/"
# CrossOver's loader looks for ntdll.so next to its resolved path.
ln -s ../lib/wine/x86_64-unix/wine "$W/bin/wine"
git -C "$ROOT" describe --always --dirty > "$W/version" 2>/dev/null || true

log "wine-mono and wine-gecko"
# WineHQ's prebuilt add-ons, at the versions this Wine asks for (appwiz.cpl/addons.c);
# without them creating a prefix stops at an installer dialog.
fetch https://dl.winehq.org/wine/wine-mono/10.4.1/wine-mono-10.4.1-x86.tar.xz \
    a16606ef0724202e6a6848ece6e0cbba64d11e2f11aefe744af1d93c6d9f99bb wine-mono-10.4.1-x86.tar.xz
fetch https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86.tar.xz \
    2cfc8d5c948602e21eff8a78613e1826f2d033df9672cace87fed56e8310afb6 wine-gecko-2.47.4-x86.tar.xz
fetch https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86_64.tar.xz \
    fd88fc7e537d058d7a8abf0c1ebc90c574892a466de86706a26d254710a82814 wine-gecko-2.47.4-x86_64.tar.xz
mkdir -p "$W/share/wine/mono" "$W/share/wine/gecko"
tar -xf "$DL/wine-mono-10.4.1-x86.tar.xz" -C "$W/share/wine/mono"
tar -xf "$DL/wine-gecko-2.47.4-x86.tar.xz" -C "$W/share/wine/gecko"
tar -xf "$DL/wine-gecko-2.47.4-x86_64.tar.xz" -C "$W/share/wine/gecko"

log "libraries"
# Shared libraries and their soname symlinks, without static or libtool files.
rsync -a --include '*.dylib' --exclude '*' "$DEPS/lib/" "$FW/"
# Pufflet points GST_PLUGIN_SYSTEM_PATH_1_0 here; plugins are scanned in-process.
rsync -a --include '*.dylib' --exclude '*' "$DEPS/lib/gstreamer-1.0/" "$C/SharedSupport/gstreamer-1.0/"

log "dxmt"
mkdir -p "$C/SharedSupport/renderer/dxmt/wine"
for arch in x86_64-unix x86_64-windows i386-windows; do
    rsync -a --exclude '*.a' "$INSTALL/dxmt/$arch/" "$C/SharedSupport/renderer/dxmt/wine/$arch/"
done
cp "$INSTALL/dxmt/version" "$INSTALL/dxmt/LICENSE" "$C/SharedSupport/renderer/dxmt/"
# As in the Sikarugir runtime: DXMT's experimental d3d12 is shipped but not picked
# up by name, so Wine's d3d12 (vkd3d) stays in use.
mv "$C/SharedSupport/renderer/dxmt/wine/x86_64-windows/d3d12.dll" "$C/SharedSupport/renderer/dxmt/wine/x86_64-windows/_d3d12.dll"

log "install names"
# Rewrites references to $DEPS/lib into @rpath and adds an rpath from the file
# to Frameworks. Usage: fix_macho FILE RELATIVE_PATH_TO_FRAMEWORKS
fix_macho() {
    local file="$1" rel="$2" dep args=()
    file -b "$file" | grep -q Mach-O || return 0
    case "$file" in *.dylib) args+=(-id "@rpath/$(basename "$(otool -D "$file" | sed -n 2p)")") ;; esac
    for dep in $(otool -L "$file" | awk 'NR > 1 { print $1 }' | grep "^$DEPS/lib/"); do
        args+=(-change "$dep" "@rpath/${dep##*/}")
    done
    # pkg-config files (glib's) can leave an -rpath into the build prefix.
    for dep in $(otool -l "$file" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }' | grep "^$WORK"); do
        args+=(-delete_rpath "$dep")
    done
    otool -l "$file" | grep -A2 LC_RPATH | grep -q "path @loader_path/$rel " ||
        args+=(-add_rpath "@loader_path/$rel")
    install_name_tool "${args[@]}" "$file" 2>&1 | grep -v "invalidate the code signature" || true
}
while IFS= read -r f; do fix_macho "$f" . ; done < <(find "$FW" -maxdepth 1 -type f -name '*.dylib')
while IFS= read -r f; do fix_macho "$f" ../../Frameworks; done < <(find "$C/SharedSupport/gstreamer-1.0" -type f)
fix_macho "$W/bin/wineserver" ../../../Frameworks
while IFS= read -r f; do fix_macho "$f" ../../../../../Frameworks; done < <(find "$W/lib/wine/x86_64-unix" "$C/SharedSupport/renderer/dxmt/wine/x86_64-unix" -type f)

# Nothing may still point into the build tree.
leaks="$(find "$APP" -type f -print0 | xargs -0 otool -lL 2>/dev/null | grep -v "^$APP" | grep -F "$WORK" || true)"
[ -z "$leaks" ] || { echo "build paths left in the runtime:" >&2; echo "$leaks" >&2; exit 1; }
du -sh "$APP"
