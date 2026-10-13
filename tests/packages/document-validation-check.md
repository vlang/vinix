# Explicit organization policy documents

Format-1 policy documents reject unknown or duplicate object keys in the root,
policy and individual version pins. Escaped key spellings are decoded before
comparison: `offline` and `off\u006cine` cannot coexist, while a unique escaped
spelling has the same canonical fingerprint. Sibling pins remain independent.
License strings containing quotes, braces or JSON-looking text remain strings.
Deployment roots and lock records share the same structural key checks.

`policy-review` and `policy-apply` both reject ambiguous documents before saving
configuration. The fixtures verify that configuration, installed generations and
replay history remain unchanged, including an apply with a previously valid
fingerprint. Policy review decoding also requires every installed-row field with
its JSON type, including proprietary/firmware flags and empty diagnostics;
missing disclosure cannot fall back to false or an unrestricted result.

Run the maintained V qualification driver with `--direct-tests --cross --desktop`
and the [dynamic Linux guest controller](linux-runtime-check.md) on both targets.
The isolated `tools/packages/pkgcore/document_keys_test.v` runner can be compiled
with clang and `-cflags '-fsanitize=address,undefined -fno-omit-frame-pointer'`
and `-ldflags '-fsanitize=address,undefined'` to check scanner lifetimes without
invoking signing/key generation. Sanitizer runs use `ASAN_OPTIONS=detect_leaks=0`
and `UBSAN_OPTIONS=halt_on_error=1`; this does not qualify leak freedom for the
JSON library or the complete package service.

The 2026-10-13 [host receipt](results/2026-10-13/documents-toolchain.json) records
the pinned V compiler and source/log hashes, the 16 existing assertion runners
plus the separate scanner runner, CLI, Software UI/heap checks, both target builds
and desktop typechecks. Guest receipts and serial output retain
`PACKAGE DOCUMENTS` and all existing package/runtime markers:

- [AArch64 receipt](results/2026-10-13/documents-aarch64.json) and [serial](results/2026-10-13/documents-aarch64.serial.txt).
- [x86_64 receipt](results/2026-10-13/documents-x86_64.json) and [serial](results/2026-10-13/documents-x86_64.serial.txt).

The isolated scanner passed ASan/UBSan. Sanitized full policy/deployment runners
aborted before policy parsing in compiler-generated Ed25519
`Point.bytes_generic` code during key generation, with a stack-buffer-overflow.
The same policy failure was reproduced from unchanged committed package sources;
the receipt records that baseline revision. The
[retained sanitizer traces](results/2026-10-13/documents-sanitizer.txt) include
the baseline and both changed-source failures. Full signing primitive sanitizer
qualification remains open. Functional host and guest passes
remain separate evidence, and do not establish broader runtime or ordinary-user
graphical-session coverage.
