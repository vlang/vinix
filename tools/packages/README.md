# Native V application packages

Build with `v -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/vinix-package tools/packages/main.v`. Install/state commands
support a disposable `--root /absolute/root`. Launch uses the real root and an
ordinary identity. The root desktop can hand off to an administrator-configured
`launch_user` through the isolated account session runner.

An ordinary caller with account groups automatically uses the fixed
`packages-launch` account action to strip them before launch. It preserves the
caller's identity and existing standard streams, including terminals and native
window events. The installed service rechecks package admission after that
handoff. See [ordinary launch qualification](../../tests/packages/isolated-launch-check.md).

Both desktop builders use the existing native security-tools staging path.
Standalone staging and qualification are also available:

```sh
v run tools/packages/stage.v --arch aarch64 --staging /path/to/root
v run tools/packages/stage.v --arch x86_64 --staging /path/to/root
v run tests/packages/distribution-check.v --cross --desktop
```

Desktop checks need generated examples under `build/app-src` and a headless ui2
overlay under `build/vmodules`; `VINIX_PACKAGE_TEST_UI2` selects another overlay
parent. Package implementation, publishing, staging and qualification use V.
The driver also accepts `--direct-tests` to compile/run each existing assertion
runner directly when the compiler's cached `vtest` tool cannot run. These runners
retain declarations to avoid pruning required crypto types. The launcher heap
fixture disables the compiler's crash handler in its separately linked C unit;
assertions and process exit failures still fail the check.

`--https` adds the [real TLS transport fixture](../../tests/packages/https-check.md);
`--https-only` runs it without desktop/UI prerequisites. It uses native curl and
OpenSSL to check range recovery, certificate/redirect refusal and signed
transaction state. The fixture binds only to loopback and uses a temporary CA.

Software's **Failure details** pages through the latest bounded service failure,
including long paths and exit status. It survives catalog reloads until another
failure, explicit clearing or window close. The view is read-only and marks
omitted output. See [qualification](../../tests/packages/software-failure-check.md).

Compact failure views at least 180 pixels wide and 200 high show short pages with
Previous/Next and arrow/Page-key navigation. Resizing retains the short page and
its corresponding full page. Both views use individual monospace line labels;
smaller windows retain Back. See [navigation qualification](../../tests/packages/software-failure-navigation-check.md).

Package details, policy disclosures, health reports, deployment checks and saved
receipts also render every prepared line as an individual monospace label. Narrow
report panels paginate shorter UTF-8 fragments so complete provenance, paths and
diagnostics remain available. See [disclosure checks](../../tests/packages/software-disclosure-lines-check.md).

Repository proposals offer **Read review** through the same reader. Compact
windows disclose complete current/previous source URLs, publisher keys,
fingerprint, authenticated catalog metadata and trust/revocation effects.
Reading neither approves trust nor advances the existing source URL review
gate; return to the full proposal to cancel or confirm. Pending work blocks
entry. See [qualification](../../tests/packages/software-trust-reader-check.md).

Personal-data inventories offer **Read inventory**, with item navigation for
complete IDs, installed state, account-scoped locations and diagnostics. Frozen
deletion confirmations offer **Read review** for their exact target and loss
warnings. The reader cannot delete, cancel or reload; return to the full screen
to review or confirm deletion. Root desktops and pending work cannot enter it.
See [qualification](../../tests/packages/software-data-reader-check.md).

Compact **Package details** windows at least 180 pixels wide and 220 high now
show complete short pages and Previous/Next section controls. Left/Right and
Page keys turn pages; Up/Down and Tab/Shift-Tab change sections. Resizing retains
the short page and its corresponding full page. Smaller windows retain Back.
This applies to catalog facts and frozen install, remove, update, repair,
deployment, rollback and offline-export reviews. See
[compact detail checks](../../tests/packages/software-details-navigation-check.md).

Software's warning and status paragraphs also use individual wrapped lines.
Deletion, trust, launch and restore explanations fit their minimum full-window
frames; long keys and paths can split within a word. Oversized summaries show an
ellipsis, and administrator status stays below the approval controls. See
[paragraph checks](../../tests/packages/software-paragraphs-check.md).

