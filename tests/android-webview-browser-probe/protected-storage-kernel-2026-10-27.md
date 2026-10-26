`patch-kernel.v --protected-storage-maps` installs the existing frozen PIDFD
kernel into a fresh protected-storage Maps diagnostic stage. The separate
profile requires the exact original r5 manifest and boot image, seven original
module hashes (including `maps-account.tar`), appended
`protected-storage-diagnostic.tar`, and the diagnostic receipt's kind, base,
framework, native and retained launch pins. The browser and `--maps-account`
profiles retain their existing contracts. Kernel replacement, complete frozen
build verification, module readback, firmware preservation and once-only guards
continue through the same implementation.

The streaming hash buffer is explicitly freed after each hash. Independent
source review checked its synchronous lifetime and the profile's trust chain.
The expanded self-test rejects changed/missing receipt fields, changed input
pins and altered module/configuration contracts. All existing digest, guard and
browser/Maps FAT tests pass, together with a real FAT fixture containing seven
baseline modules and the protected-storage overlay.

The final host build took 18.72 seconds, maximum RSS 359,809,024 bytes; the full
self-test took 3.35 seconds, maximum RSS 22,806,528 bytes. Both exited zero and
recorded zero swaps. Build command:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod -gc boehm -path '@vlib|build-support|build-support/android' -o /Users/alex/.local/state/vinix/android/protected-storage-kernel-patcher-2026-10-27-r1/patch-kernel tests/android-webview-browser-probe/patch-kernel.v
```

The complete small host audit directory is retained outside Git at
`/Users/alex/.local/state/vinix/android/protected-storage-kernel-patcher-2026-10-27-r1`.
It contains the executable, exact entry source, local module source/header,
compiler identity and command, failed first compile, successful compile and
self-test logs. Its sibling `protected-storage-kernel-patcher-2026-10-27-r1-sha256.txt`
inventories those files; checksum verification passed. Inventory SHA256:
`d8ad7872fdfae98152a0bac577741dbe34581da60b1eea71296672061d111e99`.
The sibling `protected-storage-kernel-patcher-2026-10-27-r1-seal` also binds all
11 typed entries and metadata. Seal and independent check pass; manifest SHA256:
`b8387055e8180d3dcd2d51a672e2115dae8e2f7c6b0d46fd6081ef4c96f530f9`.

| Input/artifact | SHA256 |
| --- | --- |
| Entry source | `ff349e719de56404fd2c2689f00ea3cb386cf61268a1cae9ed0c81c6ea3908d2` |
| Host executable | `492f6ec429330cdf8288381305ea8aa77c819a6c7d6274de9356a3a65d930f6c` |
| V compiler | `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe` |

The source snapshot is the implementation in this change, built from parent
revision `7c1b86aec7e8e35dcba1267fb42b53105d72b86d`. The original compiler,
standard library and macOS SDK remain required; the retained host audit does
not replace their complete dependency bundles.

After cloning a complete, sealed, unlaunched protected-storage diagnostic stage:

```sh
/Users/alex/.local/state/vinix/android/protected-storage-kernel-patcher-2026-10-27-r1/patch-kernel --protected-storage-maps FRESH_CLONE /Users/alex/.local/state/vinix/android/pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2 1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d
```

These results validate the host profile and installation fixtures. No guest was
launched for this change, and they do not establish Google account sign-in.
