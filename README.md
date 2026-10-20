# pufflet-runtime

The Wine runtime used by [Pufflet](https://github.com/talhabalaj/pufflet): an
x86_64 Wine 11.0 for macOS (run under Rosetta 2) with DXMT, built from
CodeWeavers' CrossOver sources plus a few patches of our own.

## Branches

- `crossover`: each CrossOver source release, imported verbatim as one commit
  (`sources/`, see `CROSSOVER` for the tarball URL and checksum). Only the
  trees we build are imported: `wine`, `freetype`, `gnutls`, `moltenvk`,
  `gstreamer` and `glib`.
- `main`: `crossover` plus our patches, one commit each, and the build scripts.

To move to a new CrossOver release, import it on `crossover`, then rebase
`main` onto it:

```sh
git switch crossover
rm -rf sources && tar -xzf crossover-sources-X.Y.Z.tar.gz ... # same dirs as before
git add -f sources CROSSOVER && git commit -m "Import crossover-sources-X.Y.Z"
git switch main && git rebase crossover
```

## Patches

| Commit | Why |
|---|---|
| ntdll: Search WINEDLLPATH_PREPEND before the builtin dll directory | Pufflet puts the renderer (DXMT or D3DMetal) first this way; CrossOver does it through its closed compatibility database. |
| ntdll: Emulate int $0x2e system calls on x86-64 | Protectors that copy Windows' syscall stubs execute `int 0x2e`, which Wine treated as an access violation (Car Parking Multiplayer 2). |
| ntdll: Implement get_thread_times() on macOS | Thread times were a FIXME on macOS. |
| ntdll: Point GSBASE at the TEB while running PE code on macOS | CrossOver reverts upstream's GSBASE switching, so `%gs`-relative TEB reads such as Mono's `%gs:0x68` (LastErrorValue) returned pthread data (Unity games). `tests/gs-teb.c` checks it. |
| ntdll: Skip WINEDLLPATH directories that don't exist | A missing directory left a gap in `WINEDLLDIRn`, which hid every later one from the PE loader; a fresh prefix then failed to load kernel32. |
| ntdll: Keep CrossOver's GSBASE scheme in D3DMetal processes | Apple's D3DMetal calls from PE code straight into native code that expects `%gs` to stay at pthread data, so when `WINEDLLPATH_D3DMETAL` is set the GSBASE switching is off (Unity games under D3DMetal keep the old limitation). |

## Building

Needs an Apple silicon Mac with Xcode, and from Homebrew:
`bison flex llvm lld mingw-w64 meson ninja nasm cmake pkg-config autoconf automake libtool freetype`,
plus Xcode's Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`) for
MoltenVK and DXMT.

```sh
scripts/build-wine.sh tools   # native arm64 winebuild/widl/wrc
scripts/build-deps.sh         # x86_64 libraries into build/deps
scripts/build-wine.sh         # Wine into build/install/wine
scripts/build-dxmt.sh         # LLVM 15 + DXMT into build/install/dxmt
scripts/stage.sh              # build/install/PuffletRuntime.app
```

`tests/run.sh` then checks the staged app in a throwaway prefix with Pufflet's
environment: the `%gs` TEB test, gnutls (bcrypt RSA), freetype, a D3D11 device
through DXMT, and H.264/AAC decoding through Media Foundation and GStreamer.

`build/install/PuffletRuntime.app` is the `SOURCE_APP` for Pufflet's
`scripts/ci/package-runtime.sh prepare`, which signs and packages it.

Everything is built from source. From the CrossOver import: Wine, GMP, GLib and
GStreamer. CrossOver's nettle, freetype and gnutls trees are git snapshots that
don't build as shipped, so those come from upstream releases instead (nettle
3.10 and freetype 2.13.3, identical to CrossOver's; gnutls 3.8.13, a newer 3.8
that builds against nettle 3.10), as does gst-libav 1.24.13 (1.24.4 predates
FFmpeg 7). The rest are pinned, checksummed releases: SDL2, libinotify-kqueue,
the Vulkan loader, FFmpeg 7.1 (LGPL configuration), MoltenVK 1.4.1, LLVM 15 and
DXMT. Every download's checksum is in the scripts. Wine Mono 10.4.1 and Wine
Gecko 2.47.4 are WineHQ's prebuilt add-ons, the versions this Wine asks for.

## License

Wine and the libraries keep their own licenses (mostly LGPL-2.1-or-later; see
each tree under `sources/` and each downloaded release). Our patches are under
the license of the file they change. The build scripts are under LGPL-2.1-or-later.