Catalog, health and deployment-audit searches accept clipboard text as a whole
within 256 UTF-8 bytes. Controls, malformed text and overflow preserve the query,
focus, selection and current results, with a diagnostic. Empty or unfocused
pastes do nothing. Clipboard text cannot trigger keyboard navigation or cancel
reviews; ordinary keyboard editing and search during catalog reload remain
available. See [search input checks](../../tests/packages/software-search-paste-check.md).

Empty clipboard events also leave policy filenames, launch arguments, pending
file grants and administrator passwords unchanged, including their selection.
Native application fields keep their current clean/edited state, so an empty
paste does not create an unsent edit or block closing. Keyboard deletion still
clears fields, and Enter can send an explicitly cleared native field. See
[empty-paste checks](../../tests/packages/software-empty-paste-check.md).

Compact organization-policy screens offer **Read policy** after a successful
read or review. The reader shows complete settings, source filenames, licenses
and installed-app effects in short UTF-8 pages, including previous/proposed
headings. Left/Right and Page keys turn pages; Up/Down and Tab/Shift-Tab change
topics. Back or Escape returns to the same policy or frozen review. Resizing
retains the short-page anchor; tiny windows retain Back. See
[policy reader checks](../../tests/packages/software-policy-reader-check.md).

Compact health reports, deployment checks and saved-deployment receipts offer
**Read report** or **Read receipt** for their loaded metadata. The shared reader
shows complete short UTF-8 pages; item controls and Up/Down/Tab/Shift-Tab walk
the current filtered package results. Left/Right and Page keys turn pages.
Back or Escape returns with the report, query and source/digest intact. Resizing
retains the short-page anchor, and tiny windows retain Back. See
[report reader checks](../../tests/packages/software-report-reader-check.md).

**Verify installed** supports Stop/Cancel/Escape in full and compact windows.
Stopping retires unaccepted progress/output and keeps the catalog for retry.
Completion and human success output wait for successful worker exit; late
failures retain their diagnostics. Verification frames from transactions or
running apps do not make those operations cancellable. See
[navigation checks](../../tests/packages/software-verify-navigation-check.md).

Software's **Health report**, also available as `vinix-package [--json] health`,
inspects every installed app, runtime and data dependency. It lists all affected
packages with installed provenance and paged diagnostics, even when catalogs are
unavailable. Search matches installed metadata and diagnostics, and **Issues only**
filters the loaded snapshot. Reload retains these controls; returning preserves
the catalog search and selection. See [search/filter qualification](../../tests/packages/health-search-check.md).
A complete report returns zero with issues recorded in its rows;
`verify` retains its failure exit behavior. **Review all repairs** obtains a fresh
authenticated repair proposal before authorization. See
[qualification](../../tests/packages/health-report-check.md).
During inspection, Software shows the current package and offers **Stop
inspection**, including in a small window. Stopping discards the partial report
and permits Reload. CLI clients can use `--json --progress health` to receive the
unchanged JSON on stdout with live progress on stderr. A complete report still
requires a successful process exit. See
[progress/cancellation qualification](../../tests/packages/health-progress-check.md).

Compact Health reports retain Reload, status, progress, failure access and the
generation summary when space permits. Resizing preserves the search, filter,
selection and detail page. Cancel, Stop inspection and Escape discard an
unaccepted scan and permit a fresh read. Completed checks remain provisional
until service exit. See [navigation checks](../../tests/packages/software-health-navigation-check.md).

Launcher verification now captures and rechecks the generation’s `share` and
`applications` directories, so identical files reached through aliased or unsafe
parents fail integrity checks. Health identifies the affected apps; reviewed
offline repair rebuilds their registration in a fresh generation. Ordinary launch
checks registration before preparing private data or running a program. See
[qualification](../../tests/packages/launcher-parent-check.md).

**Clean up versions** reviews obsolete generation IDs and retains the active,
rollback and running versions. Only **Delete listed versions** authorizes removal,
using the exact review fingerprint through the administrator transport. A changed
eligible set or filesystem identity requires Reload and fresh confirmation.
Cached downloads, interrupted stages and personal data are retained. CLI clients
use `cleanup-review` and `cleanup-apply FINGERPRINT`; broader administrator `gc`
still collects caches/stages. See
[reviewed cleanup qualification](../../tests/packages/reviewed-cleanup-check.md).

