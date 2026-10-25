# Fresh clean Maps launcher

The maintained `launcher.v` was freshly compiled as a static ARM64 executable.
Its source is exactly the retained trace200 source with ten
`VINIX_ANDROID_TRACE_*` setters removed; child arguments, polling and remaining
environment behavior are unchanged. The historical launcher has no retained
compiler receipt, so this does not claim to reproduce its compilation.

The source input checkout was `b92440a5fab07afb0f66de64a63dd125b0e7fbed`;
`launcher.v` SHA256 is
`4c31af25fc8621a495db1e6e722416b523bed9c0f139078fb78b7da6287ac447`.
The complete fresh build is retained at
`/Users/alex/.local/state/vinix/android/maps283-clean-launcher-2026-10-25`.
Its `sha256.json` pin is
`9e8256b31be97aa97c7bf8b4b353624514ea9cd7d9acfb7f7315d24c26670f10`;
`run-android-calculator` SHA256 is
`406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0`.

The retained builder check passed from both the original and retained paths.
Before/done receipts bind exact compiler arguments and stable input hashes.
The 182-input closure includes consumed V modules, generated C snapshots,
per-invocation C dependencies and linker traces, static libraries, the V
compiler and five crosscompiler programs. The final compilation consumes only
frozen discovery inputs. Files, hidden paths and directories are inventoried;
special files are rejected.

Source self-tests reject changes to child arguments, tracing and polling.
`maps-clean-launcher-negative.v` checks complete APFS clones with coherent
manifest updates. Both negative checks passed: omitting a consumed input and
changing both compile receipt arguments were rejected. Results are retained at
`/Users/alex/.local/state/vinix/android/maps283-clean-launcher-negative-2026-10-25`.

Recheck the fresh build without compiling or starting a VM:

```sh
cd /Users/alex/code/vinix
/Users/alex/.local/state/vinix/android/maps283-clean-launcher-2026-10-25/builder check /Users/alex/.local/state/vinix/android/maps283-clean-launcher-2026-10-25
```

This qualifies the launcher build. Maps283 staging and application behavior
require their separate receipts and observations.
