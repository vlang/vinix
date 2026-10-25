# Bitmap PNG encoding

Base source revision: `1b46d5690be5c81bd8b105e4fdb597799f07f422`.
The preceding Maps291 replay reached search, directions and route-preview
instructions, but logged six worker-thread failures for the absent native
`Bitmap.native_save_to_png(J)[B` implementation.

`bitmap_png.v` supplies that binding with a bounded PNG encoder. It writes
top-down straight RGBA pixels, preserving RGB values even for transparent
pixels, and expands padded ALPHA_8 rows to black RGB with the stored alpha.
The encoder borrows the bitmap without changing its ownership. It writes
stored DEFLATE blocks with PNG CRCs and a zlib Adler checksum; this trades
compression ratio for a small implementation without additional codec inputs.
Only one native output buffer is allocated and freed after the JNI copy.

`bitmap-png-host.v` compiles the production encoder with allocation and JNI
fault injection. Its independent checker uses the standard CRC and DEFLATE
implementations, checks Adler-32 separately, and rejects corrupted CRC/Adler
negative controls. Cases cover asymmetric RGBA colors, transparency, padded
multirow RGBA and ALPHA_8 storage, one pixel, Adler reduction, exact and crossed
65,535-byte DEFLATE boundaries, invalid dimensions/stride/storage, native
allocation failure and pending exceptions at JNI entry, allocation and copy.
The checks also require unchanged source pixels/reference counts and no live
native output allocation after each call.

Normal and AddressSanitizer runs passed all cases. Their final bundles are
`/Users/alex/.local/state/vinix/maps293-png-host4` and the same path suffixed
`-asan`, with manifest SHA256 values
`bc2917d87506b2b00991b83e289b9f84cbfee90e4035a9ca01e8fbd4d37fb94b`
and `896cb62ef66f04c1654ebe0498530494f13f04548d549de839d6acea3db3ed09`.
Independent readback passed all 67 files in each bundle; an incorrect manifest pin
was rejected. They retain the source, harness, runner/compiler executables,
generated C, direct checker-library sources, argv and logs. They do not claim
a complete historical host C/SDK/V toolchain closure. Earlier passing source
variants remain sealed in the sibling `maps293-png-host{,-asan,2,2-asan,3,3-asan}` bundles.
The runner defaults to external state and rejects existing directories, regular
files and dangling symlinks before writing. These rejection checks preserved
their sentinels and the prior host3 manifest. The receipt is
`/Users/alex/.local/state/vinix/maps293-png-host4-freshness/receipt.txt`, SHA256
`bb224a5ff3b5b524ea08f09884e1c95a1f449411b407e3d969840bc4343ed1bc`.

The first native cross-build failed because fixed-array iteration/indexing
emitted `v_fixed_index`, absent from the freestanding runtime. Fixed signature
writes and a pointer to the local CRC table avoid that helper. The revised
builder rejects any remaining reference before cross-compilation. The failed
build remains complete at
`/Users/alex/.local/state/vinix/android/bitmap-png293-failed-build-2026-10-25`,
manifest SHA256
`5d4e2bcba3406b25ce34a18ca38333bf441aa42f033055516afdf47f7cbed82d`.
Independent readback verified all 2,407 files and the exact fileset.

The final Native293 cross-build passed strict C compilation, with no
`v_fixed_index` references. Native286's timed runtime is byte-identical; the
source delta adds `bitmap_png.v` and appends one generated JNI wrapper. Actual
ELF JNI exports increase from 597 to 598, adding only
`Java_android_graphics_Bitmap_native_1save_1to_1png__J`. Framework290 is unchanged.
The final encoder source SHA256 is
`3d2c4da52847c75fdda3e2eb80220811c33eabbe65d93e8ac7b73a60bdc992b1`;
the native library SHA256 is
`8a19a48ad2fe03d643ebe446507db68ecbbbc406e704e5fd4ef3a5dfe5c12e2d`.
The complete build bundle is
`/Users/alex/.local/state/vinix/android/bitmap-png293-build-2026-10-25`,
manifest SHA256
`a24be4fa0f2d97e8d4f2e1d90099c45245f9657be5f83e3c1124ead5c217aa63`.
Independent readback passed all 2,406 files and the exact fileset.

Fixture294 ran the same signed APK for 45 seconds against Native286 and
Native293, with the same Framework290, clean launcher283, initial media and
other runtime inputs. Native286 reproduced the exact missing PNG native method.
Native293 passed independent Java CRC/DEFLATE decoding and pixel comparisons,
including transparent RGB, quality 0/100, one pixel and padded ALPHA_8 rows.
Null arguments, stream failure, invalid dimensions and recycling contracts
passed. Both guests confirmed absent trace variables; frozen shared inputs
matched before and after each run. The native library was the only variant
input difference. The raw startup classifier remains `window_observed`, with
the semantic fixture verdict recorded separately.
The signed APK SHA256 is
`4d27d13762204fd42c9bffc0903018eed42521569d4aef25e8b9348000e83e49`.
The complete fixture bundle is
`/Users/alex/.local/state/vinix/android/bitmap-png294-fixture-2026-10-25`,
manifest SHA256
`20d4f1b978b6fe08e95272e1b2684d676a75532ba013aff0b9151474db6e8c8d`.
Independent readback passed all 592 files and the exact fileset.

