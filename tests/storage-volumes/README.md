# Storage-volume qualification

`--host-cipher-scrub-reference` and `--cipher-scrub-reference` qualify complete
ciphertext scrub binding to a supplied reference, private pinned inputs,
historical findings and bounded lifetimes across reordered reboot. The oracle
independently reconstructs 18 persisted files. See [ciphertext binding](cipher-scrub-reference.md).

`--host-scrub-reference` and `--scrub-reference` qualify complete historical
scrub/reference binding, native geometry, failure precedence and repeated
lifetimes across reordered reboot. The independent oracle reconstructs 24
complete persisted artifacts per guest. See [reference binding](scrub-reference.md).

`--host-data-scrub-history` and `--data-scrub-history` qualify offline multi-disk
scrub comparisons: complete reference/row binding, all four transition classes,
whole-report fingerprints, ordinary reader/output faults, unchanged live views,
repeated process lifetimes and reordered reboot. See
[scrub history](data-scrub-history.md).

`--host-data-scrub-view` and `--data-scrub-view` qualify validated offline plain
scrub inspection: complete canonical syntax and semantic checks, ordinary
reader/output faults, unchanged live mappings, repeated utility lifetimes and
reordered reboot. See [scrub report inspection](data-scrub-view.md).

`--host-data-reference` and `--data-reference` qualify offline plain multi-disk
reference comparisons: exact saved metadata, every recorded digest, complete
reports/fingerprints, ordinary reader and output failures, unchanged inputs/live
views, repeated utility lifetimes and reordered reboot. See
[reference comparison](data-reference.md).

`--host-data-auto` and `--data-auto` qualify automatic plain multi-disk checksum
creation, verification and complete scrubbing: canonical validation before
discovery, original physical pins, identity/mode continuity through publication,
exact manual/automatic artifacts, failure cleanup, bounded lifetimes and
reordered boot. See [automatic data operations](data-auto.md).

`--host-reference` and `--reference` qualify offline checksum reference
inspection/comparison: complete private inputs, exact saved metadata, full-width
reports and fingerprints, stable/changed/error precedence, unchanged inputs
and live views, repeated utility lifetimes and reordered reboot. See
[reference queries](reference.md).

`--host-ciphertext-auto` and `--ciphertext-auto` qualify automatic checksum
creation and verification in both credential domains and saved modes. They
check validation/erasure before discovery, selected physical pin continuity,
exact manual/automatic references, complete corruption detection, no-overwrite
publication, occupied views, real-KDF lifetimes and reordered reboot. See
[automatic checksums](ciphertext-auto.md).

`--host-auto-scrub` and `--auto-scrub` qualify authenticated identity-based
automatic ciphertext scanning, validation/erasure before discovery, retained
physical identity/mode, complete manual/automatic report equality, existing
destination refusal, live descriptors, real-KDF lifetimes and reordered boot.
See [automatic scrubbing](auto-scrub.md).

`--host-scrub-compare` and `--scrub-compare` qualify offline encrypted scrub
history comparisons, exact reference binding, all four transitions, complete
private input validation, output failure precedence, bounded lifetimes and
persisted history across reordered reboot. See [comparison](scrub-compare.md).

Persistent encrypted scrub findings extend the actual recovery/ciphertext model
with complete clean/changed reports, operational failure precedence, private
no-overwrite cleanup and offline report validation. `--host-ciphertext-scrub`
and `--ciphertext-scrub` qualify both domains/modes, independent reference
fingerprints, restored corruption, stable live views, real-KDF lifetimes and
historical findings across device-reordered boots. See [scrub reports](ciphertext-scrub.md).

Encrypted ciphertext references add exact public geometry/CRC binding,
full-extent native-sector streaming, independent digest checks, corruption and
post-read/post-lock device changes to the actual recovery reader/publisher
model. `--host-ciphertext` and `--ciphertext` qualify both credential domains,
private no-overwrite publication, stable live views and reordered reboot, with
four warmup/four measured real-KDF recording/recovery verification pairs. See
[ciphertext references](ciphertext.md).

Encrypted growth previews extend the actual reader/physical-probe model with
both credential domains, declared candidate capacity, signed/native-sector
extent bounds, exact original/candidate/action reports, erased secrets before
probes/output and no entropy/publication/import. Targeted `--host-growth-preview`
and `--growth-preview` modes qualify fault cleanup, four warmup/four measured
paired real-KDF/recovery previews, unchanged live views/inputs/ciphertext and
actual capacity expansion after reordered reboot. See
[growth previews](growth-preview.md).

