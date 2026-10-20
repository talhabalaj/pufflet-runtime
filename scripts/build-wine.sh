#!/bin/bash
# Builds Wine for an x86_64 host (run under Rosetta) with new WoW64.
# Library paths are rewritten to @rpath by scripts/stage.sh.
# Native arm64 build tools are built first, then the x86_64 tree is cross-compiled.
#   scripts/build-wine.sh tools      native winebuild/widl/wrc/... only
#   scripts/build-wine.sh [all]      tools (if needed), configure, build, install
source "$(dirname "$0")/config.sh"
WSRC="$SRC/wine"
export PATH="$BREW/opt/bison/bin:$BREW/opt/flex/bin:$BREW/bin:/usr/bin:/bin:/usr/sbin:/sbin"

build_tools() {
    [ -x "$TOOLS/tools/winebuild/winebuild" ] && return
    log "wine tools (arm64)"
    mkdir -p "$TOOLS" && cd "$TOOLS"
    # A tools-only tree still wants a PE compiler; sfnt2fon needs a native FreeType.
    PATH="$BREW/opt/llvm/bin:$BREW/opt/lld/bin:$PATH" "$WSRC/configure" \
        --enable-archs=aarch64 --with-mingw=clang --disable-tests \
        --without-x --with-freetype --without-gnutls --without-sdl --without-vulkan \
        --without-gstreamer --without-ffmpeg --without-opencl \
        CC=/usr/bin/clang CXX=/usr/bin/clang++ CFLAGS="-O2 -g0" \
        FREETYPE_CFLAGS="-I$BREW/opt/freetype/include/freetype2" \
        FREETYPE_LIBS="-L$BREW/opt/freetype/lib -lfreetype"
    make -j"$JOBS" __tooldeps__
}

build_wine() {
    log "wine (x86_64)"
    mkdir -p "$WBUILD" && cd "$WBUILD"
    # wrc wants the nls tables next to the tools tree.
    for f in "$WSRC"/nls/*.nls; do ln -sf "$f" "$TOOLS/nls/${f##*/}"; done
    export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig" PKG_CONFIG_PATH=""
    if [ ! -f Makefile ]; then
        "$WSRC/configure" --prefix="$INSTALL/wine" \
            --host=x86_64-apple-darwin --build=aarch64-apple-darwin --with-wine-tools="$TOOLS" \
            --enable-archs=i386,x86_64 --with-mingw --disable-tests \
            --without-alsa --without-capi --with-coreaudio --with-cups --without-dbus \
            --without-fontconfig --with-freetype --with-gnutls --without-gphoto --with-gstreamer \
            --without-krb5 --without-netapi --without-oss --without-pulse --without-sane --with-sdl \
            --without-udev --without-usb --without-v4l2 --with-vulkan --without-x --without-wayland \
            --with-ffmpeg --with-inotify --without-pcap \
            CC="clang -arch x86_64" CXX="clang++ -arch x86_64" OBJC="clang -arch x86_64" \
            i386_CC=i686-w64-mingw32-gcc x86_64_CC=x86_64-w64-mingw32-gcc \
            CFLAGS="-O2 -g0" CROSSCFLAGS="-O2 -g0" CPPFLAGS="-I$DEPS/include" \
            LDFLAGS="-L$DEPS/lib -Wl,-headerpad_max_install_names" \
            PKG_CONFIG="$BREW/bin/pkg-config"
    fi
    # configure silently drops optional features; insist on the ones the runtime ships.
    local need
    for need in SONAME_LIBFREETYPE SONAME_LIBGNUTLS SONAME_LIBSDL2 SONAME_LIBVULKAN; do
        grep -q "#define $need " include/config.h || { echo "missing $need" >&2; exit 1; }
    done
    for need in HAVE_FFMPEG HAVE_SYS_INOTIFY_H; do
        grep -q "#define $need 1" include/config.h || { echo "missing $need" >&2; exit 1; }
    done
    grep -q "^GSTREAMER_LIBS = ." Makefile || { echo "missing gstreamer" >&2; exit 1; }
    make -j"$JOBS"
    rm -rf "$INSTALL/wine"
    make install-lib
}

build_tools
[ "${1:-all}" = tools ] && exit 0
build_wine
