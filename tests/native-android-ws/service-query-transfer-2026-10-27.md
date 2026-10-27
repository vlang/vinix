# Bounded service-query fixture delivery

The new `service-query-transfer.v` serves the exact credential-free ART fixture
runner and two APKs to a live QEMU guest without rebuilding its image. The guest's
retained r5 module inventory contains `/usr/bin/wget`; the root session also
confirmed that executable and `/bin/busybox` in the live guest. A curl executable
is absent. The retained inventory remains required at
`/Users/alex/.local/state/vinix/android/maps-account-r5/original-module-inventory.json`
(SHA256 `d3c2fcc3ede63edc181729940123929c60acb07fdf2d76972f0bd41e3a6f5423`).

The tool accepts only exact GET URLs, binds `127.0.0.1`, caps each fixed input at
32 MiB, copies and hashes in 64 KiB chunks into a fresh private external directory,
and serves those read-only snapshots. Requests cannot resolve filesystem paths.
Headers are bounded at 8 KiB, accepted reads at five seconds, and the service at
12 requests and an absolute 600-second deadline after snapshots finish. It exits
after transferring all three unique inputs. Serving requires the pinned compiler's
`-d net_nonblocking_sockets` option so blocking peers respect socket deadlines.

| Exact URL | Original input | SHA256 |
| --- | --- | --- |
| `/service-query-run` | `service-query-run-arm64-r1` | `8ef76b9e4c9f1eb0cc84780eaa0b618a3a70f317cd4f0e87824ddcdffcae8727` |
| `/client.apk` | `service-query-fixture-2026-10-27-r1/client/probe.apk` | `890de9d4ff410aaf5cd87a52b630ccfa7280fd3c0b2b38eee57159d525b1565d` |
| `/disabled.apk` | `service-query-fixture-2026-10-27-r1/disabled/probe.apk` | `e5075f571f3b8334dded40accb08257ccfdf83e8526a7b61e502d586daa66048` |

All original paths above are under `/Users/alex/.local/state/vinix/android/`.
Their three file hashes were checked independently by the implementer and reviewer.
The complete original fixture producer, runner provenance, and framework bundle
remain required; the transfer audit does not replace them.

Use the retained tool on the host with a fresh output directory:

```sh
/Users/alex/.local/state/vinix/android/service-query-transfer-build-2026-10-27-r1/service-query-transfer serve /Users/alex/.local/state/vinix/android/service-query-transfer-live-2026-10-27-r1 18765
```

After `SERVICE-QUERY-HTTP READY`, use the root-protected guest input directory
prepared by the root session:

```sh
wget -O /var/lib/service-query-input-r1/run http://10.0.2.2:18765/service-query-run
wget -O /var/lib/service-query-input-r1/client.apk http://10.0.2.2:18765/client.apk
wget -O /var/lib/service-query-input-r1/disabled.apk http://10.0.2.2:18765/disabled.apk
chmod 755 /var/lib/service-query-input-r1/run
chmod 644 /var/lib/service-query-input-r1/client.apk /var/lib/service-query-input-r1/disabled.apk
```

The host emits `ready.json` with exact input/snapshot identities and `result.json`
with every request result. These records must be retained with the guest results.
Only the root session starts or stops VMs. This helper's host tests establish no
Google account login or Maps rendering result.

Validation used `/Users/alex/code/v-tccbin-bootstrap-20261026/v`
(`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`),
`-new-compiler -prod -gc boehm -d net_nonblocking_sockets`.
Source SHA256 is `84fdda6ac08afba1651a94e4b6b48c197bc0f654310b28442214c422b73dc5eb`;
executable SHA256 is `6f2e9753accc4564dace24e35d9126c927bf8dba2ea9bb3e14a5a223455e162c`.
The successful build took 15.68 seconds, peak RSS 1,197,867,008 bytes; self-test
took 0.32 seconds, peak RSS 5,521,408 bytes. Both used zero swaps. The initial
compiler rejection of deprecated `usize`/`isize` names is retained separately.

Self-tests passed exact binary transfer over several buffers; incorrect hashes;
symlink, empty and existing-output rejection; method, protocol, declared body,
traversal and query rejection; request exhaustion; and an idle accept deadline.
Independent source review passed the fixed allowlist, input identities, buffer
bounds, deadlines and fd cleanup. Accepted-client stalls and actual trailing-body
socket cases are not separately exercised by these tests.

The complete host build and self-test outputs are under
`service-query-transfer-build-2026-10-27-r1` and
`service-query-transfer-selftest-2026-10-27-r1` in external Android state. Both are
sealed in `service-query-transfer-audit-2026-10-27-r1` with two roots and 15 entries,
manifest SHA256 `be8eb3e9113a9b4976595f52d943952224a3fb6ce81189cf770d6e206a19bfd8`.
Creation, internal verification and a separate unchanged-sealer check passed.
Exact commands, copied source, tool, compile rejection/success logs and review
record are retained. This report was prepared on shared parent revision
`ea671986f3afcf65499674b49958b0a88270bd79`; the source hash identifies the tested bytes.
