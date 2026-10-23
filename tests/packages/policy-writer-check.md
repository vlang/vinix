# Public policy document authoring

`tools.packages.pkgprotocol.PolicyDocument.encode()` authors the existing full
format-1 policy file consumed by `vinix-package policy-review`. It always emits
all seven settings and both range endpoints of every pin, including empty
lists, empty range endpoints, false flags and zero reserve. The result has no
trailing newline and belongs to the caller. Inputs remain borrowed and their
values and list order are preserved.

For example, an SDK consumer can own its proposal independently of the encoded
file:

```v
import os
import tools.packages.pkgprotocol

mut proposal := pkgprotocol.PolicyDocument{
    format: 1
    architecture: 'aarch64'.clone()
    policy: pkgprotocol.PolicySettings{
        offline: true
        allowed: ['org.example.editor'.clone()]
        permissions: ['files'.clone(), 'process'.clone()]
        reserve_bytes: 1024 * 1024
    }
}
text := proposal.encode()!
proposal.close()
defer { unsafe { text.free() } }
os.write_file('policy.json', text)!
```

`encode()` checks format 1, valid UTF-8, byte/count limits and the escaped 8 MiB
metadata limit. It accepts at most 4096 allowed IDs, pins and licenses, and five
permission strings. Architecture is at most 16 bytes, IDs 128, version endpoints
29, permission names 16 and licenses 256. These are wire bounds. The service
still decides supported architecture, valid IDs/versions, duplicate rejection,
range validity, known permissions, reserve ceiling and authority to apply a
review. Encoding neither approves nor applies a policy. In particular, it does
not sort or deduplicate a proposal. `PolicyDocument.validate()` and
`decode_policy_document()` validate canonical service presentations instead;
an arbitrary-order authoring file need not pass those stricter checks.

Submit the saved file to the existing read-only review command:

```
vinix-package --json policy-review policy.json
```

Use `decode_policy_review()` to read that canonical response. Apply continues
through the separate existing fingerprint and administrator approval workflow.
The writer grants no trust, publisher consent or package/runtime availability.

## Qualification

The V driver [policy-writer-build.v](policy-writer-build.v) captures the complete
selected source-file inventory and hashes, copies it to a private build root,
and verifies original and copied sources again after the checks. It retains
literal command arguments, build/run logs, generated C, executables and hashes.
All checks use explicit errors or panics and remain enabled under `-prod`.
`-backend c` selects the target-compatible backend, and `-keepc` retains its C.

With the existing local pinned compiler and target sysroots, run from the
repository root (the output directory must not exist):

```
env V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1 \
  V_MACOS_V3_CALLER_VEXE_PRESENT=1 V_MACOS_V3_CALLER_VCHILD_PRESENT=0 \
  V_MACOS_V3_CALLER_VEXE="$PWD/build/package-https-runtime-work/toolchain/v" \
  VEXE="$PWD/build/package-https-runtime-work/toolchain/v" \
  build/package-https-runtime-work/toolchain/v -backend c -keepc -gc none \
  -manualfree -prod -o build/policy-writer-build tests/packages/policy-writer-build.v
build/policy-writer-build "$PWD" "$PWD" "$PWD/build/policy-writer-qualified"
```

The focused suite checks the exact complete schema, escaping, independent output
lifetime, unchanged borrowed inputs, every field/count bound, UTF-8 refusal and
escaped-size refusal. Normal and production tracked builds repeat 1000
encode/decode/refusal/double-close cycles with 256 pins and eight oversized
refusals; these measured scopes retain zero V bytes and records. ASan/UBSan and
the existing strict policy decoder suite also run.

[policy-writer-check.v](policy-writer-check.v) is a public SDK consumer. The
driver runs its normal/production builds against normal/production real package
CLIs. Each combination accepts empty settings and full settings in arbitrary
and canonical order, verifies equal canonical review fingerprints, and refuses
eight semantic proposals: architecture mismatch, duplicate allowed ID, invalid
ID, reversed pin range, duplicate pin, unknown permission, duplicate license
and excessive reserve. After every outcome the entire private package
configuration/state/sentinel tree is byte-for-byte unchanged. Every proposal
file and caller array also remains unchanged.

The same consumer is cross-linked as static ELF64 for aarch64 and x86_64 and
its ELF architecture is checked. These are host API/CLI and target compilation
checks; they do not claim target execution, policy apply, graphical workflows,
publisher enrollment or full SDK acceptance. The receipt pins V, the two
runtime helper headers and cross clang; it does not inventory imported
vlib/thirdparty, complete musl sysroots or transitive host tools. The build is
not qualified as hermetic or reproducible. LeakSanitizer is disabled on this
host; the stated manualfree scopes are measured separately.

The retained result is
[sdk-policy-writer.json](results/2026-10-23/sdk-policy-writer.json).