Cleanup reviews support Stop/Cancel/Escape before deletion. Small windows keep
Back, reload, status and failure access; confirmation remains in the full view.
Resize keeps the first visible generation. Stopped or failed post-cleanup reads
retain the completed result until a successful review reload; approved deletion
remains protected. See [navigation checks](../../tests/packages/software-cleanup-navigation-check.md).

Rollback restores the previous package set in a fresh generation and retains
the set it replaced, so cleanup cannot strand its rollback link. It uses verified
local source files without cache or repository access, checks the disk reserve,
and leaves personal data intact. Another rollback undoes the restoration.
`review rollback` identifies the source in `target_generation`; read `status`
for the new active identity. See
[qualification](../../tests/packages/rollback-check.md).

Start, Quick Launch and Open With use bounded installed-state presentation
decoding with complete fields, explicit ownership and canonical generation
identities. Damaged metadata is refused before menu replacement; restoring it
permits refresh. See [registration qualification](../../tests/packages/registration-check.md).

Package permission lists now use the SDK's bounded set contract throughout
packing, publishing, installation, presentation and launch. Repeated or excess
grants are refused before a new package can install and fail its launch context.
See [permission qualification](../../tests/packages/permission-contract-check.md).

Package state locks and launch generation leases reject special files and busy
holders with diagnostics. FIFO replacements cannot hang status, transactions or
launch admission; restoring a sound lock/lease permits retry. See
[coordination qualification](../../tests/packages/coordination-check.md).

Stored generations require complete manifests and provenance, including explicit
false flags, empty lists and dependency bounds. Damaged current or rollback
metadata refuses dependent operations before cleanup; restoring trusted records
permits retry. See [stored-state qualification](../../tests/packages/state-schema-check.md).

Launch, inventory and purge share account-home directory checks. Launch creates
private app data and temporary directories without following aliases or changing
an alias target's permissions. Unsafe entries fail with diagnostics and remain
available for correction. See [launch-data qualification](../../tests/packages/launch-data-check.md).

Space checks use filesystem allocation units and reject invalid or overflowing
reports. The V [space qualification](../../tests/packages/space-check.md) covers
differing I/O/allocation sizes through the production function; run
`v run tests/packages/space-check.v` (`--sanitize` adds ASan/UBSan).

Use `publish-release REPOSITORY_DIR ID SEED_FILE SEQUENCE EXPIRES_UNIX NEW_DIRECTORY`
to emit a complete signed consumer repository with atomic publication, dependency
closure validation on each declared architecture and retained publisher sequence
history. The legacy `publish` command remains available for workspace metadata.

Read [administration/recovery](../../docs/application-distribution.md) and
[SDK 1](SDK.md) for enrollment, policy, packaging and limits. Release publisher
enrollment and catalog/runtime guest qualification remain required.

Software's **Clean up versions → Read review** presents the complete admitted
generation list, fingerprint, retained current/rollback identities and deletion
rules through the shared reader, including compact windows. Back/Escape keeps
the list position; reading cannot confirm deletion or reload the proposal.
Pending work blocks reader entry. Confirmation remains on the full review.
See [qualification](../../tests/packages/software-cleanup-reader-check.md).

`deployment-snapshot [INSTALLED_ID...]` exports exact installed app/runtime/data
metadata as an existing format-2 deployment lock, including when catalogs are
unavailable or a publisher was revoked. It preserves installed versions instead
of selecting replacements. Applying the document still requires authenticated
repository metadata and current policy approval; it contains no payloads or
trust enrollment. See [qualification](../../tests/packages/deployment-snapshot-check.md).

`deployment-snapshot-save NEW_FILE [INSTALLED_ID...]` captures the same exact
installed metadata and saves it atomically to a new file. Existing files,
symlinks, directories and racing destinations are preserved. `--json` returns a
closeable receipt with the captured generation, architecture, literal destination,
SHA-256 and root/package counts after publication and directory flush succeed.
The file contains no payloads, private data or trust enrollment. A failure after
publication explicitly reports that the file was saved and needs inspection;
retry never overwrites it. See [qualification](../../tests/packages/deployment-save-check.md).

