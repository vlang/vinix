# Maps replay after stateful nine-patch tint

Replay317 uses committed source `1292bc867` and the exact Framework315-v2 and
Native315 artifacts qualified by [regression316](nine-patch-tint316.md).
Maps/Play Services/Play Store APKs, the clean283 launcher, the 5,120 MiB disk
gate and the historical 600-second startup classifier are unchanged.

Skip removes onboarding and displays the base map. Paris search displays
suggestions. Selecting Paris then exits the app with
`NoClassDefFoundError: Failed resolution of: Landroid/text/style/TtsSpan;`.
The first app frame is `agdh.f(CharSequence,String):Spannable`, source line20;
the cause is `ClassNotFoundException: android.text.style.TtsSpan`.
The raw outcome is `startup_failed`, with 55 seconds observed, the native
backend/maps observed and process exit code1. The replay runner's successful
outer exit denotes completed recording, not application success.

The app exits before Trip Options. This run provides no visual qualification
of Maps' switch tracks or checked tint, and does not replace the successful
route/preview results from314. Generic tint behavior remains qualified by316.
The failure screenshot shows the host's "The Android APK has exited" message;
it must not be treated as a working Maps screen.

The complete stopped-guest bundle is
`/Users/alex/.local/state/vinix/android/maps317-2026-10-25`, typed manifest
SHA256 `7d7ad98af1170fed5e1b20b147fef5f1a1b540803966833c7a696f60224593d2`.
Both the replay runner and independent root readback passed all 22,754 entries:

```
build/android-maps/maps317-run-recorded verify 7d7ad98af1170fed5e1b20b147fef5f1a1b540803966833c7a696f60224593d2
```

Serial SHA256:
`8590e15a4f450819105d75ada8b655f432a1513d876b9c1ca344215bd28fd4f2`.
Final application PNG SHA256:
`f22f85e367d843fcc4d7b034c07803a2a9a1995932f88e025cc39490f35bb0a0`.
The retained `map-skip-settled.png` and `paris-suggestions-ready.png` precede
the failure. No later switch capture exists in the sealed bundle.

One screenshot command attempted after shutdown failed because the QMP socket
was gone. Its streams and extended interaction log are preserved separately at
`/Users/alex/.local/state/vinix/android/maps317-post-stop-supplement-2026-10-25`,
manifest SHA256
`456b559fd18811986d04c604efe55c20741a12df0c8eff07b4b9a5bf3f6193cd`.
Independent root readback passed all 16 typed entries, including the exact
sealed interaction prefix. The original replay bundle remains unchanged.
