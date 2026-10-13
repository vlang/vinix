# Multiple encrypted boot volumes

The legacy fixed pair and named pairs in `/etc/vinix/boot-volumes.d` form one
bounded authenticated set. See [input policy, ordering and application limits](../../docs/storage-volumes.md#multiple-encrypted-boot-volumes).

Native sanitizer coverage verifies all 64 global slots, full-width geometry,
adjacent/overlapping extents, different disks, duplicate slots, invalid counts
and cached masks, whole-state preservation on rejected appends, plain-set
conflicts and bounded visible filename selection.

The discovery syscall model exercises the actual named loader, private fd reader,
codec, enumeration, scanner, whole-set pinned preflight and synchronous imports.
It keeps all earlier single-volume/discovery cases and adds independent disks,
mixed RW/RO, filename ordering, legacy/named compatibility, all 64 profiles,
65-profile and 4,097-entry rejection, ignored inputs and empty sets. Faults cover
directory access/trust, descriptor duplication/stream/enumeration failures,
second-member KDF/read/authentication/private-file/symlink failure, selected-file
removal, later physical discovery failure, directory replacement during KDF,
saved slot/extent conflicts and controlled later import/trust failures. Every
opened descriptor balances; credentials clear before every scan and both secret
workspaces clear on every ordinary return. Original inputs stay unchanged apart
from explicitly simulated concurrent removal/replacement.

Both guests create a second encrypted volume on the other physical disk with a
different known key and binary credential, persist its readonly configuration
and delete that raw key.
Four warmup and four measured two-volume unlock/remove lifetimes each use two
full-cost production KDFs, with snapshot-reader warmup and thirteen-second grace
reclamation. All earlier cohorts, 400-cycle workloads and nine boots remain.
The default per-boot deadline is 1800 seconds; the bounded
`VINIX_STORAGE_BOOT_TIMEOUT` override accommodates slower software emulation.
Exact slab and large-page comparisons remain.

Production init must restore both volumes after physical device reordering,
preserving independent keys/data, physical identities and readonly modes. When
one disk changes capacity or contracts, the complete encrypted set refuses;
the unchanged second disk remains locked too. Deliberate adoption of the first
configuration restores both on the next boot. Explicit tests reject a bad later
credential or duplicate saved slot before either encrypted import. A later live
occupied slot demonstrates the documented sequential failure: the earlier view
can remain live and the occupied view retains its generation.

Frozen isolated ALLOC_TRACK kernels are reused. No kernel source changes are
required. Both target allocation audits, actual generated-C lifetime review and
independent persisted configuration/key/ciphertext checks qualify the addition.
This unlocks data volumes after the root filesystem is available; credentials
require separately protected storage for offline confidentiality. Imports are
sequential and do not provide a global kernel transaction.

Qualification on 2026-10-13 passes all 39 ASan/UBSan suites, ten syscall
models, both init policy cases and both target allocation audits. Both
architectures finish all nine boots, eight two-volume unlock/remove lifetimes
with two production KDFs per lifetime, and all earlier cohorts and 400-cycle
workloads.

| Target | Boots | Set lifetimes | Slab classes, all deltas zero | Set large pages | Existing workload large pages |
| --- | --- | --- | --- | --- | --- |
| ARM64 | 9 | 4 + 4 | 18 | 80 → 80 | 98 → 98 |
| x86_64 | 9 | 4 + 4 | 14 | 201 → 201 | 219 → 219 |

The complete target utility C is byte-identical on both architectures, SHA-256
`a52bb06db80a59bf99248dc7228d2b64b2835cabe2c13195e93c8d8663b700ef`, with no implicit heap/runtime
dependencies. Independent source and actual native/model/target/guest C
lifetime review reports no unresolved issues. Independent OpenSSL scrypt and
ChaCha20 plus separate full HMAC checks verify both exact persisted boot pairs
and recover their independent known keys using distinct binary credentials;
an independent AES-XTS oracle matches ciphertext on both physical disks.
Complete logs, C, persistent guest disks, review and artifact manifests remain
under `logs/storage-volume-boot-set-work`; the verified artifact manifest is
`logs/storage-volume-boot-set-work/artifacts/SHA256SUMS`.

Three ARM attempts stopped before boot: unsafe access in a deferred guest wipe,
a generated fixed-array bounds dependency, and a cross-GCC filename formatting
warning. Their failed logs remain retained. The corrected fourth attempt
passes the full workload. Complete native and guest evidence was copied and
checksummed on persistent storage before detaching the owned scratch device.
Imports retain the sequential behavior described above.

The first x86 attempt stopped before boot when a shared cached bootloader
file had been removed. The second attempt reached the default 30-minute
watchdog at 324 of 400 publications without a guest failure marker; its new
boot-set retention cohort passed. Both failed logs remain retained. The complete
third x86 attempt selects a 45-minute per-boot budget through the bounded
`VINIX_STORAGE_BOOT_TIMEOUT=2700` setting and uses owned bootloader copies
matching repository pinned hashes. Production source, workload counts and all
strict memory assertions remain unchanged. ARM used the default 30-minute budget.

Auxiliary generated C, seeds and persistent guest media are retained as gzip
files, verified against both stored and original decompressed SHA-256 manifests.
Reviewed target/native/model/guest C and logs remain directly readable.
The bounded timeout helper was corrected to free its owned environment clone;
cleaned actual C and boundary tests qualify that cleanup. The exact running
x86 controller source/C is archived separately with its older bounded host-only
allocation debt recorded in the independent review.