Ordinary encrypted configuration inspection extends the same reader/discovery
model with VC1 authentication, bounded binary passphrase inputs and failed KDF
and tag paths. Targeted `--host-volume-inspect` and `--volume-inspect` modes
qualify exact reports, zero secrets before reports/probes, no imports/writable
device opens, four warmup and four measured paired real-scrypt queries, stable
occupied mappings/ciphertext and reordered reboot. See
[encrypted configuration inspection](volume-inspect.md).

Authenticated recovery inspection extends the discovery model with exact report
capture, full-width metadata, secret erasure before reports and every physical
probe, read-only candidate opens, preserved modes, input/discovery/output faults
and no import. Targeted `--host-recovery-inspect` and `--recovery-inspect` modes
qualify both commands, 200 warmup and 200 measured paired query lifetimes,
unchanged occupied mappings/ciphertext and reordered reboot. See
[recovery inspection qualification](recovery-inspect.md).

Recovery volume growth adds explicit declared-capacity checks, secret erasure
before read-only physical probes, both pinned final rechecks and signed mapping
bounds to the recovery fault model. The `--recovery-growth` guests measure
200 warmup and 200 measured plan/unlock/remove lifetimes, then adopt actual disk
expansion after reordered reboot while preserving ciphertext and RW/RO modes.
See [recovery growth qualification](recovery-growth.md).

Recovery-backup credential changes extend the private reader/publisher model
with authentication before replacement-credential access, erased buffer reuse,
no-overwrite aliases and per-stage input/publication failures. Targeted
`--recovery-rewrap` guests measure 200 warmup and 200 measured rewrap/unlock/remove
lifetimes and reopen RW/RO ciphertext after losing the old credential and
reordering disks. See [recovery credential changes](recovery-rewrap.md).

Direct recovery-key unlock extends the discovery model with exact private
backup/key inputs, header/authentication ordering, erased credentials before
disk access and input/recheck/import/report failures. The `--recovery-unlock`
guest mode measures 200 warmup and 200 measured unlock/remove lifetimes, then
reopens RW/RO ciphertext after disk reordering with ordinary keys, credentials
and configurations deleted. See [direct recovery unlock](recovery-unlock.md).

Encrypted configuration recovery adds independent ChaCha20/HMAC oracle checks,
every-byte tamper/key-half refusal and real private-reader/publication fault
coverage. The targeted `--volume-recovery` guest mode measures four warmup and
four measured backup/recover/unlock lifetimes with three production KDFs each,
then verifies production init and recovery after credential loss and device
reordering. See [configuration recovery qualification](volume-recovery.md).

Encrypted boot sets add all-64-slot/full-width metadata tests and extend the
discovery model with sorted private pairs, complete authentication and physical
preflight, independent disks/keys, late failures and retained directory replacement.
Both guests measure two-volume unlock lifetimes and production init replay after
device reordering and capacity changes. See [boot-set qualification](volume-boot-set.md).

Opt-in encrypted boot unlock adds full-width plain/encrypted conflict tests
and extends the discovery syscall model with root directory/input policy,
pinned relative reads, disabled configuration, pre-import trust rechecks and
path replacement. Production init is checked after device reordering and
capacity adoption, including capacity/contraction refusal and measured unlock
lifetimes. See [boot-unlock qualification](volume-boot.md).

Authenticated encrypted growth adds full-width/native-sector metadata tests
and extends the publication model with same-key capacity adoption, credential
buffer reuse, pinned read-only probes and pre-/post-KDF disk rechecks. Both guests
verify separate live growth with held descriptors, unchanged ciphertext,
extension conflicts, RW/RO reopening, physical adoption, reboot and contraction
refusal, with measured allocation retention. See [growth qualification](volume-growth.md).

Authenticated encrypted-volume discovery adds native syntax checks and a
sanitized syscall model covering authentication-before-scan, credential erasure,
physical aliases/duplicate identities, RW/RO modes, native geometry, pinned
rechecks and complete fault cleanup. Both guests test keyless automatic unlock,
duplicate refusal, device reordering, capacity changes and retained allocations.
See [automatic unlock qualification](volume-discovery.md).

