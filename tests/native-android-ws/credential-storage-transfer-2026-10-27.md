The bounded fixture transfer tool adds `serve --credential-storage
FRESH_EXTERNAL_DIR PORT`. This separate profile snapshots one exact ARM runner
and two exact credential-storage fixture APKs before opening its loopback
listener. The original service-query and direct-boot profiles retain their
paths and pins. Its runner endpoint is `/credential-storage-run`; the APK
endpoints remain `/client.apk` and `/disabled.apk`.

Shared transport checks are unchanged: regular canonical non-symlink inputs,
32 MiB per input, 64 KiB streaming, immutable private snapshots, GET-only fixed
allowlist, bounded headers, no bodies or pipelines, socket deadlines, twelve
requests and a ten-minute deadline. Only the selected three snapshots can be
served. This delivers a credential-free ART fixture to QEMU usernet.

Independent read-only `printf_path` review passed the profile isolation and
unchanged transport guards, and independently matched both new APK hashes.
The focused profile assertions require valid pins and distinct paths/pins
against both retained profiles; the shared transport self-tests remain intact.

The exact entry source SHA256 is
`d7a0d37daa40bca12dbb4ebd1fa6f5714b63927d8ced0c056076ef7ff8cc3e07`.
Source parent observed after checks was `51cdb49274841e78e7d22f90ef02cc209fc670dc`;
frozen source and compiler hashes matched before/after. The Boehm host build
passed in 2.91 seconds, maximum RSS 240,254,976 bytes; shared and focused
self-tests passed in 0.41 seconds, maximum RSS 5,357,568 bytes. Both reported
zero swaps. Independent final runner review matched its hash, new fixture/JAR
pins, result marker and `--credential-storage` argument contract.

The executable is
`/Users/alex/.local/state/vinix/android/credential-storage-transfer-build-2026-10-27-r1/service-query-transfer`,
SHA256 `bcd06add569cfd57b3eb7ae9e0c4dcfae22693d90c25ad6f3079a60001761db2`.
The separate `credential-storage-transfer-audit-2026-10-27-r1` audit retains
both build and self-test roots, fifteen entries, manifest SHA256
`0165dd17a96f190cc85c022f7cb6104cbe31d54c78bb3d483575114ee202a7c0`.
Creation's internal check and a separate unchanged checker invocation passed;
adjacent `.log` and `-check.log` retain their output.

The original complete runner and fixture bundles, compiler and standard library
remain required. No VM or Google account sign-in is exercised by this tool's
host validation.
