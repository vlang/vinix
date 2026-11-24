# Add release apps on an existing installation

At `d7423ea9927e9cecd7f8c41f5f5ac90cca43c652`, Software's
**Deployment → Add release apps** reviews the image's signed format-2 lock
alongside the currently selected applications. The locked release
versions govern the release closure. Other required packages keep their exact
installed versions and publisher provenance. An incompatible combination
fails review. Unused dependencies can appear as removals in the proposal.
[SDK instructions](../../tools/packages/SDK.md#declare-release-applications-in-an-image)

Software keeps the additive operation and literal declaration path through
offline and policy-controlled catalog refresh. Confirmation opens the
administrator prompt with the additive fingerprint and command. Cancellation
leaves the transaction unapplied. The host Software fixture checked full and
compact navigation and the separate approval flow. The two focused render
and navigation checks each retained zero tracked bytes over 1,000 cycles
using the retained headless UI module. The UI sources typechecked for both
targets. [Software fixture](software_release_fixture.v)

The production CLI preserved all 21 installed roots in the signed synthetic
fixture with both target configurations while adding the reviewed root and its
pinned dependency update.
The CLI verified the resulting installed state and rejected an additive
fingerprint submitted to the full-set command. The focused deployment
fixture also checked a changed installed generation, an incompatible installed
root, an incomplete lock, invalid lock formats and a repeated no-op apply.
The deployment and approval protocol checks passed on the host and the
deployment fixture passed under ASan/UBSan with leak detection disabled.
[CLI fixture](distribution-cli.v)

The production stager built the package tool and its session helper for
AArch64 and x86-64. The signed service fixtures passed in QEMU in 81.1 and
120.1 seconds respectively, including the previous exact-deployment
fingerprint checks. The guest run exercised the service and took the
ordinary poweroff path. The graphical approval checks used the host
fixture. [Guest driver](review-construction-runtime-check.v)

The broader headless allocation suite stops at the existing native window
broker check. With the retained UI module, both the baseline and the feature
build retain 560,000 bytes in that check. With the live UI checkout, the
release allocation fixture exceeds the tracker limit on both revisions.
The retained module passed both focused release and deployment form checks.

The independent archive checker verified 112 sealed entries, including both
guest run trees, target binaries, host checks and the source patch. Its
SHA-256 is `c7eb26cbb3d184e1517bfe083ba59d33aa739d4822e697becf6fb5873430a14e`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-release-additions-rq05oh/qualification.tar.gz)

## Installed system qualification

Revision `02baa639306d217039e351a7cbd1adbb663fab76` extends the four-boot VJFS
fixture. The production stager exports a separate Counter-only format-2 lock
using the same signed repository as the full release declaration. Across all
four boots the guest verifies both
documents against the staged hashes and checks their disk identity, root
ownership, mode and link count.

After the initial three-app installation, the ordinary administrator removes
Counter and selects **Add release apps** through Software's compact Deployment
view. The review installs Counter and keeps Memo and Hello. The first review
is cancelled at the administrator prompt, preserving the generation, trust and
catalog. The second carries its exact additive fingerprint and literal lock
path to the real administrator service. The audit records exactly the initial
removal and the approved addition. Counter and Memo reopen with their saved
data, and the existing upgrade, rollback, removal, cached reinstall and
cold-reopen checks pass.

AArch64 completed four boots in 321.7 seconds. The first x86-64 run stalled
after guest startup with the release ISO builder. The rerun with the shared
raw-initramfs UEFI fixture completed all four boots in 133.0 seconds. The runs
use retained kernels, locally signed repositories and headless Software
controllers. All eight boots requested shutdown from the guest.
[Installed-system driver](native-catalog-check.v)

On the host, all 43 protocol, SDK and client test files passed. The parallel
package-core sweep passed 162 files. The two FFmpeg fixtures passed on replay
with the retained, SHA-256-verified 8.0.1 source archive. The signed CLI
lifecycle also passed.

The independent archive checker verified 286 sealed entries. The compressed
initial and final disk images also matched the SHA-256 digests in the
qualification receipts when decoded. The archive SHA-256 is
`7b4fe007a8bbb20308d2d68c49c40bf665a247ccfef19c6356539bac4914e2e0`.
[Installed-system archive](/Users/alex/.local/state/vinix/r14-distribution-sweep-NmmWfI/installed.tar.gz)

## Release coverage qualification

Revision `8fd026bd3a780f3d9b78ac6a0b04f43cf69bdd8a` adds the read-only
`deployment-add-audit` command and Software's **Check release coverage**
action. Coverage checks all declared pins and requires each release root to
remain explicitly requested. Other installed apps and explicitly selected
dependencies are allowed. The report can open a fresh additive review.

Both QEMU guests passed the deployment audit suite with retained kernels and
newly built package tools. AArch64 completed in 34.3 seconds and x86-64 in
52.0 seconds. The ordinary UID 1000 check read root-owned metadata. The
signed CLI scenarios exercised extra apps, explicit selections, pin drift
and exit status 3. The core fixture exercised missing records, sequence
floors, missing explicit release selections and an empty lock refusal.
[Guest driver](deployment-audit-runtime-check.v)

The host core suite passed ASan and UBSan with leak detection disabled. The
full headless Software suite passed, including frozen-source reload, separate
additive review, and zero tracked bytes over 1,000 release-form cycles.
The headless Software sources also typechecked for both Linux targets.
[Software driver](distribution-check.v)

The independent archive checker verified 200 sealed entries. The archive
SHA-256 is
`25eea8f694ac3480066e7d62bd96ffd3b118a763272c7a796a01d368ccc8327e`.
[Release coverage archive](/Users/alex/.local/state/vinix/r14-release-coverage-AJC5O4/qualification.tar.gz)
