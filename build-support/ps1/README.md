# PlayStation emulator build inputs

`scripts/build-ps1-aarch64.sh` cross-compiles the native V frontend and
[PCSX-ReARMed](https://github.com/libretro/pcsx_rearmed) for ARM64 Vinix.
The emulator source is unchanged and pinned to commit
`c8816799b50388e61cfe237fe2cdbb7d8175f20a`; the downloaded source archive is
verified with SHA-256 before extraction. The linked core uses the NEON software
GPU, CHD support, and the MIPS interpreter. Asynchronous core workers and physical CD access are
disabled. `--core-only` builds and stages inputs without the frontend.

The default game is [Tetrade 1.0](https://github.com/Logan-Campbell/Tetrade/releases/tag/v1.0),
a complete homebrew game by Logan Campbell, with marathon and versus modes.
The author's original PS-X executable and BIN/CUE release assets are downloaded
and verified by SHA-256. Source commit:
`5155664152162a0dc04dc1f0d4f3c807c1e15388`. Its MIT license is staged beside the
game as `TETRADE-LICENSE`. Its source credits music to Sara Garrard and sound
effects to Kenney Vleugels and FilmCow. The executable includes its game assets;
the disc image includes the same executable and the boot configuration.
Use `--without-homebrew` to omit the downloadable game.

PCSX-ReARMed is GPL-2.0-or-later; its `COPYING` is included under
`/usr/share/licenses/vinix-ps1`, together with `THIRD-PARTY-NOTICES` for the
bundled libretro API, libchdr, miniz, LZMA, dr_flac, Zstandard, and xxHash. Both the complete core source and the build scripts needed
to reproduce the executable are available from the repositories linked here.

The upstream core accepts `bin`, `cue`, `img`, `mdf`, `pbp`, `toc`, `cbn`, `m3u`,
`chd`, `iso`, and `exe` content, as declared in
[its libretro implementation](https://github.com/libretro/pcsx_rearmed/blob/c8816799b50388e61cfe237fe2cdbb7d8175f20a/frontend/libretro.c).
Keep CUE sheets and their referenced track files in the same directory.
The built-in HLE BIOS runs Tetrade without additional firmware. For games that
need firmware, provide a BIOS in the frontend's system directory; the
[PCSX-ReARMed documentation](https://docs.libretro.com/library/pcsx_rearmed/#bios)
lists supported BIOS names and explains HLE's compatibility limits.

Build products are kept in ignored `build/ps1/`; `VINIX_PS1_BUILD_DIR`,
`VINIX_AARCH64_SYSROOT`, `VINIX_AARCH64_LINUX_HEADERS`, and `LLVM_BIN` override their locations.
