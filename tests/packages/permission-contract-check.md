# Consistent SDK-1 package permission admission

The previous service accepted repeated grants in a publisher manifest and signed
repository. The actual pack/publish/refresh/install reproduction activates both
a two-entry repeated list and a six-entry list containing a repeat. The first
appears in Software but fails application-context admission at launch; the second
also fails Software decoding. The retained reproduction plans the launch without
executing its synthetic payload.

The MIT application SDK now supplies one borrowed, allocation-free
`valid_permissions` predicate for its five grants: audio, display, files, network
and process. Sets may be empty or reordered; each grant appears once. SDK context,
package validation and the package presentation validators share this contract.
No permissions, manifest fields, signatures, environment variables or access
grants are added. Canonical valid metadata and environment ordering are unchanged.

Manifest decoding rejects invalid sets before pack creates a workspace or copies
objects. Prepared-root/catalog imports, signed index admission and generation
validation also enforce the contract. Review, current/installed Software columns
and desktop registration refuse repeats rather than hiding invalid metadata.
Readers do not rewrite authenticated or stored package records. Previously
accepted repeated declarations require publisher correction and the existing
damaged-state recovery procedure where retained generations are affected.

SDK assertions cover all 32 subsets in reverse input order on both declared
architectures, canonical context environment output, empty/full sets and repeated,
unknown, combined, NUL-suffixed or oversized lists. Core tests check package
admission and canonical ordering; genuine signatures authenticate invalid newer
indexes before semantic refusal. Failed refresh/enrollment and publication retain
the previous config, catalog, history and state. Retained-state tests reject
repeats in app/runtime closure admission and preserve generations/cache when
rollback/collection encounter an invalid previous generation. Restoring sound
metadata permits retry. CLI assertions require exit 1 without a panic and absent
output for invalid pack, prepared-root and catalog operations.

The SDK memory fixture measures 1000 empty/valid/full/repeated/unknown/oversized
predicate cycles, followed by the existing context decode/load/environment/
refusal/retirement cycles. It does not measure whole-service allocation lifetimes.
The frontend suite exercises Software and launcher behavior; sanitizer runs disable
leak detection. Cross staging checks static ELF machines and notices on both
targets. These checks do not claim guest runtime execution or graphical login.

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -nocache -no-skip-unused -gc none -manualfree \
  -d track_heap -o /tmp/sdk-context-memory tests/packages/sdk-context-memory.v
/tmp/sdk-context-memory
```

Public publisher enrollment, catalog migration and graphical/runtime acceptance
remain separate roadmap gates.

All SDK and protocol runners, eleven affected core runners and the complete signed CLI contracts passed. The maintained frontend driver passed Software, all eight heap modes, both desktop target typechecks and launcher assertions. Six sanitizer runners passed; permission/context heap checks retained **zero tracked bytes**. Both maintained static target stages passed their architecture and SDK notice checks.

- [Host, CLI, frontend and target-build results](results/2026-10-14/permission-contract-host.txt).
- [Before/after and initial attempt](results/2026-10-14/permission-contract-baseline.txt), [sanitizers](results/2026-10-14/permission-contract-asan.txt).
- [Source/compiler/artifact ledger](results/2026-10-14/permission-contract-toolchain.json).
