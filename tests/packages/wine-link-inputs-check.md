# Captured Wine linker inputs and replay

Bridge, guest and package C builds select `/opt/homebrew/bin/ld.lld` explicitly
and pass `--reproduce=.../link-inputs.tar` through Clang. The archive preserves
LLD's response/version records, transient compiler objects, startup objects and
complete library archives. This includes the cross-toolchain musl libraries
and startup files selected outside the supplied sysroot. Existing observed C
inputs and selected header-tree admission remain required.

Before extraction, a V reader validates the complete bounded ordinary USTAR
archive: checksums, numeric/data bounds, metadata, zero padding/end region,
relative paths and unique names. It refuses links, extended records, traversal,
case aliases and file/directory conflicts. This profile accepts only ASCII path
components without spaces or response quoting; unsupported spellings refuse.
No general-purpose archive extractor is invoked.

The response validator allows only the selected static ELF link profile, one
relative output name and one `--chroot .`. Library directories and file operands
must stay relative; direct operands must be captured members. Plugin and other
unknown options refuse. The producer extracts into a fresh replay directory,
checks every extracted hash and canonical path, and invokes the pinned linker
there with `@response.txt`. Replay must produce exactly the original executable
bytes. Linker bytes are checked before/after; its version record must match the
archive version, allowing only the known GNU-compatibility suffix in CLI output.

`link-proof.json` binds the archive/member hashes, recorded build namespace,
linker and executable hashes. Producer/controller final checks, native checks
before/after boot, the independent producer checker and full retainer re-admit
the archive, response, extracted members, replay arguments/version and output.
Native extracted members and replay output join the before-boot generated map;
all producer replay artifacts join its output map. Copied graphs preserve
ordinary records and replay files, and keep the recorded command namespace.
The linker helper source is embedded and pinned by producers and the retainer.

Run the production/manual-free module controls with V's repository module path:

```text
v -prod -gc none -manualfree -path '@vlib|REPOSITORY|@vmodules' test tests/packages/winelink
```

They cover archive corruption, traversal, duplicates, case aliases, parent-file
collisions, links, missing/trailing end data and response option/output escapes.
Optional `VINIX_LINK_PROBE_ARGV` and `VINIX_LINK_PROBE_OUTPUT` select an existing
two-unit Clang argv receipt and fresh external output for a real compiler/linker
replay. The probe removes `-H`, pins the linker and changes the output to
`program`; it preserves source inputs. Fresh production builds exercise all
three actual link replays under the full Wine checks.

The full retention control runner requires thirty-four refusals after real and
unchanged copied baselines. Five new resealed cases change an archive binding,
an extracted response, a replay executable or replay argv, or link the archive.
Every case must fail at its named check without retained output. Mutation
writes detach private copies before changing data.

This admits captured linker file bytes and an identical replay for the selected
local static ELF profile. It does not freeze compiler/linker dynamic libraries,
all unreported inputs, search absence or host controller builds, and does not
establish a complete hermetic build. Original source/distribution/notices,
selected compiler/header/sysroot/GCC/kernel inputs and historical complete
bundles/verifiers remain independently required. Default activation, owned
ARM/GUI, redistribution and broader roadmap 14 acceptance remain open.

The x86 checkpoint is `/Users/alex/.cache/vwlinkinputs-20261115-01`, with
isolated source base `b5f0b1fa1`. The production/manual-free archive controls
pass, including the case-alias and parent-file collision refusals. An initial
fixture compile refusal remains recorded. The early real linker probe passes;
fresh PE and owned runtime production and independent producer admission pass
with the final hardened helper. All three actual linker replays pass. The
signed holder-death/collection run `native-01` passes in 134.528 seconds,
including post-run linker proof admission; all 32 owned-receipt controls pass.
`controls-01` accepts the real and unchanged copied graphs and refuses all
thirty-four resealed mutations at their named checks without retained output.
Observed C target snapshots and the full selected resource-header copy remain
separate retained inputs. Original prerequisite bundles remain required.
