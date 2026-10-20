#!/bin/bash
# Builds DXMT (Direct3D 10/11 on Metal) against our Wine build tree, the way
# DXMT's release CI does: an x86_64 LLVM 15 for airconv, then the 64-bit and
# 32-bit mingw builds. Run after scripts/build-wine.sh.
#   scripts/build-dxmt.sh llvm     LLVM only (doesn't need Wine)
source "$(dirname "$0")/config.sh"
DXMT_REPO=https://github.com/3Shain/dxmt.git
DXMT_COMMIT=7c8dee1c2d73415301ceb7d1fa810861cef4cd67   # as in wine-11.0-dxmt-2
DXMT_VERSION=v0.80-244-g7c8dee1
LLVM_URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-15.0.7/llvm-project-15.0.7.src.tar.xz
LLVM_SHA=8b5fcb24b4128cf04df1b0b9410ce8b1a729cb3c544e6da885d234280dedeac6
LLVM="$WORK/llvm-15-x86_64"
DSRC="$WORK/dxmt-src"
DOUT="$INSTALL/dxmt"
export PATH="$TOOLS/tools/winebuild:$BREW/bin:/usr/bin:/bin:/usr/sbin:/sbin"

build_llvm() {
    [ -f "$LLVM/lib/cmake/llvm/LLVMConfig.cmake" ] && return
    log "llvm 15 (x86_64, libraries only)"
    fetch "$LLVM_URL" "$LLVM_SHA" llvm-project-15.0.7.src.tar.xz
    rm -rf "$WORK/llvm-src" "$WORK/llvm-build" && mkdir -p "$WORK/llvm-src"
    tar -xf "$DL/llvm-project-15.0.7.src.tar.xz" -C "$WORK/llvm-src" --strip-components 1
    cmake -S "$WORK/llvm-src/llvm" -B "$WORK/llvm-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$LLVM" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
        -DLLVM_HOST_TRIPLE=x86_64-apple-darwin -DLLVM_ENABLE_ASSERTIONS=On -DLLVM_ENABLE_ZSTD=Off \
        -DLLVM_TARGETS_TO_BUILD="" -DLLVM_BUILD_TOOLS=Off -DLLVM_INCLUDE_TESTS=Off \
        -DLLVM_INCLUDE_BENCHMARKS=Off -DLLVM_INCLUDE_EXAMPLES=Off \
        -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off
    cmake --build "$WORK/llvm-build"
    cmake --install "$WORK/llvm-build"
}

fetch_dxmt() {
    if [ "$(git -C "$DSRC" rev-parse HEAD 2>/dev/null)" != "$DXMT_COMMIT" ]; then
        rm -rf "$DSRC" && git init -q "$DSRC"
        git -C "$DSRC" fetch -q --depth 1 "$DXMT_REPO" "$DXMT_COMMIT"
        git -C "$DSRC" checkout -q FETCH_HEAD
    fi
    git -C "$DSRC" submodule update -q --init --depth 1
}

build_dxmt() { # cross-file builddir extra-args...
    local cross="$1" dir="$WORK/dxmt-$2"; shift 2
    rm -rf "$dir"
    (cd "$DSRC" && meson setup --cross-file "$cross" -Dwine_build_path="$WBUILD" "$@" \
        "$dir" --buildtype release --prefix "$DOUT" --strip)
    meson compile -C "$dir"
    meson install -C "$dir"
}

build_llvm
[ "${1:-}" = llvm ] && exit 0
fetch_dxmt
log "dxmt"
rm -rf "$DOUT"
build_dxmt build-win64.txt x86_64 -Denable_nvapi=true -Denable_nvngx=true -Denable_d3d12=true \
    -Dnative_llvm_path="$LLVM"
build_dxmt build-win32.txt i386
echo "$DXMT_VERSION" > "$DOUT/version"
cp "$DSRC/LICENSE" "$DOUT/LICENSE"
