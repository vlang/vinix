# M1 offline source audit

This audit compares Vinix with the Asahi source pinned by Omarchy's
`pkgbuilds/linux-aurora/PKGBUILD`. It reads local checkouts and runs selected
source contracts; it never connects to a Mac, boots a guest, or touches a GPU.

From the repository root:

```sh
v -cc cc -o /external/audit-m1 tools/agx-re/audit_m1_parity.v
/external/audit-m1 --asahi-linux /path/to/linux-aurora \
  --packages /path/to/omarchy-pkgs --omarchy /path/to/omarchy \
  --m1n1 /path/to/m1n1 --output /external/fresh-audit
```

Alternatively, `make -C tools/agx-re audit-m1-parity` accepts `ASAHI_LINUX`,
`OMARCHY_PACKAGES`, `OMARCHY_REPO` and optional `AUDIT_OUTPUT` directories.
The existing V tool launcher compiles outside the source checkout.

Sparse Linux checkouts must include `drivers/dma-buf/dma-fence.c` as well as
the Asahi and scheduler sources. Fence-completion checks use the packaged
Linux core implementation; the audit checks and retains that source too.

The report distinguishes:

- Exact selected facts: normalized DRM command numbers, the barrier sentinel,
  submission count, VM permission flags and three declared scalar layouts.
- Selected firmware/protocol contracts checked by `g13contract`.
- Areas whose complete behavior has not been verified.

The scalar-layout reader supports only ordinary integer fields. Unknown
expressions, missing declarations, attributes, arrays and nested layouts are
errors. They are never silently interpreted as matching. The package must use
an immutable kernel pin, the reference HEAD must equal it, and the relevant
reference inputs must be clean. Source hashes are checked before/after the
audit and before retention. Snapshots include the inspected source trees;
retaining a file does not imply that every function in it was reviewed.

Exit **1** means parity is not established. `not_equivalent` identifies a
concrete difference; `unverified` means only that the selected facts match.
Exit **2** indicates an audit/provenance error or failed protocol source gate.
`--help` exits zero. This limited source audit has no whole-driver success
state, reports no percentage, and does not certify hardware behavior.

Run reader/retention regression tests with
`v -cc cc test tools/agx-re/m1parity`. They cover malformed or spoofed input,
overflow, implicit enum values, scalar padding, dirty/missing declarations,
partial matching facts, changed retained inputs and refusal to overwrite
evidence. Keep reports and the complete checksum-pinned evidence bundle outside
Git, as described in `docs/test-artifacts.md`.
