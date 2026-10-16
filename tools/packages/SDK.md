# Application SDK 1

The public boundary is format-1 repositories/manifests, `vinix-package` commands
and versioned JSON, and the isolated launch contract below. Publishers do not
link desktop internals or write the database. Breaking changes require a new
`format`/`sdk` value; unknown versions are rejected. This does not freeze kernel,
Apple or internal compositor interfaces.

Installed `state.json` files are service-generated records, rather than publisher
templates. Every state envelope field is required; duplicate/unknown nested
fields, invalid provenance, orphaned packages and inconsistent runtime/root
closures are rejected. Generation names are canonical positive u64 values and
rollback links name earlier generations. Collection validates retained metadata
and admits regular-file leases before removal. Applications and publishers must
use the service instead of writing this state. See
[state validation qualification](../../tests/packages/state-validation-check.md).

Stored provenance and every nested manifest, dependency and payload declaration
must also be complete. False proprietary/firmware/executable flags, empty lists
and dependency bounds, and SDK values are explicit; null or coerced values do
not supply defaults. `window_protocol` remains optional at zero for format-1
compatibility. Canonical writer bytes are unchanged. Restore damaged records
from trusted retained state while holding the writer lock or stopping package
workers; do not reconstruct omitted declarations by guessing defaults. See
[stored-state schema qualification](../../tests/packages/state-schema-check.md).

Collection checks obsolete-generation leases with a bounded descriptor pair,
then reopens the same directory/lease identities and relocks before removal.
The writer lock excludes new launch admission throughout both phases; an already
admitted holder that becomes busy remains protected. See
[descriptor-limit qualification](../../tests/packages/collection-limit-check.md).

Collection also captures the generation parent identity and validates obsolete
roots as ordinary administrator-owned directories on that filesystem, without
write access for other accounts. Every root/lease passes preflight before any
stage, generation or cache removal. Removal inventories directories and reopens
components relative to captured descriptors without following aliases; it unlinks
leaf names without opening special files or changing hard-link targets. The named
lease remains until all other generation contents are retired. Earlier failures
can be retried after trusted entries are restored. If the final empty-directory
removal fails after lease unlink, inspect storage and restore an empty regular
lease under the writer lock before retrying. See
[collection retirement qualification](../../tests/packages/collection-retirement-check.md).

`cleanup-review` returns a format-1 `CleanupReview` with `architecture`, current
`generation`, retained `previous`, `fingerprint` and an ascending unique
`generations` list (at most 4096 IDs). Both retained IDs are excluded, as are busy
leases. A fresh image can return an empty review without creating package state.
`cleanup-apply FINGERPRINT` rechecks configuration, both states, the complete
eligible set and captured parent/root/lease identities under the writer lock.
Stale approvals refuse before removal. All directory inventories are admitted
before deleting the first target; later filesystem failures may leave partial
cleanup and require a new review. Cached objects, partial downloads, unpublished
stages and personal data are retained. This reviewed operation is available to
Software through `packages-change`; raw `gc` is excluded from that transport.
No publisher refresh, catalog authentication or permission/license admission is
needed for cleanup. See [qualification](../../tests/packages/reviewed-cleanup-check.md).

Software can stop and reap an unaccepted `cleanup-review` worker with Stop,
Cancel or Escape. Partial and complete-before-exit output and the confirmation
fingerprint are discarded; a fresh successful review is required to confirm.
Compact windows retain Back, reload, status and failure access, with no deletion
confirmation. Full-view resizing preserves the first visible generation. An
approved `cleanup-apply` keeps its administrator authorization and close guard;
navigation cannot interrupt it. Stopping or failing its subsequent review reload
preserves the completed cleanup result until a successful read displays it.
Service arguments, authorization, fingerprint and deletion semantics are unchanged.
See [navigation checks](../../tests/packages/software-cleanup-navigation-check.md).

State readers, writers and launch admission require ordinary regular lock/lease
files. Opens and advisory lock acquisition refuse malformed or busy entries
without waiting on FIFOs or exclusive holders. Read-only requests require the
state lock whenever active state, a catalog or trust history exists; a fresh
image can still report empty status without creating state. Invalid entries are
retained for administrator recovery. See
[coordination qualification](../../tests/packages/coordination-check.md).

Transactions admit the complete generation before recursive flushing, before
exclusive publication and after the final activation progress callback. Only
declared payloads, generated launchers, exact state bytes and an empty read-only
lease are allowed. Ordinary entries, ownership, single-link files and canonical
final modes are required. Cleanup removes an unpublished stage only while its
captured directory identity is still valid. Replacements are retained with a
diagnostic. Published failures preserve the active pointer and report the retained generation path;
retry builds a fresh generation. Rollback checks the same complete tree and
captured state bytes after progress, preserving format-1 whitespace compatibility.
See [generation admission qualification](../../tests/packages/generation-admission-check.md).

Verify, unchanged-manifest repair discovery and launch also admit each installed
package's complete `apps/ID` namespace. Only declared regular single-link files
and the directories implied by their paths are permitted. Directories use 0755;
files retain their signed executable/data modes. Ownership follows the captured
state administrator, including when an ordinary account reads root-owned
generations. Package paths are opened without following aliases and remain on
the generation filesystem. Launch checks its application/runtime/dependency
closure before preparing private data or executing a program. Repair stages a
fresh authenticated generation without mutating damaged installed entries.
Invalid state parents outside the generation require administrator restoration.
See [installed namespace qualification](../../tests/packages/installed-namespace-check.md).

Transactions and `gc` capture all abandoned stage roots before retiring any of
them. Aliases, special roots, foreign ownership/filesystems and roots writable
by other accounts refuse recovery. Cleanup checks captured directory identities,
walks components without following links and unlinks leaf entries relative to
captured directories. Incomplete metadata and missing leases are permitted in
unpublished stages. Nested aliases and FIFOs are unlinked without traversal or
opening. Unreadable or changed directories remain for inspection; restore trusted
entries while holding the writer lock or stopping package workers before retrying.
See [stage recovery qualification](../../tests/packages/stage-recovery-check.md).

Disk preflight converts `statvfs.f_bavail` using its fundamental allocation size
`f_frsize`, independently of the preferred I/O size. Zero allocation units and
u64 multiplication overflow fail with the filesystem path in the diagnostic.
Transactions, offline mirrors and publisher/catalog tools share this calculation.
See [space qualification](../../tests/packages/space-check.md).

Removal review and activation estimate downloads only for payloads without a
verified active-generation source or verified cached object. They always budget
the new staged generation, overhead and the configured reserve. Activation
recomputes under the writer lock, then verifies each copied payload; corruption
after review/preflight cannot authorize modified bytes. Install/upgrade/deploy
and the public `estimate_space` retain their cache/acquisition accounting. Size
and total arithmetic overflow is refused. See
[removal-space checks](../../tests/packages/removal-space-check.md).

## Administrator package transport

`vinix-package admin [--progress] [--offline] COMMAND ...` is the ordinary-account
client for authenticated package administration. The current account must be an
administrator and provide its own password through standard input (without echo
on a terminal). Software uses the same client with a masked, bounded password
screen; Enter/Approve submits and clears the credential, Escape/Cancel clears it
and retires the waiting unprivileged client. A submitted transaction must finish
before normal Software close. Forced client retirement closes its output stream
and leaves the approved worker to finish under the existing package journal.

The installed `packages-change` action is `auth = admin`, invokes only
`/usr/bin/vinix-package admin-authorize`, takes no caller arguments, and uses one
bounded input field. Its canonical format-1 request contains a fresh 128-bit
nonce and literal argument vector, at most 4,096 encoded bytes/69 arguments.
Unknown/duplicate keys and noncanonical transport are refused. Software accepts
single-line UTF-8 passwords, at most 256 bytes; the CLI reads a bounded single-line
secret. It is sent only to the authentication
service, separately from the action request. No password or authorization grant
is cached.

`pkgadmin.decode` returns an owned request; `Request.close()` releases its nonce
and argument strings/table and is repeatable. The bounded, nonrecursive reader
also retires partially decoded fields on refusal. Receipt construction and
validation release their SHA-256 context and scratch on every return. Canonical
bytes, 4,096-byte/69-argument limits and accepted command/status rules remain
unchanged; malformed envelopes receive bounded administrator-protocol
diagnostics. See [administrator envelope checks](../../tests/packages/admin-envelope-check.md).

`pkgadmin.run(arguments)` borrows the reviewed argument vector for a synchronous
call and owns its authentication frames, password input, nonce and listener.
Password scratch is explicitly erased on refusal; accepted input transfers to
an owned frame that wipes and frees it. Approval errors own their diagnostic
after the reply is retired, including service-provided refusal text. See
[administrator client checks](../../tests/packages/admin-client-check.md).

Allowed operations are `update`, reviewed `apply` for install/remove/upgrade/
repair/rollback, `repo-apply`, `deployment-apply`, `policy-apply`, `mirror-apply` and
`mirror-deployment-apply`. Every operation except refresh requires its exact
64-digit review fingerprint; normal service validation repeats under the writer
lock. IDs and absolute file/destination paths are checked before authorization.
Raw install/remove/upgrade/repair/rollback, alternate roots, arbitrary executables,
publisher tooling, application launches and nested administration are refused.
Read-only review/status commands remain available directly to ordinary users.

The client listens at `/run/user/UID/pkg-NONCE.sock` in its existing private
0700 session runtime, with a 0600 socket. Runtime parents must be root-owned
directories without other-user write access; links are refused. Root connects
only to the authentication service's actual caller UID, and the client accepts
only a root peer. Authorization returns quickly after forking the worker into
its own session and clearing the inherited alarm. Transaction work is streamed
separately, so the authentication service's action output/time limits apply only
to approval. No long-lived privileged daemon, setuid executable, writable job
spool or caller-selected root executable is added.

The worker preserves standard progress frames and sends a final receipt binding
nonce, canonical request SHA-256 and exit code. The client requires that receipt
and EOF; mismatched/trailing/incomplete output is failure. Nonprotocol diagnostic
lines over 16 KiB are omitted with an explicit notice; progress/receipt lines
retain their strict bounds. A disconnect never becomes reported success. Check
package state and obtain a fresh review before retrying an uncertain outcome.
Authentication audit records approval by the real account; the worker's receipt
reports the package operation's result. Repository trust application and its
following refresh are separate approvals and retain their existing diagnostics.

The package stage installs the action while preserving existing administrator
overrides. Missing authentication service/action, non-administrator accounts,
bad/throttled passwords, private-runtime/peer failures and stale reviews reach
Software. [Administrator qualification](../../tests/packages/admin-check.md)
covers real signed ordinary-account workflows on both target architectures and
the actual Software prompt/progress/credential-retirement code.

## Release image configuration

`tools/packages/stage.v --arch ARCH --staging ROOT --config FILE` initializes a
fresh image with the release builder's reviewed format-1 `Config`. The existing
desktop/security staging path also reads `VINIX_PACKAGE_IMAGE_CONFIG`; an explicit
`--config` wins. Use an absolute source path. The desktop image cache key includes
both that selection and the source contents.

The document uses the normal `architecture`, `repositories` (`id`, `url`,
`public_key`), `policy` and `launch_user` fields. Defaults are the existing
format-1 defaults; proprietary-license acceptance and firmware permission require
explicit policy entries. Review the exact public keys through your release's
trusted channel. New publisher keys must be canonical non-identity Ed25519
prime-order points. No key, repository, license acceptance or firmware permission
is supplied automatically. A selected launch account must be provisioned by the
image's account setup before application launch.

Staging captures one bounded regular input before compilation and holds its
validated canonical bytes until publication. Changed/deleted input cannot alter
that prepared configuration. The target architecture must match. Image roots and
configuration parents must be ordinary controlled directories; links and shared
write access refuse. Publication uses a flushed private temporary and exclusive
atomic rename to a 0644 new file. Concurrently created configuration is preserved.

Existing valid configuration is retained byte-for-byte and the release input is
ignored, including when that input is absent. Invalid or wrong-architecture
existing configuration refuses; it is never repaired by staging. A missing config
beside nonempty package state also refuses, so staging cannot reset retained trust
or policy. Restore that installation's trusted configuration instead. Package
state is never initialized or cleared by this operation.

V image builders can call `pkgcore.prepare_image_configuration(root, architecture,
source)` before compiling tools, then `plan.publish()` after successful staging.
It returns true only for a newly published configuration. Call `plan.close()`
after use; close is repeatable. Keep ancestor directories controlled throughout
the build. Staging updates other tool files individually and does not make the
whole image build transactional; publish the completed image only after success.

After boot, the normal Refresh, review/install, updates, rollback and uninstall
flows use this configuration. Image seeding does not fetch catalogs or accept
unsigned metadata. See [qualification](../../tests/packages/image-configuration-check.md),
including real native applications maintained from a staged configuration without
guest-side trust-file edits. Production publisher selection and complete graphical
login/runtime acceptance remain release responsibilities.

`tests/packages/native-catalog-check.v --software` additionally exercises the
actual Software controller as ordinary administrator and standard accounts
against those staged services and real native applications. It requires headless
ui2 through `VINIX_PACKAGE_TEST_UI2`; see [the integration check](../../tests/packages/software-image-check.md).
Its UI trees and service transports are qualified separately from graphical
login, compositor presentation and foreign display/audio brokers.

### Offline repository bundles in release images

Add `--repositories DIRECTORY` to the staging command, or set
`VINIX_PACKAGE_IMAGE_REPOSITORIES` to its absolute path in the desktop image
builder. The explicit option wins. With no input, staging retains its existing
configuration-only behavior. The desktop cache hashes the selected directory and
all its contents, including payload bytes; timestamp restoration cannot hide a
changed object.

The reviewed configuration must explicitly enroll each bundled publisher at
`file:///usr/share/vinix-packages/repositories/ID`. Put its complete
`publish-release` export under `DIRECTORY/ID`, containing only `index.json`,
`index.sig` and `objects/HASH`. Every configuration entry using that fixed prefix
must be present, and unconfigured bundle entries refuse. Other configured online
or removable repositories are unchanged. Supply absolute paths to the builder;
the signed repository URLs refer to the target filesystem, not the host.

Inputs must be controlled by the builder: ordinary owned directories without
shared write access, release directories 0755, metadata/objects ordinary
single-link files 0644. Publisher workspaces, seeds, extra files, aliases and
special files refuse. Each bundled repository permits at most 16,384 distinct
objects. Index identity, signature, expiry, every advertised dependency/runtime
closure, payload sizes and hashes are checked. Every package in the full export
must pass the configured allowlist, version pins, permission, proprietary-license
and firmware policy. Supplying a bundle never accepts licenses, grants firmware
permission or invents a publisher key. Builders remain responsible for permission
to redistribute their selected payloads and notices.

Before compiling, staging captures the authenticated bytes in a private temporary
directory. Source changes or removal cannot redirect the capture. Both temporary
and destination space are checked with 64 MiB of build headroom, including the
two simultaneous copies when they share a filesystem. The final image bundle is
verified again, flushed and published with an exclusive atomic directory rename.
Expiry is rechecked before publication. Failed copies or validation remove the
unpublished image stage and preserve any existing bundle. An identical destination
is verified and retained; different or damaged contents refuse rather than being
updated. Retry with the same valid source or rebuild a fresh staging image.

For V image builders, call `configuration.prepare_repositories(source)` after
`prepare_image_configuration`, publish the returned `ImageRepositories` before
publishing configuration, and call `close()` on both plans on every path. Bundle
close is repeatable. Publication binds the admitted image root and exact captured
configuration; changed trust/policy or a replaced root refuses. Keep image
ancestors controlled throughout staging. The complete tool/image build remains
per-file staging and must succeed before its output is distributed.

No consumer catalog, replay floor, generation or installed state is created by
bundling. After boot, normal Refresh authenticates the bundled index and normal
review/install creates package state. Signed updates and runtime versions keep
their existing review and rollback rules. This is an initial offline source;
later signed media or reviewed repository enrollment supplies new releases.
See [bundle qualification](../../tests/packages/image-repositories-check.md).

## Build and publish

```sh
v -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/vinix-package tools/packages/main.v
/tmp/vinix-package keygen /secure/publisher.seed
/tmp/vinix-package pack manifest.json /build/payload /build/new-repository
/tmp/vinix-package publish-release /build/new-repository company /secure/publisher.seed 1 2000000000 /srv/releases/company-1
```

`pack` captures an ordinary source directory before creating repository output.
Empty/NUL paths and leaf directory symlinks, including aliases with trailing
separators, refuse. Its sorted traversal opens every child relative to the
captured parent without following symlinks; special files refuse without waiting
on FIFOs. Each regular file supplies its length, executable mode, hash and copied
bytes through one descriptor. Identity, length and executable mode are rechecked
against that parent around hashing, cache reuse and copying; copied objects must
also match the hash before publication.

Source traversal allows at most 128 descendant directory levels, 32,768 entries
(directories and files, including empty directories), 16,384 entries within any
one directory, 16,384 regular files, 4 GiB per file and 64 GiB total payload.
Oversized file/total lengths refuse before reading that file. Ordinary/slashed
roots, sorted paths, empty files and shared read-only source files retain
canonical metadata. Root parent aliases keep ordinary path semantics.
Keep contents stable and repository parents controlled. Publisher commands share
the workspace lock described below. Output inside the captured source tree is
refused before creating output parents, including through aliases and `alias/..`.
Capture does not freeze same-user writes or authenticate upstream inputs.
A failed walk can retain verified objects/partial object temporaries but does
not replace the package manifest; inspect its diagnostic and correct the input
before retrying. See [source qualification](../../tests/packages/pack-source-check.md).

Local payload output must be an ordinary file with exactly one hard link. This
applies to fresh/resumed `file://` transfers, cache-to-generation copies and
`pack` object temporaries. A shared output refuses before truncation or writing;
remove the unintended extra name or select a new destination after inspecting
the retained data. Shared read-only sources remain supported. Destination
identity, size and link count are checked around progress callbacks and the
captured descriptor's flush, with interrupted flushes retried. Controlled parents
and serialization of other writers remain required; these checks do not freeze
arbitrary same-user in-place edits or make a failed copy transactional. See
[output qualification](../../tests/packages/copy-output-check.md).

`keygen` prints the lowercase-hex public key and creates a mode-0600, 32-byte
signing seed encoded as 64 lowercase hex digits and a newline. Its parent must
already be an ordinary directory owned by the publisher, without group/other
write access. Empty/NUL paths, invalid leaf names and a symlink at the parent
directory's final component (including redundant trailing separators) refuse
before creation. Keep the seed outside repositories/deployment images.

The service captures that directory, exclusively creates a private temporary
file, handles short/interrupted writes, checks its identity/type/owner/mode/link
count/length, and retries interrupted flushes. It then publishes with exclusive
atomic rename and flushes the captured parent. An existing or raced destination
is never replaced, including aliases and special files. Normal failures before
publication remove only the still-matching temporary; cleanup cannot remove a
replacement. Storage failure or abrupt termination can leave an unpublished
mode-0600 `.package-key-*.tmp`; inspect the owned directory before retrying.

A failure after publication explicitly says **signing seed saved**. Preserve
that seed and inspect its path and storage before retrying. After verifying
the ordinary private file, `vinix-package key-public SEED_FILE` prints its existing
public key without creating a new key or modifying the seed. It uses the same
captured, private, bounded seed admission as publishing; it accepts no public,
aliased, foreign-owned or hard-linked seed. No administrative transport exposes
these publisher commands. Controlled ancestors remain required, and arbitrary
same-user in-place edits and physical-device write-cache loss are not frozen or
qualified. See [key creation qualification](../../tests/packages/keygen-check.md).

Distribute the public key through an authenticated channel. Upload objects first,
then switch the web server to the complete new repository directory. Never change
content at an existing hash. Increase sequence for every index change, including
expiry. Administrators explicitly enroll, replace or revoke publisher keys using
the repository commands below; publishers cannot authorize their own keys.

Publisher admission requires a canonical, non-identity Ed25519 point in the
prime-order subgroup. The check applies to enrollment, index verification,
application/runtime launch and rollback. An old key record stays readable for
reviewed revocation and uninstall; no replay history is discarded. Normal
`keygen`/`key-public` output and SDK-1 signature bytes are unchanged. See
[publisher-key qualification](../../tests/packages/publisher-key-check.md).

Publisher and consumer use the [pinned V signing dependency](signing/README.md),
with its MIT license, source blob/digest ledger and reproducible V regeneration
tool. It preserves SDK-1 Ed25519 bytes and removes a compiler-sensitive variadic
point-initialization check. Upgrades require renewed source, reference-vector,
sanitizer and both-target qualification; compiler updates do not silently replace
this signing implementation. Standard-library hashing/entropy dependencies are
still part of the qualified toolchain closure.

