# Account JNI exception restoration — 2026-10-29

The account pump and account UI shutdown now explicitly clear pending JNI state
immediately before restoring a saved original Throwable. Reporting or cleanup
may leave another exception pending; calling JNI `Throw` in that state triggers
CheckJNI's fatal check and obscures the original app failure.

Both clears occur only when an original local reference was captured. The same
Throwable is restored and its local reference released once. Existing launch
cleanup, lifecycle order, global references and cancellation ownership remain
unchanged. When no original exists, a late cleanup exception stays pending.
This change does not resolve the underlying Activity/lifecycle exception or
establish successful Google authentication.

Host checks used checkout base `d720fc88a205623b7c44bd957c7767d4231cf036`
with exact modified native source hashes:

| Source | SHA-256 |
| --- | --- |
| `nativews/account_service.v` | `26ea5c897b6796ed7307e4ba46afd5adbf1836824a19f0613ed662df485775a5` |
| `nativews/account_ui.v` | `6dc63a006044a16aa044020c9f05b90ae8480e0e8b439ef63bb3f5ee76cd6bc8` |

The production-extracted pump checker passed with 11 negative mutations. New
modes leave the original exception pending after description or install a
different exception. They verify clear-before-restore ordering, exact original
identity, one local-reference release and reporting before launch cleanup. The
UI transport/input/cancellation/shutdown checker also passed. Its new cases
inject a late cleanup exception, verify original-cause restoration and preserve
that late exception when no original exists. A mutation removing the final
clear is rejected. Independent read-only review approved the reference lifetime,
conditional clears and unchanged cleanup behavior.

Both checks passed serialized with exit/child status zero and complete cleanup
under 600-MiB aggregate RSS, 300-second, 512-MiB observed shared-volume growth
and 1-GiB reserve limits. Pump/UI elapsed times were 2.959/3.781 seconds;
sampled peak RSS 367,411,200/363,905,024 bytes; time-report peak process RSS
363,479,040/348,241,920 bytes; zero swaps. These are host checks, without ART
or guest execution of the modified code.

Complete source/model/command evidence remains outside Git at
`/Users/alex/.local/state/vinix/android/account-exception-restore-check-2026-10-29-r1`.
Its in-place seal and a fresh-process full readback passed for 37 entries:
`/Users/alex/.local/state/vinix/android/account-exception-restore-sealed-2026-10-29-r1/manifest.json`,
SHA-256 `9044cc8b95c82006d1f3c2d1ea26c469f835888f335070b6d4f5d1e9fa4864bf`.
