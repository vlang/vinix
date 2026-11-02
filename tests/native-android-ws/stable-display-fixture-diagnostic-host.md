# Stable display coordinate failure diagnostics

Host qualification passed on 2026-11-02. The previous ARM run resolved the
native API and failed the first physical-size assertion without recording the
returned coordinates. This diagnostic APK identifies the exact query result and
includes both actual Point coordinates, both expected coordinates and the
configured physical/surface sizes in the assertion message. ARM execution of
this diagnostic APK is pending; the returned values and failure cause remain
unverified.

Both original coordinate equality assertions remain, along with all four native
queries, six reference-identity checks, mutation-isolation checks and existing
surface/metrics assertions. Expected physical dimensions remain `1024x768` and
surface dimensions remain `64x64`. Message construction occurs only on a
coordinate mismatch. The success and failure markers are unchanged:

```text
STABLE-DISPLAY-PASS physical-size window-size fresh-points mutation-isolation
STABLE-DISPLAY-FAIL
```

The build started at revision `d51df1bbb4f9aaa7b63db908831ff36dfb1d0972`.
The builder source SHA-256 remains
`0022d5e4011a7bd92a88ed0fb05a3447a2babd7505f53c9fbb2bf82e0cfa7bf9`;
the diagnostic `sources.v` SHA-256 is
`bfa06021c54e333354fd89c25f4f03b2f2d86ee4c0d3231f958f40b430546369`.
Complete evidence is retained outside Git at:

- `/Users/alex/.local/state/vinix/android/stable-display-fixture-2026-11-02-r2/`
- `/Users/alex/.local/state/vinix/android/stable-display-fixture-controls-2026-11-02-r2/`

| Artifact | SHA-256 |
| --- | --- |
| `probe.apk` | `190b832396158ce1ac584ef41abf279d6f13b82b001d17c35e2bd711d5ebcee1` |
| `build.json` | `b25f57ac33eba0b877ee66d5495e177c0832432b34d9cdafa6b84f43793f3df0` |
| Production and signed-extracted `classes.dex` | `3d06db54116a63889a1ade111d255ea22a2f0d6f367dd4d677206f0cf0807598` |

The unchanged builder passed exact source/tool/class closure, error-free Smali
assembly, two canonical DEX roundtrips, v3 signing verification, package/activity
badging, duplicate/single-DEX archive checks, signed DEX extraction equality and
all input readbacks. Independent source review and the generated canonical
Smali confirm safe register aliases and preserved assertion arguments.
Compilation took 1.610 seconds with a 358,236,160-byte reported peak RSS; signed
production took 5.813 seconds with a 93,536,256-byte reported peak RSS. Both
exited zero, completed process cleanup and recorded zero swaps. Original guards
remain 600 MiB aggregate RSS, 300 seconds, 512 MiB disk growth, 1 GiB reserve,
4 MiB output and `ulimit -f 16777216`.

No host compiler or Java process ran while the guest was live. This change
updates the fixture only; the production SDK, native DSO, kernel and expected
geometry are preserved for a controlled retry. Original fixture evidence is
retained separately; no assertion was relaxed to accommodate the failure.