Software's **Deployment → Save installed…** saves the complete installed set to
a new absolute filename as the ordinary user. It waits for publication, displays
paged receipt details and offers fresh installed checks or deployment review
using the captured filename. A pending write blocks Back and window closing;
failure details preserve diagnostics even when publication already occurred.
See [Software qualification](../../tests/packages/software-deployment-save-check.md).

The save form refuses pasted controls without executing editing or navigation
commands. Escape first leaves a focused filename field, then returns to
Deployment. Compact windows retain status and failure access without discarding
drafts or receipt paging. Partial and complete receipts cannot release an active
writer's navigation/close guard. See [navigation checks](../../tests/packages/software-snapshot-navigation-check.md).

The saved receipt's **Export offline…** action opens a locked export for the
captured filename and digest, with an empty new-destination field. It checks that
the source still matches, authenticates the exact package/runtime set, and
requires the full export review and administrator approval. A receipt alone
cannot authorize payload acquisition or publication. Empty snapshots have no
payload export. See [qualification](../../tests/packages/software-snapshot-export-check.md).

Offline export retains navigation, status, progress and access to failure
details in small windows. Read-only reviews can be stopped before publication;
approved exports continue until they finish. Canceling preserves the selected
destination and saved-source identity for a fresh review. See
[qualification](../../tests/packages/software-mirror-navigation-check.md).

Loaded offline export proposals offer **Read review** in full and compact
windows. It discloses complete destination/source paths and digests, target,
fingerprint, package counts and exact disk/cache requirements. Reading keeps
the frozen intent and path/package stage, and cannot advance required path
parts or approve publication. See
[reader qualification](../../tests/packages/software-mirror-reader-check.md).

`[--json] deployment-audit LOCK.json` compares that exact format-2 lock with
installed metadata, without catalog, payload or trust-history access. It reports
missing, unexpected and changed packages, including requested roots, publisher
identity and sequence floors. Exit status is 0 for a match, 3 for drift, and 1
for an error. A match describes recorded metadata; `health` checks payloads and
reviewed deployment still admits current trust and policy. See
[qualification](../../tests/packages/deployment-audit-check.md).

Software's **Deployment → Check installed** runs this comparison without an
administrator prompt. It shows the complete package union, paged source/digest
and difference details, Reload and Stop controls, and useful failure diagnostics.
**Review deployment** obtains a fresh authenticated proposal from the report's
captured source; the audit never supplies installation approval. See
[Software qualification](../../tests/packages/software-deployment-audit-check.md).

The audit supports case-insensitive search across IDs, status, versions and
changed field names, with a **Differences only** filter and visible result counts.
Filtering preserves package identity and leaves reconciliation scoped to the
complete deployment file. See [qualification](../../tests/packages/software-audit-search-check.md).

Deployment reviews support Stop, Cancel and Escape before changes begin, with
the source filename retained for a fresh review. Small windows keep navigation,
status, progress and failure access; approved transactions keep running until
completion. See [qualification](../../tests/packages/software-deployment-navigation-check.md).

Install, uninstall, update, repair and rollback reviews support Stop/Cancel/Escape
before changes begin. Small windows retain cancellation, package-details Back,
catalog reload, progress and diagnostics; approved transactions and repository
refresh remain protected. See [qualification](../../tests/packages/software-package-navigation-check.md).

Repository lists and trust reviews support Stop/Cancel/Escape, retaining entered
identity fields and the previous valid list for retry. Compact views keep
navigation and diagnostics; approved trust changes and catalog refreshes remain
protected. See [qualification](../../tests/packages/software-repository-navigation-check.md).

Repository clipboard input preserves literal field data. Controls, malformed
UTF-8 and oversized pastes are refused as a whole, keeping the field and
selection intact. Pasted Enter/Escape/Tab cannot review, cancel or navigate;
empty/unfocused pastes and pastes during reads, reviews or writes do nothing.
Keyboard commands retain their usual behavior. See
[paste checks](../../tests/packages/software-repository-paste-check.md).

Deployment files, offline-export destinations and deployment-lock sources also
use separate clipboard handlers. Pasted controls cannot blur fields, cancel
proposals or stop review workers. Invalid or oversized input preserves the
literal filename and selection; empty/unfocused pastes do nothing. Saved export
sources stay fixed, and approved writers keep running. See
[distribution path checks](../../tests/packages/software-distribution-paste-check.md).

