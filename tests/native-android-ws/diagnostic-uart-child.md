# Diagnostic child-log extraction and ARM fixtures, 2026-10-29

`diagnostic-uart-child.v ARCHIVE_JSON SHA256 FRESH_OUTPUT` extracts only
`child.log` from the existing two-file SERVICE-QUERY diagnostic archive. It
requires an explicitly pinned canonical regular input, bounds the archive to
8 MiB and each entry to 4 MiB, validates both entries' canonical base64, lengths
and SHA-256 values, and rejects duplicate or unexpected paths. It rechecks the
input before creating a private fresh directory. Fixed `child.log` and
`receipt.json` outputs use `O_EXCL | O_NOFOLLOW`, receive complete readbacks,
and are retained read-only. It neither changes the historical reconstructor nor
qualifies a strict UART import.

Bounded host compilation and `--self-test FRESH_DIR` passed. Selftests cover
binary preservation, missing/duplicate child logs, incorrect archive/content
hashes, malformed JSON/base64, size/type/path refusals, existing outputs and
input/output symlinks. Independent source review found no blocker. Compilation
took 2.310 seconds and peaked at 338,542,592 bytes sampled aggregate RSS;
selftest took 0.258 seconds. Both exited zero with complete cleanup and zero
swaps under 600 MiB RSS, 300 seconds, 512 MiB observed growth and a 1 GiB reserve.

Artifacts remain in the open runtime audit directory
`/Users/alex/.local/state/vinix/android/maps-auth-exception-runtime-audit-2026-10-29-r1`
(`A`), including `child-extractor-build/`, its frozen source, guard receipts,
selftests and fresh derived results. The checkout before this change was
`137962143b7681debeb66ef8a5bbfb18dbf32dae`. Source SHA-256 is
`415e68ca7379f603583ffe5e1100a44e8f37a1dd232ef64d20d5038fbeb97045`;
the retained executable is
`aa40719511c638a4bd10398ca1e85e5d217cde4601c6ab5590e9d87d2e47d65f`.
This report does not seal the still-active runtime audit.

Both actual ARM fixture intervals passed the unchanged no-removal planner and
diagnostic reconstructor, then the new extractor. Original UART bytes were
preserved. Each archive contains exactly `child.log` and `receipt.json`:

| Fixture | UART interval SHA-256 | Diagnostic archive SHA-256 |
| --- | --- | --- |
| Authenticator | `0ac17c607c785bd21e7e3c944c7c5ee05c0404d1f404f43da67afc6492fcc3c0` | `1ff7a9e1b233a9ee2f863d4b32ebb64ecad7e86df50c01677d1ed3792b18d68c` |
| Network | `916f30f14cda75e4ae4d4847a6a0daad20a2ed893412686db482d7172be784c2` | `bd666808fc5d8403bfc057afdc0b5f7f772350b948a8af9d2babdd2c10dbb51f` |

Their exported receipts select the correct profiles, UID/GID 10117 and wait
status zero. APK, framework, native library and runner hashes match the pinned
[runner profiles](auth-exception-fixture-run.md); both launcher hashes match
the retained deployment. Each decoded log contains one exact expected terminal
marker and one native readiness marker. Those counts were checked directly in
the decoded logs; they are not numeric fields in the existing runner receipts.
Decoded log hashes match those receipts:

- `A/auth-fixture-child/child.log`:
  `e6bbfe3d9d991b4cb853dce899c6affea129792a3a771623e72481f824f2fd04`.
- `A/network-fixture-child/child.log`:
  `129dbebf9adabd2b346b30df03346733145e3e5d656124581af15af8e6f33600`.

The pinned network verifier passed the complete finite sequence; output is
retained in `A/network-fixture-finite-check.log`. DNS returned two addresses.
IPv4 TCP connected, but TLS returned error 10 (an unclassified throwable).
IPv6 TCP timed out and its TLS probe was skipped. The hostname-based socket
constructor connected using IPv4. All observed system errno values were zero.
These observations do not identify the TLS throwable or establish Google login.

This establishes the synthetic authenticator regression on ARM and completion
of the network observations. Collection remains a diagnostic derivation, with
zero removals; no strict SERVICE-QUERY import is claimed.
