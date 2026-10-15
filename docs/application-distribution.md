# Application distribution

Vinix has a native V application package service, `vinix-package`, and a
**Software** desktop application. They manage signed repositories and immutable
application generations on AArch64 and x86_64. The desktop security-tools stage
installs the service, sandbox launcher, Software process link and XDG registration
directory. It preserves existing configuration; a fresh image enrolls no keys.

Configuration, cached catalogs, trust histories, installed state and publisher
documents share a bounded metadata reader. It captures a nonblocking descriptor,
refuses leaf symlinks and nonregular files, and reads at most the admitted file
size plus one sentinel byte, within the 8 MiB metadata limit. Size changes fail
before parsing; an atomically replaced pathname can still return its previously
captured file. Restoring trusted ordinary metadata permits retry without deleting
package state. See [qualification](../tests/packages/metadata-read-check.md).

Local payload copies validate ordinary source and destination descriptors before
writing, refuse the same file even through a hard link, and enforce the captured
source size. Oversized offline repository objects leave existing partial data
available for a retry after restoring trusted media. Signed size/hash checks
still gate cache promotion and generation activation. See
[copy qualification](../tests/packages/copy-file-check.md).

Local destinations must also have exactly one hard link. Fresh/resumed offline
transfers and publisher object temporaries refuse shared output before changing
its contents. Captured destination identity, size and link count are rechecked
around progress callbacks and flushing; interrupted flushes retry. Source hard
links remain readable. See [output qualification](../tests/packages/copy-output-check.md).

Retained download partials also require exactly one hard link, including complete
files that need no transport. Cache promotion captures the partial and its object
directory, verifies the signed length/hash on that descriptor, applies permissions
and flushes without reopening its path, then publishes with directory-relative
atomic rename. Replaced paths and shared partials refuse; an error after cache
publication says the object was saved. See
[cache-promotion qualification](../tests/packages/cache-promotion-check.md).

Payload hashing and verification use one captured ordinary-file descriptor,
opened without following leaf aliases or blocking on FIFOs. Verification checks
the authenticated length on that descriptor before hashing. Reads stop at the
captured size plus one sentinel; size or pathname-identity changes refuse before
reporting success. These checks apply to cache, generation, launch and publisher
verification. See [hash qualification](../tests/packages/hash-file-check.md).

Metadata writes use exclusively created private temporary files in a captured
parent directory, avoiding stale `.new` aliases and FIFOs. Configuration, trust
history, cached catalogs and publisher documents share this bounded writer.
It writes and flushes the file before atomic replacement, then flushes the same
parent descriptor. Failures before replacement preserve the old document; errors
after replacement explicitly report that the document was saved. See
[atomic write qualification](../tests/packages/atomic-write-check.md).

Publisher seed admission uses one private regular-file descriptor for both
publishing commands. Ownership, permissions, link count, the 128-byte size bound
and named identity are checked on that capture. Release signing and accidental
seed-payload exclusion use the same bytes. Unsafe inputs refuse without changing
their contents or publishing an index; restoring a valid seed permits retry.
See [signing seed qualification](../tests/packages/signing-seed-check.md).

Publisher key generation captures an owned parent without shared write access,
writes and flushes a private temporary, publishes it exclusively and flushes the
captured directory. Failed writes retain existing files; a failure after
publication explicitly reports that the seed was saved. `key-public` recovers that
seed's public key without replacing it or granting publisher trust. See
[key creation qualification](../tests/packages/keygen-check.md).

File and directory flushes also use captured nonblocking, no-follow descriptors.
They require the correct type, check the named device/inode before and after
`fsync`, and require unchanged file sizes. Interrupted flushes retry; changed
targets and storage failures return diagnostics before a caller reports success.
See [durability qualification](../tests/packages/durability-check.md), including
ext2 interruption/recovery at the staged, published and activated checkpoints.

This application store is separate from the Alpine `pkg`/`apk` system layer.
Existing Alpine ports and special downloads still use that frontend and its
persistence rules. They do **not** acquire these rollback guarantees. Release
migration of that catalog remains part of roadmap acceptance.