Organization policy reads and reviews support Stop/Cancel/Escape and retain
their filename for retry. Compact windows keep navigation and diagnostics;
approved saves remain protected. Stopping a reload requires a fresh read before
another review. See [qualification](../../tests/packages/software-policy-navigation-check.md).

Personal-data inventory reads support Stop/Cancel/Escape. A stopped read
requires a fresh inventory before deletion review and preserves any completed
purge result. Compact windows keep Back, reload, confirmation cancellation and
failure access; approved deletions remain protected until completion. See
[qualification](../../tests/packages/software-data-navigation-check.md).

Configuration reads reject ambiguous keys, null values and incorrect field
types while preserving legacy defaults for omitted fields. Policy typos fail
before acquisition, cleanup or activation; correcting the configuration permits
a normal retry. See [qualification](../../tests/packages/configuration-check.md).

Package metadata reads validate and consume one captured ordinary-file descriptor,
with a fixed 8 MiB limit. Replaced leaf paths cannot redirect the read to an alias
or stall it on a FIFO; in-place size changes fail with retry diagnostics. See
[metadata read qualification](../../tests/packages/metadata-read-check.md).

Local payload copies and offline transfers validate captured source/destination
descriptors before truncating or writing. Aliases, special files, the same inode,
hard-linked destinations and inconsistent resume offsets refuse; an oversized
offline source preserves the existing partial for recovery. Destination identity,
size and link count are rechecked around progress callbacks and flushing;
interrupted flushes retry. See [copy qualification](../../tests/packages/copy-file-check.md)
and [output qualification](../../tests/packages/copy-output-check.md).

Payload hashing also captures one nonblocking, no-follow descriptor. Verification
admits the signed length before reading, bounds hashing to that size plus one
sentinel byte, and refuses changed sizes or pathname identity. See
[hash qualification](../../tests/packages/hash-file-check.md).

`pack` now walks a captured source tree through parent-relative descriptors and
hashes/copies each regular file through the same open file. Changed identities,
lengths or executable modes refuse; aliases, special files and excessive
directory work cannot enter a new manifest. Sorted ordinary inputs retain
canonical metadata. See [source qualification](../../tests/packages/pack-source-check.md)
for limits, mutation/retry checks and target results.

Packing, legacy index publication and release export now share the publisher
workspace lock. Busy writers refuse before changing package documents or
objects, and interrupted owners release their locks automatically. Unsafe
workspace roots/child directories and hard-linked or replaced locks refuse;
packing output inside the captured source tree refuses before output creation.
See [workspace qualification](../../tests/packages/publisher-workspace-check.md).

HTTPS acquisition also captures its regular destination before starting curl.
Curl supplies bytes through a pipe; the service enforces the size bound before
writing, preserves retry prefixes and refuses changed destination identities.
See [HTTPS output qualification](../../tests/packages/https-output-check.md).

Metadata publication now shares one writer for catalogs, publisher documents,
configuration and trust history. Exclusive private temporary files replace
predictable `.new` names; publication, cleanup and durability checks use captured
descriptors. See [atomic write qualification](../../tests/packages/atomic-write-check.md).

Both publishing commands read one captured private signing seed, bounded to
128 bytes of hex text. Owner, permissions, link count, size and named identity
must agree before signing. Release secret exclusion uses that same capture.
See [signing seed qualification](../../tests/packages/signing-seed-check.md).

`keygen NEW_SEED_FILE` now captures an owned parent without shared write access,
writes and flushes a private temporary, exclusively publishes the new seed and flushes
that parent. Existing/raced destinations are preserved. Post-publication failures
identify the saved seed; `key-public SEED_FILE` recovers its public key through
the normal private-seed reader without changing it. See
[key creation qualification](../../tests/packages/keygen-check.md).

File and directory durability helpers capture nonblocking, no-follow descriptors,
check their types and named identities, and retry interrupted flushes. A changed
target refuses with storage/state diagnostics. See
[durability qualification](../../tests/packages/durability-check.md).

Consumer and publisher sequence histories also require complete, unambiguous
records. Missing/null floor arrays cannot reset replay protection; damaged files
are retained for administrator recovery. Revocation stays available. See
[history qualification](../../tests/packages/history-schema-check.md).