Saved volume plans have a native V controller with no Python dependency:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host --work /tmp/volume-plan-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --work /tmp/volume-plan-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --work /tmp/volume-plan-x86
```

Each work directory must be new. Host checks cover format bounds, every
truncated prefix and single-bit corruption, checksummed invalid records,
512/4096-byte identity parsing, GPT header CRC, changed identity/geometry and
atomic file publication and discovery's regular-file/symlink rejection with
ASan/UBSan. Bundle checks include every truncated prefix and single-bit
corruption, checksummed invalid headers/later records, append rollback,
duplicate global slots/disk identities, the 6208-byte version-1/64-disk bound
and output canaries. A publisher fixture replaces only synchronous syscall boundaries;
it tests EINTR and short writes, write/file-fsync/close/rename failures preserving
the old file, and directory-fsync failure retaining the new published file with
unconfirmed durability. A destination matching a temporary candidate must survive
publication and cleanup. Both architectures' complete generated utilities are
audited for implicit heap/runtime dependencies.
Capacity tests cover offline bundle edits, unchanged identity/mode/offset,
idempotent desired lengths and failed publication on shrink, alignment,
overflow, overlap or absent slots. A restore syscall model compiles the
production preflight/application code with only open/close/status/identity-I/O
boundaries replaced. It checks explicit growth opt-in, unlisted extension and
later-slot conflicts before mutation, generation/old-size races, kernel growth
refusal, later create failure, descriptor cleanup and successful resumed replay.
Offline mapping configuration tests cover additions to empty disks, middle/last
removal, preserved identities/order/modes, freed slot reuse across disks, full
64-slot/disk bounds, complete rollback of invalid additions and unchanged files
on corrupt/symlink inputs. Both command paths run publisher fault injection.
See [offline edit qualification](edit-bundle.md) and
[read-only bundle inspection/preflight](check-bundle.md).
Disk membership tests import empty/populated saved plans, retain existing
desired state, reject duplicate keys/slots and invalid inputs, and remove empty
first/middle/last participants with stable order and preserved slot ownership.
They require one remaining disk and cover the full 64-disk/slot format bound,
unchanged source files, symlink/nonregular refusal and both commands' publisher
faults. See [membership qualification](disk-bundle.md).
Extent allocation tests compare aligned gap enumeration against a cell oracle
for every small fragmentation pattern and first-fit placement against brute
force. They cover clipping, unsorted/read-only rows, global slots, all 65 gaps,
sector sizes, near-u64 rounding, atomic rejection, unchanged query bytes and
publisher faults. Guests verify raw data, live conflict rejection and held
descriptors. See [extent allocation qualification](space-bundle.md).

Physical capacity adoption covers MBR/GPT identifiers, 512/4096-byte sectors,
exact expected geometry, unchanged desired rows, identifier ambiguity, full
bundles, overflow bounds, read-only retained probes and atomic publisher faults.
An unchanged-size retry must complete the durability protocol. Guests enlarge
their existing raw disk between boots, adopt the new geometry, allocate and grow
a tail mapping, then restore old and new data on a fourth boot. See
[physical capacity qualification](capacity-bundle.md).

Persistent pool tests compare aggregate capacity and ordered cross-disk first
fit against an independent 2048-case fragmentation oracle. They cover sector
eligibility, membership validation/removal, disk-index compaction, 128-bit
totals, version-1 compatibility, version-2 corruption/import rollback and the
8768-byte/64-region bound. Pool edits and allocations run all publisher faults.
Guests verify later-disk conflict preflight, retained data/descriptors and pool
metadata across reordered boot and capacity adoption. See
[pool qualification](pool-bundle.md).

Pool expansion and mapping-growth tests preserve member order and desired rows,
require adopted capacity and contiguous member bounds, and check every small
growth fragmentation pattern against an independent sector oracle. Equal-size
retries still complete every publisher flush; output failure is detected after
publication. Guests qualify held read-only descriptors, extension conflicts,
grown writable tail data and expanded eligibility across reboot. See
[pool growth qualification](pool-growth.md).

Atomic pool batch tests compare ordered cross-disk placement with a 4096-case
cell oracle, preserve the whole set on later failure, retain matching rows and
flush durable retries. Complete previews never publish; both commands detect
buffered output failure. Guests check later-disk live conflicts, retained
descriptors and a mixed keep/new batch across reboot. See
[batch qualification](pool-batch.md).

Atomic pool growth batch tests compare in-place extensions with an independent
4096-case cell oracle, preserve the whole set and caller output on later failure,
and qualify mixed growth/equal-size retries through every publisher boundary.
Read-only previews never publish; both commands detect buffered output failure.
Guests check cross-disk conflicts, held descriptors and a grown read-only tail
neighbor across reboot. See [growth batch qualification](pool-grow-batch.md).

Atomic pool expansion batch tests compare member eligibility with an independent
6400-case cell oracle, preserve every mapping and member priority, and require
whole-set rollback on later failure. Changed and equal-end retries run every
publisher fault; previews remain usable under a writer lock. Guests check exact
cross-disk eligibility, first fit, held views and adopted-tail persistence. See
[expansion batch qualification](pool-expand-batch.md).

Physical capacity batch tests require all device pins before the final identity/
geometry pass, independently check 4096 adoption combinations, and preserve all
saved state after a later failure. Preview performs the same read-only probes
without writer locking or publication. Fault tests cover partial opens, probe
races, all publisher faults, equal-capacity retries and buffered stdout failure.
Guests preview/publish a mixed keep/adopt batch after physical growth and verify
four-boot persistence. See [capacity batch qualification](capacity-batch.md).

Pool membership batches check 4096 addition and 4096 removal cases against an
independent bounds/sector/overlap oracle, retain original member priority and
roll back all state after a later failure. Matching additions and absent removals
retry through every publisher fault. Both previews remain available under writer
locks and preserve saved bytes. Host tests cover maximum 260/68-argument CLIs,
corrupt/symlink sources, version transitions and buffered output failure. Guests
check mixed edits, first fit, desired mappings and persistent reverse-order
retries. See [membership batch qualification](pool-members-batch.md).

Priority tests enumerate all six-member permutations across interleaved pools
and mixed MBR/GPT/sector fixtures: 2880 independently constructed expected orders.
They preserve every bound, desired row and unrelated position, retain aggregate
free capacity and verify that first fit follows the new order. Both commands
cover full 64-member CLIs, invalid lists/sources, publisher faults, all-keep
retries and buffered stdout failure. Guests check actual physical first fit,
held views and explicit reordered priority across reboot. See
[priority qualification](pool-order.md).

Mapping removal batches check all 1956 nonempty ordered subsets of six slots
under four mixed-sector/MBR/GPT and interleaved-pool layouts: 7824 independent
stable-filtering expectations, each with an absent-slot request and retry.
They preserve remaining rows/modes, empty enrollment and exact pool priority,
cover full 64-slot CLIs on one or 64 disks, and reject later invalid requests
without partial publication. Publisher faults and buffered stdout errors cover
changed and all-absent orders. Guests verify omitted replay, retained live
descriptors, reused-slot preflight conflicts and persistent absence across boot.
See [removal batch qualification](removal-batch.md).

Disk enrollment batches compare 1024 existing/requested subset combinations
against independent add/keep oracles across request order and MBR/GPT/sector
layouts. They preserve desired rows and pool priority, reject later conflicts,
and cover all 64 source descriptors/67 CLI arguments at the full V2 limit.
Source fault tests check in-place changes, truncation, path replacement,
interrupted/short reads, final stat/read failures, read-only/CLOEXEC flags and
cleanup. Publisher and buffered output faults cover additions and all-keep
retries. Guests verify unavailable participants, retained views, real physical
reenrollment and exact persistent retries. See
[enrollment batch qualification](enrollment-batch.md).

Identity-based disk forgetting checks 1024 existing/requested subset combinations
against independent stable-compaction and pool-index oracles. Tests preserve
surviving desired rows and priority, reject later protected/duplicate/ambiguous
requests and retain one disk. MBR/GPT parsing and full 64-identity CLIs cover
safe absent retries after index changes. Publisher and buffered stdout faults
cover changed/all-absent batches. Guests verify writer exclusion, held views and
actual physical disk/pool compaction across reboot. See
[disk forgetting qualification](forget-batch.md).

Explicit mapping addition batches check 1024 existing/requested subset
combinations against independent append/keep oracles, preserving original rows,
disk order and pool priority. Identity-based retries follow disk compaction.
Maximum 64-request/323-argument CLIs reach the full V2 limit. Later identity,
geometry, mode and slot conflicts preserve every field and publication bytes;
publisher/output faults cover changed/all-keep batches. Guests verify mixed
actions, later live conflicts, retained views and exact seven-row reconstitution
before persistent boot replay. See
[addition batch qualification](addition-batch.md).

Explicit mapping growth batches check 1024 existing-growth/requested subsets
against independent length/action oracles, preserving offsets, modes, row/disk
order and pool priority. Identity-based equal-size retries follow compaction.
Maximum 64-request/195-argument CLIs exercise the full V2 limit near u64 bounds.
Later identity, shrink, overlap, alignment/overflow and slot conflicts preserve
every field and file byte. Publisher/output faults cover changed/all-keep batches.
Guests verify mixed actions, complete live-extension preflight, held descriptors
and exact desired-length reconstitution across persistent boot replay. See
[explicit growth qualification](explicit-growth-batch.md).

Pool contraction batches check 1024 existing/requested subsets against independent
end/action oracles, preserving mappings, inactive storage, interleaved other pools
and priority. Boundary-crossing desired rows protect their occupied intersections;
sector-aligned ends need not match allocation alignment. Identity retries follow
compaction. Maximum 64-request/132-argument CLIs preserve the full V2 set near u64
bounds. Later member/identity/bounds/occupation failures roll back every field.
Publisher/output faults cover changed/all-keep batches. Guests verify retained
views, bounded future allocation and actual contracted metadata across reboot.
See [pool contraction qualification](pool-contract-batch.md).

Cross-pool resizing checks 1024 transfer subsets and 2592 two-sided occupation
cases against independent expected windows and a cell oracle. Requests select
identity/pool pairs; same-disk adjacent pools can exchange unused capacity in
either request order. Both boundaries preserve clipped desired intersections;
final overlaps and later failures roll back every field. Maximum 64-request/
259-argument CLIs, changed/all-keep publisher/output faults and writer exclusion
remain covered. Guests check new capacity, held views and actual resized bounds
across reboot. See [cross-pool resize qualification](pool-resize-batch.md).

Observed capacity contraction checks 4096 independent identity/sector/size
conditions, full 64-identity/195-argument batches, protected desired tails and
every pool window. Retained read-only devices undergo a final all-descriptor
recheck; later probe/race/publication/output failures preserve whole-set rules.
Two additional boots shrink the disposable physical disk from 24 to 20 MiB,
adopt exact observed geometry and restore seven unchanged desired mappings/data.
See [physical contraction qualification](capacity-contract-batch.md).

Multi-pool allocation checks 4096 independent fragmentation/priority cases,
interleaved same-pool requests, mixed exact retries and sector filtering. Full
64-request/259-argument batches reach the V2 limit. Later failures retain every
source/result field; changed/all-keep publisher/output faults and writer locks
remain covered. A seventh boot restores two additional placements across two
pools with all original rows and data intact. See
[multi-pool qualification](multi-pool-batch.md).

Multi-pool growth checks 16384 independent extension-cell cases, own-member
constraints despite preferred empty alternate disks, interleaved pools and
whole-set rollback. Full 64-pool/195-argument batches reach the V2 limit.
Changed/all-keep publication faults and complete live growth preflight remain
covered. An eighth boot restores both grown lengths with held-descriptor and
extension data intact. See
[multi-pool growth qualification](multi-pool-grow-batch.md).

SHA-256 manifests hash every desired extent through pinned read-only devices.
Later corruption rejects complete verification without success rows. Reference
creation, writer exclusion, partial reads, identity changes and publication
faults are covered. All eight existing boots remain enabled; a ninth verifies
nine grown extents against a guest-produced persistent manifest. See
[data checksum qualification](data-checksums.md).

Complete scrubbing records every match/mismatch and a SHA-256 fingerprint of
the trusted reference, preserving it and old reports on incomplete scans.
Host models cover multiple corruptions, later read failure, publication faults
and output errors. Guests preserve both held views while scanning and restore
all test corruption before repeated workloads and the nine persistence boots.
See [complete scrub qualification](scrub-data.md).

Encrypted-volume checks include the FIPS-197 AES-256 example, 60 aligned NIST
CAVP XTS vector prefixes in both directions, and an independent AES oracle for
512/4096-byte sectors and full-width tweak indices. Mapper models check allocation
and budget refusal, failed publication, short/error I/O, balanced repeated
lifetimes, zeroed scratch storage and erased keys with retained descriptors.
CLI models cover private regular keyfiles, interrupted/short reads, changed
length/owner, parent/ioctl failures and complete request erasure. Guest tests
exercise ciphertext, positioned/vector/sendfile I/O, growth, removal, read-only
reopen and persistent data after device reordering, alongside all earlier
storage workloads. See [encrypted-volume qualification](encrypted-volumes.md).

Key recovery tests cover the RFC ChaCha20/HMAC vectors, an OpenSSL stream oracle,
independent HMAC transcript checks, every single-bit envelope/key mutation,
canonical bounds and unchanged outputs on failed verification. Real filesystem
and syscall models exercise private inputs, fresh nonces, short/EINTR transfers,
source rechecks, no-overwrite publication, temporary ownership, durability/output
faults, descriptor balance and secret erasure. Guests delete the original key,
recover exact private bytes, reopen real ciphertext, repeat 400 backup/restore
lifetimes and recover after reboot and device reordering. See
[key recovery qualification](key-recovery.md).

Sealed-key tests compare scrypt against complete RFC vectors and OpenSSL across
work parameters, binary inputs and the 64-byte HMAC-key boundary. They check the
production cost, complete envelope/key mutations, authentication before release,
allocation and unmap faults, vector erasure, private inputs and no-replacement
publication. Guests unlock without a raw keyfile, verify RW/RO behavior and
recovered bytes, measure repeated full-cost KDF lifetimes separately, and unlock
after raw-key deletion and device reordering. The earlier 400-cycle workload and
nine boot assertions stay enabled. See [sealed-key qualification](sealed-keys.md).

Credential rewrap tests check authentication before new input/output access,
old credential erasure before buffer reuse, long-to-short binary passwords,
fresh salt/nonce, same-key recovery and preservation of every existing entry.
Faults cover both stages, entropy, publication, cleanup and reporting. Guests
rewrap with no raw keyfile, unlock with new credentials, reject old credentials
against the new envelope, measure full-cost repeated lifetimes and unlock after
reboot/device reordering. See [rewrap qualification](rewrap-keys.md).

Encrypted configuration tests authenticate disk identity, native sectors,
slot/extent/mode and wrapped key together. They cover complete bit mutations,
invalid authenticated payloads, pinned MBR/GPT probes, physical changes before
publication/import, preserved readonly mode, private recovery and error cleanup.
Guests verify real data without raw keyfiles or geometry arguments, wrong-disk
and tamper refusal, full-cost retention, reordered boot and rejection of changed
physical capacity. See [configuration qualification](volume-config.md).

Configuration credential-change tests preserve authenticated MBR/GPT identity,
512/4096-byte sectors, slot/extent/mode and key. They check authentication before
new input/output, erased buffer reuse with shorter binary credentials, private
no-overwrite publication, fault cleanup and continued original access. Guests
unlock both RW/RO configurations without raw keys, reject old credentials and
wrong disks, measure full-cost lifetimes and repeat unlock after device reorder.
See [configuration rewrap qualification](volume-rewrap.md).

Saved-plan lock tests hold directory locks across independent processes, reject
all writer families, keep read-only previews available and verify publication
stays locked through rename/directory fsync. They cover directory aliases,
independent destinations, path replacement, descriptor cleanup and killed-owner
recovery. Guests exercise the packaged utility's contention/retry behavior on
both architectures; repeated mutation cycles also measure lock retention. See
[writer-lock qualification](plan-lock.md).

Plan-set checks cover duplicate disks/slots, 64 plans and all global
slots, directory ordering, ignored names, selected nonregular files, descriptor
ownership and the 4096-entry limit. The same controller runs both native init
policy variants, including
missing utility, synchronous reaping, fork/exec failure and failed restore.
Generated utility, init and guest C are checked for unexpected heap or V
runtime dependencies.

Guest runs need target musl compilers, Clang/LLD, QEMU, `mke2fs`/`debugfs`, and
the cached Limine and firmware files from the image builders. ARM also needs
mtools; AMD64 needs `xorriso`. `VINIX_OVMF_CODE` and `VINIX_OVMF_CODE_AMD64`
override firmware paths.
AMD64 uses the cached Alpine BusyBox and musl loader from
`build-amd64-userland/staging`; `VINIX_AMD64_USERLAND_ROOT` overrides that root.
On AMD64 a V console adapter redirects init's output to serial and execs the
unchanged packaged desktop init as PID 1.
The controller boots QEMU directly with disposable disk files, drains serial
output into retained logs, limits each boot to 1800 seconds by default and
terminates only its own process. `VINIX_STORAGE_BOOT_TIMEOUT` optionally selects
a per-boot budget of 60..7200 decimal seconds; for slower TCG hosts,
`VINIX_STORAGE_BOOT_TIMEOUT=2700` allows 45 minutes without changing workload
counts or assertions. The allowance includes 16400 utility processes across 200 warmup
and 200 measured forty-one-command cycles, with pool membership, query, batch
allocation/growth/expansion batch previews/publications,
physical-capacity batch previews/publications, offline mapping/disk edits and live preflight
on x86 TCG; the strict retention
checks are unchanged.
Serial output is streamed to disk, with a fixed marker window for read boundaries;
pipe buffers are freed after writing, and the completed transcript is read once.
This bounds capture memory during verbose development-kernel NVMe qualification.
It preserves logs and a copy of the saved plan in the work directory.

On AMD64, `--nvme` adds two disposable NVMe disks, one with an injected critical
warning. Use a `PROD=false` kernel because the driver retains development-only
probing. The fixture checks actual controller-wide health, CLI exit 0/3, bad
output pointers, descriptor/partition policy, unchanged I/O counters, 200 successful
and 200 bad-pointer queries per disk inside the retention measurement, and health
after reboot.
Bounded monitor sessions on both controllers exercise standard thermal/wear
fields and full-width counter deltas, retaining exit 0/3; their separate result
marker is required on the first boot.
See [health qualification](../storage-health/README.md).

The fixture boots from an ext2 system disk. A separate raw disk holds managed
views, and a third disk with different MBR identity first tests wrong-target
rejection, then holds an independently configured mapping.
The first boot runs production init with a deliberately invalid plan, verifies
the failure is reported and the application still starts, then saves
writable/read-only mappings. It rejects corrupt plans, writable boot
configuration, duplicated physical identities and conflicting slots before
creation. It accepts physical aliases, skips symlinks/partitions, checks
idempotence and restoration with an already matching slot. A multi-disk set then
rejects corrupt later plans, duplicate disk keys/global slots, missing disks,
untrusted directories/files and selected symlinks without creating a prefix.
Conflicting requested slots and unlisted overlapping views on the later disk
leave earlier disks untouched. Directory-only and legacy-plus-directory restore
both preserve data and existing generations. A bundle then replaces the individual
enrollment. Failed saves with a missing later disk or repeated physical identity
preserve the previous file; invalid arguments do not replace it. Corruption,
missing disks, untrusted bundle mode/owner, final symlinks, legacy enrollment
conflicts and later occupied/unlisted slots fail without creating a prefix.
Explicit and boot bundle replay preserve data and existing generations.
The capacity fixture then plans larger views without changing live geometry,
rejects invalid edits and default replay, and checks later-disk/extension
conflicts before growth. Writable and read-only views grow in place, keeping
their generations. An already open raw descriptor writes and flushes the new
extent, which remains readable after reboot at the saved larger capacity.
The fixture warms both retained snapshot buffers and the snapshot reader before
measurement, resets them on reuse, and records paired ready snapshots before
recapturing the baseline. Every class and large-page count must stay flat or
decrease. It measures slab/large retention over 200 cycles after 200 warmup
cycles, with both disks enabled. Each cycle saves the bundle, previews/publishes unchanged
two-disk mapping capacity, previews/verifies/republishes both unchanged physical capacities,
previews/publishes admission of two pool members and unchanged allocation priority,
previews/publishes a mixed expand/keep batch, queries the pool and previews/allocates a two-mapping
batch, previews/publishes a two-mapping growth batch, explicit identity retries, contraction and cross-pool resize previews/publications, checks and previews/removes the scratch
mappings, previews/enrolls two empty offline participants and previews/forgets
both by identity,
explicitly replays growth and runs boot restoration.
A flushed phase marker
and the atomically published bundle stay on ext2 across an
abrupt VM stop. The physical disks are reordered for the second boot. Production ARM
native init or AMD64 desktop init restores both disks from the bundle before the
test application starts, and the application checks persisted data, read-only
mode, the correct physical disks after reordering and idempotence. The host does
not inject the bundle or phase marker between boots. The controller requires
the bundle and capacity preflight markers before accepting the first boot.
After the ordinary second-boot assertions pass, the controller extends only
the disposable raw file from 16 to 24 MiB, preserving its MBR and prior bytes.
The third boot must reject the old saved geometry before the application previews
and publishes a mixed keep/adopt capacity batch, retries both capacities,
previews/publishes the tail's expanded eligibility,
retries its equal end, allocates and grows a tail view, and publishes a mixed
keep/new batch with a read-only tail neighbor. A growth batch then retains the
writable tail length and grows that neighbor, preserving its held descriptor.
It persists the complete bundle
and phase marker. The fourth boot must restore all seven mappings through
production init and retain durable old/tail data, both neighbor pages and read-only modes. Both pool
regions must survive the reordered second boot and enlarged fourth boot. The
new tail pool's expanded eligibility, grown mapping and batch neighbor must
survive the fourth boot too.

The fixture touches its readable ELF load pages before sampling. This keeps
cold faults in the long-lived test program's diagnostic code from appearing as
workload retention. Allocation tracking is started when available, and a
failed retention check dumps the remaining sites for diagnosis.
Large-allocation page totals are printed before the slab deltas on every run.

The same first-boot fixture now qualifies the read-only health ABI: actual
QEMU AHCI SMART identity, data/checksum and threshold status on AMD64;
unsupported VirtIO on ARM; invalid pointers and descriptor/resource rejection;
the packaged `health` command; and 200 additional health queries within the
retention measurement. See [the health tests](../storage-health/README.md).

It also executes `vinix-volume monitor` with two samples on the physical disk,
checks unavailable health on a logical volume and rejects a regular file.
The first boot must emit the monitor qualification marker. Host fault, reset,
warning/recovery and 200-sample coverage is in
[the native V monitor suite](../storage-monitor/README.md).

The block-volume host and guest commands below also use native V controllers.

Run the unchanged production volume, metrics and security code with mocked
host allocation/I/O boundaries:

```sh
V=/path/to/v tests/storage-volumes/host
VINIX_HOST_SANITIZE=1 V=/path/to/v tests/storage-volumes/host
V=/path/to/v python3 tests/block-storage/run.py
V=/path/to/v tests/mounted-disk-policy/host
```

Build ordinary kernels in isolated worktrees and then run both disposable guest
fixtures. No qualification ioctl or fault-enabled kernel is required:

```sh
VINIX_KERNEL_DIR=/path/to/arm-worktree/kernel V=/path/to/v \
  tests/storage-volumes/run --arch aarch64
