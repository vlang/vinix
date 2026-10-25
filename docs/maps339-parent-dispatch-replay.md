# Maps339 parent-dispatch replay

Maps339 passed onboarding, rendered the map, and opened Paris with place photos.
Attractions remained a blank loading sheet. The transition Future failed with a
missing `ViewPropertyAnimator.translationZ(float)` method; this replay does not
establish complete Maps compatibility.

The framework source is `edf5cb5cc27ca67e580110e450ce2a0a3a8103ba`
(`android: Dispatch layout requests through parent overrides`). Replay tooling
is committed at `3642d2135836bc30d963fce1eb429493684d1945`. The qualified
framework JAR SHA256 is
`c9d7d096d763730ed9f3eed1735272ef11a65e88da3d297731f832a434c6c788`.
It is the sole changed entry in the authenticated Maps335 prelaunch runtime;
108 entries, native payload, diagnostic launcher, kernel, base media and the
600-second classifier remain unchanged. This fresh attempt corrects the
Maps337 baseline configuration path without modifying its failed evidence.

All times are UTC on 2026-10-25. The recorded envelope ran 16:32:55–16:44:11;
the suite ran 16:33:19–16:43:34 and started the guest at 16:33:27. Both command
receipts exited 0. The envelope records unchanged input pins, 50 clean
environment entries and no forbidden environment keys. The unchanged classifier
reports `startup_failed`, `backend_ready=true`, `native_maps_observed=true`,
`process_exited=false`, `qemu_alive_before_capture=true`,
`observation_elapsed_seconds=600` and `functional_passed=null`. Its failure
markers are the missing-method exception and its `ExecutionException` wrapper;
successful collection is separate from this functional failure.

Paths below are relative to `/Users/alex/.local/state/vinix/android/`.
Real QMP PNGs, input receipts and logs are retained under
`maps339-2026-10-25/results/attempt339/google-maps/`:

| Time | Observation | PNG | SHA256 |
| --- | --- | --- | --- |
| 16:33:52 | Rendered map after Skip | `map.png` | `07284f65897ce81195a7feac302bb4417929a990773ebc3506087ca3ef91edf0` |
| 16:34:35 | Paris map, place sheet and loaded photos after selecting a search suggestion | `paris-place.png` | `37033165886ecd88251675f57a5f1f54d4a7fed282c120be5d0ffc883afadb3b` |
| 16:35:53 | Blank Attractions sheet, 71 seconds after the category click | `attractions-at-163550.png` | `606aedb2a886e449a8494f53be39d664ce05bc119378818b17eebde84cef43dd` |

`interaction.log` records the Attractions click at 16:34:42 and intermediate
blank-sheet captures at 16:34:52 and 16:35:22. The last filename embeds an earlier
time; the table uses the recorded command timestamp. `serial.log` lines
12494–12518 show `ANDROID-WS-TRANSITION-FUTURE-FAIL`, followed by
`NoSuchMethodError: No virtual method translationZ(F)Landroid/view/ViewPropertyAnimator;`
in the transition Runnable. The missing API is established directly; map and
photo screenshots do not qualify the unfinished category transition.

| Retained artifact | SHA256 |
| --- | --- |
| Generated `maps339-run.v` | `6fae32080f40194b2be164ebe28b312d48232fd488ebab6c24517335ce6c2faa` |
| Recorded runner | `a0ace8274552f184e32df2b7f7f04a6956028d45107b7b590ade9f14c5cb678a` |
| Launch pins | `e0b6cadf599e7adb931eebc810cfd37e221b43c7a1af4321bbd4a87f4e211f46` |
| Prelaunch typed manifest | `bafdeb50543691bc6530ba7ab515102326f96bd35d649eda46b5adbce0c47b86` |
| Preparation envelope manifest | `06e597f1d858af78048b28732edba4f2b18ed2415eedf9a2e23dfe0243ffdb66` |
| Run envelope manifest | `5e2afd6c7a288041a95181a594fc0b8931a2ffada1db506ed492f5650d61069f` |
| Canonical `maps339-2026-10-25/sha256.json` | `e57e61afe3d5d1ff9e75cb84218627b090953b9653b6032eedcfe6bfafb49d5b` |

The complete canonical bundle retains original inputs, source/compiler closures,
generated C, command receipts, runtime logs, PCAP, PNGs and postrun media.
The recorded runner's complete typed readback passed all 43,742 entries;
the external output is `maps339-final-child-readback-2026-10-25.log`.
An independent peer passed the same inventory, retaining
`maps339-completed-peer-readback-2026-10-25.log`.
The unchanged `build/android-maps/build-bundle-check290` passed all nine files
in the run envelope; external receipts are
`maps339-wrapper-child-readback-2026-10-25.json` and
`maps339-launch-peer-readback-2026-10-25.json`. Reproduce canonical readback
from the repository root with:

```sh
build/android-maps/maps339-run-recorded verify e57e61afe3d5d1ff9e75cb84218627b090953b9653b6032eedcfe6bfafb49d5b
```
