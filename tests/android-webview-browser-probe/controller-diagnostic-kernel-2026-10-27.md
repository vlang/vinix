The kernel patcher now has a separate `--maps-controller` profile for the
three-file controller diagnostic. It requires the exact sealed startup-r1
base and corrected ARM controller, unchanged framework/JNI/launcher receipts,
and the declared deployment delta for both controller inputs and the sole
`inputs_sha256` field change. All eight original modules must match their
pinned digests and order; `maps-controller-diagnostic.tar` is the only appended
module.
Existing profiles and the frozen PIDFD kernel installation path are unchanged.

Focused tests reject missing or changed fields/inputs, obsolete controller
receipts and paths, deployment-delta additions/removals, changed module pins
or order, and receipts from another profile. They and all existing digest,
inventory, browser/Maps/protected FAT and installation tests pass. An added
eight-module FAT fixture checks kernel replacement, all nine module readbacks,
firmware/configuration preservation and once-only installation. That fixture
uses its temporary baseline; the exact external startup-base branch is
reviewed source logic pending actual stage installation.

Independent read-only review by `printf_path` passed the complete source delta
and final producer pins. The host build exited zero in 9.73 seconds with
372,604,928 bytes maximum RSS; the complete self-test exited zero in 4.28 seconds
with 17,039,360 bytes maximum RSS. Both recorded zero swaps. Build command:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod -gc boehm -path '@vlib|build-support|build-support/android' -o /Users/alex/.local/state/vinix/android/maps-controller-kernel-patcher-2026-10-27-r1/patch-kernel tests/android-webview-browser-probe/patch-kernel.v
```

The immutable small tool audit is
`/Users/alex/.local/state/vinix/android/maps-controller-kernel-patcher-2026-10-27-r1`:
exact entry source, both local dependency files, executable, commands,
qualification and full build/self-test logs. Its sibling
`maps-controller-kernel-patcher-2026-10-27-r1-seal` binds all 11 typed entries.
Creation, internal and separate checks pass; manifest SHA256:
`6150b0b6de62ce91e4ea9bbfafcdfe659aa95f931dc6c3082c5adb849d4c42a3`.
The original complete startup/controller bundles, compiler, standard library,
SDK and frozen kernel build remain required. No SDK copies or kernel rebuilds
were made.

| Artifact | SHA256 |
| --- | --- |
| Entry source | `8fe47f2c2b0d5bde73de414491a1a7e214b71ca53396d5dc90009ace16271fe2` |
| Host executable | `715922e210e3d120ac747337a4451875f75629fcf77b943098cd4f9d79467977` |
| V compiler | `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe` |
| Startup base manifest | `f79065bc79d816f8cf35a21c72ef375369229b0ee8170165890808e3d194e332` |
| Startup base boot | `24999d2743f4c86196b39113b68062908a698945864c2ca551dff4f0578677c6` |
| Controller manifest | `1b8e4555a67eae4c3b1c109f3d94064c96eba65dd3fd3c88d72649b5fdbc9106` |
| Controller executable | `894e57f0eaf773777b3107100068edf1f9b57b427b565756767c576a0de8c6b6` |

The startup/controller manifests and controller executable were directly hashed
in their original bundles. The startup boot digest was read from the sealed
inventory; actual patch execution hashes its bytes. The built source snapshot
is this change, from parent revision `d6d72faa07e30faf9e441cd7ed57242d28bd1960`.
Entry, dependencies and compiler hashes matched before/after build and test.

For a complete, sealed, unlaunched controller-stage clone:

```sh
/Users/alex/.local/state/vinix/android/maps-controller-kernel-patcher-2026-10-27-r1/patch-kernel --maps-controller FRESH_CLONE /Users/alex/.local/state/vinix/android/pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2 1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d
```

These results validate the host tool and fixtures. This change performed no
VM action or diagnostic-stage installation. Google account sign-in remains
unverified.
