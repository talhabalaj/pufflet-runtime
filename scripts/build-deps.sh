#!/bin/bash
# Builds the x86_64 host libraries Wine loads into $DEPS.
#   scripts/build-deps.sh            every library not built yet
#   scripts/build-deps.sh NAME...    only these (rebuilds them)
# Libraries CrossOver ships come from sources/; the rest are pinned downloads.
# Install names are rewritten to @rpath when the runtime is staged.
source "$(dirname "$0")/config.sh"
export PATH="$BREW/opt/bison/bin:$BREW/opt/flex/bin:$BREW/opt/llvm/bin:$BREW/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig" PKG_CONFIG_PATH=""
export CC="clang -arch x86_64" CXX="clang++ -arch x86_64" OBJC="clang -arch x86_64"
export CFLAGS="-O2" CXXFLAGS="-O2" CPPFLAGS="-I$DEPS/include"
export LDFLAGS="-L$DEPS/lib -Wl,-headerpad_max_install_names"
HOST=x86_64-apple-darwin
BWORK="$WORK/deps-build"
STAMPS="$DEPS/.stamps"
mkdir -p "$BWORK" "$STAMPS"

# Pinned downloads for libraries CrossOver doesn't ship.
SDL2_URL=https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-2.32.10.tar.gz
SDL2_SHA=5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165
INOTIFY_URL=https://github.com/libinotify-kqueue/libinotify-kqueue/releases/download/20240724/libinotify-20240724.tar.gz
INOTIFY_SHA=5cc3fb7af407b17b7daa871cc98bb882716c4b5c296fadfb66bfe86c37cc599c
VKHEADERS_URL=https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz
VKHEADERS_SHA=4a078be12bef21cfebc09d878b77a63cff9d68f899254a0b00d0e37ef73e7f7e
VKLOADER_URL=https://github.com/KhronosGroup/Vulkan-Loader/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz
VKLOADER_SHA=941eff558fc74f248745fb7df367640cf89a8457f216dae498a74ae14b6ba6f7
FFMPEG_URL=https://ffmpeg.org/releases/ffmpeg-7.1.5.tar.xz
FFMPEG_SHA=de668509caf9e35e3cd162473441fdb29538c6d96ed080292b3cf9e6fc5d558f
# CrossOver's nettle is an unmodified 3.10 checkout without the hand-written Makefile.in.
NETTLE_URL=https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz
NETTLE_SHA=b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c
# CrossOver's gnutls 3.8.3 tree has generated build files out of sync with its sources
# and predates nettle 3.10; use a current 3.8 release (same libgnutls.30 ABI).
GNUTLS_URL=https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.13.tar.xz
GNUTLS_SHA=ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e
# gst-libav 1.24.4 (CrossOver's GStreamer) doesn't build against FFmpeg 7; 1.24.13 does.
GSTLIBAV_URL=https://gstreamer.freedesktop.org/src/gst-libav/gst-libav-1.24.13.tar.xz
GSTLIBAV_SHA=150e2b70588fa32a1294f42665756f2175417ce4b5988e2c2081b683719aa6c1
# CrossOver's freetype is the 2.13.3 release as a git checkout, missing its dlg submodule.
FREETYPE_URL=https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz
FREETYPE_SHA=0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289
# MoltenVK newer than CrossOver's 1.2.10, matching the Sikarugir runtime we replace.
MOLTENVK_TAG=v1.4.1

# Unpacks a verified download into a fresh build directory and enters it.
unpack() { # name url sha256 file
    fetch "$2" "$3" "$4"
    rm -rf "$BWORK/$1" && mkdir -p "$BWORK/$1" && cd "$BWORK/$1"
    tar -xf "$DL/$4" --strip-components 1
}