Maps295 reuses Framework290, the clean launcher, initial media, classifier and
600-second workload from Maps291. Exact comparison of all 109 runtime files
finds 108 unchanged and only the native library replaced; the typed inventory
also matches after substituting that library's pin. Its frozen runner source
SHA256 is `a7851a5d9b71bc1fbf687f2eab4e4de67cd444dc5ae62cdef3db03a88ee5b168`.
Launch pins SHA256 is
`b1a261b6c97a2237e9fda0e23cf2307f59bf41820992dcb2c5684575b5c91a88`;
the prelaunch manifest is
`da3bc668f77b42d0ad9255ebbc68685cc6f77fc0e6bc9b39b5d782a56d43ac53`.
The evidence root is
`/Users/alex/.local/state/vinix/android/maps295-2026-10-25`;
screenshots and timestamped `interaction.log` are under
`results/attempt295/google-maps/` in that bundle.

Manual screenshot inspection establishes these states (UTC, 2026-10-25):

| Capture | Time | Observed state |
| --- | --- | --- |
| `after-skip.png` | 05:00:06 | Onboarding gone; North America tiles visible |
| `paris-suggestions-ready.png` | 05:00:37 | Paris, France and other live search suggestions |
| `paris-place.png` | 05:00:49 | Paris place card, map, photo and Directions button |
| `directions-start.png` | 05:01:01 | Starting-point search |
| `eiffel-suggestions.png` | 05:01:20 | Eiffel Tower, Avenue Gustave Eiffel, Paris suggestion |
| `route-ready.png` | 05:01:52 | Eiffel Tower → Paris, 15 min estimate, blue route line and Preview button |
| `preview-first.png` | 05:02:12 | “Head toward Pont d'Iéna” and route line |
| `preview-next.png` | 05:02:29 | Next changes instruction to “Turn left onto Pont de l'Alma”, 750 m |
| `preview-previous.png` | 05:02:46 | Previous returns to “Head toward Pont d'Iéna” with route line |
| `preview-final.png` | 05:07:10 | Preview remains visible with the same instruction and route line |

These capture times describe observed states, not exact interaction latency.
The first Paris typing command immediately followed the search click; the next
capture showed an empty field. Retyping after inspecting the field succeeded.

The complete 600-second run exited successfully, with no process exit or
classified failure markers. The unchanged raw classifier reports
`window_observed` and `functional_passed: null`; the UI results above are manual
screenshot observations. Missing PNG implementation errors, native-link errors,
fatal exceptions and out-of-memory markers are all absent from the final log.
The final serial SHA256 is
`fc1a4c8bdabfa0c20fc79122d78f24fc7c72a0c53ed5e37246f9fcccb4357159`;
raw `results/attempt295/results.json` SHA256 is
`06ac2becf3f8eb1ea86cc85879a244d720915acf237a54f6dc3c92974a553851`.
The completed bundle manifest SHA256 is
`9afdab2a70620fdd98432390f37235663aec4695c62136bd9381d924b2ba08a9`.
Independent completed-bundle readback passed all 7,120 typed entries and their
contents; an incorrect manifest pin was rejected.
Unsupported `Path.op` warnings remain: 65,949 adjacent `Path` / `STUB: op`
pairs. The observed route drawing does not qualify every graphics operation
or continuous navigation.
`maps295-result-audit.v` authenticates the final serial/results against the
completed manifest and records its exact literal-count definitions. Its
passing build/run receipts, source, executable and counts are retained at
`/Users/alex/.local/state/vinix/android/maps295-result-audit2-2026-10-25`,
manifest SHA256
`b8a41d691ae195cdf059d4b214070e4f072c4a7de6e8b145f080b6f90458a892`.
The initial checker remains intact in the sibling `maps295-result-audit-2026-10-25`,
manifest SHA256
`e003fd47fe89fc8e5ff84306263c60178bf74eaef88c0e40d1558daf5351e04a`.

Two preparation attempts exhausted host disk space before launching any guest.
Their complete bundles remain under `/Users/alex/.local/state/vinix/android/`:

| Bundle | Manifest SHA256 |
| --- | --- |
| `maps295-prepare-failed-enospc-2026-10-25` | `71308140c8f064d2d9bd18c3f31ba60269bf096bcb0d0c226fd1647403e28514` |
| `maps295-prepare-failed-enospc2-2026-10-25` | `7b1e52984deb5be6646890e3278f00eaef3a6d07f8fb5d12d158a2f89b3ddb73` |

The existing framework controls `Bitmap.compress` and output-stream exceptions.
This change adds PNG encoding; other compression formats and `Path.op` remain
outside this fix. The existing unsynchronized compress/recycle race is unchanged.
