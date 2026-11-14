# Poll signal-fixture allocation warmup

The reproduced 320-byte ARM cleanup-guard growth is initial capacity for the
global futex table: two 64-byte dense-array buffers and one 192-byte map metadata
allocation. The thread-using fixture could complete its qualification and warmup
without a contended futex wait, then initialize that table during measurement.
The temporary waiter is released; deleting the last key retains map capacity.
This is a first-use cost, not storage retained by each interrupted poll.

The fixture now performs a private FUTEX_WAIT with a positive one-nanosecond
relative timeout before qualification. It requires ETIMEDOUT and an unchanged
word. A zero timeout would return before creating the kernel futex and would
not warm the table. Both arguments use explicit synchronous stack storage.
The 672 semantic checks, 64 warmup cycles, 200 measured cycles and every strict
slab/large-page/taint guard remain unchanged. Production kernel sources and
previous checkers are unchanged.

## Attribution

An isolated ARM kernel starts allocation tracking immediately before the first
privileged slab read, then dumps every live group before the second read. The
exact previously qualified production probe ELF is reused. This reproduces
size-64 live objects 122/124 and size-192 objects 386/387. Its normal strict
storage checker refuses the growth. All three target allocations resolve to
`futex.get` through the map insertion paths; the trace's six live entries have
zero dropped groups. The other three entries are size-256 background timers,
whose replacements do not increase the corresponding slab count.

The same diagnostic kernel with the warmed probe has only those three timer
entries and no size-64/192 entries in the tracked interval. Both root and
UID1000 cohorts stay flat. This pairs source inspection of `futex.get`/`put`
with allocation-site evidence, rather than attributing growth from sizes alone.
The diagnostic tracker uses try-lock recording, so it is not a census of every
concurrent allocation; the observed target site counts match the reproduced
slab deltas exactly.

An earlier experiment lowered allocsites' fifty-object filter and added two
userspace dumps. That changed the probe ELF and did not reproduce growth: its
before/after groups were identical. It is retained separately from the exact-ELF
kernel-only attribution. The delta checker now verifies group sums against live
headers and rejects missing groups, duplicate headers/rows, dropped groups,
malformed addresses and overflow. Generator/checker controls pass three positive
and fifteen negative cases. Independent lifetime/arithmetic review passes for
the warm helper, diagnostic stack/global buffers and counters, and generated C.

## Qualification and evidence

The production kernels are byte-identical to the interrupted-poll qualification
at `57c608b09ad4df7e1c9f894c2ed93bb18059536c`; no production rebuild is claimed.
Fresh same-ELF Linux 6.12.51 comparisons pass all 672 checks per architecture.
Native and registered warmed fixtures pass on both architectures. Every live
slab class remains flat in both credential cohorts, large pages stay 89/89 on
ARM and 222/222 on x86-64, and taint stays 0/0. Generated fixture C changes only
the warm helper and its child-entry call after canonicalizing path hashes.

Diagnostic kernels are built in an isolated worktree from that revision with
ALLOC_TRACK=1, V 0.5.2 `7d74206`, PROD=true, LIMINE_MP=1 and link seed 42. The
versioned alloc-trace and slab-trace generators retain their separate source
patches. The symbolizer and its libraries are retained with the new bundle.
The first ARM registered attempt lacked the cross sysroot and remains a failed
setup receipt; the corrected explicit-sysroot run passes.

`ppollsignal-warm-evidence.v NEW-BUNDLE HISTORICAL-BUNDLE`, built without
`-prod`, audits both complete inventories, invokes the frozen historical
auditor, checks source/probe/kernel identities, resolves the target call chains,
compares the cold/warm traces and requires the unchanged strict guards to pass
on the warmed runs. `ppollsignal-alloc-check.v` exercises the generators and
full-dump delta parser.

New evidence: `/Users/alex/.cache/vx-sa-1114/bundle`, with a 365-file manifest
SHA-256 `0f784767bf3c36d2e6b1f2363c00dc8d658da6e27f97a6245a08070adff902f7`.
Required historical evidence: `/Users/alex/.cache/vx-ps-1114/bundle`, whose
785-file manifest remains
`f2721913f472189a9e1a84e72d9ecdebde97acaa0e516ce3c1298645b08c101e`.
The original guard refusals, Linux oracle failures and incomplete native runs
remain required by that historical audit.

The older baseline's additional size-64 object is not attributed by this trace.
This closes the reproduced 320-byte first-use pattern; it does not establish a
cause for every historical object delta or close the global memory gate.
Broader §15 semantics, installation/integration and translated-runtime gates
remain open.