# Copies a sources/ tree so out-of-tree tools can't dirty the checkout.
copy_source() { # name dir
    rm -rf "$BWORK/$1" && mkdir -p "$BWORK" && cp -R "$SRC/$2" "$BWORK/$1" && cd "$BWORK/$1"
    # git doesn't keep mtimes; make generated autotools files newer than their inputs
    # so make doesn't try to regenerate them with whatever automake is installed.
    local f
    for f in aclocal.m4 configure Makefile.in config.h.in; do
        find . -name "$f" -exec touch {} + ; sleep 1
    done
}

cmake_build() { # extra cmake args...
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS" \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
        -DCMAKE_PREFIX_PATH="$DEPS" -DCMAKE_INSTALL_NAME_DIR="$DEPS/lib" "$@"
    cmake --build build -j "$JOBS"
    cmake --install build
}

meson_cross() {
    cat > "$BWORK/x86_64-darwin.ini" <<EOF
[binaries]
c = ['clang', '-arch', 'x86_64']
cpp = ['clang++', '-arch', 'x86_64']
objc = ['clang', '-arch', 'x86_64']
objcpp = ['clang++', '-arch', 'x86_64']
ar = 'ar'
strip = 'strip'
pkg-config = '$BREW/bin/pkg-config'
nasm = '$BREW/bin/nasm'

[properties]
needs_exe_wrapper = false

[built-in options]
c_args = ['-I$DEPS/include']
cpp_args = ['-I$DEPS/include']
c_link_args = ['-L$DEPS/lib', '-Wl,-headerpad_max_install_names']
cpp_link_args = ['-L$DEPS/lib', '-Wl,-headerpad_max_install_names']
pkg_config_path = '$DEPS/lib/pkgconfig'

[host_machine]
system = 'darwin'
subsystem = 'macos'
kernel = 'xnu'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
    echo "$BWORK/x86_64-darwin.ini"
}

meson_build() { # extra meson args...
    meson setup build --cross-file "$(meson_cross)" --prefix="$DEPS" --libdir=lib \
        --buildtype=release -Ddefault_library=shared --wrap-mode=nodownload "$@"
    meson compile -C build
    meson install -C build
}

build_gmp() {
    copy_source gmp gnutls/gmp
    ./configure --host="$HOST" --prefix="$DEPS" --enable-shared --disable-static --disable-cxx
    make -j"$JOBS" && make install
}

build_nettle() {
    unpack nettle "$NETTLE_URL" "$NETTLE_SHA" nettle-3.10.tar.gz
    ./configure --host="$HOST" --prefix="$DEPS" --libdir="$DEPS/lib" --enable-shared --disable-static \
        --disable-documentation --disable-openssl
    make -j"$JOBS" && make install
}

build_gnutls() {
    unpack gnutls "$GNUTLS_URL" "$GNUTLS_SHA" gnutls-3.8.13.tar.xz
    ./configure --host="$HOST" --prefix="$DEPS" --enable-shared --disable-static \
        --with-included-libtasn1 --with-included-unistring --without-p11-kit --without-idn \
        --without-zlib --without-brotli --without-zstd --without-tpm --without-tpm2 --without-leancrypto \
        --disable-doc --disable-manpages --disable-tests --disable-tools --disable-cxx \
        --disable-openssl-compatibility --disable-nls --disable-guile
    make -j"$JOBS" && make install
}

build_freetype() {
    unpack freetype "$FREETYPE_URL" "$FREETYPE_SHA" freetype-2.13.3.tar.xz
    ./configure --host="$HOST" --prefix="$DEPS" --enable-shared --disable-static \
        --without-png --without-harfbuzz --without-brotli --without-bzip2 --with-zlib
    make -j"$JOBS" && make install
}

build_sdl2() {
    unpack sdl2 "$SDL2_URL" "$SDL2_SHA" SDL2-2.32.10.tar.gz
    cmake_build -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF
}

build_inotify() {
    unpack inotify "$INOTIFY_URL" "$INOTIFY_SHA" libinotify-20240724.tar.gz
    # fdclosedir is in the SDK but only exists from macOS 26.4 on.
    ./configure --host="$HOST" --prefix="$DEPS" --enable-shared --disable-static ac_cv_func_fdclosedir=no
    make -j"$JOBS" && make install
}