`publish-release REPOSITORY_DIR ID SEED SEQUENCE EXPIRES NEW_DIRECTORY` builds a
complete consumer release without changing workspace indexes. It returns one
format-1 JSON object with `repository`, `public_key`, `sequence`, `expires`,
`index_sha256`, absolute `directory`, `package_count` and unique `object_count`.
The output contains only `index.json`, `index.sig` and `objects/`; publisher
manifests, state, locks and seeds are excluded. The seed must be an ordinary
private file owned by the publisher. Workspaces and destination ancestors must
be controlled by that administrator; sticky shared directories are supported.
Do not modify the workspace or seed while publishing.
An object whose digest matches the signing seed file is refused, catching an
accidentally packed seed; keep all credentials out of payload sources as well.

Both `publish` and `publish-release` capture the seed through one nonblocking,
no-follow descriptor. The captured file must belong to the invoking publisher,
have no group/other permissions or additional hard links, and contain exactly
64 hexadecimal digits with optional surrounding ASCII whitespace, within a
128-byte file limit. Uppercase hex and CRLF are accepted. Restore a private
ordinary file (normally mode 0600) before retrying a refusal; publication does
not repair permissions or remove the input. The raw-file digest used by
`publish-release` to exclude an accidentally packed seed comes from the same
bytes that select its signing key. See [qualification](../../tests/packages/signing-seed-check.md).

Every advertised version must have a complete dependency closure within this
workspace for its declared host architecture. An `all` data package must resolve
on both hosts. Runtime entrypoints and version bounds use the consumer solver;
a newer working version cannot hide an older broken version. The complete check
has the resolver's shared 100,000-step budget, counting processed constraints and
candidate checks across every version and host. Exhaustion reports the search
limit without falling back to a misleading missing-package diagnosis.
This checks structural installability;
it does not execute apps, qualify foreign APIs, accept consumer licenses or
authorize firmware use. Proprietary/firmware declarations stay in signed metadata.

The consumer resolver uses an iterative worklist and bounded backtracking, with
at most 4,096 requested roots, 32,768 authenticated catalog variants, 4,096 selected
packages and 128 dependencies per package. Late constraints, shared dependencies,
cycles and runtime entrypoint fallback use the same search. Equal versions prefer
the host architecture over `all`; a non-upgrade install first tries an exact
installed variant still present with its authenticated provenance. Package
identities remain bound to their installed repository. These limits supplement
the signed metadata bounds; they do not truncate an accepted closure. See
[resolver qualification](../../tests/packages/resolver-check.md).

Failed resolution reports the encountered requirement, its version bounds and a
dependency path from the requested application. Skipped policy refusals do not
replace a later missing dependency's cause. Deep paths retain their root and
failing suffix, with omitted middle hops marked explicitly; diagnostics are
bounded to 4,096 UTF-8 bytes. Release closure checks include the fixed advertised
version's root. Search-budget exhaustion remains a direct limit error. See
[diagnostic qualification](../../tests/packages/resolver-diagnostics-check.md).

Installed preference moves the exact authenticated variant to the front of its
identity group without copying it into the candidate list twice. Other variants
retain their sorted version/architecture order. A late dependency constraint can
therefore replace a preferred installed version without retrying unrelated
single-version packages. Current sequence metadata comes from the catalog;
different package metadata, repository or key does not match. Explicit upgrades
continue to try the newest version first. See
[preference qualification](../../tests/packages/resolver-preference-check.md).

The command verifies and deduplicates objects, checks destination space with a
64 MiB reserve, creates a private `.vinix-release-*` sibling tree, verifies copied
bytes and flushes the tree. Exclusive atomic rename publishes the complete new
directory and refuses every existing destination, including one created during
the export. Output objects/metadata are 0644 and directories 0755. Filesystems
without exclusive atomic rename support fail closed. A post-publication flush
failure reports that the complete directory exists but its durability is uncertain.
Upload this complete release to a new remote directory, then switch the server's
release route. Serving a mutable workspace can expose a torn metadata pair.

Complete-stage verification runs before directory flushing/sequence reservation
and again after reservation immediately before publication. It requires the exact
captured signed metadata, root/object namespace, authenticated payload lengths
and hashes, ordinary single-link files and final modes. An early refusal preserves
the prior publisher floor. A late refusal keeps the intended reserved floor and
requires an exact retry or a newer sequence; it never publishes the changed stage.
These additional scans share offline mirror admission and add object reads.
See [release admission qualification](../../tests/packages/release-admission-check.md).

Keep `.publisher/history.json` with the workspace and back it up. `pack`, legacy
`publish` and `publish-release` share the private `.publisher/lock`; prepared-root
and catalog imports take it when packing their materialized payloads. Busy
writers fail without waiting or changing payloads, manifests, indexes or release
history. Retry after the writer finishes. `pack` holds the lock through object
verification and manifest publication; both signing commands hold it throughout
their publication. Process exit releases it; preserve the lock file rather than
removing it to bypass a busy writer.

Workspace roots must be ordinary directories owned by the publisher, without
group/other write access. Empty/NUL/over-4096-byte roots and leaf aliases refuse,
including aliases with trailing separators. Parent aliases resolve once to controlled
physical ancestors; ordinary roots with redundant separators remain supported.
`pack` creates missing roots beneath controlled parents. Object/manifest folders
must also be ordinary owned directories. Locks require an owned private regular
file with one hard link and matching named identity before/after acquisition.
Neither admission nor locking freezes manual writes by the same administrator.
See [workspace qualification](../../tests/packages/publisher-workspace-check.md).

Before release publication, durable history
reserves the index sequence/digest for the repository ID and public key. Lower
sequences or changed metadata at the same sequence are refused. After a failure
or abrupt termination, retry the same seed, metadata, sequence and expiry into
the same absent destination or another new directory, or choose a higher sequence.
Never restore an older history to reuse a signed sequence. Normal failures remove
staging; an abrupt stop can leave a hidden tree that the administrator may remove
after the publisher process has stopped. Retry builds from the workspace, never
from abandoned staging. Keep client enrollment/replay checks in place as well.

`publish REPOSITORY_DIR ID SEED SEQUENCE EXPIRES` remains the workspace metadata
command for development and existing callers. It replaces the signature and
index separately and does not maintain publisher release history or check a
self-contained dependency closure. Use `publish-release` for distribution.

`pack` inventories ordinary payload files with paths, lengths, SHA-256 and
executable bits, and copies verified content into the repository. It replaces the
template's `files`. Symlinks/devices/sockets/path collisions are rejected. Include
upstream copyright/license documents. Packages, paths, dependencies, permissions
and MIME types are sorted, and JSON field order is fixed. Identical payload bytes,
sequence, expiry and seed produce identical index bytes and Ed25519 signature.
Binary build reproducibility remains the compiler/upstream build's responsibility.

### Import a prepared guest root

`pack-root recipe.json /build/guest-root /build/new-repository` imports an explicit
selection from a prepared upstream root. Verify upstream signatures and obtain
redistribution permission before preparing that root. This command does not
authenticate upstream packages, solve their dependencies, run install scripts or
infer licenses. Record the complete app/runtime dependency closure in the Vinix
manifest and include the upstream copyright/license files among the selectors.

```json
{
  "format": 1,
  "manifest": {
    "id": "org.example.musl-runtime",
    "version": "1.0.0",
    "architecture": "aarch64",
    "name": "Example Linux runtime",
    "license": "GPL-2.0-or-later AND MIT",
    "kind": "runtime"
  },
  "entries": [
    {"source": "bin/vinix-linux-runner", "path": "bin/vinix-linux-runner"},
    {"source": "lib", "path": "lib"},
    {"source": "usr/lib", "path": "usr/lib"},
    {"source": "licenses", "path": "licenses"}
  ]
}
```

Both selector paths are relative; destinations cannot overlap. The input root
must be an ordinary directory and remain unchanged during import. File and
directory aliases are materialized into regular files in a private workspace;
absolute links resolve inside the captured **guest** root, never the publisher's
host filesystem. Relative parents are resolved after intermediate links and
cannot traverse above that root. Broken links, cycles, more than 40 link hops,
special files and oversized payloads fail. Input files/links are untouched.
Executable modes become 0755 and other file modes become 0644, with no inherited
setuid bits. The existing `pack` canonical inventory/signing rules then apply.
Identical materialized bytes produce identical metadata, regardless of selector
order or the upstream aliases. Do not select account databases, host settings,
devices or unrelated applications. Proprietary and firmware flags stay explicit
publisher declarations, subject to administrator policy.

`pack-root`, `pack-catalog` and the Native, SQLite and FFmpeg profile builders
share input-root admission. Empty and NUL-containing paths refuse. Redundant
trailing separators are stripped while preserving `/`, so a symlink at the
root's final component refuses even with trailing slashes. Each admitted root
is captured with directory, no-follow, nonblocking and close-on-exec flags and
checked as a directory before any destination parents are created. Parent
aliases retain ordinary path semantics. Subsequent pathname replacement cannot
redirect the captured namespace; source contents still need to stay stable.
Ordinary paths with trailing separators preserve canonical package/catalog
metadata. See [prepared-root qualification](../../tests/packages/prepared-root-check.md).

Prepared-root recipes reject unknown or duplicate fields (including escaped
spellings), null collections and mismatched JSON types before opening the input
root or creating an import workspace. `manifest`, `entries`, and each selector's
`source`/`path` are explicit. The omitted format still defaults to 1, and manifest
templates retain the same omitted-field defaults as `pack`.

The bounded recipe reader admits at most 8 MiB, 1,024 selectors and 1,024 bytes
per selector source/destination, with the existing manifest field/count bounds.
It owns the decoded template and selector fields and retires partial results on
refusal. Selector validation preserves equal/parent/child destination refusals
without allocating temporary path prefixes. Canonical output and source-root
admission are unchanged. See
[recipe decoding qualification](../../tests/packages/root-recipe-decode-check.md).

### Build a pinned application catalog

Pinned catalog decoding bounds metadata to 8 MiB, imports to 4,096, target names
to two 16-byte strings and import sources to 1,024 bytes. Existing selector and
manifest bounds apply within each import. Catalog recipes, manifests, dependencies
and payloads require complete declarations; source-template defaults cannot
silently fill a lock. Only omitted `window_protocol` retains its legacy zero.
The decoder owns its result and retires partial imports on failure. Architecture,
coverage, dependency and source-path validation still run before construction;
canonical locks and signatures retain their existing bytes. See
[catalog decoding qualification](../../tests/packages/catalog-decode-check.md).

`pack-catalog catalog.json /build/prepared-roots /build/new-workspace` builds an
entire publisher workspace in one operation. Prepare authenticated upstream
sources and their redistribution notices first. Inventory them with `pack-root`,
review its returned package metadata and complete file records, then retain those
records in the catalog lock. The builder never guesses libraries, architecture,
permissions, licenses or publisher trust from an upstream installation.

| Field | Meaning |
| --- | --- |
| `format` | Required integer `1`. |
| `architectures` | Required nonempty list of distinct `aarch64`/`x86_64` targets. |
| `packages` | Required nonempty list of at most 4,096 imports. |
| `packages[].source` | `aarch64`, `x86_64` or `shared`, optionally preceded by profile directories such as `media/aarch64`, beneath the prepared-roots directory. |
| `packages[].recipe` | A format-1 prepared-root recipe, with its complete manifest and explicit selectors. |
| `recipe.manifest.files` | Required, nonempty pinned inventory: every file has explicit `path`, `sha256`, `bytes` and `executable`. |
| `recipe.manifest.proprietary`, `firmware` | Required booleans, including explicit `false` declarations. |

Each target-specific import's final source component must match its manifest
architecture. Data declared `all` uses a final `shared` component. Optional
profile components are valid package identifiers; source paths have at most eight
components and retain the normal relative-path byte limit. Every ID/version must
cover every declared target;
duplicate identities and mixed shared/target-specific versions fail. Explicit
runtime runners and every dependency must resolve for each advertised version.
As in release publication, `all` data must resolve on both supported hosts.
The recipe rejects unknown fields, duplicate fields (including escaped spelling),
missing disclosures and missing file pins. The existing 8 MiB metadata limit
applies, and normal package/selector bounds still apply.

Catalog locks require complete manifest, dependency and payload declarations,
using the same fields as signed indexes; only legacy `window_protocol` may be
omitted at zero. All fields have their declared JSON types. Null collections,
quoted counters, fractional/overflowing integers and unknown/duplicate fields
are refused before importing, staging or composing a lock. Canonical output for
valid existing complete locks is unchanged. See
[publisher schema qualification](../../tests/packages/publisher-schema-check.md).

The builder captures every selected source directory before copying any package.
Every profile/source component must be an ordinary directory; ancestor and final
symlinks are refused. Replacing a captured profile path cannot redirect the import.
Guest symlinks resolve beneath that captured architecture root using `pack-root`
rules. Unexpected files, wrong sizes or changed executable status fail before
copying those files; changed bytes and missing pins also fail. There is no
fallback to an unpinned source, another architecture or a host library.

Imports remain in a private staging directory. Space checks cover unique objects,
metadata, the largest materialized package and a 64 MiB reserve, with a separate
check of the temporary filesystem. Before publication, the builder verifies all
manifests, objects and canonical recipe again. Success atomically publishes a
new 0700 workspace containing `objects`, `manifests` and `catalog.json`; an
existing destination is never replaced. Failed builds remove their staging
directory. An abrupt process kill can leave an unpublished private
`.vinix-catalog-*` directory; inspect/remove that owned directory and retry with
a new destination. A reported parent-directory flush failure means the workspace
is already visible and needs storage verification before signing.

Success emits one format-1 JSON object with `directory`, sorted `architectures`,
`package_count`, `object_count` and `catalog_sha256`. The digest covers the exact
canonical `catalog.json` bytes. Package/selector/file ordering and input JSON
whitespace do not change canonical output. Identical pinned inputs produce
identical workspace manifests; the normal release publisher then produces the
same index/signature for the same sequence, expiry and seed.

```sh
vinix-package pack-catalog catalog.json /build/prepared-roots /build/new-workspace
vinix-package publish-release /build/new-workspace company /secure/publisher-seed 1 EXPIRES_UNIX /build/new-release
```

Expose the release directory to consumers and enroll its authenticated public key
through the existing repository workflow. Catalog construction emits no signed
index, generates no key and accepts no license on behalf of consumers. The
canonical workspace lock records that import; later manual `pack`/`pack-root`
changes require a newly reviewed lock/build for reproducible catalog assembly.
This publisher workflow does not authenticate upstream archives or qualify the
applications' executable/runtime ABI or graphical sessions.

### Compose application catalogs

`compose-catalog NEW_LOCK_DIRECTORY PROFILE CATALOG.json [PROFILE CATALOG.json...]`
combines between one and 64 complete reviewed catalog locks. Each profile ID must
be distinct and valid. All inputs must cover exactly the same architecture set;
duplicate package ID/architecture/version identities are refused, even if their
metadata matches. Package count, source depth, file pins, disclosures, target
coverage and complete runtime dependency closures are checked again on the
combined catalog. Composition retains every manifest and selector unchanged.

Sources acquire the profile prefix: `aarch64` from `sqlite` becomes
`sqlite/aarch64`. This keeps unrelated loaders and libraries in separate prepared
roots, even when they share filenames. Existing scoped sources can be composed
again within the eight-component bound. Prepare ordinary directories matching
these prefixes; links to profile/architecture directories are refused. Guest
payload aliases inside each captured architecture root retain `pack-root` rules.

For the qualified SQLite and FFmpeg profiles, prepare this layout (copy the
prepared roots into these directories while preserving their file modes):

```text
/build/roots/sqlite/aarch64/...
/build/roots/sqlite/x86_64/...
/build/roots/media/aarch64/...
/build/roots/media/x86_64/...
```

```sh
vinix-package sqlite-catalog 3.53.4 1.0.0 /build/roots/sqlite /build/sqlite-lock
vinix-package ffmpeg-catalog 1.0.0 /build/roots/media /build/media-lock
vinix-package compose-catalog /build/combined-lock sqlite /build/sqlite-lock/catalog.json media /build/media-lock/catalog.json
vinix-package pack-catalog /build/combined-lock/catalog.json /build/roots /build/combined-workspace
vinix-package publish-release /build/combined-workspace company /secure/publisher.seed 1 EXPIRES_UNIX /build/combined-release
```

The composer checks destination space plus a 64 MiB reserve and atomically
publishes a new private 0700 directory with `catalog.json` and `composition.json`.
The latter records sorted profile IDs, canonical input-lock SHA-256 digests,
combined catalog digest, architectures and package count, without host input
filenames. Input order and JSON formatting do not change these bytes. The CLI
returns format-1 JSON with `directory`, `catalog`, `catalog_sha256`,
`architectures`, `package_count` and `sources` (`id`, `catalog_sha256`).
Keep the provenance file with the reviewed lock; `pack-catalog` imports the
combined lock through its existing pinned workflow.

An existing destination is never replaced. Failures remove the private staging
directory; an abrupt kill can leave an unpublished `.vinix-composition-*`
directory. A parent-flush diagnostic after publication requires storage
verification. No payload acquisition, consumer state/trust changes, signing or
license acceptance occur. A composed release uses its publisher's one key;
composition does not merge independently signed repositories or authenticate
upstream inputs. See [qualification](../../tests/packages/composition-check.md).

### Native SDK publisher profile

`native-catalog VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY` emits a pinned catalog
for the existing Hello, Counter and Memo applications. `VERSION` is a canonical
three-component package version applied to all three apps in this fixed profile.

Each of `PREPARED_ROOTS/aarch64` and `PREPARED_ROOTS/x86_64` must contain:

```text
bin/package-hello
bin/counter
bin/memo
licenses/application-sdk-MIT.txt
licenses/v-MIT.txt
licenses/musl-MIT.txt
```

Executables must be ordinary, executable, static ELF64 images for the declared
host, without an ELF interpreter. ELF headers must declare the supported 64-byte
header and 56-byte program entries. Nonempty segment file ranges must fit the
captured file; load segments need valid memory sizes and alignment. Static and
PIE entries must point into file-backed executable load segments. PIE images
need exactly one absolute, NUL-terminated interpreter of at most 4096 bytes
including the terminator; shared libraries and static images cannot declare one.
The checks admit target/format structure; they do not prove every instruction,
syscall, library function or application behavior. See
[ELF admission qualification](../../tests/packages/elf-profile-check.md).
Notices must be nonempty ordinary files of at most 1 MiB. Root directories
cannot be aliases; the importer captures both target directories before copying.
Imported executable bytes and notice sizes are checked again before publication.
All fixed profiles require their exact declared file inventory after import;
see [inventory qualification](../../tests/packages/profile-inventory-check.md).

The six manifests retain the example contracts: Hello has `files` permission,
`text/plain` association and no window protocol; Counter has only `display` and
protocol 1; Memo has only `display` and protocol 2. All use SDK 1, license MIT,
no shared runtime and explicit false proprietary/firmware flags. Each app carries
its three redistribution notices. This profile grants no additional capability.
Updating statically linked SDK, V or musl code requires a newly reviewed
application build/version; these apps have no independently updated runtime.

The service preflights destination and temporary-filesystem space, inventories
payload hashes, canonicalizes complete target coverage and atomically publishes
only `catalog.json` to a new private lock directory. Failures remove the private
staging workspace; abrupt termination can leave an unpublished
`.vinix-native-profile-*` directory. A directory-flush error after publication
requires checking the named published destination before retrying.

Use the [combined V builder](../../examples/package-catalog/README.md) to compile
all six applications and produce prepared roots, the reviewed lock, a private
publisher workspace and an artifact receipt. For separately prepared roots:

```sh
vinix-package native-catalog 1.0.0 PREPARED_ROOTS NEW_NATIVE_LOCK
vinix-package pack-catalog NEW_NATIVE_LOCK/catalog.json PREPARED_ROOTS NEW_WORKSPACE
```

The lock also works with `compose-catalog` alongside SQLite and FFmpeg profiles;
place roots under matching profile subdirectories when importing a composed
lock. Publishing, authenticated key enrollment, installation review and account
selection remain explicit. The examples' local builders and manifests remain
supported. See [native catalog qualification](../../tests/packages/native-catalog-check.md).

### SQLite CLI publisher profile

`sqlite-catalog SQLITE_VERSION RUNTIME_VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY`
inventories a specific Linux application closure and emits its reviewed catalog
lock. Both `PREPARED_ROOTS/aarch64` and `PREPARED_ROOTS/x86_64` must exist, each
with these ordinary payloads and redistribution notices:

```text
bin/sqlite3                 musl PIE command-line executable
bin/vinix-linux-runner      static SDK 1 runner
lib/libc.so                musl shared loader/libc
lib/libsqlite3.so.0         shared SQLite library
licenses/sqlite-COPYRIGHT
licenses/musl-COPYRIGHT
licenses/vinix-COPYING
```