Cached repository snapshots require complete typed, unique records and ordinary
metadata files. A present null/ambiguous cache cannot become an empty legacy
migration input. Restoring trusted cache/history permits retry; revocation and
uninstall remain available. See [cache qualification](../../tests/packages/snapshot-schema-check.md).

Use `pack-catalog CATALOG.json PREPARED_ROOTS NEW_WORKSPACE` to assemble reviewed
prepared-root recipes and pinned inventories atomically, with complete declared
architecture/version/runtime coverage. It emits a canonical catalog lock and a
private publisher workspace for `publish-release`. See the
[catalog contract](SDK.md#build-a-pinned-application-catalog).

Prepared-root imports, catalog builds and all three fixed profiles capture an
ordinary source directory before creating output parents. Empty/NUL paths and
leaf directory aliases refuse, including aliases with trailing separators.
Ordinary directories with redundant separators retain the same canonical
metadata. See [root admission qualification](../../tests/packages/prepared-root-check.md).

`sqlite-catalog SQLITE_VERSION RUNTIME_VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY`
creates the concrete SQLite CLI/musl runtime lock for both supported hosts. It
retains redistribution notices and separates compatible library updates from
the CLI. See the [publisher profile](SDK.md#sqlite-cli-publisher-profile) and
[real SQLite lifecycle qualification](../../tests/packages/sqlite-profile-check.md).

All fixed profiles check captured ELF segment ranges, load alignment and memory
sizes, file-backed executable entry points and bounded interpreter paths before
publishing a lock. These checks run on the copied objects as well as the source;
see [ELF admission qualification](../../tests/packages/elf-profile-check.md).

`native-catalog VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY` pins Hello, Counter and
Memo for both hosts, retaining their SDK permissions, native window protocols
and redistribution notices. The [combined V builder](../../examples/package-catalog/README.md)
compiles all six variants and assembles a publisher workspace. See the
[profile](SDK.md#native-sdk-publisher-profile) and
[qualification](../../tests/packages/native-catalog-check.md).

`ffmpeg-catalog RUNTIME_VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY` creates a
pinned FFmpeg 8.0.1 local media profile: FFmpeg and FFprobe share a separately
versioned musl/library runtime, with notices, upstream source and V build tools.
See the [profile](SDK.md#ffmpeg-local-media-publisher-profile) and
[qualification](../../tests/packages/ffmpeg-profile-check.md).

Fixed native, SQLite and FFmpeg profiles recheck the complete imported file list
and bounded, nonempty notices before publishing a lock. Replacing a required
file with a directory cannot omit a notice or bypass the FFmpeg source pin.
Failed imports leave no output lock and permit retry with restored inputs. See
[profile inventory qualification](../../tests/packages/profile-inventory-check.md).

Software's **Launch in Terminal** action runs an installed CLI application in a
PTY within its window. `run-terminal ID [ABSOLUTE_FILE...]` provides the same
ordinary-account launch from an existing terminal; it refuses redirected input
or output. See [terminal execution](SDK.md#interactive-terminal-execution) and
[qualification](../../tests/packages/terminal-check.md).

`run-args` and `run-terminal-args` accept literal command arguments after `--`.
Use `--file ABSOLUTE_FILE` before the separator for each explicit document grant;
these grants do not append arguments. See [command execution](SDK.md#literal-command-arguments).

Software's **Launch options…** offers quoted arguments, explicit file grants,
private-data/installed-app working folders, batch diagnostics and PTY execution.
The form defaults to private data for relative outputs; CLI clients select that
folder with the additive `--data-cwd` flag. See the
[launch-options qualification](../../tests/packages/launch-options-check.md).

Small launch-option windows retain Back, status and failure access. Resizing
preserves the draft and file-page selection; Escape leaves a field or returns
an idle form to the catalog. Pasted control bytes cannot navigate, and running
applications keep their runtime leases and close protection. See
[navigation qualification](../../tests/packages/software-launch-navigation-check.md).

**Read draft** exposes complete launch arguments, working folder, installed
identity/file permission, each allowed path and any unadded path in the shared
full/compact reader. File navigation leaves the form's selection and paging
intact; Back/Escape also preserves field focus and selection. The reader cannot
edit grants or run commands, and is unavailable during execution. See
[launch reader qualification](../../tests/packages/software-launch-reader-check.md).

`compose-catalog` combines reviewed profile locks into one publisher catalog,
with separate prepared-root directories for each profile. It retains pins,
permissions and license declarations and rechecks targets and dependencies.
See [catalog composition](SDK.md#compose-application-catalogs) and
[qualification](../../tests/packages/composition-check.md).

The [application SDK module](appsdk/context.v) supplies an owned launch context
with installed app/runtime versions, publisher provenance, admitted generation,
private data paths and declared permissions. All launch modes receive the same
versioned environment contract. See [the SDK interface](SDK.md#application-context-interface)
and [native guest qualification](../../tests/packages/sdk-context-check.md).

Software's **Export offline** action reviews current catalog versions or the
exact versions in an organization deployment lock, with their dependency closure,
publisher provenance, licenses, permissions, destination and cache disk requirements
before exporting to new local media. The equivalent catalog
`mirror-review` / `mirror-apply` commands bind confirmation to signed metadata,
policy and destination filesystem identity. Both direct and reviewed exports
support `--progress`. See [offline administration](../../docs/application-distribution.md#offline-and-organization-deployment)
and [qualification](../../tests/packages/offline-export-check.md).

`mirror-deployment-review` / `mirror-deployment-apply` export the exact package
and runtime versions pinned by a nonempty format-2 organization deployment lock.
The media includes the captured lock as `_deployment.json`, published with the
verified closure. This preserves older approved runtimes when catalog mirrors
would select newer versions. Publisher keys still require consumer enrollment.
In Software, cycle the export scope to **Organization deployment lock** and enter
its absolute file path. Visit every destination/source path part and the document
digest, then review the package closure before confirming. The source and
destination arguments stay frozen; changes to the document require a new review.
See [locked mirror qualification](../../tests/packages/locked-mirror-check.md).
See [Software locked export qualification](../../tests/packages/software-locked-mirror-check.md)
for graphical presentation, argument and memory checks.

Stored generations now use strict state/schema and complete runtime/root closure
validation. Canonical bounded generation identities prevent aliases and overflow;
garbage collection admits retained states and obsolete-generation leases before
deleting anything. Corrupt rollback metadata or malformed leases preserve cache
and generation contents for administrator recovery. See
[state validation qualification](../../tests/packages/state-validation-check.md).

Collection preflight uses a bounded descriptor pair instead of retaining one
descriptor per obsolete generation. Removal rechecks directory/lease identities
and the live lock under the package writer lock. See
[collection qualification](../../tests/packages/collection-limit-check.md) for
the reproduced 128-generation / 32-descriptor failure and corrected workflow.

A damaged resumed download now retries once from byte zero with the same signed
payload requirements. Invalid complete/oversized partials start fresh; a bad
source stops without changing activation or rollback. Metadata, verification and
offline sources reject special files before opening. See
[download recovery qualification](../../tests/packages/download-recovery-check.md).

Native apps can opt into signed `window_protocol:1` metadata. Software renders
their bounded label/button/rectangle display lists and returns frame-bound button
and close events over standard streams. `run-window` retains the ordinary-account
sandbox and generation lease without X11 or hardware display grants. The
[counter example](../../examples/package-counter/README.md) builds both targets;
see [native window qualification](../../tests/packages/window-check.md).

Signed `window_protocol:2` adds single-line UTF-8 input with 256-byte bounds,
explicit Enter-to-send/Escape-to-discard editing, and frame-bound field/control
identities. Protocol 1 remains compatible. The
[memo example](../../examples/package-memo/README.md) demonstrates explicit saving
to private data; see [text-entry qualification](../../tests/packages/window-input-check.md).

Ordinary-user Software sessions authenticate reviewed administrative changes
through the fixed `packages-change` action. A root worker returns progress over
a private, kernel-peer-checked runtime socket; passwords stay off command lines
and the desktop clears them after submission or cancellation. CLI clients use
`vinix-package admin [--progress] [--offline] COMMAND ...` for the same bounded
reviewed-operation transport. See [administrator qualification](../../tests/packages/admin-check.md).