build_vulkan() {
    unpack vulkan-headers "$VKHEADERS_URL" "$VKHEADERS_SHA" Vulkan-Headers-1.4.363.0.tar.gz
    cmake_build
    unpack vulkan-loader "$VKLOADER_URL" "$VKLOADER_SHA" Vulkan-Loader-1.4.363.0.tar.gz
    cmake_build -DVULKAN_HEADERS_INSTALL_DIR="$DEPS" -DBUILD_TESTS=OFF -DUPDATE_DEPS=OFF \
        -DAPPLE_USE_SYSTEM_ICD_LOCATIONS=OFF
}

build_moltenvk() {
    # xcodebuild runs $CC as a single program; let Xcode pick its own compilers.
    unset CC CXX OBJC CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
    if [ "$(git -C "$BWORK/moltenvk" describe --tags 2>/dev/null)" != "$MOLTENVK_TAG" ]; then
        rm -rf "$BWORK/moltenvk"
        git clone -q --depth 1 --branch "$MOLTENVK_TAG" https://github.com/KhronosGroup/MoltenVK.git "$BWORK/moltenvk"
    fi
    cd "$BWORK/moltenvk"
    # Xcode 27 rejects the projects' 11.0 deployment target.
    find . -name '*.pbxproj' -o -name '*.xcconfig' | xargs sed -i '' \
        "s/MACOSX_DEPLOYMENT_TARGET = 1[01]\.[0-9]*;/MACOSX_DEPLOYMENT_TARGET = $MACOSX_DEPLOYMENT_TARGET;/"
    local i
    for i in 1 2 3; do ./fetchDependencies --macos && break; [ "$i" = 3 ] && return 1; done
    make macos
    mkdir -p "$DEPS/lib"
    cp Package/Latest/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib "$DEPS/lib/"
}

build_ffmpeg() {
    unpack ffmpeg "$FFMPEG_URL" "$FFMPEG_SHA" ffmpeg-7.1.5.tar.xz
    # LGPL build: decoders, demuxers and parsers only, which is what winedmo uses.
    ./configure --prefix="$DEPS" --enable-cross-compile --arch=x86_64 --target-os=darwin \
        --cc="clang -arch x86_64" --cxx="clang++ -arch x86_64" --x86asmexe="$BREW/bin/nasm" \
        --enable-shared --disable-static --disable-programs --disable-doc --disable-network \
        --disable-encoders --disable-muxers --disable-devices --disable-filters --disable-avdevice \
        --disable-postproc --disable-autodetect --enable-videotoolbox --enable-audiotoolbox \
        --install-name-dir="$DEPS/lib" --extra-ldflags="-Wl,-headerpad_max_install_names"
    make -j"$JOBS" && make install
}

build_glib() {
    copy_source glib glib
    # gdbus-codegen in 2.78 imports distutils, which Python 3.12 removed; its "since"
    # versions are plain numbers, so a tuple of ints sorts them the same way.
    sed -i '' -e '/^import distutils.version$/d' \
        -e 's/distutils\.version\.LooseVersion(v)/tuple(int(x) for x in v.split("."))/' \
        gio/gdbus-2.0/codegen/utils.py
    # proxy-libintl, pcre2, libffi and gvdb come from the subproject wraps; fetch them up front.
    rm -rf subprojects/gvdb  # empty submodule directory in the CrossOver tree
    meson subprojects download proxy-libintl pcre2 libffi gvdb
    meson_build -Dtests=false -Dinstalled_tests=false -Dnls=disabled -Dlibmount=disabled \
        -Dselinux=disabled -Dxattr=false -Dman=false -Dgtk_doc=false -Ddtrace=false \
        -Dsystemtap=false -Dsysprof=disabled -Dglib_debug=disabled -Dlibelf=disabled \
        --force-fallback-for=pcre2,libffi
}

