#!/bin/bash
# Runs the probes against a staged runtime in a throwaway prefix, with the
# environment Pufflet uses, and always tears that prefix's wineserver down.
#   tests/run.sh [PuffletRuntime.app]   (default: build/install/PuffletRuntime.app)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/install/PuffletRuntime.app}"
W="$APP/Contents/SharedSupport/wine"
R="$APP/Contents/SharedSupport/renderer/dxmt/wine"
[ -d "$R" ] || R="$APP/Contents/Frameworks/renderer/dxmt/wine"   # not yet packaged
OUT="$(mktemp -d)"
export WINEPREFIX="$OUT/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
export WINEDLLPATH="$W/lib/wine/x86_64-windows:$W/lib/wine/i386-windows:$W/lib/wine/x86_64-unix"
export WINEDLLPATH_DXMT="$R" WINEDLLPATH_PREPEND="$R" WINEESYNC=1 WINEMSYNC=1 WINEBOOT_HIDE_DIALOG=1
export DYLD_FALLBACK_LIBRARY_PATH="$W/lib:$APP/Contents/Frameworks:/usr/lib"
export GST_PLUGIN_SYSTEM_PATH_1_0="$APP/Contents/SharedSupport/gstreamer-1.0"

teardown() {
    timeout 20 "$W/bin/wineserver" -k
    timeout 30 "$W/bin/wineserver" -w
}
trap teardown EXIT
trap 'exit 130' INT TERM

cc=x86_64-w64-mingw32-gcc
$cc -O1 -o "$OUT/gs-teb.exe" "$ROOT/tests/gs-teb.c"
$cc -O1 -o "$OUT/probe.exe" "$ROOT/tests/probe.c" -lbcrypt -ld3d11 -ldxgi -lgdi32 -luuid -ldxguid
$cc -O1 -o "$OUT/media.exe" "$ROOT/tests/media.c" -lmfplat -lmfreadwrite -lmfuuid -lole32 -lstrmiids -luuid

timeout 300 "$W/bin/wine" wineboot -i >/dev/null 2>&1
timeout 60 "$W/bin/wineserver" -w

status=0
timeout 120 "$W/bin/wine" "$OUT/gs-teb.exe" 2>/dev/null | tee "$OUT/gs-teb.log"
grep -q "GS-TEB PASS" "$OUT/gs-teb.log" || status=1
timeout 120 "$W/bin/wine" "$OUT/probe.exe" 2>/dev/null | tee "$OUT/probe.log"
grep -q "gnutls rsa keygen: ok" "$OUT/probe.log" && grep -q "d3d11: ok" "$OUT/probe.log" &&
    grep -q "winemetal.dll loaded: yes" "$OUT/probe.log" || status=1
if command -v ffmpeg >/dev/null; then
    ffmpeg -v error -y -f lavfi -i testsrc=duration=1:size=320x240:rate=30 -f lavfi -i sine=duration=1 \
        -c:v libx264 -pix_fmt yuv420p -c:a aac "$OUT/test.mp4"
    timeout 120 "$W/bin/wine" "$OUT/media.exe" "Z:${OUT//\//\\}\\test.mp4" 2>/dev/null | tee "$OUT/media.log"
    grep -q "mf: decoded samples stream0=[1-9]" "$OUT/media.log" &&
        grep -q "dshow (gstreamer): RenderFile ok" "$OUT/media.log" || status=1
else
    echo "ffmpeg not found, skipping the media probe"
fi
echo "$([ $status = 0 ] && echo PASS || echo FAIL) (logs in $OUT)"
exit $status
