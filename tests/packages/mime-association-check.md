# Bare MIME association admission

Package manifests and registration snapshots now share the bare MIME-name
validator in `pkgprotocol/mime.v`. The previous printable-string checks accepted
empty components, additional slashes, whitespace and desktop-entry escapes.
Both components now start with an ASCII letter/digit and use the restricted
characters in [RFC 6838 section 4.2](https://www.rfc-editor.org/rfc/rfc6838.html#section-4.2).
The existing 128-byte total limit and literal case are retained. Vendor names,
structured suffixes and `x-scheme-handler/https` remain valid. This validates
association syntax; it does not attest IANA registration.

Isolated source baseline: `9f8609211`, plus the retained qualification patch.
`qualification-06` completed with controller exit zero. Four old-validator
controls compiled successfully and then failed at the expected malformed-name
diagnostic: manifest and registration admission, each normal and `-prod`.
All nine fixed runs passed: validator, registration and manifest/launcher tests,
each normal, `-prod` and ASan/UBSan. New checks use explicit failure branches
that remain active in production builds. Registration and manifest tests decode
JSON before validation and preserve valid literal launcher metadata.

Each tracked validator run executed 20,000 scans of borrowed strings and required
zero retained allocation bytes/records, unchanged input and exact work counts.
This measurement covers the validator, not the whole functional fixture process.
ASan leak detection is disabled; address/undefined-behavior errors remain fatal.

Evidence is retained at
`/Users/alex/Library/Caches/vinix-codex/section14/package-mime-20261026`.
Final-run `qualification-06/SHA256SUMS` SHA256:
`0f621124c251cc232d6c9b8115b9e2ea1801482cd8bbf188139cb6d8bebb21d2`.
The 3,007-file history manifest `HISTORY.sha256` has SHA256
`f8fc7b82bc6c7d4406dd726855cfb6af933c347a920f9d2dc1b70fb58c9f7d11`.
The maintained retainer independently checked it after sealing. The mutable
sibling worktree is excluded; nine final source/document files have independent
copies under `qualified-source`. Successful generated C is checked for the
selected private builtin origin, hashed and removed with the binaries; failed
intermediates remain. Raw argv, logs, Results, cleanup and before/after selected
input maps are retained. Those input maps match.

The private V executable SHA256 is
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`;
LLVM23 clang is
`4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8`.
The runner observes the full private vlib/thirdparty tree and selected source
closure before/after, including explicit compiler-selection environment.
The host SDK and loaded system libraries are not frozen. Each child has a
300-second limit, sampled 80MiB fresh-state cap, actual 2GiB free-space admission
and 1GiB floor. These are observed limits, not filesystem quotas.

Earlier refusals remain in the bundle: an overflowing disk-limit literal,
unnecessarily compiling unused V-library waitpid functions, two origin-checker
spelling mistakes and an incorrect assumption that `-keepc` leaves one C file
rather than two identical copies. `attempt-observations.md` identifies actual
collected exit status and the unavailable first outer status. Earlier bootstrap
executables were overwritten; their logs do not prove historical reproducibility.
The final checker accepts at most two identical C copies, still requiring one
translation unit and the selected private builtin origin.

Reproduce with the pinned compiler/clang, a complete matching private toolchain,
and nativeguard/recoveryguard module paths. Build `mime-association-check.v`
with `-gc none -manualfree`, then pass a fresh external directory. Exact selected
environment and child argv are retained in the bundle. This qualification is
host-only; no guest, Open With UI or broader package runtime gate is completed.