build_gstreamer() {
    fetch "$GSTLIBAV_URL" "$GSTLIBAV_SHA" gst-libav-1.24.13.tar.xz
    copy_source gstreamer gstreamer
    rm -rf subprojects/gst-libav && mkdir subprojects/gst-libav
    tar -xf "$DL/gst-libav-1.24.13.tar.xz" -C subprojects/gst-libav --strip-components 1
    # A release wants the same core release; any 1.24 core is ABI compatible.
    sed -i '' "s/^  gst_req = '>= ' + gst_version$/  gst_req = '>= 1.24.0'/" subprojects/gst-libav/meson.build
    # Only what winegstreamer builds pipelines from: decodebin and its demuxers/parsers,
    # gst-libav decoders, audioconvert/audioresample/videoconvert, videoflip and deinterlace.
    meson_build -Dbuild-tools-source=system -Dauto_features=disabled -Dgpl=disabled -Dlibav=enabled -Dbase=enabled -Dgood=enabled \
        -Dbad=enabled -Dugly=enabled -Dtools=disabled -Ddevtools=disabled -Dges=disabled \
        -Drtsp_server=disabled -Dpython=disabled -Dgst-examples=disabled -Dtls=disabled \
        -Dqt5=disabled -Dqt6=disabled -Dlibnice=disabled -Dsharp=disabled -Dvaapi=disabled \
        -Dwebrtc=disabled -Dorc=disabled -Dintrospection=disabled -Ddoc=disabled -Dtests=disabled \
        -Dexamples=disabled -Dnls=disabled \
        -Dgstreamer:tools=disabled -Dgstreamer:check=disabled -Dgstreamer:ptp-helper=disabled \
        -Dgst-plugins-base:app=enabled -Dgst-plugins-base:audioconvert=enabled \
        -Dgst-plugins-base:audioresample=enabled -Dgst-plugins-base:playback=enabled \
        -Dgst-plugins-base:typefind=enabled -Dgst-plugins-base:videoconvertscale=enabled \
        -Dgst-plugins-base:videorate=enabled -Dgst-plugins-base:audiorate=enabled \
        -Dgst-plugins-base:volume=enabled -Dgst-plugins-base:rawparse=enabled \
        -Dgst-plugins-base:subparse=enabled -Dgst-plugins-base:ogg=disabled \
        -Dgst-plugins-good:isomp4=enabled -Dgst-plugins-good:matroska=enabled \
        -Dgst-plugins-good:avi=enabled -Dgst-plugins-good:wavparse=enabled \
        -Dgst-plugins-good:audioparsers=enabled -Dgst-plugins-good:id3demux=enabled \
        -Dgst-plugins-good:apetag=enabled -Dgst-plugins-good:deinterlace=enabled \
        -Dgst-plugins-good:videofilter=enabled -Dgst-plugins-good:autodetect=enabled \
        -Dgst-plugins-good:flv=enabled \
        -Dgst-plugins-bad:videoparsers=enabled -Dgst-plugins-bad:mpegtsdemux=enabled \
        -Dgst-plugins-bad:mpegdemux=enabled -Dgst-plugins-bad:ivfparse=enabled \
        -Dgst-plugins-ugly:asfdemux=enabled -Dgst-plugins-ugly:realmedia=disabled
}

ALL="gmp nettle gnutls freetype sdl2 inotify vulkan moltenvk ffmpeg glib gstreamer"
if [ $# -gt 0 ]; then
    for name in "$@"; do rm -f "$STAMPS/$name"; done
    set -- "$@"
else
    set -- $ALL
fi
failed=
for name in "$@"; do
    [ -f "$STAMPS/$name" ] && continue
    log "$name"
    if ( "build_$name" ) > "$LOGS/deps-$name.log" 2>&1; then
        touch "$STAMPS/$name"
    else
        echo "$name failed, see $LOGS/deps-$name.log" >&2; tail -20 "$LOGS/deps-$name.log" >&2
        failed="$failed $name"
    fi
done
[ -z "$failed" ] || { echo "failed:$failed" >&2; exit 1; }