The profile applies the same ELF64 target, segment, entry and interpreter
checks as the native profile, with an interpreter on the PIE CLI and none on
the static runner or shared libraries. It checks imported object bytes again.
Executable payloads are limited to 512 MiB each; notices must be nonempty and
at most 1 MiB.
The imported inventory must contain every declared file at its exact path, with
notice sizes checked again. A directory substituted after preflight cannot
replace a required notice, executable or library in the catalog lock.
This structural check does not identify an arbitrary file as genuine SQLite,
authenticate its source or certify its library ABI. The publisher declares the
numeric SQLite version and a runtime version in `>=1.0.0,<2.0.0`, and must build
and qualify that closure before signing it.

The lock contains four pinned packages: `org.sqlite.cli` and
`org.vinix.sqlite-runtime` for each architecture. The application contains the
CLI and SQLite notice. Its separate runtime contains the runner, library, musl
loader/libc and all three notices; the same musl bytes are also installed at
`lib/ld-musl-ARCH.so.1`. The application declares a runtime dependency in
`>=1.0.0,<2.0.0`, so a qualified compatible library update can leave the CLI
package unchanged. Changes outside that range require a revised application
contract. Licenses remain visible in package metadata and payloads; proprietary
and firmware disclosures are explicitly false for this profile.

The CLI requests no optional permissions or associations. In Software, select
the installed SQLite application and choose **Launch in Terminal**. From an
existing Terminal, use `vinix-package run-terminal org.sqlite.cli`; it opens
`@DATA@/database.sqlite3` in the ordinary account's private app data directory.
SQLite WAL, journals and temporary files stay inside the existing sandbox
contract. The baseline file operations include advisory locks (`flock`), which
operate on open file descriptors and grant no additional paths. The launcher's
descriptor-closing rules still apply. Arbitrary home-directory databases,
document arguments and extension loading are outside this profile. Uninstall
removes the app/runtime closure and registrations while retaining the database;
rollback also retains it.

Success atomically publishes a new 0700 directory containing only `catalog.json`
and returns format-1 JSON with `profile: "sqlite-cli"`, `directory`, `catalog`,
`catalog_sha256`, both versions and `architectures`. No key, signed index or
consumer enrollment is created. The usual captured-root import, free-space
checks, canonical metadata and no-overwrite rules apply. Handled failures remove
temporary payloads; an abrupt kill can leave a private `.vinix-sqlite-profile-*`
directory for inspection and removal. Keep prepared roots stable and review the
lock; `pack-catalog` rejects changes to its pinned inputs.

```sh
vinix-package sqlite-catalog 3.53.4 1.0.0 /build/sqlite-roots /build/sqlite-lock
vinix-package pack-catalog /build/sqlite-lock/catalog.json /build/sqlite-roots /build/sqlite-workspace
vinix-package publish-release /build/sqlite-workspace company /secure/publisher-seed 1 EXPIRES_UNIX /build/sqlite-release
```

The maintained [SQLite qualification](../../tests/packages/sqlite-profile-check.md)
builds unmodified, hash-pinned upstream SQLite using V orchestration, then checks
real database, library upgrade, rollback and offline reinstall behavior on both
hosts. The fixture publisher key is for testing; it is not a supported public
repository or an enrollment decision for users.

## Manifest

```json
{
  "id": "org.example.editor",
  "version": "1.0.0",
  "architecture": "aarch64",
  "name": "Example Editor",
  "description": "A text editor for project documents",
  "homepage": "https://example.org/editor",
  "license": "MIT",
  "proprietary": false,
  "firmware": false,
  "kind": "native",
  "runtime": "",
  "entrypoint": "bin/editor",
  "arguments": [],
  "permissions": ["files"],
  "associations": ["text/plain"],
  "dependencies": [],
  "files": [],
  "sdk": 1
}
```

IDs begin with lowercase ASCII and contain lowercase letters, digits, dot, dash
or underscore, at most 128 bytes. Versions have three numeric components without
leading zeros/prereleases. Architecture is the **Vinix host target**, `aarch64` or
`x86_64`. Only data declares `all`; publish binaries for the actual qualified
host/runtime combination. No implicit architecture aliases/fallback exist.

Generated file records are
`{"path":"bin/editor","sha256":"64 lowercase hex characters","bytes":1234,"executable":true}`.
There are no setuid bits, device nodes, link instructions, absolute output paths
or package scripts. Limits: 16,384 files, 4 GiB/file, 64 GiB/package, 8 MiB per
index/combined cached snapshot/state record. Relative paths have no dot/parent or
empty components, backslashes or controls, and are at most 1,024 bytes.

`permissions` is an explicit set of at most five distinct SDK-1 grants:
`audio`, `display`, `files`, `network` and `process`. Empty sets are valid; order
does not change access. Duplicate, unknown or excess entries are refused during
manifest preflight, signed catalog admission and stored-state validation. They
are also refused in package reviews, Software views and launcher registration.
Readers preserve the authenticated declarations rather than dropping repeats.
Correct source manifests and publish a newer signed sequence; damaged retained
state follows the existing administrator recovery procedure.

The MIT SDK's `appsdk.valid_permissions(values)` checks this borrowed list
without allocating or changing it. Publication, package admission, presentation
and `Context.validate()` share that predicate. Context environment output keeps
its existing canonical grant order. See
[permission-contract qualification](../../tests/packages/permission-contract-check.md).

Dependencies are
`{"id":"org.example.runtime","minimum":"2.0.0","before":"3.0.0"}`.
Minimum is inclusive, before exclusive; either may be empty. Each ID appears once.
Encode runtime/API compatibility in these bounds. Virtual providers, optional
dependencies and external solver hooks are outside format 1.

### FFmpeg local media publisher profile

`ffmpeg-catalog RUNTIME_VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY` inventories
the pinned FFmpeg **8.0.1** local media profile on AArch64 and x86_64. Its three
packages are `org.ffmpeg.cli`, `org.ffmpeg.probe` and
`org.vinix.ffmpeg-runtime`. Both applications declare only `files`, share the
runtime in the compatible `>=1.0.0,<2.0.0` range, and use the packaged static
Linux runner and musl loader. Firmware/proprietary flags remain false.

Each `PREPARED_ROOTS/aarch64` and `PREPARED_ROOTS/x86_64` contains:

```text
bin/ffmpeg, bin/ffprobe                 ELF64 musl PIE applications
bin/vinix-linux-runner                  static target V SDK runner
lib/libc.so                            target musl loader/library
lib/libavcodec.so.62, libavdevice.so.62
lib/libavfilter.so.11, libavformat.so.62
lib/libavutil.so.60, libswresample.so.6, libswscale.so.9
licenses/ffmpeg-LICENSE.md, ffmpeg-COPYING.LGPLv2.1
licenses/musl-COPYRIGHT, vinix-COPYING, v-COPYRIGHT
sources/ffmpeg.tar.xz                   exact pinned upstream source archive
sources/build.json                     retained build command vectors
sources/linux-runner.v, ffmpeg-build.v, ffmpeg-source.json
```

The source archive's length and SHA-256 must match
[ffmpeg-source.json](../../tests/packages/ffmpeg-source.json). ELF format,
architecture, load/entry structure, bounded interpreter path and ordinary
executable metadata are checked before import and again on captured payload
objects. All notices/build sources
are required, nonempty and bounded, including in the imported inventory. Every
declared file must retain its exact path: substituting a directory for the
source archive cannot skip the archive's length, hash and mode checks.
Symlinks are materialized within captured
guest roots. The output is a canonical `catalog.json` only; temporary payload
copies are removed. Both architectures, closure, source pin, disk reserve and
new destination requirements are enforced before publication. `pack-catalog`
subsequently rechecks the exact inventory pins.

