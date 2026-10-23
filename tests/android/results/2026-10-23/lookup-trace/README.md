One signed standalone APK passes on framework236 and on framework237 with the
lookup trace disabled and enabled. All three runs reach READY, stay alive and
have raw `window_observed` outcomes with no failure markers. Native235 is
identical in all three staged runtimes.

The fixture checks root-before-descendant identity, direct and nested lookup,
depth-first duplicate ordering, missing IDs, existing NO_ID identity and lookup
after removing and reparenting children. Measured resource calls occur only
while a lookup runs. They are zero by default on framework237 and present on
framework236 and with `VINIX_ANDROID_TRACE_VIEW_LOOKUP=1`. Explicit warning and
error messages emitted by the fixture remain visible in every mode. Removing
only the two trace gates restores the entire generated baseline ViewGroup byte-for-byte.
This verifies skipped diagnostic work; it is not a performance benchmark.

The authoritative framework237 source archive contains the frozen framework236
module plus the lookup generator and its hook. The raw builder manifest scanned
the concurrently edited checkout and includes an Insets source/hook which were
not compiled into framework237. It is retained as a raw artifact, not a source
receipt; the independent frozen source hashes and actual JAR disassembly verify
the tested inputs. Native235 sources and its binary identity are inherited from
the retained interpolation proof. The mutable shared boot image was not hashed
before each boot; configurations retain its path, not a measured kernel identity.

Run from the repository root:

```
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/lookup-trace/validate.v
```

The prepare/build helpers, exact fixture smali and DEX, launchers, source
archives, raw results, serial logs and six staged runtime identities per boot
are retained. The clean standard launcher uses no Maps-specific diagnostic
probes. No Maps usability or timing result is claimed here.

The framework builder was compiled with `v_old -nocache -cc cc` and
`-path '@vlib|build/android-maps/framework237-lookup/sources|tests/native-android-run'`.
Its execution set `VINIX_V_COMPILER=/Users/alex/code/v/v_old`.