VINIX_AMD64_KERNEL=/path/to/x86-worktree/kernel/bin/vinix V=/path/to/v \
  tests/storage-volumes/run --arch amd64
```

The ARM runner uses the existing musl SDK; set `VINIX_AARCH64_SYSROOT` for the
static compiler. Both architectures snapshot the requested kernel and directly
own QEMU with private ISO, firmware variables and serial log.
AMD64 needs `x86_64-linux-musl-gcc`, QEMU and Limine/OVMF. `--state-dir` requires
a fresh directory and preserves the generated initramfs and 16 MiB disk.
`VINIX_QEMU_TIMEOUT` defaults to 300 seconds. The runner never selects a host
physical device; it creates and attaches only its disposable disk.
`--kernel-dir` selects either architecture's kernel directory; `--build-only`
produces the fixture, utility, archive and disk without booting. The native
supervisor kills QEMU with SIGKILL before checking sentinels, preserving the
power-cut contract. The host command retains artifacts in a fresh directory
selected by `VINIX_VOLUME_HOST_DIR`. Its original volume assertions remain
unchanged, and the production health dispatcher now receives an independent
host device and access/output-fault tests.

The guest verifies actual physical translation with guard sectors, geometry,
read-only opens, rejection of overlap/shrink/overflow, management privilege,
invalid ioctl/read/write pointers, stable namespace rules, mknod aliases,
growth with open descriptors, active-swap exclusion, stale-descriptor removal,
generation reuse and the native CLI. Concurrent opens race 100 removals. After warming metadata and
graces, it checks that no slab class or large allocation count increases
across 200 more create/write/discard/grow/remove cycles using distinct extents.
AMD64 also checks real partition translation. Host tests cover bounded
discard batches, exec cancellation, securelevel changes, failure cleanup,
unsupported commands, protocol range encoding and DMA quarantine.

NVMe discard currently has host controller qualification only. Production
kernels disable NVMe initialization; an attempted development guest panicked
before the fixture started. Native NVMe qualification remains open.

Controller timeout/short-completion faults run separately in `block-storage`;
physical mounted/swap extent admission runs in `mounted-disk-policy`. These are
not a claim of RAID, full-disk encryption, automatic mapping discovery, live
filesystem resizing, filesystem-aware free-space trimming or hardware SMART
qualification.
