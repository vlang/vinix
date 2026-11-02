# Permission-constrained process-local broadcasts

`Context.sendBroadcast(Intent, String)` now filters delivery using the primary
application's immutable permission snapshot. A null permission delegates to the
existing native one-argument dispatcher. A supported permission gates that same
dispatcher before either registered or manifest receivers run. A denied or
unproven permission delivers to neither. A null Intent still throws before the
permission decision. This implements the
[receiver-permission constraint](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/core/java/android/content/Context.java#L1817)
for the existing process-local transport.

The supported grant subset is deliberately narrow: a permission requested and
declared with signature base type by the same authenticated primary APK.
[Android signature permissions](https://developer.android.com/guide/topics/manifest/permission-element#plevel)
require matching requester and declarer certificates. The constructor checks
verified signing metadata and nonempty signer entries, then copies eligible
declaration names into a fresh unmodifiable set. Permission trees, duplicate
names, other owners, unrequested names, other base types and missing verification
are denied. No permission name is hardcoded. PackageManager's coarse grants,
Context overrides and temporary account-broker caller identity are not grant
authorities for this path.

Each ATLLoadedApp instance owns a private final snapshot. The primary loader
verifies certificates before constructing and publishing its holder; no app
callbacks precede the constructor hook. Only `getPrimaryApplication()` supplies
the delivery authority, so constructing a secondary holder cannot replace it.
Only a boolean query is exposed; public mutable parsed-package metadata is not
reread for delivery. Unverified framework/GStub holders get no supported grants.

The exact source delta is two changed classes and one new fieldless utility.
Context retains all 106 methods and gains one Java overload. ATLLoadedApp keeps
all 22 methods, changes only its constructor to initialize the private final
Set, and gains one public final boolean accessor. The helper has two static
methods. No existing native declaration, JNI binding, one-argument body,
package/action routing or receiver callback bridge changes. Context and
ATLLoadedApp are native-consumed classes, so a fresh coupled native build remains
required even though native method declarations are unchanged.

The existing dispatcher supports only process-local recipients. This change
does not add cross-process grants/delivery, a general permission database,
registration-time sender-permission enforcement or category/data matching.
Those existing limitations remain explicit; the new constraint is never ignored.
The actual GMS call passes its requested, self-declared signature permission;
its broader startup and shared-preference propagation remain runtime checks.

Focused checks passed 14 malformed/repeated/helper-collision refusals and eleven
independent authority/member controls, plus API-28 assembly and two DEX
roundtrips. They preserve every old member, bind the exact constructor hook,
private final field and primary-only gate, and compare helper instruction and
branch-target identity through assembly. Canonical second-roundtrip bytes are
stable. Root and independent native-source reviews approved the provider;
separate checker review covers its refusal and roundtrip oracles.

The first proof reached roundtrip comparison but rejected adjacent conditional
and goto labels that baksmali emitted for one instruction. That failed attempt
is preserved unchanged. The checker now compares branch target instruction
positions and explicitly rejects different targets; the provider did not change.
The fresh `proof-check-r2` passes with receipt
`d22d85bd4e1f67d612a8f2f4a7179be13bb295864276f4e613ae5234ba202f7b`.
It took 6.809 guard seconds, sampled 204,980,224 bytes aggregate RSS and recorded
177,242,112 bytes detailed RSS. Compiler maxima were 262,389,760/278,560,768
bytes sampled/detailed. Admitted guards/children exited zero with complete
cleanup and zero swaps under the original 600 MiB RSS, 300-second, 512 MiB
shared-growth, 1 GiB reserve, 4 MiB output and file cap 16777216 limits.

Complete focused evidence, frozen owned sources, generated C, input pins,
original/patched DEX and both attempts remain outside Git at
`/Users/alex/.local/state/vinix/android/broadcast-permission-source-check-2026-11-02-r1`.
Source parent before this commit is `d720922c8705847b91bb2ae80672cc53e0b58fd0`.
Provider/integration/driver/checker SHA-256 values are respectively
`85e9359270850af0c5725b819ceb023f0d214a04abdc600dc917930edeb2df46`,
`e1cfa8755302edc63c97dfc568cf9e73f82642017391649c5beaf919de5ad45b`,
`482fa5f0c67e37c5b17b0a40dfc515497a313e22a1d021595f27fe596f8cb467`
and `c94f66e42cde60e6be2376c652ec4ebb307448b866c7f9f9b506d871c6de931f`.
Full SDK production, coupled native, signed ARM fixture and live GMS/Maps checks
remain separate. These host checks establish no authentication or imagery result.