An ordinary-user **Software** session asks for the current administrator's own
password before applying its reviewed package, repository, deployment or offline
export change, or refreshing signed catalogs. The fixed `packages-change`
authentication action checks the real caller's account and administrator
membership. A separate root worker runs the frozen command and returns progress
and its completion receipt over that user's private runtime socket. Both sides
check kernel peer credentials. Passwords never enter command arguments, package
requests, progress or logs; the UI masks and clears its credential buffer. The
root desktop continues to execute administrative commands directly. See
[administrator transport](../tools/packages/SDK.md#administrator-package-transport)
and [qualification](../tests/packages/admin-check.md).

Repository enrollment and its subsequent refresh require separate approvals.
Cancelling refresh clearly reports that trust was already saved. Cancelling a
password prompt starts no authorized transaction. Once approved, a transaction
keeps its normal lock/journal lifetime even if its client disconnects; a missing
completion receipt instructs the caller to check installed state before retrying.
Application launches, private-data operations and publisher tools stay outside
this administrative interface. Full ordinary-user graphical login/application
launch qualification remains a separate release gate.

Ordinary-account application launches now use a separate fixed `packages-launch`
action when account memberships need stripping. It asks for no password and
selects only the kernel-authenticated caller, re-executing the installed package
CLI after the checked isolated identity transition. Existing standard streams
travel as descriptors, preserving native-window input/output and terminal I/O.
The completion supervisor also drops privileges. Package trust, policy, payload
and generation-lease admission repeat as the ordinary user. See
[launch qualification](../tests/packages/isolated-launch-check.md); a full graphical
login/display workflow remains a release requirement.

The [pinned catalog builder](../tools/packages/SDK.md#build-a-pinned-application-catalog)
assembles a complete publisher workspace atomically from reviewed prepared-root
recipes and file inventories. It checks every declared target/version and runtime
closure, rejects changed sources and retains a canonical import lock. The normal
release publisher signs and exports this workspace. Catalog assembly does not
enroll a publisher or accept proprietary/firmware terms for consumers.
The [catalog qualification](../tests/packages/catalog-build-check.md) covers
canonical release reproduction, refusal/cleanup and real Linux guest execution.

Prepared-root imports, catalog builds and the three fixed publisher profiles
share source-root admission before creating destination parents. Empty/NUL
paths and leaf directory aliases refuse even with trailing separators. Ordinary
roots retain canonical metadata and a captured namespace that later pathname
replacement cannot redirect. See
[root admission qualification](../tests/packages/prepared-root-check.md).

The lower-level `pack` command also captures its source root and walks children
through descriptors relative to their captured parents. Hashing and copying
share each regular file's descriptor, with identity, length and executable-mode
checks before metadata publication. Aliases, special files and excessive
directory work refuse; ordinary inputs retain canonical manifests. Keep source
contents stable and publisher output outside the source tree. See
[source traversal qualification](../tests/packages/pack-source-check.md).

Packing and both publication commands share a private workspace lock, so a
release cannot race another cooperating package writer. Busy writers preserve
objects, manifests, index bytes and release history; retry after the owner exits.
Workspace admission refuses NUL paths, leaf aliases and directories writable by
other users. Packing output inside its captured source tree also refuses before
creating output parents. See
[workspace qualification](../tests/packages/publisher-workspace-check.md).

The complete release is checked before reserving its sequence and again before
publication. Changed signed metadata, payloads, permissions, links or unexpected
entries refuse and remove the unpublished stage. Refusal before reservation keeps
the prior floor; refusal after reservation retains the intended sequence/digest,
so retry the same inputs or publish a newer sequence. See
[release admission qualification](../tests/packages/release-admission-check.md).

The [native SDK publisher profile](../tools/packages/SDK.md#native-sdk-publisher-profile)
provides a single pinned catalog for Hello, Counter and Memo on both targets.
Its [V builder](../examples/package-catalog/README.md) compiles six static apps
with redistribution notices, preserving file grants, MIME registration and
native window protocols 1/2. The normal signed workflow handles their updates,
rollback and retained private data. See [qualification](../tests/packages/native-catalog-check.md).

The [SQLite publisher profile](../tools/packages/SDK.md#sqlite-cli-publisher-profile)
provides a concrete dual-architecture CLI and separately versioned musl/SQLite
runtime, with pinned payloads and redistribution notices. Its
[guest qualification](../tests/packages/sqlite-profile-check.md) uses real SQLite
to check WAL/database reopen, ordinary-account isolation, library-only updates,
rollback and cached offline reinstall while retaining application data. It does
not enroll a public publisher or migrate the other advertised applications.

The [FFmpeg local media profile](../tools/packages/SDK.md#ffmpeg-local-media-publisher-profile)
packages FFmpeg/FFprobe with a shared, explicitly versioned musl/FFmpeg runtime,
license notices, upstream source and V build tools. It supports local
AVI/MPEG-4 and WAV/PCM workflows with a limited codec/filter set; network,
hardware acceleration and external codec libraries are disabled. The
[qualification](../tests/packages/ffmpeg-profile-check.md) covers real media
encoding, decoding and inspection through the package service on both targets.

All three fixed profiles validate the imported inventory before publication,
requiring their exact file paths and nonempty, bounded license/build notices.
Changes after preflight cannot substitute a directory for the required FFmpeg
source archive or publish empty notices. Failed imports remove staging data and
permit retry after restoring inputs. See [inventory qualification](../tests/packages/profile-inventory-check.md).

[Catalog composition](../tools/packages/SDK.md#compose-application-catalogs)
combines independently prepared profiles into one publisher release while
keeping their loaders and libraries in separate directories. It preserves every
payload pin, permission and license disclosure, checks complete architecture and
runtime coverage, and retains canonical source-lock provenance. The
[combined-catalog qualification](../tests/packages/composition-check.md) exercises
SQLite, FFmpeg and FFprobe in one signed release, including a SQLite-only runtime
update, rollback, offline cache reinstall and data-preserving uninstall.

## Trust and configuration

The image stage creates `/etc/vinix-packages/config.json` with an empty
repository list and the target architecture. An administrator can review and save
organization policy with the commands below; the launch account remains selected
in that file:

```json
{
  "format": 1,
  "architecture": "aarch64",
  "launch_user": "",
  "repositories": [],
  "policy": {
    "offline": false,
    "allowed": [],
    "pins": [],
    "permissions": ["network", "files", "process", "display", "audio"],
    "licenses": [],
    "allow_firmware": false,
    "reserve_bytes": 67108864
  }
}
```

Enroll a publisher using its public key obtained through your organization's
authenticated channel:

```sh
vinix-package repo-list
vinix-package repo-enroll company https://software.example.org/vinix PUBLISHER_PUBLIC_KEY_HEX
vinix-package update
vinix-package --json repo-list
vinix-package repo-revoke company
```

Software's **Repositories** screen offers the same administration workflow.
Select an existing repository or enter its ID, HTTPS/local source URL and public
key. **Review trust** verifies the signed catalog without enabling trust, then
shows its publisher key, previous key/source when replacing one, architecture,
sequence, expiry and catalog entry count. Compare the key through your trusted
channel. Long source URLs are paged; each part must be displayed before
confirmation becomes available. **Confirm trust** applies that exact review and
refreshes authenticated catalogs. Applications still require installation review.

An admitted trust or revocation proposal also offers **Read review** in full and
compact windows. The shared read-only reader preserves the complete current and
previous sources/keys, fingerprint, signed catalog digest, sequence/history
floor, expiry and entry count. It explains independent key comparison, key
replacement and revocation effects. Three short native lines keep every byte
readable at 180×220 or larger; Back/Escape and resizing retain reader and source
URL anchors. Reading cannot confirm/cancel trust, edit fields, start operations
or mark source URL parts as reviewed. Confirmation remains in the full proposal
under its existing URL-review and administrator guards. Pending readers and
writers cannot enter. See [trust reader checks](../tests/packages/software-trust-reader-check.md).

ID, URL and key paste events accept literal valid UTF-8 within their existing
128/4096/64-byte bounds. Control characters, malformed UTF-8 and oversized
input are refused as a whole; the previous field and selection stay intact.
Empty or unfocused pastes do nothing. Pasted Enter, Escape, Tab and editing
controls cannot start/cancel a review, change focus or edit a frozen proposal.
Pastes are ignored while a repository operation is running. Keyboard commands
and final repository validation remain in place. See
[repository paste checks](../tests/packages/software-repository-paste-check.md).

**Review revocation** and **Confirm revocation** disable an existing publisher
without downloading metadata. If the repository list cannot be loaded, enter its
ID to review revocation directly. Signature, expiry, stale-review and access
failures reach the window. A refresh failure after successful enrollment clearly
reports that trust was saved while the catalog remains unavailable; reload or
refresh after correcting the failure. Organization policy and the launch account
are preserved; there is no implicit privilege escalation or license acceptance.

Trust reviews bind the configuration, operation and exact repository identity.
Enrollment additionally binds retained sequence history and the exact verified
index digest. Apply re-reads those inputs under the writer lock and rejects a
stale confirmation before publishing configuration/history. Revocation review
does not need valid/reachable catalog or history data. Script clients can use
`repo-review enroll ID URL KEY` / `repo-review revoke ID`, followed by
`repo-apply FINGERPRINT enroll ID URL KEY` / `repo-apply FINGERPRINT revoke ID`.
The ordinary enrollment/revocation commands remain available.

`repo-enroll` verifies a current signed index against that exact ID/key and
retained sequence history before atomically enabling trust. It downloads only
metadata; `update` then publishes the combined catalog. Invalid signatures,
expiry, identities, URLs and replayed metadata leave configuration unchanged.
Enrollment preserves the target, launch account and organization policy. Using
an existing ID explicitly replaces its URL/key; the old catalog is unavailable
until refreshed. A URL change retains the same publisher's sequence floor. Key
rotation permits the new key's own sequence while retaining the old key's floor.
`--offline repo-enroll ID file:///media/repository KEY` uses a local repository
without changing the persistent offline policy. No key is learned from an index.

Keep configuration/state owned by the administrator and unwritable by ordinary
users. The commands share the package writer lock, reject unsafe configuration
files/directories and flush private temporary files before atomic replacement.
Configuration reads reject unknown or duplicate fields, including escaped
spellings of the same key, null values and incorrectly typed policy entries.
Omitted fields retain their documented defaults; an explicit empty permissions
list or zero disk reserve stays explicit. A misspelled allowlist or permissions
field fails before acquisition, cleanup or activation. Correct the configuration
under the package lock, then retry; no state reset is needed. See
[configuration qualification](../tests/packages/configuration-check.md).
`repo-revoke` requires no reachable repository or valid catalog/history. It
revokes acquisition, rollback and subsequent launches from that publisher while
retaining payloads, personal data and history for inspection and uninstall.
Software lists configured identities through `repo-config`, so damaged cached
metadata cannot prevent selecting a publisher for reviewed revocation. This
read-only list checks configuration and coordination locks, without checking
catalog authenticity or replay history. `repo-list`, enrollment and updates
retain their verification requirements and still refuse damaged metadata. See
[configuration-list qualification](../tests/packages/repository-config-check.md).
A root administrator can still alter installed code or local sequence records;
this is not hardware protected antirollback.

Publisher keys must encode canonical, non-identity points in the Ed25519
prime-order subgroup. New enrollment, index verification, application/runtime
launch and rollback enforce this check. Existing configuration/history stays
readable for reviewed revocation and uninstall of an old unusable key, preserving
replay floors and personal data. See
[publisher key qualification](../tests/packages/publisher-key-check.md).
Software and organization-policy reviews also identify invalid installed keys,
including a runtime's publisher when the application's own key is valid.
These read-only diagnostics remain available with an unusable catalog and
explicitly preserve the uninstall path. See
[diagnostic qualification](../tests/packages/diagnostics-check.md).

An old unusable key's cached index no longer blocks maintenance after reviewed
revocation or replacement when retained history already pins its exact ID/key,
sequence and index bytes. Review and listing leave the cache untouched; the
next successful refresh supersedes it while preserving every sequence floor.
This exception cannot authenticate the old publisher, admit a new invalid key,
ignore a valid key's bad signature or reconstruct missing history. Unrecorded or
changed index bytes and malformed metadata still require trusted restoration.
See [publisher recovery qualification](../tests/packages/publisher-recovery-check.md).

Ed25519 authenticates the exact index bytes **before** decoding. The service
uses a [pinned, licensed V signing dependency](../tools/packages/signing/README.md)
for publisher and consumer. Its source ledger makes changes reproducible, and
[reference/sanitizer/guest checks](../tests/packages/signing-check.md) cover the
compiler-sensitive point-initialization adaptation.
The [field-temporary checks](../tests/packages/signing-repeat-check.md) also
measure reduced allocation after discarding redundant carry-result assignments,
and exercise repeated publication in one process. The later
[table ownership checks](../tests/packages/signing-tables-check.md) qualify
lookup-table/digit cleanup and point temporary lifetimes. Subsequent
[buffer ownership checks](../tests/packages/signing-buffers-check.md) require
zero retained tracked bytes after caller cleanup for measured key derivation,
signing and verification operations, including hash padding boundaries.
An unbounded publisher lifetime and all package-service allocations remain
separate qualification work.
The service checks repository identity, format, expiry, increasing sequence and same-sequence
equivocation. `/var/lib/vinix-packages/trust-history.json` retains the highest
authenticated sequence and exact index digest for each repository ID/key,
including revoked and replaced keys. Empty refreshes, garbage collection and
re-enrollment never reset it. Authenticated legacy cached indexes migrate into
this history even after expiry or revocation.

Present consumer and `publish-release` history files require complete format and floor
records. Null/missing arrays, ambiguous keys and invalid value types fail closed;
they cannot silently reset the remembered sequence. A damaged file is preserved
and blocks refresh, enrollment and new release publication until an administrator
restores valid history under the package/publisher lock. Keep the original file
and recover from retained trusted records or a protected backup; deleting history
discards replay protection. Publisher revocation remains available with damaged
history. See [history qualification](../tests/packages/history-schema-check.md).

The cached `catalog.json` wrapper also requires complete typed snapshots with
unique, valid repository identities. Missing/null/coerced declarations, ambiguous
keys, over-limit records and dangling cache links are refused. A present null
cache cannot silently become an empty input to legacy replay-floor migration.
Signed index bytes and signature checks are preserved. Restore trusted cache and
history under the writer lock before retrying; replacing damaged records with
empty lists discards recovery information. Revocation and uninstall remain
available without a readable catalog. See
[cache qualification](../tests/packages/snapshot-schema-check.md).

Refresh verifies all configured repositories before committing metadata. A fetch
or validation failure keeps the previous catalog/history. History is flushed
before the new catalog or enrollment configuration: an interrupted publication
can leave a newer floor alongside an older catalog. Acquisition then fails
closed; retry `update` against the same or a newer signed index, or retry
`repo-enroll` if enrollment was interrupted. Do not delete history to retry.
Installed launches use their retained signed payloads and current trust/policy.
These guarantees require the filesystem/device to honor flush and rename.
SHA-256 and length authenticate every payload. Transport
accepts certificate-validated HTTPS or an absolute local `file://` repository.
HTTP, unknown architectures, unsafe paths, special files, symlinks, conflicting
file paths and ambiguous package ownership are rejected.

Signed indexes require complete, typed format-1 envelopes, package declarations,
dependency ranges and payload inventories. Unknown fields, duplicate fields
(including escaped spellings), null collections and coerced counters are refused
after signature verification. The legacy omitted `window_protocol` still means
zero. Publisher templates keep their documented defaults but reject ambiguous
fields; stored packed manifests require complete declarations before publication.
Prepared-root templates and catalog locks also reject ambiguous fields/types
before import. Catalog composition requires complete pinned declarations and
cannot normalize missing or null permissions into a publishable lock. See
[publisher schema qualification](../tests/packages/publisher-schema-check.md).
A refused refresh or enrollment preserves the previous cached catalog, trust
history, configuration and installed generation. See
[signed metadata qualification](../tests/packages/index-schema-check.md).

HTTPS acquisition opens one nonblocking, no-follow regular destination before
starting curl, refusing hard links and oversized resume prefixes. Curl writes to
a pipe; the service bounds each write before sending it to the captured file.
The file and named identity must still agree before successful completion, and
the captured file is flushed without reopening the pathname. Identity, length
and link count are rechecked before writing each body chunk and after progress
callbacks, including final progress. Changed output stops further writes; interrupted
flushes retry. See [HTTPS output qualification](../tests/packages/https-output-check.md)
and [callback/recovery checks](../tests/packages/https-output-guard-check.md).

If an HTTPS repository refuses byte-range resume, acquisition retries once from
byte zero, replacing the old prefix when fresh bytes arrive. A corrupt fresh
fallback stops without another integrity retry. Other transport failures preserve
partial data for a later transaction. Curl's internal retries are disabled because a pipe cannot
rewind bytes already delivered; each service attempt has its own captured offset.
[Real TLS transport checks](../tests/packages/https-check.md)
cover certificate/hostname trust, HTTPS-only redirects, authenticated size bounds,
range recovery, progress and preserved activation/rollback.

Dependency resolution uses an iterative worklist with bounded backtracking.
Shared dependencies and cycles expand each selected identity once, and constraints
discovered later can change an earlier choice. Runtime kind and executable
entrypoints participate in that search. At an equal version, the host architecture
precedes `all`; ordinary installs still prefer an authenticated exact installed
version, while upgrades prefer newer versions. Installed identities remain bound
to their repository.

The resolver accepts at most 4,096 requested roots and 32,768 catalog variants,
selects at most 4,096 packages and allows at most 128 dependencies per package.
Its 100,000-step budget counts constraint processing and candidate checks;
exhaustion reports the search limit directly. Publisher release validation shares
that budget across all advertised versions and both host architectures, with each
advertised root fixed to its exact variant. See
[dependency resolver qualification](../tests/packages/resolver-check.md).

## Install, maintenance and recovery

```sh
vinix-package update
vinix-package search editor
vinix-package info editor
vinix-package plan install editor
vinix-package install editor
vinix-package updates
vinix-package upgrade
vinix-package rollback
vinix-package remove editor
vinix-package verify
vinix-package gc
```

Command-line applications can receive literal flags through
`vinix-package run-args ID [--file ABSOLUTE_FILE]... -- ARGUMENT...`.
`run-terminal-args` uses the same syntax in a terminal. Package-declared arguments
come first. Each `--file` grants an existing document under the application's
declared `files` permission; it does not append that path to the command.
Only regular files, including symbolic links resolving to regular files, are
accepted. Devices, FIFOs, sockets, directories and unavailable targets fail with
the offending path before application data is created. See the
[document-grant qualification](../tests/packages/document-grants-check.md).
Include the path explicitly among the application arguments when needed.
Arguments alone grant no paths, remain literal across the ordinary-account
handoff and do not expand `@APP@`, `@DATA@` or `@RUNTIME@`. Outputs belong in the
application's private data directory or an explicitly granted existing file.
See the [SDK command contract](../tools/packages/SDK.md#literal-command-arguments).

Software's **Launch options…** opens a form for an installed application. Enter
arguments with quotes around values containing spaces. Add each existing input
or output file under **Allowed files** and use its path explicitly in the
arguments. Files can be removed or paged, and an entered file must be added or
cleared before running. The ordinary service checks the actual file access;
the desktop's administrator identity grants no additional access.

The form defaults to **Working folder: private app data**, where relative output
names are saved in the ordinary account's `~/.local/share/vinix-apps/ID`.
Switch to **installed app** when an application needs packaged assets relative
to its working folder. **Run** captures diagnostics, while **Run in Terminal**
opens the same command in Software's terminal. Input freezes during execution;
failed batch commands keep the draft for correction. Returning to the catalog
or closing discards it. Launch controls use installed name/kind/permissions even
when the catalog presents a pending update with different metadata. The service
continues to enforce the current installed state, trust and organization policy.
See [qualification](../tests/packages/launch-options-check.md).

Small windows retain **Back to catalog**, status and failure access; enlarge the
window to edit arguments/grants or launch. Resizing preserves the entire draft
and file-page selection. Escape leaves a focused field, then returns an idle
form to the catalog and discards its draft. Pasted Escape, Enter and other
control bytes are rejected without editing or navigation. Running applications
retain their close guard: Back, Escape and other form actions cannot interrupt
the service that holds their runtime leases. After exit, failures retain the
draft for correction and exact retry or transfer to Terminal. See the
[launch navigation checks](../tests/packages/software-launch-navigation-check.md).

Search covers names, IDs and descriptions. Info shows publisher, repository,
license, permissions, target and installed version. Dependency ranges have
inclusive minimum/exclusive upper versions. Resolution backtracks across all
constraints, supports cycles and selects only the host target or independent
**data**. Install prefers compatible installed versions; upgrade/deploy choose
the latest satisfiable closure. Dependencies cannot silently switch repositories.

Changes take an exclusive process-released filesystem lock. Before downloading,
space is checked for the complete staged generation, missing cached payloads,
filesystem overhead and the configured reserve. Available bytes use the
filesystem's allocation unit (`statvfs.f_frsize`) with `f_bavail`, including when
it differs from the preferred I/O size. Invalid zero units and multiplication
overflow refuse the operation with a path-specific diagnostic. Offline exports,
catalog assembly and release publishing use the same calculation. See
[space calculation qualification](../tests/packages/space-check.md).
Uninstall budgets retained files from their verified active-generation copies,
so an absent or damaged object cache does not add a download that removal never
needs. Both review and activation recheck this estimate; files that no longer
verify require the normal cache/acquisition allowance. Staging space, overhead,
the configured reserve and per-copy verification remain required. See
[removal-space qualification](../tests/packages/removal-space-check.md).
Install, upgrade and managed deployment also verify unchanged target payloads.
Missing, corrupt or nonregular files require a fresh generation from verified
cache or approved repository objects, even when versions stay the same. Software's
**Repair installed** opens a dedicated review of the complete installed closure,
including dependencies. `vinix-package repair` provides the same operation for
administrator scripts; `review repair` and `apply FINGERPRINT repair` provide
reviewed automation. It preserves installed manifests, publisher/sequence records,
versions, permissions and requested applications even when updates are available.
Every installed manifest must still appear with its exact provenance in the
current authenticated cached catalog and satisfy organization policy. Withdrawn
versions fail with guidance to refresh or review updates, rather than silently
upgrading. Repair works offline with valid cached metadata and objects, requires
no package IDs, and does not refresh repositories. Review shows affected packages as updates
and includes staging/acquisition space. Confirmation binds the affected package
set; restoration or different damage requires review again before cleanup or
downloads. Healthy identical targets remain a no-op. Trust, policy, offline and
hash checks still apply, personal data is retained, and rollback refuses damaged
previous generations. See [repair qualification](../tests/packages/repair-check.md).
Software labels these same-version `update` rows as repairs and keeps **Update
all** separate. Confirmation uses the existing reviewed administrator transport;
verification diagnostics name both the graphical control and CLI repair command.
See [explicit repair qualification](../tests/packages/explicit-repair-check.md).

Software's **Health report** checks the complete installed set and lists packages
with issues first. It records the first namespace, payload or launcher issue for
each package, with paged installed provenance and bounded diagnostics. Runtimes
and data dependencies have their own results; a clean application row does not
assert that its dependency closure can launch. Search matches installed IDs,
names, versions, kinds, repositories, publisher keys, issue categories and
diagnostics without rescanning storage; **Issues only** narrows the same snapshot.
Rows identify their issue category, and the visible count stays separate from
the complete generation summary. Reload preserves the search and filter, while
returning to packages preserves the catalog search and selection. **Back to
packages** remains available in a small window. See
[search/filter qualification](../tests/packages/health-search-check.md).
The report remains available without usable cached catalogs or currently trusted
publishers, and writes no
package state. **Review all repairs** obtains a fresh authenticated repair review
for the complete installed set, including packages hidden by report filters;
the observation itself authorizes no change. `vinix-package health` provides the
same inspection, with `--json health` for scripts. A complete report returns zero
even when rows contain issues; `verify` retains its failure exit behavior. See
[health report qualification](../tests/packages/health-report-check.md).
The report shows live package inspection progress. **Stop inspection** and
Escape stop its read-only worker, discard partial results and allow Reload;
small windows also expose Stop. CLI `--json --progress health` keeps the complete
JSON on stdout and progress on stderr. Software drains both channels through
exit and refuses incomplete or inconsistent responses and late diagnostics. See
[progress/cancellation qualification](../tests/packages/health-progress-check.md).

Compact Health reports also retain Reload, current status, progress, failure
access and the generation summary when space permits. Resizing preserves search,
filter, selection and the current detail page. Cancel joins Stop inspection and
Escape for pending reads; all discard unaccepted report/progress bytes and leave
a fresh Reload available. Completed checks show a waiting status until service
exit, before the existing report/count/exit checks can accept a result. See
[health navigation checks](../tests/packages/software-health-navigation-check.md).

Installation health also checks payload modes (0755 for executables, 0644 for
other files) and the exact generated desktop launcher/MIME contents at mode 0644.
Verify, rollback and ordinary launch enforce these checks before execution.
Missing, altered, symlinked or special-file launchers and wrong
modes trigger reviewed repair using a fresh generation. Existing inodes and
outside aliases are never chmodded during discovery. Launcher staging sets its
mode explicitly, including under umask 077. Cache object modes remain independent.
See [installation health qualification](../tests/packages/installation-health-check.md).

Launcher checks also capture the generation, `share` and `applications`
directories without following aliases. Final directories must be administrator-owned
0755 entries on the generation filesystem; the canonical 0644 launcher is read
relative to its captured parent. All directory and file identities, ownership and
modes are rechecked after reading. Shared-parent faults produce `registration`
health findings and fresh repair proposals for the affected applications.
Ordinary launch refuses damaged registration before preparing private data or
executing a runtime. Repair creates a new generation and preserves outside alias
targets, personal data and provenance. See
[launcher parent qualification](../tests/packages/launcher-parent-check.md).
Files stream in 64 KiB blocks.
Partial downloads persist as `objects/HASH.part`; retries resume and verify the
complete hash. A damaged resumed prefix triggers one fresh download from the
same authenticated source with the same size/hash requirement. A second integrity
failure discards the partial and stops; a fresh download's integrity failure does
not trigger another transfer. Invalid complete or oversized partials start fresh
directly. Verified complete partials are promoted without network access. Ordinary
transport failures retain partial data for a later retry. Network/storage failure
leaves activation unchanged. Partial directories/FIFOs refuse before opening;
metadata, object verification and offline sources also require ordinary regular
files, so special files cannot hang these reads. The
[download recovery checks](../tests/packages/download-recovery-check.md) cover
reviewed deployment recovery and refusal without changing activation/rollback.

`--progress` adds bounded, versioned progress frames to maintenance output for
refresh, install/remove/upgrade, reviewed apply, deployment and rollback. Software
uses them automatically: downloads and staged copies show byte counts, staging
shows package counts, and verification/activation remain distinct phases.
Counters describe the current phase; a finished download does not imply a
completed installation. Restarting a damaged partial resets its download counter
to zero; the restart reason appears in maintenance output. Completion is reported
only after successful publication and activation flushes. Copied installation
payloads are hashed again before the
generation can be published. HTTPS transfer monitoring reaps failed/oversized
children, retains bounded partial downloads for retry, and enforces authenticated
size bounds while the child runs.

The command service loads configuration after acquiring that lock, so a completed
repository revocation, key replacement or policy change cannot be followed by a
transaction using the command's earlier configuration. Refresh, deployment,
rollback, mirror export and garbage collection use the same boundary. Reviews,
plans, status and payload verification load configuration under a shared lock;
a busy writer yields a diagnostic before configuration is decoded. Fresh-image
status remains read-only. `--json verify` verifies every installed payload before
emitting state, just as the text command does. Administrators editing policy
files directly must serialize those writes with the package lock or stop package
operations; an unrestricted administrator can bypass the service's guarantees.

Software's **Verify installed** checks payload contents/permissions and generated
launchers without changing packages or requiring a working catalog. It displays
check progress, keeps the current list/filter/selection, and retains failures and
repair guidance in **Failure details**. Successful results remain visible;
publisher trust and organization policy still apply separately at launch.
Verification runs without an administrator prompt and supports **Stop verifying**,
Cancel and Escape in full or compact views, as well as closing the window.
Stopping reaps the read-only worker, discards unaccepted progress/output and
retains the catalog for a fresh retry. A completion frame and human success
text remain provisional while the service is running; success requires its
successful exit. Stop controls do not interrupt package transactions or running
applications, even when they emit verification progress. See
[verification navigation checks](../tests/packages/software-verify-navigation-check.md).
The CLI's `--progress verify` uses the existing bounded progress
format and reports completion only after a healthy scan. Plain/JSON Verify
output stays compatible. See [qualification](../tests/packages/verify-progress-check.md).

Each generation contains package state, the full payload closure, launcher
records and a running-application lease. Changed reviews and transactions check
the exact future state against the persistent metadata limit before downloading,
staging or deleting interrupted work. Oversized plans fail with guidance to
reduce the requested set or package metadata; a smaller set can retry normally.
See [metadata preflight qualification](../tests/packages/state-preflight-check.md).
Catalog reads also release redundant authenticated metadata while preserving
publisher, expiry and replay checks; see
[catalog ownership qualification](../tests/packages/catalog-ownership-check.md).
Manifest, dependency, repository and organization-policy validation also release
their temporary duplicate maps and avoid copying scalar fields and path
components. Repeated validation preserves the caller's metadata; see
[validation memory qualification](../tests/packages/validation-memory-check.md).
Refresh checks the exact serialized cache prefix after each authenticated
repository, including wrapper escaping and the closing byte. An oversized
prefix stops before contacting later repositories and preserves the active
cache/history; reducing the repository metadata allows a normal retry. See
[cache preflight qualification](../tests/packages/cache-preflight-check.md).
Replay-history migration and updates now own their identity/digest fields and
retire superseded records and decoded indexes. Refresh, repository review and
enrollment, status and publishing retain the same replay rules; see
[history ownership qualification](../tests/packages/history-ownership-check.md).
Configuration and consumer/publisher history writes retire their JSON buffers
on success, size refusal and write failure. Repository review fingerprints also
release serialization/hash scratch while preserving their exact digest inputs.
Persisted JSON, the newline-inclusive size limit and publication ordering stay
compatible; see [administration metadata qualification](../tests/packages/administration-metadata-check.md).
Repository signature decoding scans borrowed input and allocates an output only
for a valid 64-byte hex representation. Oversized or malformed signatures cannot
cause input-sized decoder allocations. Legacy whitespace, prefixes, hex case,
odd leading-zero spelling and diagnostic precedence remain compatible; see
[signature decoding qualification](../tests/packages/signature-decoding-check.md).
Enrollment retires loaded index/signature text when reading or authentication
fails. Read-only repository reviews retire temporary configurations and proposals
while returning independently owned review fields. Metadata reads also keep
their synchronous `stat` scratch on the stack. See
[enrollment ownership qualification](../tests/packages/enrollment-ownership-check.md).
Files/directories are flushed before
publication; POSIX rename switches `current` atomically. The next state-changing transaction
retires abandoned stages. A crash before activation exposes the old complete set;
a crash after it exposes the new complete set. Actual durability depends on the
filesystem/device honoring flush and rename. No maintainer scripts or implicit
user-data migrations run during activation.

The service verifies the whole generation before recursive flushing, before
exclusive publication and after the last activation progress callback. The tree
must contain exactly its declared payloads, generated launchers, captured state
bytes and an empty mode-0444 lease. Entries must be ordinary, owned by the service
and have canonical final modes; files must have one link. Unexpected directories
are refused without traversal. Publication cannot replace an existing generation.
Cleanup removes a refused unpublished stage only while its captured directory
identity remains valid; replacements are retained with a diagnostic. A published
generation that fails the final check is retained at the path printed in the diagnostic, with `current`
unchanged; retry builds a new generation from verified sources/cache. Rollback
also checks the complete tree and captured state bytes after progress. See
[generation admission checks](../tests/packages/generation-admission-check.md).

Transactions and garbage collection validate every abandoned stage root before
removing any stage. Invalid roots preserve the other stages, published generations
and cache. Cleanup captures directory identities, refuses foreign directories or
filesystems and walks components without following aliases. Leaf aliases, hard
links and FIFOs are unlinked without changing outside contents or modes. Incomplete
state files and missing leases are expected in interrupted stages. Unreadable or
changed directories refuse cleanup and remain for inspection. Recovery keeps a
fixed number of descriptors even for deep trees. See
[stage recovery checks](../tests/packages/stage-recovery-check.md).

Rollback checks payloads and current organization/key policy before restoring
the previous generation. Uninstall removes the app and unused dependencies from
the active generation; explicitly installed dependencies remain roots. Packages
still required by another root cannot be removed alone. Removal works without a
valid/reachable catalog, including after publisher revocation. Previous payloads
remain for rollback. `gc` retains active/previous and leased generations, removes
older unused generations and unused complete objects, and clears abandoned
partial downloads.

Rollback copies the retained package set into a fresh generation whose
`previous` points to the generation it replaced. It checks free space and the
configured reserve, stages and verifies the complete copy, and activates it
atomically. The source's manifests, provenance and requested roots are preserved;
the source tree and personal data remain untouched. Cached objects and repository
access are unnecessary. Interrupted stages recover on retry; a damaged published
copy remains for inspection without activation. Cleanup can run before or after
rollback, and another rollback restores the replaced set.

The review's `target_generation` is the source being restored. Active generation
IDs now advance on rollback; scripts should inspect `status` for the result and
obtain fresh approvals after updating from the pointer-only implementation.
Software explains the new generation and undo behavior before confirmation and
shows the restore source in Details. See
[qualification](../tests/packages/rollback-check.md).

For organization rollout or recovery records, `deployment-snapshot [INSTALLED_ID...]`
exports an existing format-2 deployment lock from the installed generation.
Omitting IDs records the requested application set; explicit IDs select only
those installed packages and their transitive runtime/data dependencies. Versions,
manifest digests, publisher identities and sequence floors remain exact even when
the current catalog has withdrawn a version or cannot be read. The command is
read-only and does not initialize an empty store.

The exported metadata supplies neither payloads nor trust. To reproduce it on
another system, provide approved repositories containing the exact manifests,
then use the existing reviewed deployment flow. Current signatures, replay
history, policy, permissions, licenses and firmware admission still apply. See
[qualification](../tests/packages/deployment-snapshot-check.md).

Use `vinix-package deployment-snapshot-save /path/to/new-lock.json` to save that
installed set directly. Optional installed IDs select a subset and its complete
runtime/data closure. The file is published atomically with mode 0644 and never
replaces an existing name, including a dangling symlink or a destination created
by another writer. The parent must already exist and permit the caller to write;
ordinary users can save root-owned installed metadata into their own directories.
`--json` returns the captured generation, destination, digest and package counts.

Write/space failures before publication clean the owned temporary. An error after
publication explicitly reports that the file was saved; inspect the file and
storage before retrying, since retry will preserve an existing destination.
Saving remains an export of historical metadata, with no payload backup, trust
enrollment or installation approval. See [qualification](../tests/packages/deployment-save-check.md).

In Software, **Deployment → Save installed…** saves the complete installed set
to a new absolute filename in a directory you can write. The service runs as your
ordinary user and preserves existing files. Software waits for the writer to
finish before allowing Back or closing the window. A successful receipt shows
the full destination, captured generation, architecture, SHA-256 and application
and package counts in paged details. **Check installed** and **Review deployment**
read the captured filename afresh; restoring still needs a separate review and
confirmation. Failure details retain storage diagnostics, including failures
after publication. Inspect the destination before retrying if saving may already
have created it. See [Software save qualification](../tests/packages/software-deployment-save-check.md).

In the save form, Escape leaves a focused filename field before a second Escape
returns to Deployment. Pasted control characters and invalid UTF-8 are refused
as a whole, preserving the filename and selection. Small windows retain Back,
status and failure access; enlarging restores the draft or receipt detail page.
Saving still blocks navigation until the service exits, including after a
complete receipt arrives. See [save navigation checks](../tests/packages/software-snapshot-navigation-check.md).

Choose **Export offline…** on a nonempty saved receipt to prepare portable media
for that exact deployment. The source filename and saved digest stay fixed;
choose a new export directory, then review the full paths, publishers,
permissions, licenses, runtime closure and space before administrator approval.
A changed source refuses review and requires saving a new snapshot. The receipt
does not supply trust or publication approval. Export uses the existing atomic
locked-mirror flow and bundles `_deployment.json`; no payloads are acquired by
opening the destination form. See [saved export qualification](../tests/packages/software-snapshot-export-check.md).

For read-only organization drift checks, run
`vinix-package --json deployment-audit /path/to/approved-lock.json`. It compares
exact installed manifests and provenance with a format-2 lock, including the
requested application set and minimum publisher sequences. The report lists
missing, extra and changed packages even without catalogs or after revocation.
Exit status 0 means metadata matches, 3 means drift, and 1 means the check failed.
The report includes the captured lock's SHA-256 and installed generation so a
deployment controller can identify its inputs. It neither verifies payload health
nor authorizes changes. Use **Health report** for installed integrity, and the
reviewed deployment flow to reconcile drift under current trust and policy. See
[audit qualification](../tests/packages/deployment-audit-check.md).

In Software, open **Deployment**, enter an exact lock path and choose **Check
installed**. The report lists matching, missing, unexpected and changed packages,
with separate expected/installed versions and paged details for every difference,
the full source path and captured digest. Reload replaces the observation; Stop
and closing the window cancel the read-only check. Small windows keep Back or
Stop available. No administrator prompt is required for observation.

The audit's **Search** field matches package IDs, result status, expected or
installed versions, and changed field names such as `public_key` or `sequence`.
**Differences only** hides matching rows; differences appear first in either
view. The result count describes the visible subset while the header retains
the full comparison totals. Search and filtering preserve selected package
identity and remain available after Reload or a stopped check. Empty search
results keep the deployment path, digest and generation inspectable. **Review
deployment** always reviews the complete captured file, including packages
hidden by filters. See [search qualification](../tests/packages/software-audit-search-check.md).

**Review deployment** on the report opens a fresh authenticated deployment
proposal using the captured source filename, even if the form was edited. Changes
to the file, installed state, current trust or policy are checked by that new
review and the existing confirmation flow. A drift report never authorizes an
installation. See [Software audit qualification](../tests/packages/software-deployment-audit-check.md).

Deployment forms and proposals keep Back, Stop, Cancel, status, progress and
failure access available in small windows. **Stop review**, Cancel or Escape
can stop and reap a pending read-only proposal, discard its unaccepted output
and retain the literal filename for a fresh review. Completed proposals and
package details retain their own cancellation/back controls after resizing.
Approved deployment transactions keep running until they finish, including
empty deployments that remove all packages. Compact windows omit confirmation
controls; enlarge the window to inspect the complete plan. See
[navigation qualification](../tests/packages/software-deployment-navigation-check.md).

Software’s **Clean up versions** opens a read-only, paged review of obsolete
generation IDs, with the architecture and current/rollback identities. Confirming
**Delete listed versions** uses administrator authorization and deletes only that
reviewed set. Cached complete/partial downloads, interrupted stages and personal
data remain available. Versions held by running applications are omitted; reload
after those applications finish to review newly eligible versions.

Pending cleanup reviews support **Stop review**, Cancel and Escape. Stopping
discards the unaccepted generation list and fingerprint; reload and inspect a
fresh review before confirmation. Small windows retain Back, reload, status and
failure access, with confirmation available in the full view. Resizing keeps
the first visible generation. Escape returns an idle review to the catalog;
approved deletion retains its close guard and cannot be interrupted through
these controls. A stopped or failed post-cleanup reload keeps the completed
result for the next successful read. See
[cleanup navigation checks](../tests/packages/software-cleanup-navigation-check.md).

Loaded cleanup reviews also offer **Read review** in full and compact windows.
The shared read-only reader shows the architecture, complete review fingerprint,
current/rollback identities, every listed obsolete generation and the permanent
deletion/retention rules. Previous/Next and arrow/Page keys traverse complete
short pages at 180×220 or larger; resizing retains the page anchor. Back or
Escape returns to the same list position. Empty reviews disclose that nothing
is listed. Reload, deletion, package actions and pasted commands stay inactive
inside the reader, and pending reviews or approved writes cannot enter it.
Deletion still requires the full review and administrator authorization. See
[cleanup reader qualification](../tests/packages/software-cleanup-reader-check.md).

The public commands are `cleanup-review` (format-1 JSON) and
`cleanup-apply FINGERPRINT`. Approval binds configuration, both retained states
and the complete removable set, including generation-parent, root and lease
identities. Activation, configuration, eligible-set or identity changes require
a fresh review before any removal. Every target directory inventory is admitted
before the first deletion; removal rechecks identities and leases. Filesystem
errors during deletion can still leave a partially completed cleanup: inspect
the diagnostic and reload before retrying. Ordinary accounts can review root-owned
state; only reviewed `cleanup-apply` crosses the administrator transport. Raw
`gc` remains an administrator CLI operation for broader cache/stage collection.
See [reviewed cleanup qualification](../tests/packages/reviewed-cleanup-check.md).

Stored generations are decoded strictly with all state envelope fields required.
Each installed provenance, manifest, dependency and payload record must retain
every declaration, including false flags and empty lists/bounds. Null and coerced
values refuse admission. Only the documented zero-valued `window_protocol`
extension remains optional. Damaged current state blocks dependent maintenance
and launch admission; damaged previous state blocks rollback and collection.
Failures preserve retained metadata, payloads and recovery work. Restore trusted
records under the package writer lock or after stopping workers before retrying;
missing declarations must not be guessed. See
[stored-state qualification](../tests/packages/state-schema-check.md).
Unknown and duplicate fields, including escaped duplicate spelling in nested
package/provenance/dependency/file records, are refused. State checks include
unique requested roots, the complete reachable dependency closure, target
architectures, provenance, runtime kind and executable runner, and an earlier
rollback generation. Activation pointers and numeric generation directories use
canonical positive u64 names; leading-zero aliases, zero and overflow are refused.
Generation directories and state files must be ordinary filesystem entries.

Before collection deletes anything, it validates both retained states, parses all
numeric generation names and checks every eligible obsolete-generation lease.
Preflight uses one directory/lease descriptor pair at a time and records their
device/inode identities. Under the same package writer lock, removal reopens
and checks those identities, then reacquires the exclusive lease. A lease that
becomes busy is retained; a replaced directory/lease refuses removal with a
retry diagnostic. New package launches cannot enter while the writer lock is held.
Busy leases remain protected. Missing, symbolic, directory or FIFO
obsolete-generation leases refuse collection without retiring another generation
or cache object; FIFO checks are
nonblocking. Corrupt rollback metadata therefore cannot discard cache objects
needed for recovery. Normal filesystem failures during subsequent removal can
still leave a partially completed collection. Restore damaged metadata from a
known-good administrator backup. Use `verify` for the active generation and
`review rollback` for the restored previous generation before cleanup or rollback;
the service does not guess manifests or rewrite corrupt history. See
[persistent state qualification](../tests/packages/state-validation-check.md).
The [collection descriptor qualification](../tests/packages/collection-limit-check.md)
reproduces the previous failure with 128 obsolete generations under a 32-FD limit
and checks successful cleanup with bounded descriptor use and protected live leases.

Collection captures the generation parent too: moving an unchanged generation
and lease into a replacement parent refuses removal. Obsolete roots must be
ordinary administrator-owned directories on the parent's filesystem without
write access for other accounts. Root/lease preflight completes before stage,
generation or cache removal. Retirement inventories the directory tree, then
reopens each component without following aliases and checks captured identities.
Leaf symlinks, hard links and FIFOs lose only their generation names; targets are
neither opened nor chmodded. Names are enumerated before unlinking to avoid
directory-cursor skips. The exclusive lease remains named until other contents
are gone, so earlier failures remain retryable after restoring trusted entries.
An error after the final lease unlink reports the remaining empty directory;
inspect storage and restore an empty regular lease under the writer lock before
retrying. Active and rollback generations and busy leases remain protected.
See [collection retirement checks](../tests/packages/collection-retirement-check.md).

Installed package verification now checks each complete `apps/ID` namespace too.
Extra files, empty directories and FIFOs, directory aliases, hard-linked payloads,
foreign ownership and changed directory permissions fail verification and produce
repair rows for affected unchanged packages. Ownership comes from the captured
state administrator, allowing ordinary accounts to inspect root-owned installations.
Traversal uses captured directories without following aliases and keeps descriptor
use independent of depth. Launch checks the selected app's runtime/dependency
closure before private-data preparation or execution. Repair uses authenticated
cache objects to stage a fresh generation, preserving damaged old generations,
outside targets, trust history and personal data. Restore invalid state parents
outside the generation administratively before retrying. The
[namespace checks](../tests/packages/installed-namespace-check.md) cover Verify,
repair review/application, stale approvals, ordinary launch refusal and rollback.

Readers, writers and launch admission also check the captured lock/lease file
type. FIFO replacements refuse promptly, without opening a blocking read or
changing the FIFO's permissions. Directory, socket and symbolic replacements
cannot become coordination files. A busy writer or exclusive generation holder
returns a retry diagnostic instead of waiting indefinitely. Read-only status,
Software views, trust and policy requests require a lock whenever durable
catalog/history or active state exists; fresh-image reads still create no state.
Refusal preserves malformed entries, retained metadata, payloads and abandoned
stages. Stop package workers and application processes before repairing a lock
or lease: replacing a file that is still held would separate its existing holders
from new requests. Restore trusted state rather than bypassing the checks, then
retry `verify`. See [coordination qualification](../tests/packages/coordination-check.md).
Coordination files also require exactly one hard link and the captured named
inode before and after locking. Writers acquire exclusion before changing lock
permissions. Launch, collection and data purge share the lease checks; malformed
obsolete leases stop collection preflight before any generation/cache removal.
See [identity qualification](../tests/packages/coordination-identity-check.md).

Personal data under `~/.local/share/vinix-apps/ID` survives uninstall/rollback.
Launch captures the account home and each data-parent directory without following
links, and requires caller ownership without write access for other accounts.
Missing data parents are created privately. App data and its `tmp` child are
validated before their captured descriptors receive mode `0700`; symlinks,
special files, foreign ownership and shared writable modes refuse launch. This
prevents creation or permission changes through a planted app-data alias.
Existing contents survive a corrected-entry retry. See
[launch-data qualification](../tests/packages/launch-data-check.md).
After uninstall an ordinary user can explicitly erase it with
`vinix-package purge-data ID`. No package owns arbitrary home files. Data/schema
compatibility across rollback remains the developer's responsibility.

Purge holds the package reader lock through cleanup, refuses an installed app,
and checks every retained generation containing its ID for a live lease. The
check is conservative: another app using that same generation also prevents
purge. Stop those apps and retry. Reinstall and collection cannot race the
deletion. Missing personal data is a successful no-op.

The home and each `.local/share/vinix-apps` component must be ordinary directories
owned by the caller and not writable by other accounts. The deletion walk uses
directory descriptors, never follows links, checks directory identity before
removal and refuses filesystem crossings. Nested symlinks are removed as links;
their targets remain untouched. A symlink or special file used as the top-level
app data directory is refused. Storage errors, concurrent file operations or a
tree deeper than 64 directories can leave partial cleanup; correct the reported
problem and retry. See the [personal-data purge qualification](../tests/packages/purge-data-check.md).

Software’s **Personal data** page lists the current ordinary account’s retained
application directories, including IDs no longer present in a repository.
Installed apps require uninstall first. Unsafe directories show a diagnostic
and cannot be selected for deletion. **Review deletion** shows the exact ID,
scope and permanent-loss warning; **Delete permanently** starts cleanup without
an administrator password. The ID stays fixed through confirmation and retries.
Live-generation failures keep the confirmation available and explain what to
stop before retrying. A successful purge reloads the inventory. Root desktops
show a sign-in explanation and cannot choose another account’s data.

Inventory reads support **Stop reading**, Cancel and Escape. Stopped reads
discard unaccepted output and require a fresh reload before another deletion
review, including reads following a completed purge. The deletion result is
retained for the next successful reload. Small windows keep Back, reload,
confirmation cancellation and failure access; enlarge the window to review
the permanent-loss warning and confirm. Escape cancels an idle confirmation
or returns to the catalog. Approved deletions retain their close guard and
cannot be cancelled through these controls. See the
[personal-data navigation checks](../tests/packages/software-data-navigation-check.md).

**Read inventory** opens the shared read-only reader in full and compact windows.
It shows this account's retained-data count, application IDs, exact relative data
locations, installed state and complete inventory diagnostics. Next/Previous item
and Up/Down or Tab/Shift-Tab browse applications without wrapping; Next item
selects the first application from the initial overview. Empty inventories keep
the account-scope and retention explanations. Returning to a smaller full list
keeps the selected row visible, while same-size redraw preserves list paging.

A frozen deletion confirmation instead offers **Read review**, including its
exact ID/directory, permanent-loss warning, retained document grants and live
lease/state rechecks. Item navigation is disabled in that review. Reading cannot
delete, cancel, reload or open another application; Back/Escape returns to the
same inventory or confirmation. Pending inventory reads and approved deletions
cannot enter the reader. Confirmation remains on the full screen. See
[personal-data reader checks](../tests/packages/software-data-reader-check.md).

`vinix-package --json data-list` provides the same bounded, read-only inventory;
it uses installed state without refreshing repositories and works offline. The
inventory is an observation; deletion rechecks current installation, leases and
filesystem safety. Names that are not valid package IDs are outside this view.
No disk-size estimate or recovery promise is made for personal data. See the
[personal-data manager qualification](../tests/packages/personal-data-check.md).

## Software and execution

**Software** offers catalog, installed and updates filters, description search,
publisher/permission/license review, install/uninstall confirmation, repository
refresh, update-all, rollback, launch, progress and recent failure output. A running
mutation prevents normal window close. Mutations require administrator access;
there is no setuid service or automatic privilege escalation.
Its **Configured repositories** view remains available when cached indexes or
replay history need repair. Revocation still requires review and administrator
approval; the list does not repair metadata or enable acquisition.

Catalog, health and deployment-audit clipboard searches use the same bounded
insertion rule. Valid text is inserted literally, up to 256 UTF-8 bytes; controls,
malformed UTF-8 and overflow are refused as a whole with a diagnostic. Refusal
preserves the query, focus, selected text, result projection and page. Empty or
unfocused pastes do nothing. Pasted editing/navigation controls cannot blur a
search, cancel a proposal or stop verification. Reviews and writes ignore catalog
search pastes; ordinary catalog reads still permit searching, and keyboard
editing/navigation retains its existing guards. See
[search clipboard checks](../tests/packages/software-search-paste-check.md).

Empty clipboard events also preserve policy filenames, launch arguments and
pending file grants, administrator password bytes/masking, and native-window
input. Focus, selected text and native clean/edited state stay intact. An empty
paste cannot create an unsent native edit that blocks buttons or closing.
Keyboard deletion still clears fields; Enter can commit an explicitly cleared
native input as an empty protocol-2 text event. See
[empty clipboard checks](../tests/packages/software-empty-paste-check.md).

Compact health reports, deployment checks and saved-deployment receipts expose
**Read report** or **Read receipt** after a complete result has loaded. Their
shared reader shows complete provenance, integrity diagnostics, drift fields,
filenames, hashes and saved metadata limitations in short UTF-8 pages at 180×220
or larger. **Prev item**/**Next item**, Up/Down and Tab/Shift-Tab select packages
within the report's current search/filter projection. Left/Right and Page keys
turn pages; full-size views show the corresponding canonical page. Empty audit
results retain their source/summary disclosure, and empty saved deployments
retain their receipt; an empty health search has no selected package to read.
Resizing keeps the short-page anchor; tiny windows retain Back. Back or Escape
returns to the report with its query, filters and captured source/digest intact.
Repair, reconciliation, saving and offline export remain on their existing
screens. Pending reads and saves retain their lifecycle guards. See
[compact report qualification](../tests/packages/software-report-reader-check.md).

Pending install, uninstall, update, repair and rollback reviews support
**Stop review**, Cancel and Escape before changes start. Stopping reaps the
read-only worker and discards its proposal, fingerprint and unaccepted output;
catalog search, filter and selection stay intact for a fresh review. Completed
reviews support Escape and Cancel. Small windows retain review cancellation,
Back from package details, catalog reload, status, progress and failure access,
with confirmation available only in the full review. Approved transactions and
repository refreshes keep running until completion. See
[package navigation checks](../tests/packages/software-package-navigation-check.md).

The repository screen keeps Back, Stop, Cancel, status, progress and failure
access in small windows. Stop or Escape can cancel a pending configuration list
or trust review, reap the child and discard unaccepted output while preserving
the previous valid list and entered ID, URL and key. Review cancellation also
retires the proposal and fingerprint. Retry obtains a fresh review; compact
views never expose trust confirmation or bypass the complete URL review.
Approved enrollment, revocation and authenticated catalog refresh keep running
until they finish. A refresh failure still reports that trust was saved. See
[repository navigation checks](../tests/packages/software-repository-navigation-check.md).

Select a package and choose **Package details…** to read its complete overview,
description, repository/publisher key, permissions, license and diagnostics.
Each section has **Previous**/**Next** pages, including long UTF-8 text. Control
bytes appear as `\xHH`. Catalog and update details identify the displayed version
separately from installed launch permissions and native-window protocol; older
services report unavailable installed fields explicitly.
Installed package diagnostics follow the active dependency closure: revoked or
invalid publisher keys, permission restrictions, licenses, firmware policy and
version pins on a runtime are also shown against its dependent applications.
A pending update that removes or repairs a blocked dependency keeps the current
launch diagnostic until activation. Unrelated applications remain unaffected;
uninstall remains available. These are trust/policy diagnostics, not a payload
integrity scan or an application launch test.

The same button is available for each package in an install, uninstall, update,
deployment, rollback or offline-export review. It shows the reviewed operation,
role, generations and disk byte counts, plus deployment/export paths when
present. **Back to review** or Escape returns to the unchanged confirmation and
selection. Only navigation is active while details are open. See the
[package-details UI checks](../tests/packages/details-ui-check.md).

Package details remain readable in compact windows at least 180 pixels wide
and 220 high. Previous/Next changes short pages within the selected section;
Prev section/Next section changes the facts being shown. Left/Right and Page
keys navigate pages, Up/Down and Tab/Shift-Tab change sections, and Escape
returns to the same catalog or frozen review. Resizing keeps the short page
and its corresponding full page. Smaller windows retain Back. No confirmation,
application action or editable field is active in this view. See
[compact details checks](../tests/packages/software-details-navigation-check.md).

Prepared package, policy, health, deployment-check and saved-receipt pages now
render each line as a separate monospace label. This makes every prepared line
visible in the native renderer. Health and deployment-check side panels use
shorter UTF-8 lines for their minimum width; complete values continue across
pages. See [disclosure rendering checks](../tests/packages/software-disclosure-lines-check.md).

Warning and status paragraphs wrap into individual native labels, preserving
explicit line breaks and UTF-8 boundaries. Minimum-size checks cover complete
deletion, repository-trust, launch, saved-deployment and offline-export warnings,
plus publisher keys and permissions. Longer summaries visibly end with an
ellipsis; complete package and failure details remain in their paged views.
Administrator status no longer overlaps approval buttons at the smallest
supported prompt size. See [paragraph checks](../tests/packages/software-paragraphs-check.md).

Catalog replies now use a bounded typed reader. Missing/coerced flags, duplicate
known fields, partial installed launch metadata, incompatible architectures and
incoherent update actions are refused with a specific diagnostic. Software keeps
the previous valid view on refusal. Valid additive fields and complete older
installed-metadata shapes remain supported. Unicode search preserves case
matching, including characters whose lowercase spelling changes byte length,
and frees its temporary buffers. See
[catalog metadata checks](../tests/packages/view-metadata-check.md).

For an installed CLI application, **Launch in Terminal** opens an interactive
terminal inside Software. Type commands there; for SQLite, `.quit` exits and
reveals **Back to Software**. Keyboard input, paste, resize and bounded output
use the existing Terminal implementation. Normal window close and return wait
for the application to exit. Errors from the package service remain visible in
the terminal. The command runs directly through the package service and its
ordinary account session, with no intermediary shell or package-supplied command
text. [Terminal qualification](../tests/packages/terminal-check.md) covers the
UI lifetimes and real SQLite PTY execution on both supported hosts.

The progress display accepts fragmented frames, bounds incomplete lines and
ignores unsupported/malformed presentation events. It keeps human failure output
separately, so transfer updates cannot hide checksum, disk-space or authorization
diagnostics. Read-only JSON catalog/review replies use their existing protocol.

After a service failure, **Failure details** opens paged diagnostic output from
the status area. It keeps the latest failure across successful catalog reloads,
including long Unicode paths, the operation and exit status. **Previous**/**Next**
read the retained output; **Back** or Escape returns to the same form or review.
Package actions stay inactive while the details are open. **Clear failure**
discards this window's snapshot; another failure replaces it and closing Software
releases it. Output is bounded to 8 KiB of retained service bytes, with an explicit
notice when earlier output or oversized lines were omitted. Controls and invalid
UTF-8 bytes appear as visible escapes. The view writes no log file and does not
copy administrator password input. Terminal and native-window applications keep
their existing diagnostic views. See
[failure-details qualification](../tests/packages/software-failure-check.md).

Failure details can also be read in compact windows at least 180 pixels wide
and 200 pixels high.
Short pages preserve every retained diagnostic fragment, with Previous/Next,
Left/Right and Page Up/Page Down navigation. Enlarging shows the corresponding
full page; shrinking restores the current short page. Both views draw individual
monospace lines so native single-line labels cannot hide later diagnostic lines.
Smaller windows retain Back. See [compact diagnostic checks](../tests/packages/software-failure-navigation-check.md).

The Updates filter and `vinix-package updates` use the same complete dependency
resolution as `review upgrade`. They show runtime/data changes even when the
application's version stays unchanged, dependencies added or removed by an
update, same-version manifest/key changes and any version change required by
organization pins. Planned versions satisfy the full set of installed roots;
incompatible newer versions and another publisher's replacement of an installed
identity are not advertised as updates. Signed index expiry/sequence renewal
alone does not advertise an application update.

Each pending change offers **Review updates**, which reviews the complete
upgrade rather than making a dependency an explicit installation root. Repairing
an unchanged implicit dependency is also unavailable in Software; use **Update
all** to maintain it with its applications. Dependency removals remain visible
until the reviewed upgrade is applied. If resolution fails, Software shows
**Updates unavailable** with the resolver's reason and retains installed versions
and provenance. The `updates` CLI also returns a failure diagnostic. Catalog
entries for new applications show publisher metadata and still require full
installation review. Reading the view holds a package reader lock and neither
downloads objects nor activates a generation.

`vinix-package run ID [ABSOLUTE_DOCUMENT...]` executes as an ordinary user through
`vinix-sandbox`, failing closed if confinement is unavailable. Apps have private
data, temporary directories and Wine prefixes. Package/runtime paths come from
one immutable generation, with no implicit host Wine/Linux/Apple installation.
The environment is explicit and arguments are literal. `files` authorizes only
supplied documents. Display/audio paths are granted only when declared. See
[the sandbox's enforcement boundaries](../tools/sandbox/README.md).

For today's root desktop, an administrator can set `launch_user` to an existing
ordinary account in the root-owned configuration. Software shows **Launch as
NAME**. The service starts `vinix-session run --isolated NAME` and re-executes
itself after the session tool has verified all user/group IDs, cleared account
memberships and capabilities, and set `no_new_privs`. The ordinary service then
re-reads current trust/policy, acquires the generation lease, verifies payloads
and creates private data as that user. Root never creates or changes files in
the application data directory. The child's exit status and output reach Software.

Launch selects configuration under the reader lock. The ordinary child repeats
that read and acquires its generation lease before releasing the lock, closing
the gap between configuration loading and launch admission. Busy package writers
refuse launch promptly. Once admitted, a process retains its validated policy
snapshot and generation lease until it exits; later revocation prevents new
launches and does not terminate an already admitted application.

An empty `launch_user` requires the caller to be an ordinary user already.
Root/system/greeter accounts cannot be selected, and an ordinary caller cannot
use the setting to change identity. Create the account with the account tools
first; staging installs the session runner but does not invent an account or
enroll a publisher. Direct unprivileged launches need empty supplementary groups;
`vinix-session run --isolated USER /usr/bin/vinix-package run ID` supplies that
profile when invoked by an administrator. Documents must be accessible to that
account, including their parent directories.

This application session does not take the hardware seat or authenticate a
desktop login. Direct display/input/audio device access remains denied without
the seat, even when a package declares those permissions. Graphical runtimes
need a separately qualified display/audio broker. Native SDK apps can instead
declare signed `window_protocol:1` metadata and `display` permission. Software
then runs `run-window` through the same ordinary session and renders bounded
labels, buttons and rectangles from the application's standard output. Input is
restricted to current-frame button identities and a close request. The broker
grants no display/input device or X11 socket; its own window supplies presentation.
Start, Quick Launch and document requests select this mode from the installed
manifest, including when catalog metadata differs. Application data, trust and
policy remain enforced by the service. See
[native window SDK](../tools/packages/SDK.md#native-window-protocol-1) and
[qualification](../tests/packages/window-check.md). Signed `window_protocol:2`
adds bounded single-line UTF-8 fields with explicit Enter-to-send and
Escape-to-discard editing. Software binds field/button identities to each displayed
frame and refuses a protocol differing from installed metadata. The
[memo example](../examples/package-memo/README.md) keeps explicit Save behavior and
ordinary-account private data; [text-entry qualification](../tests/packages/window-input-check.md)
covers the codec, broker and both native guest workflows. Full ordinary-user desktop
login and graphical Linux/Windows/Apple/audio runtime brokers remain release work.

Every admitted package process receives the
[application-context interface](../tools/packages/SDK.md#application-context-interface):
installed ID/version, app/runtime directories and version, generation, publisher
provenance, private data paths and declared permissions. The V helper owns its
decoded fields and supports explicit retirement. New launches see their admitted
state; running apps keep their original context and lease through upgrade,
rollback, uninstall and garbage collection. The
[native SDK checks](../tests/packages/sdk-context-check.md) include the static V
example, actual ordinary-account execution and unchanged running snapshots.

Installed applications appear in Start's All Programs/search and Quick Launch.
Search includes package IDs and descriptions. Both use one bounded registry read
from an administrator-owned immutable generation; arbitrary XDG `Exec` commands
are not imported. Opening a launcher refreshes registration, so install/remove,
upgrade and rollback become visible without restarting the desktop. Runtime/data
packages are omitted. Package actions use stable IDs, independent of row order.

Registration admits complete, typed presentation fields and canonical positive
u64 generation identities. Missing/null collections, duplicate known fields
(including escaped spellings), invalid Unicode, counter overflow and incomplete
records are refused before replacing the menu snapshot. Other service-owned
state fields receive bounded syntax checks without retaining payload trees.
The desktop clears unavailable registration; fixing the generation permits a
normal refresh. The package service still checks full state, publisher trust,
policy and payloads when launching. See
[registration qualification](../tests/packages/registration-check.md).

Manifest permissions use the same SDK-1 set contract at packing, signed catalog
admission, retained-state validation, review, display and launch: each supported
grant appears at most once, with at most five entries. Source templates fail
before packing creates a workspace or copies payloads. Previously accepted
repeated grants could install and then fail the launch context; they are now
refused at admission. Valid manifests retain their canonical bytes and signatures.
See [permission-contract qualification](../tests/packages/permission-contract-check.md).

Files' application chooser opens the shared, paged **Open With** dialog. Packages
are offered only for their declared MIME types when they declare `files` access.
Installation never takes over user defaults. An explicit choice is saved as
`package.ID` in the session association store and used by Files, document search
and session document requests. Removal or loss of the MIME/file grant uses the
built-in fallback while retaining that preference for rollback or reinstall.

Each package launch opens a Software window and passes literal arguments to
`vinix-package run`; the service rechecks the current package/dependency closure,
publisher policy and payloads before sandbox execution. The window shows output
and launch failures, including missing or invalid launch-account configuration.
Closing it while the application runs is prevented to retain the generation
lease. This monitor is suitable for noninteractive programs and apps using their
declared display runtime; interactive terminal input still requires the CLI.
It does not turn the internal native compositor protocol into a public GUI SDK.

Install, uninstall, Update all and Rollback first request a read-only review of
the complete resolved package set. The paged review shows additions, version or
payload changes, retained packages and removals, including implicit runtimes and
data. Each row exposes its description, old/new version, architecture, runtime,
publisher/key, license/proprietary/firmware flags and declared permissions. A
summary shows estimated next-generation/cache space, available space and the
configured reserve. Confirm appears only after a valid matching review arrives;
Cancel releases the review without changing the installation.

Confirmation passes the review fingerprint and original operation/IDs to the
service. It recomputes the plan under the writer lock and rejects changed state,
policy, provenance or payload metadata before cleanup, acquisition or activation.
A stale review returns a diagnostic and requires a new review. Ordinary CLI
maintenance remains compatible; fingerprints add a freshness check for graphical
and SDK clients, and administrator access is still required. Failed dependency
resolution and unsupported review responses leave Confirm unavailable.

Non-data/non-runtime packages also get `.desktop` launchers with MIME types,
package ID and runtime provenance. `/usr/share/applications/vinix-packages` points
through activation, so XDG registration removal/rollback follows package state.
Ordinary sessions can execute packages using the CLI or an XDG-aware launcher.

## Offline and organization deployment

```sh
vinix-package mirror /media/new-mirror editor browser
vinix-package --offline install editor
vinix-package deploy /etc/company/applications.json
```

Mirror exports signed indexes and the resolved payload closure. On the offline
machine use `repo-enroll REPOSITORY_ID file:///media/new-mirror/REPOSITORY_ID KEY`
with the same ID/key, then `update`. Expiry and sequence checks still apply;
publishers must plan suitable expiry for offline use. Indexes may advertise apps
outside the exported closure; those requests report missing payloads.

Software's **Export offline** action exports the selected catalog package,
all explicitly installed application roots, or an organization deployment lock,
with their dependencies. The catalog scopes
resolve current authenticated catalog versions under organization policy;
installed versions and personal data remain unchanged. Enter a new absolute
directory on local disk or mounted media, review the complete destination path
(long paths are paged), then review every package's publisher, permissions,
license and runtime before confirming. Destination requirements include missing
cache objects when both paths share a filesystem. A separate cache filesystem
has its own requirement and the same reserved-space policy. Export progress and
failure diagnostics stay visible, and the window remains open during export.

Small export windows retain status, progress and failure diagnostics, with Back
for the destination form, Cancel for a completed review, and Back to review from
package details. Pending read-only reviews offer **Stop review**; Stop, Cancel or
Escape reaps that worker and discards its output while preserving the chosen
destination and any saved-source pin for a fresh review. Approved exports keep
running until completion. Compact windows omit confirmation controls so paths
and package facts can be inspected after enlarging the window. See
[navigation qualification](../tests/packages/software-mirror-navigation-check.md).

Deployment-file, export-destination and deployment-lock path fields treat paste
as filename data. Controls, malformed UTF-8 and input exceeding 4096 bytes are
refused as a whole, preserving focus, selection and the previous path. Empty or
unfocused pastes do nothing. Pasted Escape cannot cancel a frozen proposal or
stop its reader; pasted Enter, select-all and backspace cannot act as keys.
Keyboard editing and cancellation remain available. Saved deployment sources
stay fixed while their export destinations remain editable. The save form uses
the same literal path insertion. See
[distribution path checks](../tests/packages/software-distribution-paste-check.md).

Cycle the scope button to **Organization deployment lock** to preserve exact
approved versions, including older runtimes. Enter the absolute path of a
nonempty format-2 lock; this works without an installed application set or catalog
selection. The details screen pages the complete destination, source filename
and SHA-256 before opening package review. Confirm uses the reviewed literal
paths and fingerprint even if form storage changes. The service checks the
document and other bound inputs again before exporting; a stale review reports
the failure and requires another review. Successful media includes the exact
document as `_deployment.json`. Export preserves the installed generation and
personal data. See [Software locked export qualification](../tests/packages/software-locked-mirror-check.md).

Administrative clients use `mirror-review NEW_DIRECTORY ID...`, then
`mirror-apply FINGERPRINT NEW_DIRECTORY ID...`. Review reads authenticated cached
metadata without creating destination parents, fetching payloads or altering
installed state. Confirmation binds the original destination argument, resolved
path, existing ancestor inode/filesystem, requested IDs, complete resolved set,
configuration and exact signed indexes. Changed media, catalog renewal, publisher
trust or policy requires a new review before acquisition or staging. Free space
and verified cache availability are checked again when applying; a failed export
can reuse the same review if those bound inputs still match. `--progress` also
works with `mirror` and `mirror-apply`. The direct `mirror` command remains useful
for authorized automation.

Export requires a new destination. The service checks space for unique objects,
metadata and policy reserves on the destination disk and for missing source-cache
objects; when both paths share a disk it budgets both copies together. It builds
an exclusive `.vinix-mirror-*` sibling directory, verifies copied sizes/hashes,
sets readable metadata/object modes, flushes the tree and publishes it with an
atomic rename that refuses to replace any existing name. Filesystems without
exclusive atomic rename support report a failure and leave the final name absent.
Normal failures clean the staging tree and retain verified cache/partial downloads
for retry. Abrupt termination may leave a hidden staging directory; after the
export process has stopped, an administrator may remove that specific directory.
A retry builds fresh staging data from authenticated metadata and verified cache;
it never imports abandoned staging data or sweeps other exports. A directory-flush
failure after publication reports that the complete mirror exists but its storage
durability needs checking. Keep media attached until export finishes.
Before flushing and after the final staging checkpoint, the service admits the
complete export again: exact signed index/signature and deployment-lock bytes,
the selected object set and its hashes, ordinary single-link files and readable
final modes. Unexpected entries or changed data refuse before publication and
completion. See [mirror admission checks](../tests/packages/mirror-admission-check.md).
The destination's resolved ancestors must belong to root or the invoking
administrator. Shared writable ancestors need the sticky bit (as `/tmp` has), so
another user cannot replace the staging path while an administrator writes it.

Organization policy restricts the complete dependency closure through `allowed`,
version `pins`, permitted `permissions` and accepted proprietary `licenses`.
Firmware is blocked unless `allow_firmware` is explicitly set; packaging does not
flash hardware. Apps cannot grant themselves policy or accept their own license.

Use the supported policy commands to serialize administration with package
operations:

```sh
vinix-package policy
vinix-package policy-review /etc/company/package-policy.json
vinix-package policy-apply REVIEW_FINGERPRINT /etc/company/package-policy.json
```

A format-1 policy document declares the host architecture and all seven policy
fields explicitly. For example:

```json
{"format":1,"architecture":"aarch64","policy":{"offline":true,"allowed":["editor","editor-runtime"],"pins":[{"id":"editor","minimum":"1.0.0","before":"2.0.0"}],"permissions":["files","display"],"licenses":[],"allow_firmware":false,"reserve_bytes":67108864}}
```

`policy` exports a canonical document from persistent configuration; `--offline`
does not alter that output. Review shows the previous/proposed settings and all
installed packages, including runtimes, licenses, firmware flags and publisher
identity. Before/after diagnostics follow each package's dependency closure, so
a denied runtime is reported against the applications that need it. Neither
catalog access nor network downloads are required. A fresh-image review does not
initialize the store.

Apply binds the complete configuration, installed state and canonical proposed
policy to the review fingerprint, rechecks them under the writer lock and saves
only policy through a flushed temporary file and atomic rename. Changed trust,
launch account, installation or proposal requires another review. Repository
keys, launch account, architecture, generations, cached objects and personal data
are preserved. Restrictions take effect for subsequent launch/maintenance;
already admitted applications retain their launch snapshot. Uninstall stays
available under restrictive policy. This does not reconcile installed roots or
activate a package generation; use a separately reviewed deployment afterward.

In Software, open **Deployment → Organization policy** to browse the active
offline setting, allowed IDs, version pins, permitted permissions, accepted
proprietary licenses, firmware permission and disk reserve. Empty allowlists are
unrestricted within trusted publishers; empty permission/license lists permit
no grants/accept no proprietary licenses. These meanings are shown explicitly.

Enter an absolute policy file path and choose **Review policy**. The review
starts with the complete frozen filename; browse each settings category to
compare previous and proposed values, and **Installed-app effects** to inspect
every installed package’s provenance, license/firmware flags and before/after
diagnostics. Long values remain available across pages. **Confirm policy** uses
the exact file and fingerprint through the existing administrator approval
transport for ordinary sessions. Read and review need no password. Cancellation
before approval writes nothing. Apply failures invalidate the displayed policy
and require reload/review; success reloads persistent settings. Normal window
close is blocked while an approved change runs. Policy changes retain installed
packages and personal data; a deployment is a separate reviewed action. See the
[policy manager qualification](../tests/packages/policy-ui-check.md).

Pending policy reads and reviews support **Stop**, Cancel or Escape, which reap
the read-only worker and discard unaccepted output and proposals. The literal
filename survives for fresh retry. A stopped review returns to the known current
policy; a stopped reload requires a fresh read before another review, including
after a successful save. Small windows retain Back/Stop/Cancel, status, progress
and failure access without exposing confirmation. Resizing preserves review
sections and pages. Approved saves keep running until they finish, and stopping
their subsequent read-only reload preserves the saved result. See
[policy navigation checks](../tests/packages/software-policy-navigation-check.md).

Once a policy or review has loaded, compact windows offer **Read policy**.
Its read-only disclosure shows complete current/previous/proposed settings,
source filenames and installed-app effects. At 180×220 or larger, short UTF-8
pages include canonical headings and preserve every prepared value; separate
monospace line labels keep them readable in the native renderer. Previous/Next
turn pages, and topic controls or Up/Down/Tab/Shift-Tab move between available
categories without wrapping. Left/Right and Page keys also turn pages. Resizing
keeps the short page and its canonical full-page anchor. Smaller windows retain
Back. Back or Escape returns to the unchanged current policy or frozen review;
only disclosure navigation is active while the reader is open. Confirmation
remains on the full policy review, and pending readers/approved saves retain
their existing Stop/close guards. See
[compact policy qualification](../tests/packages/software-policy-reader-check.md).

Documents reject missing/null fields, type coercion, malformed version ranges,
unknown/duplicate object keys (including escaped spellings), duplicate entries/pin
IDs and unknown permissions. Keys are checked independently in the document,
policy and each version-pin record; JSON-looking license text remains ordinary
text. Policy review responses require explicit proprietary/firmware flags and
before/after diagnostics for every installed package, so an incomplete disclosure
cannot silently appear unrestricted. Allowlists, pins and accepted
licenses are limited to 4096 entries, permissions to the five named grants and
disk reserve to 1 TiB. Lists are sorted for reproducible review identity; input
order is immaterial. Existing configurations with duplicate policy entries must
be corrected before use. License acceptance and firmware permission are explicit
administrator choices; no package or per-command option adds them implicitly.

A format-1 deployment manifest reconciles the requested roots atomically and
selects the latest satisfiable packages in the authenticated catalog:

```json
{"format":1,"architecture":"aarch64","packages":["editor","browser"]}
```

Use `deployment-review FILE` and `deployment-apply REVIEW_FINGERPRINT FILE` to
review the complete installation/removal and disk requirements before activation.
Review is bound to the canonical document, current configuration, installed state
and resolved closure; edits or completed administration require another review.
Both commands take the package lock before loading their inputs. `deploy FILE`
remains available for administrative scripts and validates the same document.
Documents require explicit fields/types, matching architecture and unique roots;
missing/null/coerced fields, unknown/duplicate keys and unsafe metadata files fail.

In **Software**, select **Deployment**, enter the absolute file path and choose
**Review deployment**. The review shows the entire resulting set, including
dependencies, runtime updates, retained packages and removals, with publisher
keys, permissions, licenses, firmware flags and disk requirements. Confirm uses
the reviewed file path and deployment fingerprint through `deployment-apply`;
editing the form cannot redirect a confirmation. Changed document contents,
trust, policy or installed state require another review. A successful transaction
returns to the catalog; failures retain the file path and show service diagnostics
for retry. Cancel only discards a review, before changes begin. An empty deployment
explicitly removes the complete installed package set while retaining personal
data. The workflow also accepts approved offline deployment locks after their
repositories and policy have been configured.

To reproduce an approved application/runtime set across machines, export a
format-2 deployment lock rather than resolve names again on every installation:

```sh
vinix-package deployment-lock editor browser > /etc/company/deployment.json
vinix-package deployment-review /etc/company/deployment.json
vinix-package deployment-apply REVIEW_FINGERPRINT /etc/company/deployment.json
```

Without IDs, `deployment-lock` exports the current requested roots, preferring
installed versions that remain authenticated. With IDs, they replace that root
set. It records every dependency/runtime with exact version, architecture,
repository ID, publisher key, minimum signed sequence and a digest of the complete
package manifest. Installation requires those exact manifests in the current
authenticated catalog; payload bytes remain checked against their signed hashes.
Newer signed indexes may retain those manifests, but changed launch metadata,
permissions, license or payloads under the same version are rejected. Missing
dependencies, unrelated locked packages and publisher substitutions fail before
downloads or cleanup. The usual policy/version/architecture/runtime checks apply;
the lock grants no permissions, license acceptance or firmware approval.

For offline deployment, export the exact locked payload closure with
`mirror-deployment-review NEW_DIRECTORY LOCK.json`, then confirm with
`mirror-deployment-apply FINGERPRINT NEW_DIRECTORY LOCK.json`. The review has
the same publisher, license, permission and disk disclosures as a catalog mirror,
and includes the literal lock filename and its SHA-256. It accepts a nonempty
format-2 lock and resolves only its authenticated package/runtime pins, even
when a newer version is advertised. Confirmation binds exact lock bytes, filename,
signed indexes, policy and destination before acquisition or parent creation.
The lock is captured once, copied byte-for-byte as `_deployment.json`, and
published atomically with the verified repository payloads. The leading underscore
cannot collide with repository identifiers, including on case-insensitive media. `--progress` is supported.
The installed generation remains unchanged.

Enroll the mirror with the recorded publisher ID/key, refresh its signed index,
then review/apply the media's `_deployment.json`. URLs are not pinned, so approved
mirrors can move;
publisher identities, metadata, expiry and anti-replay checks still apply. Keep
the approved versions available in the signed index and mirror. Cached payloads
alone cannot substitute for an authenticated, unexpired catalog.

Deployment does not change trust/policy or refresh repositories implicitly. An
unchanged set needs no new generation; an explicit empty set removes all roots.
Rollback and data retention use the normal transaction history. Runtime updates
are ordinary signed packages in a newly reviewed lock or upgrade/deployment
closure; no background updater is introduced.

## SDK and qualification

[SDK 1](../tools/packages/SDK.md) defines reproducible metadata, signing,
publishing, format and launch interfaces. The
[V fixtures](../tests/packages/distribution-check.v) exercise real filesystem
transactions, signatures, resolution, recovery, rollback, publisher tooling and
Software controls, registry trust/retirement, shared launchers and document
associations, plus both package target builds and desktop configurations.
Allocator fixtures check menu redraws, registration decoding/refusal/retirement
and cached reads for zero retained storage. Registration no longer uses the
generic JSON decoder's historical EOF-marker allocation allowance. Software
review ownership is covered by the review metadata checks below.
Service and CLI fixtures check complete dependency disclosure and rejection of
changed catalogs, policy, active state or operation/IDs before acquisition.
Repository administration fixtures cover invalid enrollment, preserved policy,
revocation with corrupt metadata, key rotation, mirror changes, legacy expiry
migration, retained replay/equivocation floors after empty refresh, and recovery
from history published ahead of the catalog. Unsafe configuration and predictable
temporary-file symlinks are also covered.
Trust-review fixtures check read-only previews, exact signed-metadata and policy
binding, sequence-floor changes, changed operation/intent, replaced-key revocation
refusal and reviewed revocation with corrupt/unreachable metadata. Repository UI
fixtures check key editing, frozen intent, URL paging, cancel/confirm, stale and
invalid responses, successful revocation and saved-trust/failed-refresh diagnostics.
Allocator checks measure repository form/review redraw, status/review replacement
and retirement against the independent JSON decoder baseline.
Software view fixtures additionally check dependency-only upgrades, new/removed
dependencies, constrained version selection, policy/key changes, blocked plans
and retained publisher ownership. UI checks exercise complete upgrade review
from each pending row and prevent accidental dependency-root promotion; allocator
checks cover redraw, decoded view replacement and repeated blocked-plan status.
Package/trust/offline-export confirmation metadata now uses complete bounded
schema readers. False proprietary/firmware/requested flags, empty fields and zero
counters must be explicit. Missing, unknown, duplicate or incorrectly typed
fields, malformed Unicode and integer overflow refuse confirmation, including
inside nested deployment-export reviews. Reader and Software lifecycle checks
retain zero tracked bytes across 1000 valid/partially invalid decode, redraw and
retirement cycles; historical generic-decoder allocation allowances no longer
apply to these reviews. See [qualification](../tests/packages/review-metadata-check.md).
Service fixtures check configuration reads after lock acquisition, policy changes
invalidating review before acquisition/cleanup, revocation denying rollback/mirror
export, offline overlays, architecture changes and refusal of unsafe lock links.
CLI and guest fixtures check busy-writer diagnostics before decoding a corrupt
configuration and reject tampered payloads even with `--json verify`.
Policy fixtures cover complete strict documents, reproducible review identity,
runtime denial propagation, license/firmware disclosure, atomic policy-only
publication, stale configuration/state/proposal refusal, administrator ownership,
busy locks and uninstall under restrictions. CLI/guest checks apply and restore
policy and reject ordinary-user policy writes.
Mirror fixtures cover unique-object space estimates, failed acquisition cleanup,
same-size copy corruption, existing files/directories/dangling links, a destination
created immediately before publication, and abrupt process exit followed by a
cache-only retry. CLI and both Linux guests consume signed offline closures on
clean stores; guest checks include readable objects under ordinary credentials.
Publisher release fixtures cover reproducible all-architecture metadata,
per-version dependency closure, explicit consumer license/firmware restrictions,
private seed/state exclusion, space preflight, changed copies, writer exclusion,
existing/raced destinations and interrupted publication with retained sequence
history. CLI and both Linux guests install complete signed release output into
clean offline stores. `publish-release` is the supported complete-release command;
the legacy `publish` command still writes workspace metadata separately.
The [accounts guest suite](../tests/accounts/README.md) adds a `packages` scenario
for signed installation, the root-to-account handoff, literal documents,
user-owned data, publisher revocation and uninstall. Its sandbox substitute
observes the exec boundary; it does not qualify pledge/unveil or GUI runtimes.

The [production-sandbox guest check](../tests/packages/runtime-check.md) signs
native applications and an explicit runtime dependency, installs them with the
real CLI and launches through the staged native `vinix-sandbox`. It checks
private-data writes, literal document grants, denied reads outside those grants,
read-only application/runtime files, network and process permission enforcement,
and rejection of modified application/runtime payloads. While an app is running,
it upgrades the app/runtime, uninstalls them and collects garbage: the leased old
payload closure stays readable until the app exits, after which it is collected
and personal data remains. Passing retained runs include artifact hashes.

This checks the native package launch contract on both architectures. A socket
creation check does not qualify network services; the explicit native fixture
runtime does not qualify Linux, Wine, Mach-O or graphical API compatibility.
The guest root is an initramfs, so these runs do not qualify persistent-device
power-cut durability.

Publishers can now use `vinix-package pack-root` with explicit source/destination
selectors to import a verified prepared guest root. It materializes library and
directory symlinks within the captured guest namespace, rejects escapes/cycles
and special files, and emits the same canonical regular-file package inventory.
Upstream authentication, redistribution permission and the explicit runtime
dependency closure remain publisher responsibilities. License documents,
proprietary/firmware declarations and runtime updates remain visible in signed
metadata and organization policy; no upstream install scripts run.

The [dynamic Linux qualification](../tests/packages/linux-runtime-check.md)
packages a target musl loader, the static SDK runner and a shared V library as an
explicit runtime. A dynamically linked ELF application uses that loader and the
signed closure's `lib`/`usr/lib` directories through the production sandbox.
The fixture checks ordinary identity, literal arguments, private-data writes,
hidden host paths, runtime tamper refusal, missing-library diagnostics, rollback
and removal of the unused runtime with personal data preserved. It also checks
CLI enrollment/revocation, launch/rollback denial after revocation, replay refusal
after an empty refresh, re-enrollment without changing installed state, and a
runtime-only update appearing in both the Software JSON view and CLI Updates. It
qualifies the loader/package contract; individual upstream applications and graphics
services still require their own coverage.

The [persistent-storage recovery check](../tests/packages/persistence-check.md)
adds a real ext2 volume and abrupt QEMU SIGKILL/reboot cycles at the staged,
published and activated transaction checkpoints. It verifies the old/new active
set, partial-object/cache recovery, offline upgrade, rollback, removal,
registration and personal-file metadata. The same volume survives both boots;
the host neither restores package state nor repairs the filesystem. These
completed checkpoints passed on both targets; interruptions inside filesystem or
device operations and physical write-cache loss remain outside this fixture.

The release gate remains open: enroll a release publisher, migrate/qualify the
advertised native/Linux/Wine/Apple catalog, integrate ordinary-user graphical
sessions, qualify wider filesystem/device crash windows and measure wider
runtime sandbox profiles. Apple packaging does not provide general macOS/AppKit
compatibility; Windows/Linux packaging does not expand runtime API coverage.
