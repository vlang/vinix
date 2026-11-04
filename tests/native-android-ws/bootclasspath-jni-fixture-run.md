# Boot-classpath fixture with corrected JNI loading

Additive selectors `--bootclasspath-jni` and `serve --bootclasspath-jni-api`
deliver the unchanged signed [fixture](bootclasspath-fixture-run.md) with the
[corrected native](framework-jni-load-pair-2026-11-04.md). Historical selectors,
pins and protocol rules remain unchanged. The shared APK exception is limited
to the exact old/new boot fixture routes and pinned APK.

Paths use `S=/Users/alex/.local/state/vinix/android`.

| Tool | Path below S | SHA-256 |
| --- | --- | --- |
| ARM runner | `bootclasspath-jni-api-run-2026-11-04-r1/run` | `1b1103b948baf32b7b71741887cbdb033b7833c9833ce114ad0addbe0b4eb24c` |
| Transfer | `bootclasspath-jni-api-transfer-build-2026-11-04-r1/transfer` | `02fc384b35bd89ebfaa92652aa22900658b6b987f75af22d344636d3e0a89d82` |

All five qualification phases passed first attempt: 5,087 runner rejections,
eight shared-APK collision controls and all original transfer tests. ELF
readback confirms static AArch64 EXEC without INTERP/DYNAMIC segments.
Original 600 MiB RSS, 300-second, 512 MiB growth, 1 GiB reserve and output/file
caps remain unchanged; guards/children exited zero with complete cleanup.
The four runner/run-build/transfer-build/transfer-controls roots named
`bootclasspath-jni-api-*-2026-11-04-r1` passed a 30-entry seal and fresh readback:
`S/bootclasspath-jni-api-tools-sealed-2026-11-04-r1/sealed/manifest.json`,
SHA-256 `33e57e3514bf26971f7cdb62aec6908cf30585f62c3b7f6f414dc8da9e14b0c8`.
Complete originals remain required. ARM behavior remains unverified.

Follow the original guest recipe's unused-account/path checks and verified
read-only,nosuid,nodev,wxallowed mount, using account `bootclasspath-jni-probe`,
UID/GID 10155, mount `/opt/bootclasspath-jni-runtime` and output
`/var/lib/bootclasspath-jni-r1`. Start transfer only when ready to fetch:

```text
transfer serve --bootclasspath-jni-api FRESH_HOST_OUTPUT 55547
```

Fetch `/bootclasspath-jni-api-run` and `/bootclasspath-jni.apk` into
`/opt/input/bootclasspath-jni-run` and `/opt/input/bootclasspath-jni.apk`.
Verify the runner pin above and APK pin
`bd7384342cb18c6d9d519186f921bba9c6acfe5c0f07b75f3db16dfc650a22e4`,
and executable/read permissions before launch:

```text
/opt/input/bootclasspath-jni-run --bootclasspath-jni /opt/bootclasspath-jni-runtime /opt/input/bootclasspath-jni.apk 10155 10155 /var/lib/bootclasspath-jni-r1
```

All six input identities, eleven checks, exact sole PASS/READY, drained EOF and
clean exit remain required. Keep input idle through export END; retain the
complete UART, derive an exact interval and use unchanged zero-removal
reconstruction. Release the mount after validated pass before separate GMS/Maps.
Preserve failures without a protocol or health waiver.
