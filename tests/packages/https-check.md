# HTTPS acquisition and range recovery

The pre-change downloader repeatedly resumed the same partial when a server
ignored its Range header. Real curl returned error 33 each time, leaving the
retained prefix unusable until an administrator removed it manually.

Acquisition now makes one fresh HTTPS transfer on curl's
explicit range-support refusal. Other transport failures keep partial data for
later commands. Acquisition reports whether it actually resumed; if a fresh
fallback fails its signed hash, the transaction stops rather than making a third
integrity transfer. Both transfer attempts retain the same URL, TLS/redirect
policy, authenticated size limit and transport time bounds. The captured-output
writer replaces the old prefix only when fresh bytes arrive (or empty success).
Curl's internal retries are disabled: its output pipe cannot rewind delivered
bytes. The service controls the fresh fallback and preserves interrupted bytes
for a later transaction. See [captured output qualification](https-output-check.md).
Progress starts with the retained offset and resets to zero for a fresh fallback.

`https-fixture.v` serves a loopback TLS repository. `https-check.v` invokes the
production fixed `/usr/bin/curl` through public fetch and signed service APIs,
using a newly generated local certificate supplied only to the child process.
It does not replace curl or install a trust anchor. A planted `insecure` curlrc
must be ignored. The controller restores its environment and stops its server.

| Fixture | Required behavior |
| --- | --- |
| Honored Range | Preserve the prefix, acquire the suffix and verify signed bytes. |
| Ignored Range | One ranged request, one fresh request, reset progress, successful activation. |
| Damaged resumed prefix | One completed range and one fresh integrity retry. |
| Corrupt fresh fallback | Exactly two object requests; checksum refusal, no third attempt or activation. |
| Interrupted response | Retain the enlarged prefix; the next transaction resumes at its new offset. |
| HTTP 403 or insecure redirect | Preserve the prefix and active generation; local rollback still works. |
| Untrusted certificate, wrong hostname, offline mode or plain HTTP | Refuse acquisition and preserve the prefix. |
| Declared body exceeds authenticated size | Refuse before writing the response body. |

The signed transaction fixture starts with installed and removed generations,
then checks review binding, verified cache promotion, unchanged state on failure,
staging cleanup and rollback. Certificates, generated inputs, request/event logs,
programs and failed baseline output stay in its private work directory.

Run with a native OpenSSL development library/CLI and the pinned V compiler:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused \
  -o /tmp/distribution-check tests/packages/distribution-check.v
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 \
  /tmp/distribution-check --direct-tests --https-only
```

`--https` adds this transport fixture to the normal distribution suite.
`--https-only` runs it independently of the desktop/UI fixtures. The destination
regression also runs in these modes and refuses aliases, hard links,
FIFOs, directories, NUL paths, oversized resume prefixes and delayed substitutions.
Curl and OpenSSL versions are part of the retained qualification evidence. These are
host HTTPS checks; they do not qualify a guest TLS stack, public repository,
proxy fleet, physical-media interruption or broader application runtimes.

The real TLS fixture, maintained `--https-only` driver, all 29 core runners and signed CLI contracts passed. The complete client/controller also passed clang ASan/UBSan with leak detection disabled. Both target services built as static ELF binaries with machine checks; these are build checks, not guest TLS execution.

- [Transport assertions](results/2026-10-14/https-transport.txt), [request log](results/2026-10-14/https-requests.txt).
- [Host/build/tool results](results/2026-10-14/https-host.txt), [sanitizer run](results/2026-10-14/https-asan.txt).
- [Baseline and initial fixture attempt](results/2026-10-14/https-baseline.txt), [source/compiler/artifact ledger](results/2026-10-14/https-toolchain.json).