The V builder [ffmpeg-build.v](../../tests/packages/ffmpeg-build.v) checks the
archive pin, snapshots and extracts the unmodified upstream source, invokes its
configure/make build with target musl compilers, and compiles the V SDK runner.
It disables automatic external dependencies, GPL/nonfree options, network,
hardware acceleration and assembler optimizations. The enabled local media
subset includes AVI/MPEG-4, WAV/PCM, raw video, generated test video/sine audio,
scale/format and audio resampling. This profile is deliberately narrower than
an unrestricted Alpine FFmpeg installation. The upstream
[license description](https://ffmpeg.org/doxygen/trunk/md_LICENSE.html) explains
the LGPL/GPL configuration split. LGPL notices and corresponding
upstream source are retained with the runtime; runtime versions are an explicit
publisher compatibility declaration, not inferred ABI certification.

```sh
ffmpeg-build /secure/ffmpeg-8.0.1.tar.xz /build/new-ffmpeg-inputs
vinix-package ffmpeg-catalog 1.0.0 /build/new-ffmpeg-inputs/roots /build/new-ffmpeg-lock
vinix-package pack-catalog /build/new-ffmpeg-lock/catalog.json /build/new-ffmpeg-inputs/roots /build/new-ffmpeg-workspace
vinix-package publish-release /build/new-ffmpeg-workspace company /secure/publisher.seed 1 EXPIRES_UNIX /srv/new-ffmpeg-release
```

The source pin records exact bytes from the official upstream HTTPS archive;
it does not verify the upstream PGP signature or enroll a consumer publisher.
Authenticate upstream delivery and review the configuration before public
publication. [Qualification](../../tests/packages/ffmpeg-profile-check.md)
covers the retained compiler/kernel tuple and enabled media subset.

### Wine Win64 publisher profile

`wine-catalog RECIPE_DIRECTORY PREPARED_ROOTS NEW_LOCK_DIRECTORY` inventories a
publisher-supplied Win64 application and a separately versioned Wine runtime for
both hosts. It produces the same canonical lock consumed by `pack-catalog`,
`compose-catalog` and `publish-release`. It does not download Wine, select a
publisher, accept proprietary terms or turn a host-wide Wine installation into
an isolated runtime.

Supply four ordinary bounded prepared-root recipe files:

```text
recipes/aarch64/application.json     roots/aarch64/...
recipes/aarch64/runtime.json
recipes/x86_64/application.json      roots/x86_64/...
recipes/x86_64/runtime.json
```

Each application template must declare `kind: "windows"`, its exact host
`architecture`, `runtime`, `entrypoint: "bin/wine-runner"`, and a first argument
of `"@APP@/bin/program.exe"`. Its sole dependency names that runtime and provides
both `minimum` and `before` version bounds. Select individual source files for
`bin/program.exe` and `licenses/application-LICENSE.txt`, plus any resources and
additional notices. The program must be an ordinary x86-64 PE32+ GUI or console
application with a file-backed executable entrypoint; DLLs, PE32/i386, ARM64 PE,
EFI images, truncated headers and out-of-file sections refuse. Unix executable
permission on the PE payload is unnecessary.

Each runtime template declares `kind: "runtime"`, its exact host architecture,
version and license. It selects a statically linked **native host ELF** at
`bin/wine-runner`, `licenses/runtime-LICENSE.txt`, and every loader, translator,
Wine binary, library and resource needed by its launcher. Enumerate individual
files, not recursive directories, with at most 1024 selectors per recipe.
Runtime dependencies, app-launch metadata and
permissions are empty: the application's declared grants control execution.
The AArch64 launcher must supply its own x86-64 translation path. No architecture
alias or automatic host/guest substitution exists. The profile checks the native
launcher and PE structure, not arbitrary runtime library formats or API coverage.

For example, an application recipe can use:

```json
{
  "manifest": {
    "id": "org.example.editor", "version": "1.0.0",
    "architecture": "aarch64", "name": "Example editor",
    "license": "Example-EULA", "proprietary": true, "kind": "windows",
    "runtime": "org.example.wine", "entrypoint": "bin/wine-runner",
    "arguments": ["@APP@/bin/program.exe"],
    "permissions": ["files", "process", "display"], "associations": ["text/plain"],
    "dependencies": [{"id":"org.example.wine","minimum":"1.0.0","before":"2.0.0"}]
  },
  "entries": [
    {"source":"app/editor.exe","path":"bin/program.exe"},
    {"source":"licenses/editor.txt","path":"licenses/application-LICENSE.txt"}
  ]
}
```

The corresponding runtime recipe starts with:

```json
{
  "manifest": {
    "id": "org.example.wine", "version": "1.0.0", "architecture": "aarch64",
    "name": "Example isolated Wine runtime", "license": "LGPL-2.1-or-later",
    "kind": "runtime"
  },
  "entries": [
    {"source":"runtime/wine-runner","path":"bin/wine-runner"},
    {"source":"licenses/wine.txt","path":"licenses/runtime-LICENSE.txt"}
  ]
}
```

Add the complete reviewed runtime closure to `entries`; these two selectors
alone are not a usable Wine runtime. Duplicate both templates for x86_64 with
that explicit architecture and its matching native launcher. All other manifest
declarations must agree across hosts, including licenses, proprietary flags,
permissions, arguments and dependency ranges. Source selectors and payload bytes
may differ. Templates have no `files` pins: the profile records exact imported
hashes, lengths and executable flags. All `licenses/` payloads must be nonempty
and at most 1 MiB. The runtime's license expression and notices must cover its
complete closure; the profile cannot determine redistribution rights.

```sh
vinix-package wine-catalog /build/recipes /build/roots /build/new-wine-lock
vinix-package pack-catalog /build/new-wine-lock/catalog.json /build/roots /build/new-wine-workspace
vinix-package publish-release /build/new-wine-workspace company /secure/publisher.seed 1 EXPIRES_UNIX /srv/new-wine-release
```

Success returns format-1 JSON with `profile: "wine-win64"`, `directory`,
`catalog`, `catalog_sha256`, `application`, `version`, `runtime`,
`runtime_version` and `architectures`. Inputs remain unchanged. Both targets,
file selectors, space and required notices are checked before staging. Imported
PE/launcher bytes and complete inventories are checked again before canonical
lock publication. A handled failure removes private staging and leaves no new
lock; existing/concurrently created destinations are preserved. An abrupt kill
can leave a private `.vinix-wine-profile-*` staging directory for inspection.

The runtime remains an ordinary signed dependency. Updating its version within
the declared compatibility interval need not change the application; normal
review, rollback, policy, provenance and launcher/removal rules apply. Publishing
never grants consumer license acceptance. Wine prefix state uses the existing
per-user `WINEPREFIX` under private app data and follows the normal retained-data
contract. The launcher must keep generation leases valid while child processes
use runtime files and must not depend on host-global paths or unrequested grants.
Wine IPC, display, process lifetime, translated execution and real upstream
applications still require target qualification. See [profile checks](../../tests/packages/wine-profile-check.md).

### Apple iOS ARM64 publisher profile

`apple-catalog RECIPE_DIRECTORY PREPARED_ROOTS NEW_LOCK_DIRECTORY` pins one
publisher-supplied iOS application and its separately versioned runtime. Supply
`recipes/aarch64/application.json`, `recipes/aarch64/runtime.json` and prepared
files under `roots/aarch64/`. The format-1 result has `profile: "apple-ios-arm64"`,
`directory`, `catalog`, `catalog_sha256`, `application`, `version`, `runtime`,
`runtime_version` and `architectures: ["aarch64"]`. Running this publisher tool
on x86-64 does not produce an x86-64 application variant. The profile supplies
no translation runtime, Apple SDK, signing entitlement or proprietary payload.

The application template declares `kind: "apple"`, `architecture: "aarch64"`,
`entrypoint: "bin/run-ios"` and a first argument
`"@APP@/BUNDLE.app/EXECUTABLE"`. Use one top-level `.app` directory and a direct
executable filename. Additional literal arguments, explicit permissions and MIME
associations retain their normal package semantics. The sole dependency names
`runtime` and provides both `minimum` and exclusive `before` version bounds.

Select the executable, its sibling `Info.plist`,
`licenses/application-LICENSE.txt`, and every needed bundle resource/notice as
individual ordinary files. Templates have no `files` pins. Each recipe has at
most 1024 selectors; every selected `licenses/` file is nonempty and at most
1 MiB. Guest-root aliases retain the normal captured-root import semantics;
architecture-root directory aliases are refused.

The main executable must be a thin, unencrypted, plain ARM64 `MH_EXECUTE` with
`MH_PIE`, an iOS deployment-platform command and one `LC_MAIN` without a custom
stack size. The file is at most 512 MiB; the command area is at most 1 MiB with
4096 commands and 128 mapped segments. The header check enforces segment/section
ranges, a span of at most 512 MiB, no writable executable mappings, no overlapping
segments, alignment for 4K/16K hosts and an aligned, file-backed executable entry.
Universal binaries, ARM64e/PAC, macOS, simulator and x86 images refuse. Mach-O
Unix executable mode is optional: the runtime reads and maps the image.

`Info.plist` may be XML or binary, is at most 1 MiB and must be a dictionary.
`CFBundleIdentifier` equals the package ID, `CFBundleExecutable` equals the
declared executable filename, and `CFBundlePackageType` is `APPL`. These fields
are strings. The package version remains the publisher's package version; the
profile does not infer releases or permissions from other bundle properties.

For example, the application recipe can contain:

```json
{
  "manifest": {
    "id": "org.example.counter", "version": "1.0.0", "architecture": "aarch64",
    "name": "Example counter", "license": "GPL-2.0-or-later", "kind": "apple",
    "runtime": "org.example.ios-runtime", "entrypoint": "bin/run-ios",
    "arguments": ["@APP@/Example.app/Example"], "permissions": ["files"],
    "dependencies": [{"id":"org.example.ios-runtime","minimum":"1.0.0","before":"2.0.0"}]
  },
  "entries": [
    {"source":"app/Example","path":"Example.app/Example"},
    {"source":"app/Info.plist","path":"Example.app/Info.plist"},
    {"source":"licenses/app.txt","path":"licenses/application-LICENSE.txt"}
  ]
}
```

The runtime recipe declares `kind: "runtime"`, `architecture: "aarch64"`, its
version and complete license expression. Select a native static ELF64 AArch64
launcher at `bin/run-ios`, `licenses/runtime-LICENSE.txt`, and every binary,
library, framework, resource and additional notice it needs. The launcher has
Unix executable mode. Runtime dependencies, entrypoint, arguments, permissions
and associations are empty; application grants control execution. The launcher
accepts the bundle executable as its first argument, uses the admitted private
Documents/keychain paths and keeps its generation lease alive while runtime files
are used. It may delegate to another explicitly packaged runtime executable.

```json
{
  "manifest": {
    "id": "org.example.ios-runtime", "version": "1.0.0", "architecture": "aarch64",
    "name": "Example iOS runtime", "license": "GPL-2.0-or-later AND MIT", "kind": "runtime"
  },
  "entries": [
    {"source":"runtime/run-ios","path":"bin/run-ios"},
    {"source":"licenses/runtime.txt","path":"licenses/runtime-LICENSE.txt"}
  ]
}
```

Add the entire reviewed runtime closure and its notices. Neither template may
declare firmware. Proprietary flags and licenses remain explicit for both
packages; publishing cannot establish redistribution rights or consumer consent.

```sh
vinix-package apple-catalog /build/recipes /build/roots /build/new-apple-lock
vinix-package pack-catalog /build/new-apple-lock/catalog.json /build/roots /build/new-apple-workspace
vinix-package publish-release /build/new-apple-workspace company /secure/publisher.seed 1 EXPIRES_UNIX /srv/new-apple-release
```

The profile captures both recipes, checks source files and disk budgets, imports
into private staging, then rechecks copied Mach-O/plist/launcher bytes and the
complete inventory before publishing a canonical lock atomically. Later source
changes cause `pack-catalog` to refuse its reviewed pins. Handled failures clean
staging without replacing an existing or concurrently created destination; an
abrupt kill may leave `.vinix-apple-profile-*` for inspection. Normal signing,
trust, offline caching, policy, review, runtime upgrades, rollback and retained
private-data/uninstall rules apply. Composition requires catalogs with the same
architecture list; this profile cannot silently join a two-host catalog.

Header admission does not bind imports/fixups, inspect every runtime resource,
verify Apple code signatures or qualify arbitrary framework/API behavior. Use
the [publisher checks](../../tests/packages/apple-profile-check.md) and retain
target execution receipts before advertising each app/runtime tuple. The package
fixture exercises the profile with real Mach-O Foundation/keychain operations;
broader applications and graphical services remain separate acceptance gates.

## Runtimes and launch

### Native window protocol 1

Set `"window_protocol":1` and declare `"display"` in a **native** manifest.
The field defaults to zero and is omitted at zero, preserving existing canonical
manifest bytes and deployment-lock digests. Unknown protocol values, nonnative
kinds and missing display permission are refused. The signed value participates
in reviews, update detection and deployment locks. Software's view exposes
`installed_window_protocol`, so a pending candidate cannot change how installed
code launches. Start, Quick Launch, document launch and Software's Launch action
use the installed declaration. Older clients require a package-tools/Software
update to present these apps.

`run-window ID [ABSOLUTE_DOCUMENT...]` is the broker/client stream boundary.
It repeats current policy/trust/payload validation and holds the normal generation
lease until the child exits. Root delegates through `launch_user`; the ordinary
process gets `VINIX_WINDOW_PROTOCOL=1` alongside its normal SDK context. This mode
does not unveil X11 sockets or grant Unix/TTY/display-device access. Documents
still require declared `files` permission and ordinary-account accessibility.
Do not combine this stream with terminal mode or shell commands.

Use `appsdk.WindowFrame`, `WindowElement`, `publish_window_frame`,
`read_window_event` and `WindowEvent`. A frame is one stdout line prefixed by
`VINIX-WINDOW-FRAME ` followed by JSON. Human diagnostics use stderr. The maximum
JSON frame is 65,536 bytes; publishers send complete frames with increasing,
positive u64 `sequence`. Every field below is required:

```json
{"format":1,"sequence":1,"title":"Counter","width":320,"height":160,"background":16777215,"elements":[{"kind":"button","id":"increase","text":"Increase","x":16,"y":60,"width":128,"height":32,"color":1118481,"background":14673407}]}
```

Frames have at most 128 elements and logical dimensions 64–2048. Element kinds
are `label`, `button` and `rect`. Bounds must fit the frame; coordinates are
nonnegative and extents positive. RGB colors are unsigned 24-bit values.
Titles hold at most 128 UTF-8 bytes and element text 2,048, without control
characters. Buttons require distinct ASCII IDs of at most 64 bytes using the
package identifier alphabet. Labels/rectangles have empty IDs; rectangles also
have empty text. JSON fields, numbers, escapes, duplicate/unknown keys and
Unicode surrogate pairs are checked without recursive schema values. There are
no image/resource paths, executable actions, desktop settings or service requests.

The broker scales the logical frame into its application area. It prefixes UI
action IDs internally and sends only admitted button IDs. Each stdin event is
one JSON line of at most 512 bytes:

```json
{"format":1,"kind":"click","sequence":1,"id":"increase"}
{"format":1,"kind":"close","sequence":1,"id":""}
```

Ignore stale click sequences. A close request may use sequence zero before the
first frame. The SDK treats EOF as close; retire owned decoded events with
`.close()`. Publishers construct borrowed frames, while decoded frames own fields
and require `.close()`. Encoding returns an owned string. Software accepts
fragmented lines with bounded buffering, freezes presentation on protocol failure,
and keeps service diagnostics visible. Writes are nonblocking and atomic; a full
input pipe reports that a click was not sent. Normal close waits for the app and
its service lease holder. Forced broker retirement closes streams and leaves
the service alive until the app exits.

[The signed counter](../../examples/package-counter/README.md) demonstrates
button input, private data and close/EOF behavior. Protocol 1 supports
labels/buttons/rectangles; protocol 2 adds bounded text entry below. Neither supplies
arbitrary graphics, clipboard, file pickers, audio, X11 or a full ordinary-user desktop login. Qualify
those runtimes separately. [Window qualification](../../tests/packages/window-check.md)
records the host renderer/codec/ownership checks and both native guest tuples.

### Native window protocol 2: text entry

Declare signed `"window_protocol":2` with native kind and display permission.
The launch service sets `VINIX_WINDOW_PROTOCOL=2`; Software admits only format-2
frames for that installed declaration. SDK/context and package-format versions
remain 1. Protocol 1 keeps its original encoding, event limit and reader.
Publishers using protocol 2 must require a package-tools/Software release that
supports it; older clients refuse these manifests.

Format-2 frames use the same complete frame/element schema and limits as format
1. They additionally admit `kind:"input"`: a single-line field with valid UTF-8
`text` of at most **256 bytes**, without ASCII control characters or DEL. Its ID
uses the button alphabet/64-byte limit and is unique across both buttons and
inputs. No application receives raw keys, clipboard access or compositor APIs.

Clicking a field starts a local edit of its displayed value. Ctrl+A selects all,
Backspace deletes a complete UTF-8 character, Enter sends the complete replacement,
and Escape discards it. Pasted controls/invalid UTF-8 and oversized replacements
leave the field intact. Buttons, changing fields and normal close require the
pending edit to be sent or discarded first. A newer application frame discards
the old edit and reports that change; stale UI control identities cannot activate
the new frame. Protocol errors disable editing. The app remains responsible for
explicit saving and for reporting persistence failures.

Every format-2 event has **five required fields**, including `text` even when it
is empty. Click/close events require empty text; `text` events require a positive
sequence and the current input ID. Each JSON line including newline is at most
2,048 bytes, retaining atomic nonblocking pipe writes.

```json
{"format":2,"kind":"text","sequence":1,"id":"memo","text":"replacement"}
{"format":2,"kind":"text","sequence":2,"id":"memo","text":""}
{"format":2,"kind":"click","sequence":3,"id":"save","text":""}
{"format":2,"kind":"close","sequence":4,"id":"","text":""}
```

Use `WindowEvent.encode()` for serialization and
`read_window_event_for(appsdk.window_text_protocol)` for negotiated input. The
reader rejects another protocol and translates EOF to a format-2 close at sequence
zero. `WindowFrame.accepts(event)` checks protocol, frame sequence, control ID and
kind before an app applies input; it accepts EOF close and current-frame close.
`validate_window_input(text)` exposes the shared UTF-8/size check. Ownership and
explicit `.close()` rules remain the same. Window fields/events cannot invoke
package-manager operations: their IDs remain inside the broker's own namespace.

[The signed memo example](../../examples/package-memo/README.md) builds static
payloads with SDK/V/musl notices for both targets, commits typed replacements and
explicitly saves private data. [Text-entry qualification](../../tests/packages/window-input-check.md)
records host codec/broker checks, repeated heap measurements and actual signed
ordinary-account guest execution. This adds a bounded native interface; graphical
foreign runtimes and full ordinary-user desktop login still need qualification.

| Kind | Requirements |
| --- | --- |
| `native` | Executable entrypoint in its own payload or explicit runtime. Static V is the initial portable case. |
| `linux` | Explicit target loader/library runtime and executable runner, qualified against Vinix's syscall/ABI subset. |
| `windows` | Explicit target Wine/translation runtime and runner; executable/resources remain in the app payload. |
| `apple` | Explicit target Mach-O compatibility runtime and runner for its qualified API subset; no general AppKit promise. |
| `runtime` | Target-specific immutable runtime files, updated as a normal dependency, with no app launcher. |
| `data` | Assets/docs or explicitly licensed firmware payloads; no app launcher. |

`runtime` names a declared dependency of kind `runtime`; `entrypoint` then names
an executable **inside that runtime**. For example, a Windows app uses
`"entrypoint":"bin/wine-runner"` and `"arguments":["@APP@/program.exe"]`.
Runners must use packaged loaders/libraries rather than host-global installations.
Use `pack-root` to materialize a verified prepared runtime's symlinks, or supply
ordinary files directly to `pack`.

For a dynamically linked **musl** Linux application, package the target static
[`vinix-linux-runner`](linux-runner.v) inside its runtime. Package staging builds
the SDK artifact at `/usr/libexec/vinix/vinix-linux-runner`; the installed app
must declare its signed runtime copy as the entrypoint. For an AArch64 example:

```json
{
  "kind": "linux",
  "runtime": "org.example.musl-runtime",
  "entrypoint": "bin/vinix-linux-runner",
  "arguments": ["@RUNTIME@/lib/ld-musl-aarch64.so.1", "@APP@/bin/application"],
  "dependencies": [{"id":"org.example.musl-runtime","minimum":"1.0.0","before":"2.0.0"}]
}
```

The runner execs that absolute loader with `--library-path`, the service's
`LD_LIBRARY_PATH`, the application and literal arguments/documents. The ELF's
host-global PT_INTERP path is not used. Library directories include `lib` and
`usr/lib` in the app, runtime and transitive dependency payloads. The production
sandbox hides host loader/library paths; missing packaged libraries fail with
the loader's diagnostic and exit status. No shell or runtime download occurs.
The process inherits the ordinary identity, permissions and service generation
lease. This runner targets musl's loader protocol; other Linux loaders need an
explicit qualified runner. Bundling libraries alone does not supply every Linux
syscall, service, plugin/data search path or graphics API.

The explicit environment includes `HOME`, `TMPDIR`, `WINEPREFIX`, `PATH`,
`LD_LIBRARY_PATH`, `LANG`, and declared `DISPLAY`. Argument substitutions
`@APP@`, `@DATA@`, `@RUNTIME@` are literal paths, never shell evaluation. Supplied
document paths follow those arguments. Apps receive read/execute payload/runtime
access and write/create private-data access, including advisory file locking.
`files` grants supplied documents, not the entire home; `network`, `process`,
`display`, `audio` request corresponding sandbox promises/device or IPC paths.
Organization policy can refuse requests.
See [actual enforcement limits](../sandbox/README.md).

For `apple` packages, the service also supplies
`VINIX_IOS_DOCUMENTS=@DATA@/Documents` and
`VINIX_IOS_KEYCHAIN=@DATA@/Keychains` (expanded absolute paths). These override
ambient settings in normal, literal-command and terminal launches. The existing
iOS compatibility runtime uses them for Foundation's container/home/search and
temporary-directory APIs and its private keychain files. The bundle stays in
the immutable generation; these locations stay under the ordinary user's
existing private-data grant. No extra paths, devices or promises are granted.
The normal service prepares private `tmp`; Foundation creates Documents when
needed. Keychain storage retains its existing ownership, mode and no-follow
checks. Records use the runtime's authenticated encryption with a separate local
0600 key file. They have no hardware key protection, device lock-state service
or shared-access-group entitlement service; see the [runtime limits](../../docs/ios.md).

The existing Foundation path profile remains bounded to 1023 bytes. Ordinary
uninstall retains this app data; deliberate data removal uses the normal
separate purge operation.

The [Apple package check](../../tests/packages/apple-runtime-check.md) executes
V-generated ARM64 iOS Mach-O images through a signed copy of the real static
runtime under the production sandbox. Its packaged native launcher checks the
admitted context before exec. The Mach-O itself checks Foundation's home,
Documents and temporary paths, writes files there and maintains a generic-password
keychain counter across user-separated launches, upgrade, rollback and cached
reinstall. Duplicate/delete/not-found and unsupported access-group behavior are
also checked. This qualifies that API subset and the maintenance lifecycle;
broader Apple frameworks and applications remain open. The current runner
executes on AArch64; no x86-64 translation, macOS/AppKit or graphical compatibility
is implied.

Apps must handle denied access/missing services and save in private data or a
supplied document. Keep on-disk data compatible with version rollback. A service
lease preserves the generation until the launched process exits; runners must
remain alive while children use runtime files.

Installed apps register automatically in Start and Quick Launch. A declared
`associations` MIME type plus the `files` permission makes an app available in
the shared Open With chooser. Documents are appended as literal arguments;
install/upgrade never changes user defaults. Uninstall removes active handlers,
with user preferences retained for rollback/reinstall. Desktop launches use a
Software output/diagnostic window and the same `run` contract; terminal input
requires CLI execution. Execution requires an ordinary user identity with no
supplementary groups. An administrator may configure `launch_user` for the root
desktop: the session runner drops credentials before re-executing the service,
and the ordinary service rechecks trust and acquires its own generation lease.
The chosen account cannot come from a package, an argument or an environment
variable. This profile does not acquire the hardware seat; display/audio runtimes
still require broker qualification. An ordinary caller uses its own identity.

Ordinary login sessions retain their account memberships. If the package CLI
finds supplementary groups, every launch mode automatically uses the fixed
`packages-launch` action with `auth = account`. The authentication service checks
the kernel peer's ordinary account without requesting a password. The root-only
`vinix-session package-launch` helper loads that same account from the trusted
database and accepts only `run`, `run-terminal`, `run-window`, `run-args` or
`run-terminal-args` for a valid installed-package ID. No selected identity,
executable, environment, root directory or administrative operation is accepted.
The root-desktop `launch_user` setting never overrides an ordinary caller.

A random 128-bit invitation connects both sides through the existing private
runtime transport, with root/caller peer checks. The canonical bounded request
travels on that socket; its 512 KiB encoded limit preserves the full 64 KiB
literal-command contract, including JSON escaping. The fixed action's input is
only the 32-digit invitation. Three SCM_RIGHTS descriptors carry the caller's
existing stdin/stdout/stderr, without combining diagnostics and native frames or
replacing a terminal with a pipe. Additional/missing rights fail and are closed.
The child starts the ordinary isolated session before package admission; the
completion supervisor also drops root and all account groups before waiting.
The helper reads only protected public passwd/group metadata; no shadow records
enter the application session or the supervisor that sheds root.
Its final receipt binds the nonce, canonical request digest and exit code, with
EOF required. Missing/malformed completion is failure. No launcher grant is
cached, and a missing/refused action fails closed with account-tool diagnostics.
Callers already without supplementary groups retain the direct launch path.
See [ordinary-account launch qualification](../../tests/packages/isolated-launch-check.md).

Launch reads trust/policy under the package reader lock and acquires its generation
lease before releasing that lock. The ordinary child repeats this admission check
after the credential handoff. Later revocation prevents new launches; an already
admitted process retains its validated snapshot and lease until exit.

After trust, payload and document admission, launch prepares private data through
captured directory descriptors. The account home and every `.local/share/vinix-apps`
component must be ordinary caller-owned directories without write access for
other accounts. Missing data parents are created with mode `0700`; the existing
home and parent modes are retained. App data and its `tmp` child must also be
ordinary, caller-owned, and on the same filesystem as their respective parents.
Both receive mode `0700` through captured descriptors after validation. Links,
special files, foreign ownership and shared writable modes refuse launch before
the application starts. Correcting the entry permits retry with existing contents
retained. See [launch-data qualification](../../tests/packages/launch-data-check.md).

The built-in `NativeApp` V interface and VAPP version 11 remain internal desktop
contracts. Third-party ui2 clients need compositor adapter qualification. Importing
`desktop/app_process.v` is not a supported standalone UI SDK protocol.

### Personal data cleanup

Personal data survives uninstall and rollback. An ordinary account can use
`vinix-package purge-data ID` after uninstall, or the additive SDK 1 method
`Service.purge_data(id) !`, to erase only its own data. Root and alternate
installation roots are refused. Cleanup holds the package reader lock and
checks all retained generations containing the ID for live leases; any app
using one of those generations blocks purge until it exits. This prevents
deleting an uninstalled app's still-active data or racing reinstall/collection.

The home and `.local/share/vinix-apps` parents must be ordinary caller-owned
directories without write access for other accounts. Cleanup opens every
component without following links, walks captured descriptors and refuses
filesystem crossings. Nested links are unlinked without touching their targets;
an aliased/special top-level data directory is refused. Missing data is a no-op.
Cleanup is not transactional: storage errors or concurrent changes may require
a retry, and nested directory depth is bounded at 64. See the
[purge qualification](../../tests/packages/purge-data-check.md).

The additive SDK 1 method `Service.personal_data() !pkgprotocol.PersonalDataStatus`
and CLI `--json data-list` return `{format:1,rows:[{id,installed,diagnostic}]}` for
the calling ordinary account. Root, alternate roots and extra positional
arguments are refused. Rows are sorted by ID; all fields are present. The list
comes from captured, caller-owned `~/.local/share/vinix-apps` descriptors and
installed state, so repository availability does not affect retained-data
discovery. Valid package IDs absent from the catalog are included. Names that
are not valid package IDs are ignored, but count towards the 4096-directory-entry
limit. Missing data parents return an empty list; unsafe parents fail the whole
request. Aliased, special, shared, foreign-owned or filesystem-crossing app
entries carry diagnostics. Inventory never follows links or opens app entries.

`pkgprotocol.decode_personal_data` requires the complete format-1 schema and
rejects unknown/duplicate fields, duplicate IDs, incorrect types, missing fields,
trailing input, invalid UTF-8 and excessive bounds. Replies are limited to 8 MiB,
4096 rows, 128-byte IDs and 512-byte diagnostics. Produced/decoded statuses own
their rows and strings; call `.close()` after use. Its bounded parser releases
partial rows on failure and uses arrays that release replaced buffers under
`-gc none`. Neither an `installed:false` row nor an empty diagnostic authorizes
deletion: `purge-data` repeats all live checks at execution time.

Software exposes this inventory through **Personal data** and requires explicit
confirmation of permanent deletion for a frozen ID. Purge failures retain the
confirmation for retry/cancel; success reloads the list. Personal-data commands
run as the caller, without the package administrator transport or a password.
The root desktop cannot redirect cleanup through `launch_user`. Forced process
termination or storage errors can leave partial cleanup; reload and retry after
resolving the diagnostic. See the
[manager qualification](../../tests/packages/personal-data-check.md).

Stopping a Software inventory read with Stop/Cancel/Escape discards partial or
complete output received before worker exit. A fresh successful inventory is
required before selecting another deletion, including after a
stopped post-purge reload. Completed purge results survive that stop. Compact
windows retain navigation, reload, cancellation and failure access; permanent
confirmation requires the full view. Escape cancels an idle confirmation or
returns to the catalog. Approved purge workers remain protected until exit;
their command arguments and own-account authorization are unchanged. See
[navigation checks](../../tests/packages/software-data-navigation-check.md).

### Interactive terminal execution

`run-terminal ID [ABSOLUTE_FILE...]` is an additive SDK 1 command. Standard input
and output must both be terminals; redirected streams fail before launch. It
uses the same package state lock, payload/trust/policy verification, ordinary
identity transition and immutable-generation lease as `run`. The explicit
terminal launch adds the `tty` promise and `TERM=linux`. Filesystem grants and
package permissions remain the normal declared closure/private-data/document
grants; it unveils no device directory. Plain `run` retains its existing promise
set and batch behavior. Manifests, signatures and metadata digests are unchanged.

Software exposes **Launch in Terminal** for installed applications. Its trusted
Terminal implementation starts `/usr/bin/vinix-package run-terminal ID` on a
new PTY through literal `execve` arguments, with an explicit environment and no
shell. The child claims the controlling terminal and receives only descriptors
0, 1 and 2. Linux/Vinix closes all higher descriptors with `close_range`; host
fixtures enumerate their open descriptors before fork. Geometry is set before
execution, reads are nonblocking, and ordinary Terminal input/paste, resizing,
UTF-8/VT rendering and bounded scrollback apply.

The application occupies Software until it exits, then **Back to Software**
refreshes the catalog. Normal close/return is refused while it runs. Forced
desktop retirement closes the PTY and lets terminal hangup reach its process
group; it does not kill a package lease holder independently of its sandbox
child. Applications that ignore hangup may remain alive with their leases.
The existing Start/Quick Launch requests retain their launch behavior; this
terminal action is an explicit choice within Software. This provides CLI
interaction, not a graphical display broker or an arbitrary application runtime.
See [qualification](../../tests/packages/terminal-check.md).

### Literal command arguments

```text
vinix-package run-args ID [--data-cwd] [--file ABSOLUTE_FILE]... -- [LITERAL_ARGUMENT...]
vinix-package run-terminal-args ID [--data-cwd] [--file ABSOLUTE_FILE]... -- [LITERAL_ARGUMENT...]
```

These additive SDK 1 commands keep the signed entrypoint and fixed manifest
arguments, then append the supplied literal argument vector. Values after `--`
are never parsed as service options, evaluated by a shell or substituted with
package/data/runtime paths. Empty arguments, spaces, newlines, leading options
and shell punctuation retain their bytes; NUL and arguments exceeding 4,096
bytes are refused. The input permits at most 256 arguments and 256 documents,
with at most 64 KiB total including terminators.

`--file` is an access grant, separate from the argument vector. Each document
must be an existing absolute regular file and the application must declare
`files`; grants retain the normal read/write semantics. Symbolic links remain
usable when their resolved target is a regular file. Directories, devices,
FIFOs, sockets, missing paths and links to those targets are refused before
application data is created or the executable starts. The diagnostic identifies
the refused path. Update a granted file without `O_CREAT`; the grant adds no
create/remove permission. Documents are **not**
automatically appended in this mode. A path appearing in an argument grants
no access by itself. New output files can be created in private application
data; outside that directory, an existing file requires an explicit grant.
`--data-cwd` selects that private data directory as the working folder, so
relative outputs are retained there. It adds no paths, permissions or argument
substitutions. Without the flag, the working folder remains the installed app.
The ordinary child validates the request again after the credential handoff.
For example, after installing the FFmpeg profile as an administrator:

```sh
vinix-package run-args org.ffmpeg.cli -- -version
vinix-package run-args org.ffmpeg.cli --data-cwd -- -f lavfi -i testsrc2=size=64x48:duration=1 -c:v mpeg4 -threads 2 "example with spaces.avi"
vinix-package run-args org.ffmpeg.cli -- -f lavfi -i testsrc2=size=64x48:rate=10:duration=1 -c:v mpeg4 -threads 2 /home/alex/.local/share/vinix-apps/org.ffmpeg.cli/example.avi
vinix-package run-args org.ffmpeg.probe --file /home/alex/.local/share/vinix-apps/org.ffmpeg.cli/example.avi -- -v error -show_streams /home/alex/.local/share/vinix-apps/org.ffmpeg.cli/example.avi
```

Use the ordinary account's own private-data path. The root caller uses only the
administrator-configured `launch_user`, reconstructs literal `--file`/`--`
arguments for the isolated child, and the child rechecks limits, trust, policy,
files and payloads before sandboxing. Generation locking/leases and declared
permissions remain the usual launch contract. Terminal mode additionally checks
terminal input/output and supplies `tty`/`TERM=linux`. `run`/`run-terminal` keep
their existing document-appending behavior. Manifest/index/signature formats
and digest encoding are unchanged.

V SDK callers use `command_launch(argv) !CommandLaunch` to parse the service
prefix and `Service.run_command(id, input, terminal) !int` to execute it;
`command_launch_plan` exposes the same validated sandbox plan for inspection.
Parsed requests own both vectors and every string. Keep the parsed request in a
mutable variable and call `input.close()` after use, including when launch fails;
repeated close is safe and resets `data_cwd`. The CLI closes its parsed request
after the run call. `Service.run_command` and `command_launch_plan` borrow their
input, so manually assembled inputs may continue to borrow caller fields and
must not close those borrowed values.

Parsing uses a bounded temporary vector of borrowed document paths, validates
the complete request before cloning strings, and retires prefix scratch on every
refusal. The ordinary-user isolation transport also validates borrowed prefix
paths without retaining clones or growth buffers. Its 772-value envelope and
diagnostics remain unchanged. The 256-argument/document, 4096-byte value and
64 KiB aggregate limits, literal ordering and error precedence remain unchanged. See
[command request ownership checks](../../tests/packages/command-ownership-check.md).

The sandbox planners (`launch_plan`, `terminal_launch_plan`,
`command_launch_plan`) and `launch_session` return independently owned `Launch`
values. Keep each result in a mutable variable and call `plan.close()` after
inspection or after the child finishes. Close releases the argument strings,
vector and paths, resets every field and can be repeated. Source requests,
decoded state, account names and directory strings may be retired as soon as
planning returns. Planner inputs remain borrowed; manually assembled `Launch`
values with borrowed fields must not close those borrowed values. Do not close
copies of the same owned result as separate owners.

Planning retires dependency traversal, intermediate paths, environment and
template substitutions on success and refusal. The synchronous application and
account-session runners close their plan after the child has finished, including
pre-execution failures. This ownership contract preserves the sandbox argument
order, generation context, document grants and literal command tail. See
[launch-plan ownership qualification](../../tests/packages/launch-ownership-check.md).

The service also owns its loaded launch configuration, installed-state snapshot,
state-directory path and generation lease as one private preparation object.
Preparation closes partial ownership after configuration/state/lease refusal;
the runner closes the complete owner after validation or synchronous child
completion. Repeated close does not close a subsequently reused descriptor.
The reader still retires immediately after admission, while the generation lease
remains held through execution. No new public interface or serialized field is
introduced. See [launch-service lifecycle checks](../../tests/packages/launch-service-check.md).

The synchronous runners borrow their plan through child completion and retire
their argument-pointer vector and launch-status descriptors on return. They
inherit the existing environment, identity and separate standard streams; closed
standard descriptors remain closed. Exit codes, including 126 and 127, and
`128 + signal` statuses are returned unchanged. Failure to enter the planned
working directory or execute its program returns a diagnostic with the path,
stage and numeric OS error instead. The process never executes after a failed
directory change. A private close-on-exec status channel distinguishes setup
failure from an application's own exit code. The parent retains the generation
lease until the child is reaped. See
[launch-process checks](../../tests/packages/launch-process-check.md).

The isolated launch envelope keeps its existing canonical JSON and receipt
bytes. Its bounded reader owns the decoded nonce and argument strings and
releases partial records after malformed input; call `Request.close()` on a
decoded result. Receipt hashing and completion reads also release their scratch
on success and refusal. The 772-value, 512 KiB envelope and existing command
limits are unchanged, including literal non-NUL argument bytes. See
[launch-transport checks](../../tests/packages/launch-transport-check.md).

On Vinix, a peer's write shutdown remains readable after buffered input drains,
so a partial launch frame reports interruption without waiting for its input
deadline. See [socket EOF and resource recovery](../../tests/packages/launch-socket-check.md)
for both-architecture regression coverage and the deferred socket-budget limit.

The account authentication framing used for package actions keeps its VAUT
version-1 bytes and bounds. Its V `text_frame`, `decode` and `read_frame` results
own their fields and support wiping, repeatable `Frame.close()` cleanup.
Borrowed requests retain the existing wipe-only contract. Stream writes erase
and release their encoded scratch; failed receives erase and release partial
fields. See [authentication frame qualification](../../tests/packages/auth-frame-check.md).

The isolated-launch client also closes its owned authentication requests and
checks approval bytes without allocating text copies. Its caller-owned argv
remains borrowed throughout the handoff. Tests exercise a real root peer,
ordinary callers, protected stream transfer and complete cleanup after failed
approval or completion; see [launch client qualification](../../tests/packages/launch-client-check.md).

On Linux, account-session launch reads its executable identity directly from
`/proc/self/exe` with bounded stack storage. An unavailable, empty or oversized
identity refuses with a diagnostic before the session helper starts.

Software's **Launch options…** form exposes these commands for installed apps.
Enter arguments using single/double quotes to group values and backslash to
escape the following character outside single quotes. Empty quoted arguments
are preserved. Variables, wildcards, substitutions, redirection and pipelines
remain literal; incomplete quotes/escapes fail before starting the service.
The fields retain UTF-8 text exactly and reject invalid/control-character pastes
and edits beyond 4,096 bytes instead of silently truncating them.

Add each document's absolute path to **Allowed files**, then use its path
explicitly among the app arguments. Duplicate paths are refused, files can be
paged and removed, and an unfinished file entry must be added or cleared before
launch. **Working folder: private app data** is the default in this form; its
relative outputs are saved under the ordinary account's
`~/.local/share/vinix-apps/ID`. Choose **installed app** for apps needing their
packaged assets as the working folder. **Run** shows captured diagnostics;
**Run in Terminal** transfers the exact vector to Software's PTY. Input, grants
and working-folder choice cannot change while a worker is active. Returning to
the catalog or closing clears the draft; failed batch execution retains it for
correction. The service performs the actual file/access/trust/policy checks.

Compact Software views retain Back, status and failure access. Editor and
launch controls appear in the full form; resize preserves arguments, explicit
grants, working folder, field focus and file-page selection. Escape leaves a
focused field and clears its selection; from an idle form it returns to the
catalog and discards the draft. Pasted control bytes, including Escape and
Enter, are rejected as text without navigating or replacing the field. Active
batch workers retain their runtime leases and close guard, ignoring Back,
Escape, editor and repeated launch actions until exit. This is a UI change;
literal vectors, installed permission checks, ordinary-account handoff and
the Terminal command contract are unchanged. See
[navigation checks](../../tests/packages/software-launch-navigation-check.md).

`pkgprotocol.command_words(text)` implements this bounded quoting grammar and
returns owned strings; `command_vector` validates and builds owned CLI arguments.
Release either with `free_command_values`. SDK vectors accepted by `run-args`
remain literal and never pass through this editor grammar again.

### Application context interface

Every package launch supplies these additive SDK-1 environment fields from the
admitted installed manifest and generation. They are the same for ordinary,
literal-argument and terminal launches, including the root-to-account handoff.
The sandbox starts with an empty environment and the service supplies these
values explicitly; ambient `VINIX_APP_*` values from the caller are discarded.

| Variable | Meaning |
| --- | --- |
| `VINIX_APP_SDK` | Context interface version, currently `1`. |
| `VINIX_APP_ID`, `VINIX_APP_VERSION` | Installed application ID and numeric three-component version. |
| `VINIX_APP_ARCHITECTURE`, `VINIX_APP_KIND` | Host target (`aarch64`/`x86_64`) and installed `native`/`linux`/`windows`/`apple` kind. |
| `VINIX_APP_GENERATION` | Canonical positive decimal generation counter. |
| `VINIX_APP_REPOSITORY`, `VINIX_APP_PUBLIC_KEY`, `VINIX_APP_SEQUENCE` | The application's admitted publisher ID, lowercase Ed25519 key and positive index sequence. |
| `VINIX_APP_DIR` | Absolute immutable app directory in the admitted generation. |
| `VINIX_APP_DATA` | Absolute ordinary-account private data directory; equals `HOME`, with `TMPDIR` at its `tmp` child. |
| `VINIX_APP_RUNTIME_ID` | Explicit runtime dependency ID, or empty for a self-contained app. |
| `VINIX_APP_RUNTIME_VERSION`, `VINIX_APP_RUNTIME_DIR` | Installed runtime version and directory in the same generation; for a self-contained app these equal its own version and directory. |
| `VINIX_APP_PERMISSIONS` | Sorted, space-separated declared permission names; empty when none are declared. |

The context reports the admitted snapshot. Upgrade/rollback/removal changes the
context of new launches. A running process retains its original fields and
generation lease, including when it reads the environment again after those
operations. It does not query a newer active state. The application index
sequence can differ from its runtime's sequence; the application fields describe
the application record. Determine the actual process identity with the normal
OS user/group interfaces.

The MIT-licensed [V application module](appsdk/context.v) exposes `Context`,
`Fields`, `load`, `decode`, `Context.validate`, `Context.declares`,
`Context.environment`, `Context.close` and `free_values`. It depends on V's
standard `os` module and does not import the package manager or signing library.

```v
import tools.packages.appsdk

mut context := appsdk.load()!
defer { context.close() }
println(context.id + ' ' + context.version)
println(context.data_directory)
```

`load` reads the current process environment and verifies `HOME`/`TMPDIR`.
`decode(Fields)` borrows input fields and returns an independently owned context.
It refuses missing/unsupported SDK values, malformed IDs/versions/key, zero,
noncanonical or overflowing counters, paths with controls/parent traversal,
mixed generation directories and unknown/duplicate permissions. Paths are at
most 4,096 bytes; IDs 128 bytes; numeric version components nine digits;
permission text 64 bytes and five distinct names. No shell expansion occurs.
`environment` returns owned literal `NAME=VALUE` strings; free them with
`free_values`. Close decoded/loaded contexts when done under manual memory
management. Older services without this interface produce a load error.

`declares` reports manifest permissions. Paths, document access, network,
process and device operations still use the actual sandbox and account policy.
These environment values are metadata, not an authentication token for another
process; applications can change their own environment. See
[native SDK qualification](../../tests/packages/sdk-context-check.md).

## Repository and JSON interfaces

Signed format-1 indexes require all five envelope fields (`format`, `repository`,
`sequence`, `expires`, `packages`). Each package requires all 18 base fields in
the `Package` model, including empty description/homepage/runtime strings, false
proprietary and firmware declarations, empty argument/permission/association/
dependency lists and `sdk`. Only the legacy `window_protocol` field may be
omitted, meaning zero. Each dependency declares `id`, `minimum` and `before`;
each payload declares `path`, `sha256`, `bytes` and `executable`, including
zero/false values.

The consumer verifies the signature over the original bytes before decoding.
JSON object/array/string/boolean/number types must match their fields. Null
collections, quoted counters, fractional/overflowing integers and unknown or
duplicate keys are refused, including duplicates written with Unicode escapes.
Unique escaped keys, arbitrary object field order and ordinary JSON whitespace
remain valid. Existing canonical publisher bytes and signatures are unchanged.

`pack` source templates retain documented omitted-field defaults but reject
unknown/duplicate fields and mismatched types. Packed inventory manifests require
complete declarations before `publish` or `publish-release` signs them. A failed
consumer refresh or enrollment leaves cached metadata, replay floors,
configuration and activation unchanged. See
[signed metadata qualification](../../tests/packages/index-schema-check.md).

Source templates and packed inventories use the bounded stored-manifest reader.
Source omissions keep their decoder defaults, including nested dependency and
payload fields; inventory declarations remain complete. `pack` still substitutes
the captured source inventory for template `files`. Both paths enforce manifest
field/count bounds before output creation, keep canonical publication bytes and
retire partial decoder storage. Full package validation remains in the publisher.
See [publisher manifest qualification](../../tests/packages/manifest-decode-check.md).

`pkgprotocol.decode_metadata_key` decodes one quoted JSON key into an owned
string, with 32 UTF-8 bytes and 194 input bytes as limits. It handles Unicode
escapes and surrogate pairs, rejects invalid UTF-8/escapes and trailing data, and
allows surrounding JSON whitespace. Free the returned string when finished.

```text
index.json                       format, repository, sequence, expires, packages[]
index.sig                        hex Ed25519 signature of exact index.json bytes
objects/SHA256                   immutable content
manifests/ID-ARCH-VERSION.json    publisher input, not consumer trust input
```

Expiry is UTC Unix seconds; sequence is a positive increasing integer. The signed
index embeds full manifests/hashes; consumers never acquire unsigned side metadata.

`repo-enroll ID URL PUBLIC_KEY_HEX` authenticates a current index with the supplied,
independently authenticated Ed25519 key before enabling that repository. Run
`update` to publish its catalog. Reusing an ID replaces the URL/key and preserves
architecture, launch account and policy. Local `file://` repositories support
offline enrollment. `repo-revoke ID` disables that publisher without fetching
metadata or deleting installed payloads/personal data; uninstall remains available.
Key replacement also revokes launch/rollback trust for old-key installations.

`--json repo-list` emits `{format:1,architecture,repositories,history}`.
Repositories contain `{id,url,public_key}`; history contains
`{id,public_key,sequence,index_sha256}` for enrolled, revoked and replaced keys.
Listing takes a shared lock once a package store exists; an active writer gives
a busy diagnostic. A fresh image can be listed without initializing its store.

`--json repo-config` emits the separate
`{format:1,scope:"configuration",architecture,repositories}` document. It reads
only configured ID/URL/key identities under the package reader lock, without
fetching or inspecting catalog/history. Configuration errors and unsafe/busy
coordination still fail. It creates no package state on a fresh image. This
read API allows Software to select and review revocation even when maintenance
metadata is damaged; the existing `repo-list` contract remains unchanged.
Plain-text output explicitly says catalog/history have not been checked.
Neither result authorizes trust changes or proves that a repository is usable.

`pkgprotocol.decode_repository_configuration` requires the explicit scope and
all typed fields, validates up to 4096 unique repository identities, bounds the
reply to 8 MiB and owns its returned text/arrays until `close()`. Unknown,
duplicate/escaped duplicate, missing, null/coerced and incomplete fields are
refused. Configuration and full-history documents cannot substitute for each
other. Software requires this new read API from its paired package service;
unavailable or malformed responses preserve the previous valid list. Reviewed
revocation still reloads current configuration and uses the authenticated
administration transport. See [configuration-list checks](../../tests/packages/repository-config-check.md).

`repo-review enroll ID URL KEY` and `repo-review revoke ID` emit a read-only
format-1 `RepositoryReview`: `operation`, `architecture`, `id`, `url`,
`public_key`, `previous_url`, `previous_public_key`, `fingerprint`,
`index_sha256`, `sequence`, `expires`, `package_count` and `remembered_sequence`.
Enrollment verifies a current signed index with the supplied key and checks
retained replay/equivocation floors. No objects are downloaded and neither trust
nor persistent package state changes. A private metadata workspace is removed
on ordinary completion. Revocation needs only current configuration; its index
digest, sequence, expiry, count and remembered-sequence fields are empty/zero.
Its previous/current URL and key identify the exact configuration to disable.

Call `repo-apply FINGERPRINT enroll ID URL KEY` or
`repo-apply FINGERPRINT revoke ID` with the reviewed operation/arguments. Under
the writer lock, the service reloads configuration and compares the complete
intent; enrollment also re-verifies the signed index and sequence history.
Changed metadata, policy, launch account, repository/key or remembered floors
fail as stale before publishing trust/history. Review again. The fingerprint is
an opaque freshness check and grants no administrator authority. After successful
enrollment call `update` to load the combined catalog; a refresh failure does not
undo the trust change. Revocation retains payloads, personal data and history.

Software can stop the read-only `repo-config` and `repo-review` workers with
Stop, Cancel or Escape before publication. It kills and reaps the child,
discards partial or complete-but-unaccepted output and retires any trust
proposal/fingerprint. The previous valid list and literal entered ID/URL/key
survive for retry. Enrollment, revocation and their following authenticated
catalog refresh cannot be stopped through these controls and retain their
normal close guard. The subsequent configuration listing is read-only again.
Compact windows retain Back/Stop/Cancel, status, progress and failure access;
they expose no confirmation and preserve URL paging/review state across resize.
An idle Escape blurs the editor first, then returns to Software. See
[navigation checks](../../tests/packages/software-repository-navigation-check.md).

The lightweight [`pkgprotocol` repository module](pkgprotocol/repositories.v)
provides bounded `decode_repositories`, `decode_repository_review`, input/response
validation and explicit `close()` methods for consumers with manual memory
management. Status has at most 4096 repository/history records and encoded
responses are bounded to 8 MiB. Unknown formats and incomplete intents fail closed.

V callers of `pkgcore.repository_configuration(root)` receive independently
owned architecture/repository fields. Call `RepositoryConfiguration.close()`
after use; repeated close of the same owner is harmless. The reader transfers
only the public projection and retires unused policy/launch-account storage and
its directory path. `Service.policy()` similarly retires source configuration
and paths while returning the existing owned canonical `PolicyDocument`; keep
calling its `.close()`. Neither reader opens catalog/history or creates fresh
state, and both retain reader locking and their existing wire formats. Policy
reads report stored settings independently of the service's offline overlay.
See [configuration observation qualification](../../tests/packages/configuration-observation-check.md).

`pkgcore.repository_status(root)` returns an owned strict `RepositoryStatus`:
call `.close()` after use. Its architecture, configured repositories and replay
floors remain valid independently of source files and other observations. The
reader retires unused configuration fields and paths, including complete source
configuration on refusal. Format, wire ordering, reader locking and authenticated
legacy-floor recovery are unchanged. Synthetic documents can borrow fields and
must keep their caller-managed lifetime. See
[strict repository observation qualification](../../tests/packages/repository-status-ownership-check.md)
for the original measured scope. The subsequent
[bounded signed-index qualification](../../tests/packages/index-decode-check.md)
removes the decoder residual and requires zero retained bytes on authenticated
status paths. Indexes use the stored-manifest reader's field bounds while keeping
signature-first verification, complete declarations, exact publisher bytes and
the full unsigned sequence/signed expiry ranges.

History is keyed by ID/key, independent of mirror URL, and records exact signed
index bytes. Reject lower sequences and changed bytes at an existing sequence;
increase sequence for expiry renewals too. Revocation and empty refreshes retain
floors. History is durable before configuration/catalog publication: retry an
interrupted enrollment/refresh with the same or a newer signed index. An older
cache is refused until refreshed. The administrator owns this local history;
it is not a hardware trust anchor. See the
[administration and recovery contract](../../docs/application-distribution.md#trust-and-configuration).

After explicit revocation/key replacement, migration can retire a cached
snapshot whose key fails current curve admission only if existing history pins
the exact ID/key, SHA-256 of index bytes and decoded sequence. The pinned text
must still have a complete valid index shape. No floor is synthesized, lowered
or removed. A valid key always requires signature verification, even when its
cached bytes already match history. Missing/different history, altered text,
ambiguous cache records and still-enabled invalid identities fail closed.
Enrollment review/apply evaluate the proposed configuration consistently, so a
verified replacement can recover before the old cache is refreshed. Read-only
review/status and enrollment leave that cache unchanged; successful refresh
publishes the replacement catalog. The original invalid key remains unusable
for enrollment, launch and rollback. No wire/schema changes are required. See
[recovery checks](../../tests/packages/publisher-recovery-check.md).

Consumer `trust-history.json` and `publish-release`'s `.publisher/history.json` are complete
durable records. Their format-1 envelopes require `format` and respectively
`repositories` or `indexes`. Every floor requires `id`, `public_key`, positive
`sequence` and `index_sha256`. Unknown/duplicate fields, escaped duplicate names,
null collections and invalid JSON value types are refused, including a root
`null`. Explicit empty arrays remain valid for a fresh store; an absent file
still follows initial/legacy migration rules. Canonical writer bytes are unchanged.
Present malformed files are never normalized into empty history or overwritten
by a failed refresh/enrollment/publication. Restore the retained history under
the appropriate writer lock before retrying; revocation requires no history.
See [history qualification](../../tests/packages/history-schema-check.md).

Both history envelopes use the internal bounded stored-metadata reader. It
enforces the 8 MiB input and 4,096-identity limits while parsing, preserves the
full u64 sequence range and exact writer bytes, and retires partial fields on
refusal. Only `ENOENT` permits initial empty history; other path errors, leaf
aliases and special files refuse. Decode diagnostics keep their consumer or
publisher prefix while retiring the original error. See
[complete decode and file-reader checks](../../tests/packages/history-decode-check.md).

The local `catalog.json` cache is an array of complete
`{repository:{id,url,public_key},text,signature}` snapshots, with at most 4,096
distinct repository IDs. Configuration has the same repository limit and shares
identity/source validation. The signed text is nonempty and signatures are
nonempty strings of at most 256 bytes, including permitted legacy whitespace;
signature authentication, expiry and replay-floor checks still follow decoding.
Exact signed bytes are preserved. Missing/unknown/duplicate fields, null or
coerced values, invalid identities and a root null refuse admission. An absent
cache or explicit empty array remains valid; a dangling cache link is an error.
Restore damaged cache/history under the package writer lock instead of resetting
them to empty records. See [cache qualification](../../tests/packages/snapshot-schema-check.md).

Cached wrappers use the internal bounded stored-metadata reader. It enforces
field bounds and the 4,096-record/8-MiB limits during parsing, retires partial
owned records and keeps signed text and legacy signature whitespace exact.
Cache-file reads retire source/path/error scratch and treat only `ENOENT` as an
initial empty cache. Restoring trusted ordinary metadata permits retry without
rewriting a damaged cache. See [complete snapshot decode checks](../../tests/packages/snapshot-decode-check.md).

`view` emits one `{format:1,generation,architecture,offline,catalog_error,update_error,rows,launch_user}`
JSON object. Rows include ID/name/description, available/installed version, target,
kind, repository/key, license/proprietary/firmware flags, permissions, explicit
install/update flags and policy diagnostic. Additive `installed_name`,
`installed_kind` and `installed_permissions` fields describe the actual installed
manifest for launch controls; an explicitly empty installed permission set must
not inherit the planned candidate's permissions. Older consumers may ignore
these fields; older services retain the previous presentation fallback.
`installed_window_protocol` adds the installed native-window declaration.
For an installed row, `diagnostic` gives the first trust/policy blocker in the
active installed dependency closure, including a revoked or cryptographically
invalid runtime publisher. A pending candidate cannot hide that blocker until
activation. If the installed closure has no blocker, the field checks the
displayed candidate's own trust/policy. It does not resolve a new application's
complete closure or promise a successful launch. Catalog expiry, payload
integrity and sandbox/device/runtime failures are separate checks. Uninstall
remains available. See [diagnostic checks](../../tests/packages/diagnostics-check.md).
Pending rows include `update_action`
(`install`, `update`, `remove`; otherwise empty), with `updatable:true`. They
come from one complete `upgrade` resolution and include runtime/data additions,
updates and removals, even if no application version increases. `version` is the
planned target; removals retain the installed version/provenance. Constraints,
policy and installed publisher ownership determine this plan. Manifest/key
changes and pin-required downgrades also count; index sequence renewal alone
does not. Call `review upgrade`, then `apply` with that review to maintain this
whole set. Installing an individual dependency makes it an explicit root and
has different semantics.

Expired/missing catalogs set `catalog_error`; resolution failures set
`update_error`, leave all update flags false, and retain installed metadata.
`updates` returns nonzero for either error, so an empty successful result means
no advertised package changes. New catalog applications show available publisher
metadata; full installation resolution occurs during review. The view is read
under a shared package lock and rejects more than 4096 rows or 8 MiB of encoded
metadata. `status` emits format-1 installed
state; `plan` emits `{requested,packages}`; `--json search/info/updates` emits one
row per line. Consumers ignore additional fields and reject unknown formats.
Success is exit 0; failures are nonzero with stderr diagnostics. Human progress
text is not a machine protocol.

V clients receive independently owned snapshots from `Service.state()` and
`Service.verify()`, including the fresh empty state. Retire each result with
`State.close()`; repeated close of the same owner is harmless. Configuration and
directory scratch retire before returning, and verification failures release
their captured state before returning the caller-owned error. For example:

```v
mut installed := service.state()!
defer { installed.close() }
println(installed.generation)
```

This close contract applies to owned status/verification observations. Transaction
and plan results, low-level fresh `read_state` values and caller-built states can
borrow metadata and must retain their existing lifetimes. Status skips payload
scanning; verify holds its reader lock through completion. Returned metadata is a
captured observation, rather than a continuing lease on installed files. Wire
fields and output bytes are unchanged. See
[status ownership qualification](../../tests/packages/status-ownership-check.md).

[`pkgprotocol.decode_software_view`](pkgprotocol/view_reader.v) returns an owned
`SoftwareView`; call `.close()` on cancellation, replacement or retirement.
All eight header fields and eighteen base row fields are required, including
empty diagnostics/strings/arrays, zero counters and false flags. Duplicate known
keys (including escaped spellings), null/coerced fields, invalid UTF-8/Unicode,
noncanonical/overflowing counters and trailing input are refused. Row identities
must be unique, architectures must match the header (or `all` for data), and
update flags/actions must agree with installed versions and error status.

Installed launch columns support three complete shapes: none (legacy),
name/kind/permissions, or all four including window protocol. Partial groups and
empty installed name/kind in a supplied group are refused. Explicitly empty
installed permissions remain empty; they never inherit the displayed candidate's
grants. Unknown additive fields are ignored after bounded JSON syntax/Unicode
checking, with an extension recursion limit of 32. Known field bounds still
apply: 8 MiB per reply, 4096 rows, five permissions per set, and the existing
package text limits. Partial records, arrays and temporary extension buffers
are freed on refusal under manual memory management. Software publishes only a
complete valid view and frees refusal errors. See
[catalog metadata qualification](../../tests/packages/view-metadata-check.md).

`pkgprotocol.decode_registration(text)` reads the desktop presentation projection
of a format-1 installed generation. Its owned `RegistrationSnapshot` contains
`format`, positive `generation`, `architecture` and `packages`; each
`RegisteredPackage` contains `id`, `name`, `description`, `architecture`, `kind`,
`permissions` and `associations`. Input packages retain the stored state's
`{"package":{...},...}` envelope. Call `.close()` on the returned snapshot.

Every projected field is explicit, typed and unique, including escaped key
spellings. Empty strings/arrays remain explicit; null, malformed Unicode,
trailing input, duplicate package IDs and fractional/overflowing generation
numbers are refused. Bounds are 8 MiB, 4096 packages, five permissions and 128
MIME associations per package, with the existing ID/text limits. Other stored
state fields are syntax-checked with at most 32 extension nesting levels and
retired without building a payload/provenance tree. Partial input releases its
owned fields and arrays on refusal. The compositor also requires a canonical
positive u64 activation target and matching snapshot generation/architecture.
The package service remains authoritative for complete state, trust, policy and
launch admission. See [registration qualification](../../tests/packages/registration-check.md).

For live operation progress, pass `--progress` to `update`, `install`, `remove`,
`upgrade`, `repair`, `apply`, `deploy`, `deployment-apply`, `rollback`, `verify`,
`mirror` or `mirror-apply`. Health supports a separate stderr channel described
below. Other progress commands refuse `--json`. Ordinary human output/diagnostics are retained;
presentation records occupy complete stdout lines prefixed by
`VINIX-PACKAGE-PROGRESS ` followed by a format-1 JSON object. The producer flushes
each frame. Readers must handle frames split across pipe reads and multiple
frames in one read. These events neither authorize changes nor replace exit
status, payload verification or the installed-state protocol.

Every record explicitly contains `format`, `phase`, `package`, `repository`,
`path`, `current` and `total`. Phases are `resolve` (resolved reviewed inputs),
`metadata` (signed catalog transfer), `download`, `verify`, `copy` (staged payload),
`stage` (staged package count), `activate` and `complete`. Package/repository IDs
may be empty when a phase covers the entire operation. Paths are safe relative
payload/metadata paths. Download/copy counters use bytes; stage counters use
packages. A zero total is indeterminate. A byte counter reaching its total
does not mean the transaction completed. `resolve`, `verify` and `activate`
have zero counters; `complete` has `current:1,total:1` and is emitted only after
the relevant durable publication/activation succeeded, including unchanged
transactions. Failures may leave a partial phase and emit no completion event.

Downloads preserve bounded partial files for transport retries and promote only
verified bytes. If a completed resumed transfer fails its signed size/hash check,
the service discards that partial and retries once from byte zero at the same
source. Invalid complete/oversized partials start fresh directly. Fresh-transfer
integrity failures stop; transport failures retain their new partial. Progress
may reset to zero during recovery, and completion still requires activation.
Metadata, payload verification and offline sources require ordinary regular
files; directories/FIFOs in partial cache paths refuse before transfer. See
[download recovery qualification](../../tests/packages/download-recovery-check.md).

Existing partials must have exactly one hard link, even when already complete
or invalid/oversized. Unsafe shared partials are retained for inspection without
changing the other file's bytes or permissions. Retire only the partial alias
under the writer lock or with workers stopped; an ordinary verified partial can
then retry without its upstream object. Promotion captures the object directory
and partial, verifies length/hash on that descriptor, checks named identity/link
count before mutation/publication, and uses captured `fchmod`/`fsync` and
directory-relative atomic rename. Interrupted flushes retry. A post-publication
storage failure reports **cached payload saved**; it does not report transaction
completion. See [cache-promotion checks](../../tests/packages/cache-promotion-check.md).

An HTTPS server's explicit byte-range refusal (curl exit 33) also discards the
prefix and permits one fresh transfer. A completed fresh fallback is classified
as fresh, so an integrity failure cannot trigger another transfer. Certificate,
hostname, access-denial and redirect failures preserve the prefix. The existing
HTTPS-only, TLS, size and retry/time bounds apply to both attempts. See
[real TLS transport qualification](../../tests/packages/https-check.md).

HTTPS output rechecks captured size, named identity and the single-link rule
after admission/progress callbacks and before writing each body chunk. A changed
file stops further writes, including when only an empty response remains; final
progress cannot change it and still produce transport success. Flushes retry
`EINTR`; other storage errors retain bounded data for inspection and retry.
These checks require controlled package directories and the writer lock; they
do not freeze concurrent administrator changes between system calls. See
[callback/recovery qualification](../../tests/packages/https-output-guard-check.md).

Frames are bounded to 8192 bytes. Identifiers/paths, phase-specific counter
limits, JSON field types and formats are validated by
[`pkgprotocol.decode_progress`](pkgprotocol/progress.v). The nonrecursive reader
also rejects unknown/escaped-duplicate fields, invalid UTF-8 and noncanonical
numbers, and retires partial results on refusal. Decoded events own their
strings; `.close()` releases them under manual memory management. Operation consumers
ignore unsupported/malformed frames and continue to report human diagnostics
and process exit status. Counter progress is sampled approximately every 200 ms
during HTTPS transfers and local copies, plus initial/final transfer counters;
package and verification boundaries may emit additional frames.

Software's dedicated Verify worker exposes Stop/Cancel/Escape in full and
compact views. Cancellation kills/reaps only that read-only scan, discards its
unaccepted progress, pending bytes and human output, and preserves catalog
query/filter/selection for a fresh retry. Search focus is left when starting
the scan; pasted Escape does not trigger cancellation. A `complete` frame keeps
a waiting status until the worker exits, including when subsequent human output
claims success. Late failure output remains available for final diagnostics.
Only successful exit with final completion admits success. Transactions and
running applications can emit `verify` frames without acquiring these stop
controls. Service arguments, authorization, scan behavior and progress format
are unchanged. See [navigation checks](../../tests/packages/software-verify-navigation-check.md).

V administrative clients set `Service.progress` to an optional observer.
Config-taking transaction fixtures use `TransactionOptions.progress`; the service
uses its own configured observer when forwarding transaction options. Callbacks
receive borrowed event strings valid for the call: clone any retained fields,
and do not close borrowed events. Observers are presentation hooks, outside the
review identity; current trust, policy and resolved inputs are still checked
under the package lock. No observer enables an installation cancellation mode.

Maintenance commands load configuration under the package writer lock; read-only
review/plan/status/verification use its reader lock. The command's startup cannot
retain an older policy or publisher after a completed administration change.

State locks and generation leases require one hard link and the same named
regular inode at admission and after acquiring the nonblocking lock. Writers
change lock permissions only after exclusion. Collection and data purge recheck
the lease relative to its captured generation directory; a shared or replaced
lease refuses. Stop workers/applications before restoring trusted coordination
files. These checks do not freeze later administrator namespace changes. See
[coordination identity checks](../../tests/packages/coordination-identity-check.md).

`verify`, including `--json verify`, checks all installed payloads before reporting
success. Readers and launches return a busy-transaction diagnostic promptly.
`--progress verify` uses the existing format-1 indeterminate `verify` frames:
one scan-start event, an event identifying each payload and application launcher,
and `complete` only after all checks pass. It remains read-only under one reader
lock. Plain and JSON Verify output retain their existing shapes; `--progress`
cannot be combined with `--json`. A failed scan emits its diagnostic and no
completion or partial JSON state. Status does not scan or emit verification
progress. Empty/fresh installations report a completed empty scan without
creating package state. Integrity verification does not authorize launch or
require a working catalog, repository history, network or publisher enrollment.

Software's **Verify installed** starts this read-only worker without an
administrator prompt or catalog refresh. It preserves the current package list,
filter and selection, shows streamed check paths, and retains failures in
**Failure details** with repair guidance. Success stays visible instead of being
replaced by a catalog reload. Exit failure or a missing/finally superseded
completion frame cannot report success. The window may close during a scan;
closing stops only its verification reader. Review confirmation screens do not
offer verification. See [verification checks](../../tests/packages/verify-progress-check.md).

`health` inspects every installed package even when earlier packages have issues.
It takes no IDs and returns exit 0 when the complete report was produced,
including reports with integrity issues. Configuration/state/lock failures still
return nonzero. Scripts use `--json health` and inspect the rows, or use `verify`
when they need a nonzero exit for damaged installed files. `--progress health`
emits flushed format-1 progress records on stderr, leaving the human report on
stdout. It also supports `--json --progress health`: stdout contains exactly the
same complete JSON snapshot as `--json health`, and stderr carries progress or
fatal diagnostics. Consumers must drain both pipes, including after process
exit, and require exit 0 plus a valid complete report; a completion frame alone
does not establish success. Other commands retain their stdout progress format
and continue to refuse `--json --progress`.

The owned SDK 1 `pkgprotocol.HealthReport` contains required `format:1`,
`generation`, `architecture` and `rows`. Rows are sorted by unique ID and require
`id`, `name`, `version`, `kind`, `repository`, `public_key`, `issue` and
`diagnostic`. `issue` is empty for verified files/registration, or `namespace`,
`payload`, or `registration` for the first issue in that package. Every package
gets a row; a clean application row does not assert that its dependencies are
healthy. Counts are derived from the rows. These are installed provenance
records, not a current publisher/trust claim or repair approval.

`Service.health()` holds one reader lock, loads configuration/state without
loading catalogs, and returns independent owned presentation fields. Its optional
observer emits indeterminate `verify` frames for packages and `complete` when
the report is finished, even if issues exist. It writes no health cache or state.
Missing, expired, damaged or revoked repository metadata does not prevent an
integrity observation. The report does not relax trust or policy for repair or
launch, and it does not inspect personal data or extraneous generation-global
names. Existing controlled-parent and same-authority mutation limits apply.

`decode_health` rejects missing/unknown/escaped-duplicate fields, wrong types,
invalid UTF-8, noncanonical/overflowed counters, unsorted/duplicate IDs and
incoherent issue/diagnostic pairs. Responses are bounded to 8 MiB and 4,096 rows;
diagnostics are at most 384 UTF-8 bytes. The scanner escapes unsafe filesystem
bytes and visibly marks truncation. `HealthReport.close()` retires service-created
or decoded rows. Software's **Health report** lists problems first and pages the
complete retained provenance and diagnostic; **Review all repairs** obtains a fresh
version-preserving repair review before administrator confirmation. See
[health report qualification](../../tests/packages/health-report-check.md).

Software shows the currently inspected package and indeterminate progress. It
accepts one initial `verify` frame, bounded package/repository `verify` frames,
then one `complete` frame. It requires the number of package frames to match the
decoded report rows, drains stderr independently of the 8 MiB stdout snapshot,
and refuses malformed, partial, out-of-order or oversized progress and any
stderr diagnostic, including after completion. Failure details retain the bounded
stderr tail. **Stop inspection** or Escape kills and reaps only this read-only
worker, discards partial results and leaves Reload available; compact windows
also offer Stop. Closing the window uses the same read-only worker retirement.
See [progress/cancellation checks](../../tests/packages/health-progress-check.md).

Software also accepts Cancel for the pending health read. Stop clears buffered
stdout, pending stderr, errors, package counts, report pages and truncation
state; the query/filter and prior diagnostics remain for a fresh Reload.
Compact views expose Reload, status/progress, failure access and the generation
summary when space permits, while retaining selection and detail paging across
resizes. A complete progress frame shows a waiting status until process exit;
the existing strict report/count/progress/exit admission remains unchanged. See
[health navigation checks](../../tests/packages/software-health-navigation-check.md).

On a fresh image, status/verification do not initialize package state. Direct
administrator edits to configuration must honor the same lock or quiesce package
operations; arbitrary root filesystem writes are outside this contract.

Changed install/remove/upgrade/deployment reviews also preflight the exact future
generation's serialized state, including its generation and previous counters.
The persistent state must fit the existing 8 MiB metadata limit even when every
signed repository and individual manifest is valid. Apply repeats this check
under its writer lock before retiring abandoned stages, acquiring objects or
creating a generation. Oversized state returns a diagnostic asking for a smaller
requested set or less package metadata; the active state, caches and recovery
work survive. A successful apply writes the same bytes it preflighted. No-op
reviews and rollback retain their existing behavior. See
[generation metadata checks](../../tests/packages/state-preflight-check.md).

Catalog reads authenticate each selected signed index once and check retained
sequence/digest floors before exposing its manifests. Temporary decoded cache
wrappers, histories and index envelopes retire after the read; returned package
fields remain valid. Configured publisher identity strings retain their existing
borrowed lifetime. A later repository's signature, schema, expiry, identity or
replay failure returns no partial catalog. Revoked snapshots remain ignored by
catalog admission, without weakening enrolled publisher checks. The
[catalog ownership qualification](../../tests/packages/catalog-ownership-check.md)
records that initial reduction and its remaining allocations.

Model admission now checks identifiers, digests, printable fields, relative paths
and version components directly from their bytes. Manifest, dependency,
configuration and organization-policy validators release their duplicate maps
on success and rejection. Path collision checks borrow a prefix only for map
membership. These functions preserve their borrowed inputs and existing error
messages. `version_parts` still returns an owned three-element array; clients
using manual memory management must free it, and rejected calls return only an
owned diagnostic. The [validation memory qualification](../../tests/packages/validation-memory-check.md)
measures model scratch separately from decoded metadata, returned errors and
whole-service memory.

Refresh incrementally encodes authenticated snapshot wrappers in their existing
JSON array format. After each repository passes signature, schema, expiry and
retained sequence/digest checks, its serialized prefix must fit the 8 MiB cache
limit, including commas, JSON escaping and the final closing bracket. A prefix
that cannot fit fails before later repositories are fetched or the new catalog
is decoded. The existing cache and replay history remain unchanged; refresh's
temporary workspace is removed. A smaller set of metadata can retry normally.
Fetched signed text, its decoded indexes and encoder buffers retire on
success and failure; returned catalog manifests remain independently owned.
See [cache preflight qualification](../../tests/packages/cache-preflight-check.md).

Replay-history updates and legacy-cache migration return independent identity,
key and digest fields. Their internal consumers retire the superseded history
and temporary authenticated indexes instead of keeping borrowed snapshots alive.
Repository status transfers those owned history records to its result; reviewed
enrollment and publisher release retire their private copies after use. Sorting,
identity limits, rollback/equivocation checks, retired-key recovery and persistent
JSON stay compatible. The [history ownership qualification](../../tests/packages/history-ownership-check.md)
separates history/hash scratch from remaining reader and whole-service memory.

Configuration and consumer/publisher replay-history serialization use owned
buffers that retire after writing or refusal. The 8 MiB persisted-document limit
includes the trailing newline, and overflow preserves the previous document.
Repository review identities keep their exact existing JSON and SHA256 digest;
their combined hash input does not acquire a persisted-document size limit or
newline. Enrollment/revocation retire temporary comparison digests after use.
See [administration metadata qualification](../../tests/packages/administration-metadata-check.md)
for byte compatibility, boundaries and measured serializer/hash ownership.

Signature decoding scans the caller's string with fixed scratch and returns an
owned 64-byte result only for a valid hex representation. It preserves the six
ASCII outer whitespace bytes, optional `0x`/`0X`, mixed hex case and a 127-digit
form with an implicit leading zero. Invalid hex retains its first-byte/index
diagnostic before wrong-length refusal. Scanning remains linear in input size;
the verifier still checks index size, publisher key, cryptographic signature,
metadata identity and expiry in the same order. See
[signature decoding qualification](../../tests/packages/signature-decoding-check.md).

Enrollment transfers loaded signed text only after signature and metadata
admission; every earlier failure retires those inputs. Temporary proposals own
their array and cloned new publisher identity, while retained identities and
policy borrow the current configuration. Read-only reviews retire these
proposals and their decoded configuration after cloning the returned review
fields. Rejected review construction retires its partial owned fields too.
Metadata descriptor reads keep synchronous `stat` scratch on the stack.
See [enrollment ownership qualification](../../tests/packages/enrollment-ownership-check.md)
for failure/retry, ownership and persistent-trust checks.

Configuration JSON preserves legacy omitted-field defaults, including partial
policy objects. Present fields must have the declared JSON types; null values,
unknown keys and duplicate keys (including escaped equivalent spellings) are
rejected at the envelope, repository, policy and version-pin levels. Explicit
empty arrays, false booleans and zero reserves keep their meaning. This prevents
a policy typo from silently selecting default permissions or an unrestricted
allowlist. Rejection happens before transaction cleanup or acquisition and
preserves configuration bytes, cached metadata and installed generations. Restore
valid configuration under the same package lock before retrying. See
[configuration qualification](../../tests/packages/configuration-check.md).

V administrative clients can use [`pkgcore.Service`](pkgcore/service.v) with
`root` and a per-command `offline` flag. It retains no configuration snapshot.
Its `refresh`, `transact`, `deploy`, `plan`, `review`, `rollback`, `collect`,
`mirror`, `review_mirror`, `apply_mirror`, `state`, `verify`, `health` and `run` methods acquire the appropriate lock before
loading configuration. Config-taking core functions remain explicit snapshot
operations for isolated fixtures; they do not reload administrator configuration.
Production clients should use the service or the versioned CLI protocol.

`deployment-lock [ID...]` emits a format-2 `{format,architecture,packages,locked}`
document. `packages` contains sorted explicit roots; `locked` contains the entire
resolved dependency/runtime closure, sorted by ID. No IDs selects the current
requested roots; explicit IDs replace them. Resolution prefers authenticated
installed versions, otherwise the latest compatible candidates. Each locked
record requires `id`, `version`, `architecture`, `repository`, `public_key`,
`minimum_sequence` (positive unsigned 64-bit) and `metadata_sha256` (lowercase
SHA-256). Roots and records are unique and bounded to 4096 each.

`pkgprotocol.decode_deployment_document` reads either deployment format into an
owned `DeploymentDocument`; call `close()` when finished, including under
`-gc none`. The JSON schema, 8 MiB input limit, 128-byte IDs, 29-byte versions,
16-byte architecture fields, 64-byte key/digest fields and 4096-entry arrays are
enforced during parsing. Unknown/duplicate/escaped duplicate, missing, null,
coerced, truncated and trailing fields fail with partial storage released. Field
order and unique escaped keys remain valid; format 1 forbids `locked`, while
format 2 requires it. This wire decoder checks structure and bounds. The service
also validates IDs, canonical versions, digests, positive sequences, target
architecture and uniqueness, then authenticates catalog provenance and policy.
Decoding alone grants no trust or deployment authority. See
[decoder qualification](../../tests/packages/deployment-decoder-check.md).

The metadata digest is SHA-256 of SDK-1 JSON encoding of the complete `Package`
struct, plus a terminating LF. Fields follow the order in [`model.v`](pkgcore/model.v),
including empty/default fields; files sort by path, dependencies by ID,
permissions and MIME associations lexically. Launch arguments retain their order.
`package_metadata_digest` is the supported V implementation. Repository identity,
key and minimum sequence are separate lock fields; index expiry/sequence renewal
does not change the manifest digest. Every selected package must match exact
ID/version/architecture/publisher/digest in the current authenticated catalog,
whose signed sequence must meet the lock floor and persistent replay history.
The regular resolver still checks policy, installed publisher ownership, version
ranges, runtime entrypoints and full closure; unused/missing records fail.
Exact matching indexes pin IDs and scans the authenticated catalog once, using
storage proportional to the number of pins. Candidate results borrow catalog
manifest fields, and matching/digest scratch is retired after use. More than one
exact identity refuses as ambiguous even if one record has the approved digest.
Canonical metadata digest bytes retain their SDK-1 definition above. See
[matching qualification](../../tests/packages/deployment-candidates-check.md).

`deployment-snapshot [INSTALLED_ID...]` emits the same format-2 document from
installed metadata alone. Without IDs it records every explicitly installed
root; explicit IDs select installed roots and their complete transitive
dependency/runtime closure. Missing, invalid or duplicate IDs fail. Roots and
records are sorted; versions, architecture, publisher identity, original sequence
floor and canonical manifest digest come directly from the captured generation.
It cannot substitute newer catalog versions. The reader lock protects the
snapshot, and a fresh empty system returns an empty document without creating
package state. It requires no repository, catalog, cached object or replay-history
access and remains available after publisher revocation or a policy change.

This exports historical metadata, rather than backup payloads or evidence that
the recorded apps are healthy or currently authorized. Deployment review/apply
and offline mirror export still require the exact manifests in an authenticated
catalog, current publisher keys, replay floors and policy admission. If a version
has been withdrawn, restore it in approved repository media before deployment.
Snapshotting does not enroll a key, accept a license or bypass an expired index.
Use `Service.snapshot_deployment(names)` from V. Both this method and
`Service.lock_deployment(names)` return independently owned `DeploymentLock`
fields; `.close()` retires the returned document. See
[installed snapshot qualification](../../tests/packages/deployment-snapshot-check.md).

Construction borrows installed manifests only until the independent lock is
built. Selection and JSON encoding scratch, including buffer growth, retire on
success or refusal. Saved receipts and audit input digests retire hash scratch
while preserving exact bytes. Stored configuration/state readers also retire
partial fields on refusal, bound nested collections during parsing and preserve
legacy defaults. Stored integer fields require canonical unsigned decimal
spelling. Native tracking and sanitizers cover 100 repeated public snapshot,
save, audit and existing-file-refusal cycles in an isolated store, alongside
the construction fixtures. This does not qualify every service operation or
system-root caller. See [construction qualification](../../tests/packages/deployment-observation-check.md)
and [stored metadata qualification](../../tests/packages/stored-decode-check.md).

`deployment-snapshot-save NEW_FILE [INSTALLED_ID...]` saves that same sorted
format-2 snapshot plus one terminating LF. The reader lock covers generation
capture and publication. Catalogs, replay history, cache objects, payload health
and current repository/policy admission are not consulted. Invalid/missing roots
or malformed state refuse before a temporary file is created. A fresh store
produces an empty file/document without initializing package state. The
destination is a literal absolute or relative path in the caller's filesystem;
`--root` selects only the installed package store, not the export location.
Parents must already exist. Paths are nonempty printable UTF-8 up to 4096 bytes.

Publication captures an ordinary parent descriptor without following a final
parent symlink, creates an exclusive random 0600 sibling temporary, handles short
and interrupted writes, sets 0644, flushes the file and atomically renames it with
exclusive creation. Existing ordinary/special files, dangling aliases and
directories fail before writing; destinations created during capture/write also
refuse at publication. Directory flushing and final parent/file identity,
size/link-count/mode admission complete before success. Filesystems lacking
exclusive atomic rename report failure. Normal prepublication errors clean only
the owned temporary and leave the final name absent or the racing name intact.
Postpublication failures retain the saved name and explicitly say it was saved;
inspect that file and storage before retrying. Abrupt termination may leave a
hidden `.package-*.tmp` sibling. After the process has stopped, its owner may
inspect/remove that specific leftover; retry never imports or sweeps it. Keep
destination ancestors controlled; simultaneous same-user in-place content edits
are not frozen by this API.

With `--json`, success returns a format-1 receipt requiring `format`, `generation`,
`architecture`, `destination`, `sha256`, `roots`, `packages`. The digest identifies
the exact saved bytes including LF; it is not a signature. Counts are unsigned,
at most 4096, roots cannot exceed packages, and zero roots/packages agree. A
generation-zero receipt is empty. CLI errors return 1 without a success receipt;
`--progress` is unsupported. V clients use
`Service.save_deployment_snapshot(path, names)` and
`pkgprotocol.decode_deployment_saved(text)`; returned receipts own their strings
and `.close()` retires them. The bounded 32 KiB reader requires complete typed
fields, canonical unsigned numbers and coherent counts; duplicate/unknown keys,
bad UTF-8/paths/digests and trailing data refuse with partial cleanup.

`atomic_write_new(path, text)` exposes the same bounded new-file writer to V
clients. Existing `atomic_write` replacement semantics remain unchanged. Saving
metadata does not enroll publishers, export payloads, accept licenses or bypass
authenticated deployment/mirror admission. It is outside the administrator
mutation transport and can run under an ordinary identity into an owned
destination. See [snapshot-save qualification](../../tests/packages/deployment-save-check.md).

Software's **Deployment → Save installed…** invokes this command without installed
IDs, using ordinary literal argv and a newly entered absolute destination. It
buffers at most 32 KiB and admits a receipt only after exit 0 and complete output,
with `destination` equal to the independently captured argument. Error exits,
partial/oversized documents and destination mismatches cannot expose success.
The worker blocks navigation and ordinary closing until it finishes, because
publication can occur before a receipt is returned. Receipt strings and paged
details are retired on Back, Save another or application retirement. Full
destination, digest, architecture, generation and both counts remain inspectable.
Fresh audit/review actions reuse the captured filename, never the editable form
or receipt as authorization. Diagnostics retain postpublication failures; no
automatic retry or overwrite is attempted. See
[Software save qualification](../../tests/packages/software-deployment-save-check.md).

For a nonempty receipt, Software's **Export offline…** action transfers owned
copies of the captured filename and saved bytes' SHA-256 into an exact locked
export intent, retires the receipt, and clears the destination field. It invokes
no service until the user chooses a new directory and requests review. Source
and scope controls are fixed for this flow; mutable form storage cannot redirect
the captured filename. `mirror-deployment-review` must return that source and
the saved digest as well as the requested destination. A mismatch closes the
decoded review before exposing confirmation, retains the source pin for retry,
and explains that a new snapshot is needed after source changes.

The existing path/digest disclosure, authenticated package/license review,
administrator confirmation, stale-input admission and atomic mirror publication
still apply. Canceling review retains the export intent; Back, opening a general
export, leaving for maintenance, or application retirement frees its owned source
and digest. Publication does not change installed applications. See
[saved export qualification](../../tests/packages/software-snapshot-export-check.md).

Software treats export review and approved publication as separate worker phases.
Only an active read-only `mirror-review` or `mirror-deployment-review` worker can
be stopped. Stop, Cancel and Escape kill and reap it, close its pipes, clear the
pending review and buffered response, and retain the destination and optional
saved-source/digest intent. Even a complete JSON document is discarded if the
worker has not exited. Retrying creates a fresh review with no old fingerprint
or path-page approval. Approved apply workers ignore these cancellation actions
and keep the existing close guard until they finish.

Compact export screens expose Stop, Cancel, Back, or Back to review according to
the active phase and nested package-details mode, plus current status, progress
and failure-detail access. They expose no confirmation button. Resizing preserves
the review and its page-disclosure state. See
[navigation qualification](../../tests/packages/software-mirror-navigation-check.md).

`[--json] deployment-audit FILE` compares an exact format-2 document with one
reader-locked installed generation. It does not resolve against a catalog, read
objects/replay history, verify installed payloads or apply policy/trust admission.
It works offline and after publisher revocation, and observes a fresh store
without initializing it. Format-1 root requests cannot specify exact desired
metadata and are refused. Every requested root must have a locked record.

The format-1 report has required `format`, `generation`, `architecture`,
`deployment_sha256`, `matches` and `rows` fields. The digest identifies the exact
captured file bytes, including whitespace. Rows are the sorted union of target
and installed IDs, with required `id`, `status`, `expected_version`,
`installed_version` and `differences`. Status is `match`, `missing`, `unexpected`
or `changed`. Absent versions are empty only for missing/unexpected rows, whose
differences are empty. Changed rows name every differing field, sorted:
`architecture`, `metadata_sha256`, `public_key`, `repository`, `requested`,
`sequence`, `version`. `sequence` means the installed sequence is below the lock's
minimum; a higher sequence satisfies that floor. Requested-root changes count
even when the complete package set is otherwise identical. Missing/unexpected
packages remain visible when auditing a subset or an empty deployment.

The CLI emits a complete report with exit 0 for a match or 3 for drift. Errors
return 1 without a report. `--json` preserves the complete structured report on
stdout for both 0 and 3; `--progress` is unsupported. V clients use
`Service.audit_deployment(path)` and `pkgprotocol.decode_deployment_audit(text)`.
Returned reports own their fields and support repeated `.close()`. Decoding
requires complete typed fields, canonical unsigned integers, coherent versions,
status/differences/result, sorted unique IDs/field names, at most 8192 union rows
and at most 8 MiB. Unknown/duplicate keys and trailing input fail with partial
allocation cleanup. The maintained signed CLI probe exercises audit as well as
snapshot export; see [qualification](../../tests/packages/deployment-audit-check.md).

A match is metadata drift detection. It does not authenticate the supplied lock,
attest filesystem health, reauthorize a revoked package, or prove that current
repositories can reproduce it. Use `health` for installed integrity and the
existing authenticated deployment review/apply flow for changes.

Software's Deployment form offers **Check installed** for format-2 documents.
It calls `--json deployment-audit FILE` directly, buffers the complete bounded
reply, waits for process exit and accepts only coherent 0/match or 3/drift pairs.
Other exits, malformed/incomplete/oversized replies and contradictory results
produce failure diagnostics without accepting a partial report. The read-only
worker can be stopped or closed without transaction authorization.

The report retains its own source filename, generation, architecture, exact input
digest and all package rows. Paged details include every changed field, expected
and installed versions, requested-root differences and sequence-floor meaning.
Reload retires the previous report before starting and uses the captured filename;
editing the deployment form cannot redirect it. The compact view retains Back or
Stop. **Review deployment** retires the observation and calls `deployment-review`
on that same filename, reading current bytes and obtaining a fresh authenticated
proposal. Confirm and administrator authorization remain separate actions. See
[Software audit qualification](../../tests/packages/software-deployment-audit-check.md).

Software projects deployment audit rows into a difference-first list of canonical
row indices. Search matches IDs, raw result status, expected/installed versions
and changed field names without case sensitivity; an independent differences-only
filter excludes matching rows. The selected row keeps its report identity when
still visible and moves to the first visible row otherwise. No visible row means
no package selection; global source/digest/generation details remain available.
Filtering keeps the selected row on a visible page, and resizing recomputes that
page without undoing deliberate paging on ordinary redraw.

Audit query text accepts at most 256 UTF-8 bytes without controls. Invalid or
oversized edits leave the query intact; Backspace retires a complete character.
Reload and Stop preserve query/filter choices while retiring the old observation.
Back, fresh reconciliation and application retirement release query, projection,
result-count and detail storage. The filters never change the captured document,
the report's full totals or the arguments to a new deployment review. See
[search qualification](../../tests/packages/software-audit-search-check.md).

`deployment-review FILE` emits the existing format-1 `pkgprotocol.Review`, with
operation `deploy`, complete target/removal rows and disk requirements. Its opaque
fingerprint binds a deployment-specific domain, canonical document, configuration,
installed state and exact authenticated plan. `deployment-apply FINGERPRINT FILE`
rechecks these under the writer lock before stage cleanup, acquisition or
activation. File-specific and generic `review/apply deploy IDs` fingerprints are
not interchangeable. Whitespace and root/record ordering do not change identity;
changed lock floors, format, policy, state or selected metadata require review.
An unchanged successful proposal can reuse its fingerprint. Installed payload
health also binds the fingerprint as described below. Apply progress is
human text by default; `--progress` adds the bounded presentation events described
above. Authorization remains administrator access.

Both file commands also accept format-1 `{format,architecture,packages}` root
documents, which resolve the latest satisfiable closure. `deploy FILE` supports
both formats without a review fingerprint for existing administration scripts.
Inputs require explicit fields and JSON types, matching architecture, bounded
regular files and unique roots/records; null, unknown/duplicate keys and malformed
digests/versions fail. An explicit empty root set in either format removes the
complete installed application/runtime/data closure; format 2 must also have an
empty `locked` array. Generic `review deploy` / `apply FINGERPRINT deploy` with
no IDs has the same empty target, using its own review domain. Empty targets
require validated configuration and coherent installed state, but no catalog,
replay history or cached payloads, so removal remains available offline or after
publisher revocation and policy tightening. Reviews disclose every removed
package's historical provenance, permissions, license and firmware flags.
Confirmation still checks review identity, writer exclusion, disk reserve and
transactional staging/recovery. Personal data and retained generations remain;
rollback retains current publisher/policy and retained-generation integrity
checks. Reviewed rollback needs its own approval. An already empty target
creates no new generation.
See [empty deployment qualification](../../tests/packages/deployment-empty-check.md).
No deployment changes trust/policy or refreshes implicitly. URLs are intentionally
unbound: approved signed mirrors work offline with the same publisher and lock,
subject to normal expiry/replay checks and availability of every locked object.
Rollback/data retention use the standard transaction contract.

Install, upgrade and both deployment formats verify unchanged target payloads
before treating a plan as a no-op. Missing, wrong-length, corrupt or nonregular
files trigger a new generation using verified cache/approved repository objects.
Software's **Repair installed** opens `review repair` for the entire installed
closure, including runtimes and data dependencies. This operation takes no IDs
and preserves exact installed manifests, provenance/sequence, versions,
permissions and requested roots. Each installed manifest must remain in the
authenticated current cached catalog with the same repository and key, and pass
current policy. A withdrawn or changed manifest fails explicitly with guidance
to refresh or review updates; repair never selects a newer version. No implicit
refresh occurs. Offline repair requires unexpired authenticated metadata and
usable objects. `repair` is also available directly to administrator scripts,
or as `apply FINGERPRINT repair` through reviewed administration.

Format-1 review admits the additive `repair` operation with empty `names`, zero
`target_generation`, and only `keep`/`update` rows whose installed and target
versions match. Older clients that do not support the operation reject it.
Software displays these update rows as repairs. The protocol uses the
existing `update` row action for each affected package, including unchanged
versions, and budgets the full transaction. It adds no protocol fields or row actions.
The opaque fingerprint binds sorted affected IDs; healthy fingerprints retain
their previous shape. Apply checks health under the writer lock and again after
the resolve observer, before cleanup/acquisition. A changed repair set requires a
fresh review. Matching damage can reuse its prior review; successful repair makes
that review stale. Healthy identical targets remain a no-op.

Repair grants no repository authority, permissions or license exceptions and
does not refresh catalogs implicitly. The normal signed source, space, cache,
staging and activation checks still apply, including offline operation. Personal
data remains outside the generation. Previous generations remain available for
inspection, but rollback still refuses broken payloads. Payload health checks
retain no scratch allocations under manual memory management; this does not
claim whole-service allocation freedom. See
[repair checks](../../tests/packages/repair-check.md).
See also [explicit repair checks](../../tests/packages/explicit-repair-check.md).

Installation health includes the canonical payload modes: 0755 when the signed
`executable` flag is true, otherwise 0644, with no setuid/setgid/sticky bits.
Verification checks the captured descriptor before/after hashing and its final
named identity/mode. Object caches and publisher sources keep their separate
mode rules. Non-runtime/data packages also require a regular desktop launcher
at mode 0644, with leaf symlinks refused and the exact service-generated Name, Comment,
Exec, MIME and package/runtime fields derived from installed metadata. Canonical
launcher bytes are unchanged, and staging sets their mode independently of umask.

Verify, rollback and ordinary launch enforce payload modes and desktop registration.
Launch completes these checks before executing the application closure. Repair uses
the existing affected-package IDs and `update` rows for these faults, so its
space, stale-confirmation, trust/policy and offline behavior remains the same.
Checks are read-only: repair stages fresh files rather than chmodding installed
files or launcher aliases. A healthy hard-linked regular launcher is readable;
a changed alias is never repaired in place. Per-user MIME defaults and personal
data remain outside this projection. See
[installation health checks](../../tests/packages/installation-health-check.md).

Launcher verification captures the generation, `share` and `applications`
directories without following aliases, requires the generation administrator’s
ownership, one filesystem and final 0755 directory modes, then opens the 0644
launcher relative to the captured parent. File type, owner, size, canonical bytes
and named identity are checked through that descriptor, and all parent identities
and modes are checked again after reading. Runtime/data packages retain their
no-launcher contract. Private stages admit their pre-flush directory modes before
the existing full publication checks. Parent faults appear as `registration`
health findings for affected applications and produce exact-version repair rows;
repair builds fresh directories without touching alias targets. Ordinary launch
refuses these faults before creating personal data or executing a runtime. See
[launcher parent qualification](../../tests/packages/launcher-parent-check.md).

V clients use `Service.lock_deployment`, `Service.review_deployment`,
`Service.apply_deployment`, `DeploymentLock`, `DeploymentPackage` and
`package_metadata_digest`. Returned reviews own presentation fields and use the
usual `Review.close()` contract. Configuration is loaded after taking the lock.

Software's Deployment form uses these file-specific review/apply commands. It
retains the complete decoded review, freezes the literal file path, and closes the
snapshot on cancellation, failed review or handoff to apply. Other SDK clients
should preserve that same intent: the returned `names` describe roots read from
the document and must not replace the reviewed file in a generic `apply deploy`
call. Keep the path available for retry and preserve the nonzero service exit and
diagnostic tail separately from progress events.
The [Software deployment checks](../../tests/packages/deployment-ui-check.md)
cover this workflow and snapshot retirement independently of the service tests.

Software can stop only the pending read-only `deployment-review` worker, with
Stop review, Cancel or Escape. It kills and reaps that child, closes its pipes,
discards all unaccepted output and retires the proposal and fingerprint. Even
complete JSON received before exit is discarded. The literal form filename
survives, so retry obtains a fresh proposal. Approved `deployment-apply` workers
keep their existing close guard and ignore these cancellation actions.

Compact deployment screens retain phase-appropriate Back/Stop/Cancel controls,
Back to review from nested package details, current status, progress and failure
access. They expose no confirmation control. Snapshot saving and installed-audit
subflows retain their own routing and lifecycle rules. The same protection
applies to empty deployments with complete removals. See
[navigation qualification](../../tests/packages/software-deployment-navigation-check.md).

`policy` emits a canonical format-1 `{format,architecture,policy}` document from
persistent configuration. `policy-review FILE` emits
`{format:1,architecture,generation,fingerprint,previous,proposed,rows}` without
modifying configuration or fetching metadata. Input files must contain the format,
matching host architecture and all policy fields: `offline`, `allowed`, `pins`,
`permissions`, `licenses`, `allow_firmware`, `reserve_bytes`. Boolean/number fields
use their JSON types; null/missing fields and type coercion are refused. Unknown
and duplicate object keys fail, including duplicate escaped spellings, at the root,
policy and each pin record. Unique escaped keys have the same canonical identity.
Policy sets contain unique entries; pin IDs appear once and version ranges use the
dependency contract. Allowlists/pins/licenses have at most 4096 entries, licenses
are nonempty printable strings up to 256 bytes, permissions use the five named
grants and disk reserve is at most 1 TiB. Sets/pins are sorted in output.

Review rows cover every installed package with ID/name/version/kind, license,
proprietary/firmware flags, publisher ID/key, requested-root flag and
`diagnostic_before`/`diagnostic_after`. Every row field is required with its JSON
type, including false flags and empty diagnostics. Empty diagnostics mean the complete
dependency closure is allowed by current trust and the corresponding policy.
Runtime restrictions consequently appear on dependent application rows too.
Key admission includes the same canonical non-identity prime-order check used
by launch; relaxing policy cannot repair an invalid publisher key. Diagnostic
reads validate each distinct enrolled key once per graph, with no persistent
validation cache. Configuration/state decoding stays readable for revocation.
Review needs neither a usable catalog nor a live publisher.

`policy-apply FINGERPRINT FILE` loads the complete configuration, installed state
and canonical proposed document under the writer lock, refuses stale reviews and
atomically saves only organization policy. Whitespace/list ordering does not
change proposed-policy identity; changed settings, trust, account selection or
installed state do. Successful unchanged proposals may reuse a fingerprint: it
is a freshness check, not a one-time authorization token. Both `policy` and apply
return a format-1 document. `--offline` never implicitly changes persistent policy.
Existing applications/data/generations/trust are retained; restrictive policy
still allows uninstall. Explicit administrator-owned configuration is required.

V clients use `Service.policy`, `Service.review_policy`, `Service.apply_policy`,
`PolicyDocument` and `PolicyReview`. `decode_policy_review` checks bounded complete
responses and installed provenance. Returned documents/reviews and decoded
reviews own their presentation fields; call `.close()` after use under manual
memory management. Unknown/duplicate keys in review roots, policies, pins and
installed rows are refused; formats other than 1 are
refused. See [organization administration](../../docs/application-distribution.md#offline-and-organization-deployment).

Core policy-file and review decoding use bounded readers that own every returned
string/array and retire partial values on failure. Admission enforces the 8 MiB
envelope, 4096 rows and 4096-byte diagnostics before retaining oversized values.
All seven settings remain required in administration documents/reviews; legacy
configuration defaults are unchanged. Pin `id` is required and omitted range
endpoints retain their empty defaults. `.close()` may be repeated and releases
independent previous/proposed settings. Borrowed `PolicyReview.validate()` uses
the same version diagnostics without allocating an unused version array. Writer
bytes, ordering rules and fingerprint identity are unchanged. See
[policy decoding checks](../../tests/packages/policy-decode-check.md).

`Service.review_policy` and `Service.apply_policy` retire loaded configuration,
installed state, identity buffers and paths on success/refusal. Fresh state borrows
the configuration architecture internally; installed state owns its decoded
fields. Returned documents/reviews remain independent owners. The CLI retires
review/apply results after serialization. Fingerprints still hash the original
typed JSON without a persisted newline or a new combined-input limit. Full
review output retains the existing 8 MiB bound, and an unchanged apply does not
rewrite configuration. A conservative minimum-output preflight refuses responses
already certain to exceed that bound before canonicalizing/cloning their output;
apply uses the same preflight before canonicalizing or fingerprinting its
proposal, including with a well-formed stale confirmation. Such proposals fail
with `organization policy review exceeds metadata limit` without changing
configuration or installed state. The final review encoded-size check remains
authoritative for other overflows. See
[policy lifecycle checks](../../tests/packages/policy-lifecycle-check.md).
The [apply admission checks](../../tests/packages/policy-admission-check.md)
retain the x86_64 metadata-budget diagnosis and both native guest results.

The lightweight `pkgprotocol` presentation module also supplies `PolicyDocument`,
`PolicySettings`, `PolicyPin`, `PolicyReview`, `PolicyImpact`,
`decode_policy_document` and `decode_policy_review` for the existing format-1
CLI responses. This decoder consumes **canonical service output**, requiring
sorted unique sets/pins/rows, complete typed fields, valid ranges/provenance,
unsigned integer bounds and UTF-8. It rejects unknown/duplicate keys (including
escaped spellings), missing/null/coerced fields and trailing input. Reply bounds
remain 8 MiB, 4096 allowed IDs/pins/licenses/installed rows, five permissions and
1 TiB reserve. The schema reader releases partial strings/arrays on failure and
replaced buffers under `-gc none`; presentation instances own their fields and
must be `.close()`d. Input policy files still use the service’s authoring contract,
which accepts arbitrary list order and canonicalizes it for review.

Software’s **Deployment → Organization policy** workflow freezes the literal
path and complete review, discloses all previous/proposed settings and installed
effects, and sends `policy-apply FINGERPRINT FILE` without a shell or progress
option. Ordinary callers use the existing peer-bound administrator/password
transport. Read/review are public operations; mutation retains the exact reviewed
arguments during approval. The UI checks the administrator request’s encoded
4096-byte bound before requesting credentials; an oversized escaped path requires
a shorter path and fresh review. A handed-off or failed review cannot be
confirmed again without fresh review. Apply errors invalidate cached policy; success
reloads persistent settings. The approval prompt remains responsible for masked,
bounded credential input and wiping. This UI never synthesizes a deployment,
accepts a license implicitly or changes firmware permission outside the reviewed
policy file. See [qualification](../../tests/packages/policy-ui-check.md).

Software can stop pending public `policy` and `policy-review` workers with Stop,
Cancel or Escape. It kills and reaps the child, closes its pipes, discards partial
or complete-but-unaccepted output and retires the proposal/fingerprint. A stopped
review returns to known current settings. A stopped reload leaves policy
unavailable for review until a fresh read succeeds: its cached document may
predate a completed save. The literal entered filename and any saved result
survive for retry. Completed reviews accept Escape or Cancel; idle Escape blurs
the editor first, then returns to Deployment.

Compact policy screens retain Back/Stop/Cancel, status, progress and failure
access, preserve review section/page state across resize and expose no
confirmation. Approved `policy-apply` ignores these cancellation controls and
retains its close guard; administrator approval remains separately cancellable
before submission. The subsequent read-only reload can be stopped without
discarding the saved result. Existing progress frames are displayed when
emitted; command arguments and administrator transport are unchanged. See
[navigation checks](../../tests/packages/software-policy-navigation-check.md).

`mirror-review NEW_DIRECTORY ID...` emits a format-1
[`pkgprotocol.MirrorReview`](pkgprotocol/mirror.v) envelope. Every envelope field
is required: `format`, the literal `input_destination`, canonical absolute
`destination`, nested `review`, `cache_needed`, `cache_available`, and
`shared_disk`. Its nested format-1 `Review` has `operation:"mirror"`,
`generation:0`, `target_generation:0`, the requested names, resolved roots,
complete sorted closure and `action:"export"` on every row. Rows include the
same descriptions, publisher keys, permissions, license and explicit runtime
information as maintenance reviews. `disk_needed`/`disk_available` refer to the
destination filesystem; when `shared_disk:true`, the requirement includes
missing source-cache objects. Otherwise `cache_needed`/`cache_available` describe
the separate source disk. The nested `disk_reserve` applies to each affected
filesystem. These counters are conservative budgets and may change before apply.

Call `mirror-apply FINGERPRINT NEW_DIRECTORY ID...` with the original literal
destination and names. Its fingerprint has a separate domain from maintenance
reviews and binds configuration, exact signed indexes, resolved closure,
destination argument/canonical path and existing ancestor inode/device. Review
does not create destination parents or transfer payloads. Apply checks freshness
under the writer lock before destination creation/acquisition, then rechecks
space, verifies every exported object and publishes the new directory atomically.
Cache recovery and free-space changes do not stale a review; altered media,
catalog metadata, policy or trust does. Progress emits `resolve`, transfer/copy
and verification phases, then `complete` after durable publication; it does not
emit installed-generation activation. The installed state is preserved.

Complete-stage admission runs before directory flushing and again immediately
before publication, after the final staging checkpoint. It requires the exact
reviewed repository/metadata/object namespace, original signed metadata and
captured deployment-lock bytes, ordinary single-link files, authenticated object
lengths/hashes and final modes 0755/0644. Directory enumeration is bounded by the
expected entries and refuses aliases. These read-only scans rehash unique
exported objects; they never import abandoned staging data. A failure emits no
completion, cleans the unpublished stage and retains verified cache for retry.
Controlled ancestors and stable administrative inputs remain required. See
[mirror admission qualification](../../tests/packages/mirror-admission-check.md).

For a locked organization deployment use
`mirror-deployment-review NEW_DIRECTORY LOCK.json`, followed by
`mirror-deployment-apply FINGERPRINT NEW_DIRECTORY LOCK.json`. The lock must be
nonempty format 2; format-1 root lists do not pin a reproducible closure.
The format-1 `DeploymentMirrorReview` envelope requires `format`, literal
`deployment` filename, `deployment_sha256` and a nested `mirror` with all fields
of `MirrorReview`. The nested rows describe the exact authenticated versions,
permissions, licenses and runtimes in the lock. Its fingerprint has the separate
`vinix-deployment-mirror-review-1` domain and additionally binds the original
filename and exact document digest. Whitespace edits also require a fresh review.
The input is captured once; its parsed pins, digest and exported bytes describe
one snapshot. Cache recovery does not stale that snapshot.

The atomically published media includes `_deployment.json` (mode 0644) alongside
the original signed repository directories. `pkgprotocol.deployment_mirror_filename`
names this case-sensitive file. Its leading underscore avoids collisions with
repository identifiers. The destination disk budget includes the document and
its metadata overhead. Consumers still authenticate/enroll the original publisher
keys, refresh local indexes and review/apply the copied lock; the document grants
no new trust or license acceptance. Expiry and replay floors remain enforced.
This export preserves installed state and supports `--progress` on apply.

V clients use `Service.review_deployment_mirror`, `Service.apply_deployment_mirror`
and `pkgprotocol.decode_deployment_mirror_review`. Produced/decoded envelopes own
their presentation fields; `.close()` retires nested mirror/row storage too.
Catalog mirrors and Software's existing export action continue to resolve current
catalog versions; choose the deployment-specific commands for exact lock media.

V clients use `Service.review_mirror`, `Service.apply_mirror` and
`pkgprotocol.decode_mirror_review`. Service-produced and decoded envelopes own
their presentation fields; `MirrorReview.close()` also retires the nested review.
Use the direct `Service.mirror`/`mirror` command for authorized automation that
does not need a presentation review. Mirror media retains the original signed
catalogs and expiry, and supplies payloads only for the exported closure.

`review install|remove|upgrade|repair|deploy|rollback [ID...]` emits a format-1 review
without downloading payloads or changing installed state. It includes the active
generation, rollback source generation (`target_generation`), operation/IDs, target requested roots,
and every package in the target closure plus removed packages. Rows contain
`action` (`install`, `update`, `keep`, `remove`), previous/target versions, runtime,
publisher/key, license/proprietary/firmware flags and declared permissions.
`disk_needed`, `disk_available` and `disk_reserve` are byte counts; estimates
include the complete next generation, missing cached objects and metadata.
Removal uses installed provenance and remains available after publisher expiry
or revocation; rollback verifies retained payloads and current trust/policy.

Blocked dependency removals name one retained requested package that needs the
target, including transitive dependencies and cycles. Batch names are excluded
from the retained roots. Implicit dependencies still cannot be removed directly;
review removal of the requested applications first. Guidance reads installed
state without authenticating a catalog or fetching metadata. See
[removal guidance checks](../../tests/packages/removal-guidance-check.md).

Rollback restores the source's exact manifests, provenance and requested roots
in a fresh generation, with `previous` pointing to the set it replaced. It copies
verified retained files without downloads or cache access, rebuilds registration,
and uses the same disk reserve, staging, flush, publication and activation checks
as installation. It requires space for the complete restored generation, even
when both package sets are identical or empty. The source remains immutable.
Cleanup before or after rollback preserves a usable previous generation; another
rollback undoes the restoration. Personal data is not restored or removed.

SDK 1 response fields and command arguments are unchanged. `target_generation`
identifies the retained source, not the newly activated generation. Read the
returned `State`/`status` for the fresh generation identity; scripts must not
assume rollback decreases that counter or walks older ancestors. Reviews issued
by the earlier pointer-only implementation must be obtained again. See
[transactional rollback qualification](../../tests/packages/rollback-check.md).

After review, call `apply FINGERPRINT OPERATION [ID...]` with the returned
`fingerprint`, operation and IDs. The service resolves again under its writer
lock and compares the complete manifests/payload hashes, provenance, requested
roots, active state, configuration/policy and rollback target. Changed inputs
fail with a stale-review diagnostic before cleanup, downloads or activation;
obtain a fresh review. Free-space/cache changes are checked again at apply time.
The fingerprint is an opaque freshness check, not an authorization credential;
administrator access is still required. Ordinary install/remove/upgrade/deploy
and rollback commands remain available for existing scripts.

Software can stop a pending read-only `review install|remove|upgrade|repair|rollback`
with Stop review, Cancel or Escape. It kills and reaps that child, closes its
pipes and discards the unaccepted proposal/fingerprint and output, including a
complete document received before exit. Catalog query, filter, selection and
scroll survive for fresh retry. Completed reviews can be canceled with Escape
or Cancel; Escape from nested details returns to the unchanged review first.
Search input stays inactive throughout a review or approved operation.

Compact package screens retain Stop/Cancel, details Back, catalog reload,
status, progress and failure access. They expose no confirmation control;
enlarging preserves the reviewed package selection and proposal. Approved
`apply` and repository `update` workers ignore these cancellation actions and
retain their close guard. Other Software subflows keep their own lifecycle
controls. See [navigation checks](../../tests/packages/software-package-navigation-check.md).

The lightweight [`pkgprotocol` V module](pkgprotocol/review.v) provides `Review`,
`ReviewPackage`, bounded `decode_review`, validation and explicit `Review.close()`
for consumers with manual memory management. Service-created and decoded reviews
own their presentation fields. Renderers should retain the snapshot while it
is on screen, pass literal arguments to `apply`, then close it on cancellation,
replacement or handoff. Format 1 requires every declared root and row field,
including empty strings/arrays, zero counters and false proprietary, firmware and
requested flags. Missing/null/coerced fields, unknown or duplicate keys (including
escaped spellings), invalid UTF-8/Unicode, noncanonical or overflowing integers
and trailing input are refused before a review is presented for confirmation.
Future schema extensions require a new supported format.

The same bounded reader covers `decode_repositories`, `decode_repository_review`,
`decode_mirror_review` and `decode_deployment_mirror_review`, including repository
identities/history and every nested review. Replies are at most 8 MiB; package
reviews contain at most 8192 rows, 4096 intent/requested IDs and five permissions
per row; repository and history lists contain at most 4096 entries. Strings are
bounded while decoding according to their public field contracts. Timestamps
fit nonnegative signed 64-bit seconds; package counts are at most 4096. Partial
records and replaced array buffers are released on failure under manual memory
management. Valid decoded instances retain their existing explicit `.close()`
ownership contract. Software releases refusal errors and never enables
confirmation or requests administrator credentials for malformed metadata. See
[review metadata qualification](../../tests/packages/review-metadata-check.md).

Software's **Package details…** inspector renders complete selected catalog or
review fields in six paged sections. Pages own their copied text, titles and
page labels; Back, Escape, service start, view replacement, review retirement
and close release them. UTF-8 is validated and field bounds checked before
pagination. Control bytes are escaped as `\xHH`; each page has at most fourteen
lines, with chunks of at most 48 bytes ending at UTF-8 boundaries. Page caches
can grow without retaining replaced buffers under `-gc none -manualfree`.

Catalog/update pages distinguish displayed permissions from installed launch
permissions/kind/window protocol. A service without installed launch fields
reports them as unavailable. Review pages retain the decoded snapshot and
literal deployment/export inputs without enabling actions through the inspector;
returning preserves the fingerprint, selected package and review scroll. This
presentation adds no protocol fields or package state. See the
[package-details qualification](../../tests/packages/details-ui-check.md).

[The V example](../../examples/package-hello/main.v) and target manifests show a
native payload. `v run examples/package-hello/build.v /build/new-example-repository`
cross-compiles and packs both ELF targets using the matching musl compilers.
Sign/enroll the repository, then install/verify/run/remove
on an ordinary Vinix session. Run [the V fixtures](../../tests/packages/distribution-check.v)
before publishing, and advertise only host/runtime/app tuples with retained guest
qualification receipts.

For the native launch contract, run the
[production-sandbox qualification](../../tests/packages/runtime-check.md) against
both target kernels. It checks real permissions, explicit immutable runtime
dependencies, tamper refusal and generation leases through update/uninstall/GC;
retained passing runs record hashes of the kernel, sandbox, payload, service,
session runner and serial output. These fixtures qualify package mechanics,
not the API coverage of a Linux, Windows, Apple or graphical runtime.

The [dynamic Linux check](../../tests/packages/linux-runtime-check.md) exercises
`pack-root`, this runner, a target musl loader and a shared V library under the
production sandbox on both architectures. Its receipts qualify this narrow
loader/package tuple; qualify actual upstream applications separately.

The current dynamic Linux fixture uses a position-independent executable. The
explicit loader is itself mapped as an executable, so a fixed-address program
can collide with its randomized image on the qualified kernel. Qualify that
address layout separately; the current PIE fixture is not evidence that every
fixed-address binary works. The dynamic-check documentation retains the observed
collision and the passing PIE reruns.

[Persistent package recovery](../../tests/packages/persistence-check.md) tests
abrupt QEMU termination and recovery on the same ext2 disk at the staged,
published and activated checkpoints on both architectures. It checks cached
partial-object recovery, offline upgrade, rollback, launcher removal and retained
personal-file metadata. Its receipts cover those checkpoints; publishers must
still qualify app data migrations, underlying filesystem/device crash behavior
and their runtime's API coverage.
