# Logical block volumes and storage counters

Vinix can expose up to 64 linear views of physical AHCI, NVMe and ARM VirtIO
block devices (including their partitions). A view maps a sector-aligned byte
range to `/dev/mapper/vinix0` through `/dev/mapper/vinix63`. Creating, growing or
removing a view changes kernel mappings only; it does not format the device or
move its contents. Kernel mappings last until reboot. Saved volume plans retain
their geometry and disk identity for explicit or configured restore after boot;
multi-disk bundles publish a complete saved configuration in one file.

Saved desired extents can also be hashed into a separate SHA-256 manifest and
verified later, including after physical device reordering. See
[data checksum manifests](#data-checksum-manifests).

The native V utility is installed as `/usr/sbin/vinix-volume` by both userland
and desktop image builders. Commands require a trusted MAC domain,
`CAP_SYS_ADMIN`, and the initial user namespace for management; status requires
ordinary read access to the device.

```sh
# Example only: choose an unused physical extent before creating a writable view.
vinix-volume status /dev/vda
vinix-volume create /dev/vda 0 1048576 8388608
vinix-volume status /dev/mapper/vinix0
vinix-volume grow /dev/mapper/vinix0 16777216
vinix-volume remove /dev/mapper/vinix0
# A read-only view:
vinix-volume create /dev/vda 1 33554432 8388608 ro
```

Lengths and offsets are decimal bytes. Creation requires an aligned nonempty
range contained in the parent device, a free slot, and no overlap with another
managed view. Writable creation opens the parent read/write; a read-only view
can use a readable parent. Nested logical views and shrinking are unsupported.
Growing retains the start offset and can happen with raw descriptors open.
This is block capacity growth, not online filesystem resizing. The existing
filesystem registration does not dynamically discover or mount filesystems in
new views; this increment provides the block management layer.

Reconfiguration reserves the physical extent before changing geometry. It
rejects mounted/protected extents, swap, pending mounts, and active raw writes;
new overlapping writes/mounts/swap cannot enter during the change. Writable
operations and mount/swap admission recheck geometry after reserving it. This
closes the gap between sampling an old length and entering after a grow.
Protection follows the actual parent disk identity, including aliases and
whole-disk overlaps, rather than user-supplied device numbers. Filesystem
protection deliberately survives unmount while detached caches can still write.

Managed nodes and the mapper directory cannot be renamed, unlinked, hardlinked,
or used as mount targets/bind sources. Volume-backed mknod aliases can be
removed normally, but cannot acquire permanent mount pins. Path collisions
fail without replacing the existing node. Removing a volume detaches its node
and marks existing descriptors offline; subsequent I/O fails with `ENODEV`.
A reused slot gets a new generation, and old descriptors cannot remove its
replacement. Object, interface, parent and node ownership drain through the
normal VFS grace period. Metadata is charged to the creating process, including
retired objects, and dynamic policy rows are recycled with a fixed bound.

## Keyfile-encrypted block volumes

`open-crypt` exposes an AES-256-XTS view of an unused physical extent. It uses
two independent 256-bit keys from one 64-byte binary file. Generate fresh random
key material for each volume and retain a secure backup outside that volume.
The file must be regular, owned by the caller and inaccessible to group/others;
the utility rejects a final symlink, wrong length and identical key halves.
Keys travel through a bounded ioctl request and never appear in arguments,
status, reports or saved plans.

```sh
# Choose an unused extent; this command does not encrypt existing plaintext.
umask 077
dd if=/dev/urandom of=/root/data.key bs=64 count=1
chmod 600 /root/data.key
vinix-volume open-crypt /dev/vda 0 1048576 8388608 /root/data.key
vinix-volume status /dev/mapper/vinix0
vinix-volume grow /dev/mapper/vinix0 16777216
vinix-volume remove /dev/mapper/vinix0
# Reopen after removal or reboot; geometry and key must match.
vinix-volume open-crypt /dev/vda 0 1048576 16777216 /root/data.key ro
```

The resulting block node uses the same privileges, extent protection, resource
charges, generation rules and removal semantics as a plain linear view. Status
reports `encrypted=1` (ABI flag 64). Native sectors must be 512 or 4096 bytes;
each native sector is one XTS data unit. Its little-endian tweak index starts
at zero relative to the view, independent of the physical offset or slot.
Whole-sector I/O is required. Growth preserves existing ciphertext and tweak
indices; new sectors must receive plaintext through the encrypted view before
their content is meaningful. A read-only reopen exposes previously written
data without allowing writes. Raw parent reads expose ciphertext.

This format is headerless: callers retain the exact physical extent, native
sector size and key. Opening never formats, converts existing data or verifies
a key. AES-XTS provides confidentiality without authentication; a wrong key or
tampered ciphertext yields unverified plaintext. Passphrase wrapping is available
through the sealed-key commands below. Key rotation, authenticated volume
metadata and encrypted-root boot integration remain separate work.
The keyfile example uses the current root filesystem; its storage must meet the
user's key protection requirements. Losing the key loses access to the data.

Encrypted views disable TRIM/discard. Saving a plain plan for a disk containing
an encrypted view fails before publication, and plain replay refuses an occupied
encrypted slot even when geometry matches. Plans do not persist encrypted
configuration; reopen it explicitly with its key after boot.

Removal serializes with each sector operation and clears the expanded key even
while old descriptors await final release. Kernel buffers used for key import
and encrypted block I/O, and the utility's ioctl request, are erased before release. Ordinary
user buffers, caches and the keyfile remain their owners' responsibility.
After any privileged encrypted-key import attempt, x86 hibernation refuses an
unencrypted RAM image for the rest of that boot, including after removal.
This restriction covers imported keys; it does not classify arbitrary key
material in userspace before import. ARM hibernation remains unsupported.

See [encrypted-volume qualification](../tests/storage-volumes/encrypted-volumes.md).

## Authenticated volume key recovery

`backup-key KEYFILE RECOVERY_KEYFILE ENVELOPE` saves an encrypted, authenticated
backup of an existing 64-byte volume key. `recover-key ENVELOPE RECOVERY_KEYFILE
KEYFILE` verifies that backup and restores the exact key into a new private file.
Generate a separate random 64-byte recovery key, keep it apart from the backup,
and retain both outside the volume. The commands reject using the volume key as
its own recovery key. Inputs must be owned regular files with no group/other
permissions, exact lengths and no final symlink; FIFOs never block an import.
The recovery key's two 32-byte halves must differ, as must the XTS key halves.

```sh
umask 077
dd if=/dev/urandom of=/root/recovery.key bs=64 count=1
chmod 600 /root/recovery.key
vinix-volume backup-key /root/data.key /root/recovery.key /root/data.backup
# Restore into an absent filename, then reopen using the original geometry.
vinix-volume recover-key /root/data.backup /root/recovery.key /root/restored.key
vinix-volume open-crypt /dev/vda 0 1048576 16777216 /root/restored.key ro
```

Both commands create mode-0600 output through a temporary file in a pinned,
locked directory owned by the caller and not writable by group/others. They
flush and close the complete file, publish it with an atomic hard link that
never replaces any existing entry, remove their own temporary name, then flush
the directory. Existing files, directories, symlinks, FIFOs and input aliases
stay intact. The filesystem must support hard links and directory fsync. Status
0 means publication and stdout flushing succeeded; status 1 means an input,
verification, I/O, publication or output error; invalid syntax returns 2.
After publication, cleanup, directory-fsync or stdout failure can leave a
complete private destination with status 1. Inspect it before retrying into a
different absent filename; retries never overwrite it. Failed pre-publication
operations remove only the temporary file they created, and report cleanup
failure if that file cannot be removed.

The fixed 160-byte `VINIXKR1` envelope uses little-endian header fields:

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 8 | ASCII `VINIXKR1` |
| 8 | 4 | Version 1 |
| 12 | 4 | Algorithm 1: ChaCha20 with HMAC-SHA256 |
| 16 | 4 | Total bytes 160 |
| 20 | 4 | Key bytes 64 |
| 24 | 12 | Fresh random nonce |
| 36 | 28 | Reserved, zero |
| 64 | 64 | Encrypted volume key |
| 128 | 32 | Full authentication tag |

ChaCha20 uses the first 32 recovery-key bytes and counter 1 for one 64-byte
block, with a fresh 96-bit nonce read from `/dev/urandom` for every backup. The
tag is HMAC-SHA256 with the last 32 recovery-key bytes over the first 32
recovery-key bytes followed by envelope bytes 0–127. This binds both key halves,
all canonical metadata, the nonce and ciphertext. Recovery validates the exact
format and compares the full tag before decrypting or publishing any key. A
wrong half of the recovery key or any changed envelope byte rejects recovery.
Secret buffers, stream/hash workspaces and candidate keys are erased on every
return; generated production C uses stack workspaces without heap copies.

This backs up key material only. Retain disk identity, physical offset, length
and native sector size separately. It does not authenticate volume data, derive
keys from passwords, rotate keys, convert plaintext storage or arrange root
unlock at boot. Losing both the original volume key and the recovery key still
loses access. Persistent keyfiles, filesystem caches and ordinary userspace
memory retain their existing protection requirements, including the hibernation
limits described above. See [key recovery qualification](../tests/storage-volumes/key-recovery.md).

## Passphrase-sealed volume keys

`seal-key KEYFILE PASSPHRASE_FILE ENVELOPE` wraps an existing volume key with
a passphrase-derived key. `unseal-key ENVELOPE PASSPHRASE_FILE KEYFILE` verifies
the envelope before restoring an exact private keyfile. `open-sealed DEVICE SLOT
OFFSET_BYTES LENGTH_BYTES ENVELOPE PASSPHRASE_FILE [ro]` verifies and unlocks the
volume directly, without creating a plaintext keyfile. The original extent,
native sector size and volume key stay the same; changing the wrapping does not
rewrite disk data.

```sh
# The passphrase file already contains your private credential bytes.
chmod 600 /root/volume.pass
vinix-volume seal-key /root/data.key /root/volume.pass /root/data.sealed
vinix-volume open-sealed /dev/vda 0 1048576 16777216 /root/data.sealed /root/volume.pass ro
# Optional explicit recovery into an absent private filename.
vinix-volume unseal-key /root/data.sealed /root/volume.pass /root/restored.key
```

Passphrase files must contain 1–1024 bytes, be owned regular files with no
group/other permissions and have no final symlink. All bytes are significant:
embedded NULs, newlines and UTF-8 sequences are preserved, with no normalization
or trimming. Use a strong passphrase. These commands accept credential files
for headless use; they do not prompt on a terminal. Passphrase bytes never appear
in command arguments, diagnostics, metadata or reports. Source reads handle
short/EINTR transfers, probe EOF and recheck size, owner and permissions.

Every seal generates a fresh 16-byte salt and 12-byte nonce from `/dev/urandom`.
The fixed scrypt profile is **N=32768, r=8, p=3**, deriving 64 bytes with a single
32 MiB private anonymous ROMix vector reused across all three lanes. Other
workspaces stay on the stack. The vector is erased completely before unmapping;
the derived key is withheld if allocation, computation or release fails. This
profile is one of the published [OWASP scrypt configurations](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#scrypt).
Unsupported file work profiles reject before KDF allocation or computation.
The work cost is deliberate; it cannot make a weak passphrase safe against
offline guessing. Store persistent passphrase files with the protection their
contents require, and retain an independent key backup/recovery path.

The exact 192-byte `VINIXKP1` format is separate from `VINIXKR1` recovery files.
Header fields are little-endian:

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 8 | ASCII `VINIXKP1` |
| 8 | 4 | Version 1 |
| 12 | 4 | Algorithm 1: scrypt, ChaCha20, HMAC-SHA256 |
| 16 | 4 | Total bytes 192 |
| 20 | 4 | Volume key bytes 64 |
| 24 | 8 | N=32768 |
| 32 | 4 | r=8 |
| 36 | 4 | p=3 |
| 40 | 16 | Salt |
| 56 | 12 | Nonce |
| 68 | 28 | Reserved, zero |
| 96 | 64 | Encrypted volume key |
| 160 | 32 | Full authentication tag |

The first 32 derived bytes key one ChaCha20 block at counter 1. The last 32
bytes key HMAC-SHA256 over the first 32 derived bytes followed by envelope bytes
0–159, binding both key halves, the work profile, salt, nonce and ciphertext.
Decoding validates the entire canonical header, derives the wrapping key and
compares the complete tag before decrypting or releasing any volume key. It
also rejects identical XTS halves or a volume key equal to its wrapping key.
Wrong passphrases, altered envelopes and unsupported profiles never publish a
keyfile or open the physical parent. scrypt retains its algorithm's
data-dependent ROMix addressing; it is not presented as a constant-time KDF.

Seal/unseal outputs follow the same pinned-directory lock, mode-0600 temporary,
file-fsync/close, no-replacement hard-link publication and directory-fsync rules
as key recovery. Existing entries and input aliases are preserved. Status 0
means the operation and output flush succeeded, 1 means a controlled input,
authentication, resource or I/O failure, and invalid syntax returns 2. A failure
after file publication can leave a complete private destination; a stdout failure
after successful direct import can leave the mapping active. Inspect that state
before retrying. Passwords, wrapping keys, plaintext candidates, imported
requests and secret workspaces are erased on ordinary returns. Process
termination, persistent credentials, caches and hibernation retain the existing
userspace/keyfile limits described above.

This authenticates the sealed keyfile, while AES-XTS volume data keeps its
existing confidentiality-only semantics. It does not verify disk data, convert
plaintext storage, rotate the volume key or arrange encrypted-root boot. See
[sealed-key qualification](../tests/storage-volumes/sealed-keys.md).

## Changing sealed-key credentials

`rewrap-key ENVELOPE OLD_PASSPHRASE_FILE NEW_PASSPHRASE_FILE NEW_ENVELOPE`
changes the credential protecting a sealed volume key without creating a
plaintext keyfile. It authenticates the original envelope with the old
passphrase, generates a fresh salt and nonce, and publishes the same volume key
under the new passphrase in a separate private envelope. The volume's geometry,
native sector size and ciphertext stay exact. No volume device is opened.

```sh
# Both credential files already contain private bytes and have mode 0600.
vinix-volume rewrap-key /root/data.sealed /root/old.pass /root/new.pass /root/data-next.sealed
# Verify the new envelope against the original extent before retiring old copies.
vinix-volume open-sealed /dev/vda 0 1048576 16777216 /root/data-next.sealed /root/new.pass ro
vinix-volume remove /dev/mapper/vinix0
```

The input envelope and both credential files use the same private-file policy,
exact-byte passphrase semantics and fixed scrypt profile as `seal-key`.
Malformed profiles and wrong old credentials reject before opening the new
credential, obtaining fresh entropy or accessing the output directory. Each KDF
allocates, erases and releases its own 32 MiB vector in sequence, so rewrapping
needs one vector at a time. Old passphrase and derived-key buffers are erased
before reading the next credential, including any unused suffix when the new
passphrase is shorter. The authenticated volume key stays in a bounded stack
workspace and is erased on every ordinary return. Credentials never enter
arguments, diagnostics or reports. Identical old/new passphrase bytes are
allowed for a fresh salt/nonce refresh.

Publication follows the same directory lock, mode-0600 temporary, file flush,
atomic no-replacement link, temporary cleanup and directory flush as sealed-key
creation. Existing destinations, source aliases and both credential files are
preserved. A failure before publication creates no destination; cleanup,
directory-flush or stdout failure after publication can leave a complete private
new envelope with exit status 1. Verify that envelope before retrying. Syntax
errors return 2; successful publication and reporting return 0.

The old envelope remains usable with its old credential. Rewrapping does not
revoke access through retained envelopes, recovered raw keys or independent key
backups, and does not rotate the volume key or rewrite disk data. Retire old
credential/envelope copies according to their storage's protection requirements
only after verifying the new envelope and preserving a recovery path. Process
termination, caches, hibernation and persistent credential protection retain the
sealed-key limits above. See [credential rewrap qualification](../tests/storage-volumes/rewrap-keys.md).

## Authenticated encrypted volume configurations

`seal-volume DEVICE SLOT OFFSET_BYTES LENGTH_BYTES KEYFILE PASSPHRASE_FILE CONFIG
[ro]` records an encrypted mapping's whole-disk identity and geometry alongside
its wrapped volume key. `open-volume DEVICE CONFIG PASSPHRASE_FILE [ro]`
authenticates that configuration, verifies the selected disk and imports the
stored mapping. It needs no raw keyfile or separate geometry arguments.
`unseal-volume-key CONFIG PASSPHRASE_FILE KEYFILE` explicitly recovers the exact
volume key into a new private file without accessing a disk.

```sh
# The key and private credential files already exist; choose the exact extent.
vinix-volume seal-volume /dev/vda 0 1048576 16777216 /root/data.key /root/volume.pass /root/data.vcrypt
vinix-volume open-volume /dev/vda /root/data.vcrypt /root/volume.pass ro
vinix-volume remove /dev/mapper/vinix0
# Explicit offline key recovery, only into an absent filename.
vinix-volume unseal-volume-key /root/data.vcrypt /root/volume.pass /root/restored.key
```

Sealing reads the physical parent through one retained read-only descriptor. It
records the disk byte count, native sector size and nonzero MBR signature or
CRC-checked GPT GUID, plus slot, offset, length and readonly mode. Only whole
physical disks and the mapper's 512/4096-byte native sectors are supported.
Bounds, alignment, distinct XTS halves and the fixed scrypt profile are checked.
The disk is probed again after the output-directory lock is acquired and before
publication; identity, byte count, sector size, runtime disk identity and physical
readonly changes observed during the operation reject publication. Sealing
does not import a mapping, write the disk, verify its ciphertext or convert
existing plaintext into encrypted data.

Opening validates the canonical format/work profile and authenticates the full
configuration before decrypting or releasing its key or opening a physical
parent. It verifies the exact saved identity and geometry twice on the same
retained descriptor, then imports through that descriptor. Wrong credentials,
tampering, wrong disks, partitions, existing mapper parents and observed identity
or geometry changes reject before import. A saved readonly mapping stays
readonly when opened without an override; optional `ro` can also restrict a
writable configuration. Slot and extent come only from authenticated metadata.
Kernel privilege, extent protection and conflict checks still govern import.
Reporting failure after a successful import can leave the mapping active.

The private `VINIXVC1` envelope is exactly 320 bytes. Header fields are
little-endian; metadata is readable and authenticated:

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 8 | ASCII `VINIXVC1` |
| 8 | 4 | Version 1 |
| 12 | 4 | Algorithm 1: scrypt, ChaCha20, HMAC-SHA256 |
| 16 | 4 | Total bytes 320 |
| 20 | 4 | Volume key bytes 64 |
| 24 | 8 | N=32768 |
| 32 | 4 | r=8 |
| 36 | 4 | p=3 |
| 40 | 16 | Fresh salt |
| 56 | 12 | Fresh nonce |
| 68 | 12 | Reserved, zero |
| 80 | 8 | Physical disk bytes |
| 88 | 8 | Native sector bytes, 512 or 4096 |
| 96 | 4 | Identity kind: 1 MBR, 2 GPT |
| 100 | 4 | Reserved, zero |
| 104 | 16 | Identity; MBR uses four bytes with a zero suffix |
| 120 | 4 | Mapping request version 1 |
| 124 | 4 | Slot, 0–63 |
| 128 | 8 | Physical offset bytes |
| 136 | 8 | Mapping length bytes |
| 144 | 8 | Mode: 0 writable, 1 readonly |
| 152 | 40 | Reserved, zero |
| 192 | 64 | Encrypted volume key |
| 256 | 32 | Reserved, zero |
| 288 | 32 | Full authentication tag |

The first 32 scrypt-derived bytes key one ChaCha20 block at counter 1. The last
32 key HMAC-SHA256 over the first 32 derived bytes followed by envelope bytes
0–287. This binds both wrapping-key halves, all disk/mapping metadata, salt,
nonce and ciphertext. The same private 1–1024-byte credential policy, fixed
32 MiB KDF vector, normal-return erasure and no-overwrite private publication
rules apply as for sealed keys. Source key/configuration/credential files stay
intact. Controlled input, authentication, resource or I/O failures return 1;
syntax returns 2 and complete operation/reporting returns 0. Post-publication
cleanup or durability failure can leave a complete private output with status 1.

Identifiers are partition-table identifiers: cloned or deliberately duplicated
identities are not a proof of unique hardware. Verification samples a pinned
device; it cannot prevent a privileged actor from changing disk metadata after
the final check. Physical capacity and extent growth can use `plan-grow-volume`
below. Sector-size, slot, start or mode changes require a fresh configuration.
Existing configurations
remain usable with their saved credentials and matching geometry. The separate
`rewrap-key` command accepts `VINIXKP1` key envelopes; use `rewrap-volume` below
for this configuration format. Keep an independent key backup and retain the
sealed-key limits for persistent credentials, process termination, caches and
hibernation. Volume
data retains AES-XTS's unverified confidentiality semantics; encrypted-root boot
and volume-key rotation remain separate work. See
[configuration qualification](../tests/storage-volumes/volume-config.md).

## Automatic encrypted-volume discovery

`open-volume-auto CONFIG PASSPHRASE_FILE [ro]` authenticates an encrypted-volume
configuration and finds its physical disk in `/dev`, using the saved whole-disk
identity, exact capacity and native sector size. Device names may change across
reboots. The stored slot, extent, key and mode remain authoritative; optional
`ro` restricts a writable configuration and never elevates a saved readonly one.

```sh
vinix-volume open-volume-auto /root/data.vcrypt /root/volume.pass
vinix-volume remove /dev/mapper/vinix0
vinix-volume open-volume-auto /root/data.vcrypt /root/volume.pass ro
```

Canonical input validation and full authentication finish before the device
directory is opened. Credential and derived wrapping-key buffers are erased
before scanning. Discovery uses the existing bounded, directory-relative
scanner: symlinks and non-block entries are skipped, partitions and mapper
parents are excluded, and physical aliases sharing one runtime disk identity
are accepted. Distinct physical disks with matching saved identities and
geometry are ambiguous and reject before import. Enumeration or unreadable
matching-geometry candidate failures also reject, since uniqueness could not be
established. The scan is limited to 4096 entries.

A writable mapping requires a separately reopened writable descriptor whose
physical identity is checked against the scanned candidate. After the complete
scan, the retained descriptor is checked twice against the authenticated disk
identity and geometry, selected runtime disk identity and readonly status,
then passed directly to encrypted import. No pathname is reopened for import,
no raw keyfile is created and no configuration or credential file is changed.
Normal returns close every retained descriptor and erase the whole secret
workspace. Status 0 means import and reporting succeeded, 1 means a controlled
failure and 2 means invalid syntax. Reporting failure after successful import
can leave a live mapping, as with `open-volume`.

This command is explicit unlock after the system has booted. Opt-in init replay
is available through [encrypted boot unlock](#opt-in-encrypted-boot-unlock) below.
Encrypted-root boot and volume-key rotation remain separate work. Saved
configurations still reject changed capacity or sector size.
Partition-table identities are cloneable; uniqueness is established among the
observable candidates during this scan, and a privileged metadata rewrite
after the final check remains outside its guarantee. The existing encryption,
credential storage, process-termination and cache limits apply. See
[automatic unlock qualification](../tests/storage-volumes/volume-discovery.md).

## Authenticated encrypted-volume inspection and discovery

`show-volume CONFIG PASSPHRASE_FILE` authenticates an ordinary private VC1
configuration and reports its saved disk capacity, native sector size, MBR/GPT
identity, mapper slot, offset, byte length and saved read-only mode offline.
`discover-volume CONFIG PASSPHRASE_FILE` also identifies the unique matching
whole physical disk through pinned read-only descriptors:

```sh
vinix-volume show-volume /root/data.vcrypt /root/volume.pass
vinix-volume discover-volume /root/data.vcrypt /root/volume.pass
```

Offline success starts with `operation=authenticated-volume`. Online success
starts with `operation=discovered-volume device=/dev/NAME`. Both then print
`disk_bytes=N sector=N identity=mbr:XXXXXXXX` (or canonical `gpt:GUID`) and
`slot=N offset=N bytes=N readonly=0|1`. Full unsigned 64-bit metadata is retained;
the read-only field describes the saved mapping independently of the physical
disk's current mode. Reports contain no passphrase, volume key or wrapped key.

Inputs use the existing private-owned-file policy and bounded 1–1024 exact
credential bytes, including embedded NULs/newlines. Canonical format, geometry
and fixed scrypt work-profile validation precede credential reads/KDF work.
The existing salted 32 MiB scrypt loader authenticates the complete metadata
and volume key and erases/releases its KDF workspace before returning. The
queries then erase passphrase, wrapping key and decoded volume key before
successful reporting or device access. Every exit erases the complete stack
workspace and closes owned descriptors. No raw keyfile or new configuration
is created, and no entropy source or writer lock is used.

Discovery requires exact saved capacity, native sectors and disk identity,
ignores partitions/logical views and accepts physical aliases sharing the
runtime disk identity. Separate matching physical clones are ambiguous and
fail. Missing/offline or unreadable matching-geometry candidates and enumeration
failures reject. Two retained-descriptor rechecks cover identity, capacity,
native sectors, runtime identity and physical read-only mode before any
successful report; the descriptor remains pinned through output flushing.
Every candidate open is read-only, even for a saved writable mapping.

These queries preserve input bytes, live mapping status/generations/open
descriptors and physical ciphertext. Discovery establishes a current physical
match; it does not reserve slots, check live extent admission, authenticate the
unauthenticated AES-XTS disk contents or guarantee a later unlock. Physical
capacity changes need a separate explicit configuration adoption. Complete
reports return 0, authentication/discovery/output failures return 1, and invalid
syntax returns 2. Failures may print diagnostics, and output failures may leave
partial authenticated reports. See [inspection qualification](../tests/storage-volumes/volume-inspect.md).

## Opt-in encrypted boot unlock

The existing `boot-restore` startup hook can unlock an authenticated encrypted
volume after restoring the plain saved set. Enable it with
`/etc/vinix/boot-volume.vcrypt`, a private `VINIXVC1` configuration, and
`/etc/vinix/boot-volume.pass`, its private credential file. The saved disk
identity, exact capacity/native sectors, key, slot, start, length and readonly
mode remain authoritative. Device reordering is handled by the existing bounded
identity scanner. No raw keyfile is created. Multiple configurations can form
one [encrypted boot set](#multiple-encrypted-boot-volumes).

```sh
# Install the credential first; the configuration enables automatic unlock.
install -m 600 /root/volume.pass /etc/vinix/boot-volume.pass
install -m 600 /root/data.vcrypt /etc/vinix/boot-volume.vcrypt
# Test encrypted unlock alone without applying plain saved plans.
vinix-volume boot-unlock
# Removing the configuration disables automatic unlock.
rm /etc/vinix/boot-volume.vcrypt
```

The directories `/etc` and `/etc/vinix` must be owned by root and not writable
by group or others. Both inputs must be root-owned private regular files; the
credential retains the existing 1–1024 exact binary byte policy. All directory
and input opens use no-follow and close-on-exec, and input opens are nonblocking.
Inputs are opened relative to the retained configuration directory and rechecked
after EOF, so path replacement cannot redirect a read. Missing configuration
means disabled, even if a credential remains; missing directories also return
success. Other access errors, hostile types/permissions, malformed envelopes or
wrong credentials fail before discovery or encrypted import. Invalid canonical
headers fail before credential access and KDF work. Credential and wrapping-key
buffers erase before any device scan; all secret state erases on normal returns.

`boot-restore` loads and validates the plain set, authenticates every encrypted
configuration, then rejects duplicate global slots or overlapping saved extents
before applying either. It discovers, pins and rechecks every encrypted physical
parent before applying the plain set. Directory trust is checked again after
authentication and before each encrypted import. Plain restore retains its
complete preflight and pinned-device checks; a plain-set failure prevents
encrypted unlock. Encrypted import uses the retained descriptors and two final
identity/geometry/readonly checks. An occupied encrypted
slot refuses a second unlock; matching geometry cannot establish that an
existing mapping uses the authenticated key.

These phases are sequential. A later encrypted discovery/import/report failure
may leave successfully restored plain mappings, and reporting failure after
encrypted import may leave the encrypted mapping live. There is no cross-phase
kernel transaction. Status 0 means disabled or successful import/reporting,
1 means a controlled failure and 2 means invalid command syntax. Existing init
reports failure and continues to its recovery desktop or shell. The ARM init
policy and both x86 init variants already call `boot-restore` before applications;
no new startup script is required.

This unlocks a data volume after the system root is available. It does not mount
filesystems or provide encrypted-root boot, interactive credential prompts,
hardware-protected credentials, volume-key rotation or authenticated data
ciphertext. A plaintext credential on the same unencrypted media permits an
offline reader to unlock the volume; use a separately protected boot source
when that threat matters. Removing the configuration does not remove an already
live mapping or erase credential copies. Disable the configuration before
changing the pair, install the new credential before the new configuration,
and make both files and their directory durable before reboot. Physical capacity
or sector changes still reject until a matching configuration is deliberately
installed. See [boot-unlock qualification](../tests/storage-volumes/volume-boot.md).

## Multiple encrypted boot volumes

`boot-restore` and `boot-unlock` combine the legacy pair above with visible
`NAME.vcrypt` configurations in `/etc/vinix/boot-volumes.d`. Each configuration
uses the exact binary credential in `NAME.pass` in that same retained directory.
The directory must be root-owned without group/world write permission; both
files retain the private root-owned regular-file policy. Different configurations
can use independent keys and credentials, different physical disks, or disjoint
extents on the same disk. Saved readonly modes remain authoritative.

```sh
mkdir -m 700 /etc/vinix/boot-volumes.d
install -m 600 /root/archive.pass /etc/vinix/boot-volumes.d/archive.pass
install -m 600 /root/archive.vcrypt /etc/vinix/boot-volumes.d/archive.vcrypt
vinix-volume boot-unlock
```

There are at most 64 encrypted configurations in total, including the legacy
pair, and at most 4,096 non-dot directory entries. Only visible, nonempty
`NAME.vcrypt` names participate; hidden files, orphan credentials and unrelated
suffixes are ignored but count toward the enumeration bound. Named configurations
are processed in bytewise filename order after the legacy configuration.
Empty or missing configuration directories disable that portion of the set.
An inaccessible directory, a symlink, a selected configuration disappearing
after enumeration, or any invalid enabled input rejects the complete load.

Every configuration authenticates before physical discovery or any mapping
application. Credential and wrapping buffers erase after each authentication;
decoded keys occupy bounded caller-owned stack storage, erased on every normal
return. Global slots must be unique across the encrypted and plain desired sets.
Saved extents on the same physical identity must not overlap; touching extents
and equal offsets on distinct disks are valid. All encrypted disks are uniquely
discovered and retained together, then rechecked after the final discovery.
A later credential, metadata or physical preflight failure creates no earlier
encrypted or plain mapping. Directory replacement cannot redirect the retained
relative inputs or physical descriptors.

Plain replay and the subsequent encrypted imports remain sequential. Existing
live conflicts, a change after preflight, an import failure or a reporting
failure can leave earlier mappings live. An occupied encrypted slot still
refuses replay, preserving its existing mapping; the utility does not guess
whether its key matches. No cross-mapping kernel transaction is added. Disable
each configuration before changing its pair; publish the credential first and
make its file, configuration and containing directories durable before reboot.
This remains data-volume unlock after root is available, with the existing
offline credential-storage and encrypted-root limits. See
[encrypted boot-set qualification](../tests/storage-volumes/volume-boot-set.md).

## Encrypted-volume configuration recovery

`backup-volume CONFIG PASSPHRASE_FILE RECOVERY_KEYFILE BACKUP` authenticates a
`VINIXVC1` configuration and backs up its exact disk identity, capacity, native
sectors, slot, extent, readonly mode and volume key under an independent private
64-byte recovery key. `recover-volume BACKUP RECOVERY_KEYFILE
NEW_PASSPHRASE_FILE CONFIG` restores that metadata and key into a new ordinary
passphrase-sealed configuration. Neither command opens a disk, imports a mapping
or creates a plaintext keyfile. The old configuration and credential are not
required for recovery once the backup exists.

```sh
vinix-volume backup-volume /root/data.vcrypt /root/volume.pass /root/recovery.key /root/data.vrecover
# After losing the original configuration or its credential:
vinix-volume recover-volume /root/data.vrecover /root/recovery.key /root/new.pass /root/recovered.vcrypt
vinix-volume open-volume-auto /root/recovered.vcrypt /root/new.pass
```

Backups authenticate the source configuration before reading the recovery key.
Recovery validates the canonical backup and authenticates it before reading the
new credential or doing KDF work. Both recovery-key halves authenticate before
any plaintext or metadata is released. Recovery keys must have distinct halves
and differ from the volume key. Existing private-file ownership, permissions,
exact sizes, retained descriptors and symlink refusal apply to every input.
New credentials use the existing 1–1024-byte binary credential policy and fixed
production scrypt profile. Every recovery generates a fresh salt and nonce.

The private recovery format `VINIXVR1` is exactly 320 bytes. It has version 1,
algorithm 1 (direct ChaCha20 and HMAC-SHA256), total size 320 and key size 64 at
the same offsets 8, 12, 16 and 20 as `VINIXVC1`. Bytes 24–55 are zero, with a
fresh 12-byte nonce at 56. All disk/mapping fields, ciphertext, authentication
tag and other reserved bytes retain the configuration layout above. The first
32 recovery-key bytes encrypt the key with ChaCha20 counter 1. The second 32
key HMAC-SHA256 over the first 32 recovery-key bytes followed by backup bytes
0–287. The separate authenticated magic prevents key-envelope or sealed-volume
format substitution. Disk and mapping metadata remain readable.

Both outputs use locked, private, no-overwrite durable publication. An existing
destination, including a dangling symlink or input alias, is preserved. Failures
before publication create no destination; post-publication cleanup, directory
flush or reporting failure can leave a complete private output with status 1.
Credential/recovery buffers erase before reuse and all plaintext secrets erase
before destination acquisition and on every normal return. Syntax returns 2,
controlled failures 1 and completed publication/reporting 0.

Keep the recovery key separately protected from the backup. A backup is an
independent access path; changing credentials does not revoke it or rotate the
volume key. Back up new geometry after deliberate growth/capacity adoption:
recovery preserves the saved geometry and never guesses changes from a live
disk. Unlock and boot replay keep their physical identity/conflict checks and
normal limits. Recovery does not repair corrupted ciphertext or authenticate
AES-XTS data. See [configuration recovery qualification](../tests/storage-volumes/volume-recovery.md).

## Direct recovery-key unlock

`open-recovery-volume-auto BACKUP RECOVERY_KEYFILE [ro]` opens the encrypted
mapping directly from its authenticated `VINIXVR1` backup and independent
64-byte recovery key. It needs no original passphrase/configuration, new
passphrase or writable configuration destination. For example:

```sh
vinix-volume open-recovery-volume-auto /root/data.vrecover /root/recovery.key ro
```

Both inputs must be exact-size private owned regular files opened without
following symlinks and rechecked on their retained descriptors after EOF.
Canonical format and geometry checks precede recovery-key access; the entire
backup authenticates before `/dev` discovery. Recovery credentials erase
before device access, and the decoded key and complete workspace erase on
every return. Nothing is published or written to either input.

The saved identity, physical capacity, native sectors, slot, offset and length
remain exact. Bounded physical discovery accepts aliases of one disk and
refuses distinct disks with the same saved identity. The selected descriptor
stays pinned through two final identity/geometry/mode rechecks and encrypted
import. Saved read-only mappings stay read-only; `ro` additionally restricts a
saved read-write mapping. Successful commands print the mapper path. Syntax
returns 2, controlled failures 1 and successful import/reporting 0. A reporting
failure after import can leave the mapping open; inspect it before retrying.

The recovery key remains an independent access credential; changing a
passphrase does not revoke it. Saved geometry must still match, and occupied
slots/protected extents retain normal import refusal. This is explicit data
volume rescue; encrypted-root startup, RAID and ciphertext authentication
remain separate work. See [direct unlock qualification](../tests/storage-volumes/recovery-unlock.md).

## Changing recovery-backup credentials

`rewrap-recovery-volume BACKUP OLD_RECOVERY_KEYFILE NEW_RECOVERY_KEYFILE
NEW_BACKUP` changes the credential protecting an authenticated `VINIXVR1`
backup. It preserves the exact volume key, disk identity, capacity, native
sectors, slot, extent and saved read-only mode, with a fresh random nonce:

```sh
vinix-volume rewrap-recovery-volume /root/data.vrecover /root/old-recovery.key /root/new-recovery.key /root/new-data.vrecover
vinix-volume open-recovery-volume-auto /root/new-data.vrecover /root/new-recovery.key ro
```

The source header and geometry validate before the old key is read. The backup
authenticates before the new key is opened. The old credential buffer erases
before reuse; the new credential and decoded volume key erase before acquiring
the destination directory. Every normal return erases the complete workspace.
Inputs retain the exact-size, private owned regular-file, pinned descriptor,
EOF/recheck and symlink-refusal policies above. The new recovery key must have
distinct halves and differ from the volume key. Reusing the same recovery key
is allowed as a fresh-nonce refresh.

The operation needs no passphrase, KDF, ordinary configuration, physical-disk
probe or mapping import. It creates a separate private backup through the
locked, durable no-overwrite publisher; input aliases and existing destinations
are preserved. Failures before publication produce no output. Cleanup,
directory-flush or reporting failures after publication can leave a complete
private backup with status 1. Completed publication/reporting returns 0;
controlled failures return 1 and invalid syntax returns 2.

Changing the recovery credential protects the new backup. Previously saved
backups remain usable with their old credentials; this operation does not
revoke copies of those backups or rotate the underlying volume key. Deliberate
capacity/extent changes still require a new backup of the adopted geometry.
See [recovery credential-change qualification](../tests/storage-volumes/recovery-rewrap.md).

## Recovery volume growth and capacity adoption

`plan-grow-recovery-volume DEVICE BACKUP RECOVERY_KEYFILE EXPECTED_BYTES
LENGTH_BYTES NEW_BACKUP` authenticates a recovery backup and publishes a separate
backup adopting a declared physical capacity and a nondecreasing extent length.
It preserves the exact volume key, disk identity, native sectors, slot, offset
and saved read-only mode. Original passphrases and ordinary configurations are
not required:

```sh
vinix-volume plan-grow-recovery-volume /dev/vda /root/data.vrecover /root/recovery.key 33554432 12288 /root/grown.vrecover
vinix-volume open-recovery-volume-auto /root/grown.vrecover /root/recovery.key
```

Capacity and length are explicit byte counts. Capacity cannot shrink and must
remain native-sector aligned. Length cannot shrink, exceed the remaining
physical capacity or exceed the kernel's signed mapping limit
`0x7fffffffffffffff`; it must also be native-sector aligned. Equal geometry is
allowed as a fresh-nonce refresh. No slot, offset, identity, sector-size or mode
change is permitted.

Canonical source checks precede recovery-key access, and authentication precedes
all physical-device access. The candidate backup receives a fresh nonce and
full authentication tag before disk verification. The recovery credential and
decoded volume key erase before opening the physical parent. The command then
opens only a pinned read-only parent, verifies its identity/sectors and exact
declared capacity, and performs two further identity/geometry/runtime-identity
and physical-mode rechecks. The final recheck runs under the destination writer
lock immediately before private no-overwrite publication. The device descriptor
and publication lock remain alive through reporting; every return erases the
complete workspace and closes owned descriptors.

This publishes desired recovery metadata. It does not resize a physical device,
filesystem or live mapping, initialize newly exposed data, or create a raw
keyfile. Existing live descriptors and ciphertext remain unchanged by planning.
Apply live growth or reopen separately through the normal kernel protection
and conflict checks. Changed capacity can make old backups unsuitable for
direct unlock until explicit adoption; their saved bytes and credentials remain
intact. Pre-publication failures create no output. Cleanup, directory-flush or
reporting failure after publication can leave a complete private output with
status 1; completed publication/reporting returns 0 and invalid syntax returns 2.
See [recovery growth qualification](../tests/storage-volumes/recovery-growth.md).

## Authenticated recovery inspection and discovery

`show-recovery-volume BACKUP RECOVERY_KEYFILE` authenticates a private recovery
backup and prints its saved disk capacity, native sector size, MBR/GPT identity,
mapper slot, byte offset/length and saved read-only mode. It works without the
disk, original passphrase or ordinary configuration. `discover-recovery-volume
BACKUP RECOVERY_KEYFILE` additionally locates the unique matching whole physical
disk and reports its current `/dev` name:

```sh
vinix-volume show-recovery-volume /root/data.vrecover /root/recovery.key
vinix-volume discover-recovery-volume /root/data.vrecover /root/recovery.key
```

Offline success begins with `operation=authenticated-recovery`. Online success
begins with `operation=discovered-recovery device=/dev/NAME`. Both then print
`disk_bytes=N sector=N identity=mbr:XXXXXXXX` (or canonical `gpt:GUID`) and
`slot=N offset=N bytes=N readonly=0|1`. Integer fields retain their full unsigned
64-bit values. These are authenticated saved metadata; the read-only flag is
the saved mapping mode, independent of the physical disk's current access mode.
No key bytes, credentials or wrapped key material appear in the report.

The commands use the existing exact private-owned-file reader and authenticated
VR1 format. Canonical header checks precede recovery-key access, and successful
authentication precedes metadata reports or device enumeration. The recovery
credential and decoded volume key erase before any successful report or `/dev`
access; the complete stack workspace erases on every return. No KDF, entropy
source, raw keyfile, configuration publication or writer lock is needed.

Discovery pins physical candidates read-only with no-follow, nonblocking and
close-on-exec flags. It matches exact saved capacity, native sectors and disk
identity, ignores partitions/logical views and accepts physical aliases with
the same runtime disk identity. Separate physical clones with the same saved
identity are ambiguous and fail. Missing/offline or unreadable matching-geometry
candidates, enumeration failures and changes to identity/geometry/runtime
identity or physical read-only mode fail before a successful report. Two final
rechecks precede reporting; the selected descriptor remains pinned through
output flushing and closes on all exits.

These are recovery queries: they preserve existing mappings, generations, open
descriptors, backup/key bytes and physical ciphertext. Discovery establishes a
current physical match; it does not reserve a mapper slot, preflight live
extent conflicts, prove the volume key matches the disk's unauthenticated
AES-XTS contents, or guarantee a later unlock. Capacity changes require separate
explicit backup adoption. Complete reports return 0, authentication/discovery
or output failures return 1, and invalid syntax returns 2. Diagnostics may be
printed on failure; output failure can leave a partial report. See
[recovery inspection qualification](../tests/storage-volumes/recovery-inspect.md).

## Offline ciphertext reference inspection and comparison

`show-volume-reference REFERENCE` validates and displays a complete private
`VINIXCH1` checksum reference. `compare-volume-references BEFORE_REFERENCE
AFTER_REFERENCE` compares two valid references for the same saved mapping:

```sh
vinix-volume show-volume-reference /root/data.vchash
vinix-volume compare-volume-references /root/before.vchash /root/after.vchash
```

Both inputs must be exact 128-byte private owned regular files. The existing
pinned no-follow reader checks ownership, permissions, size and metadata before
and after reading, retries interrupted/short reads and closes its descriptor on
every exit. Magic/version/size, reserved bytes, complete CRC, MBR/GPT identity,
native-sector alignment, slot/mode, signed extent bounds and SHA length must all
validate. Every required input validates before any successful output appears.
Comparison also requires exact saved capacity, native sector size, identity,
slot, start, length and read-only mode. A valid different mapping returns an
operational failure rather than a digest finding.

Inspection reports the saved mapping, recorded extent digest and SHA-256
fingerprint of all 128 reference bytes. Comparison reports the same geometry,
both recorded extent digests and both complete reference fingerprints. The
two-line inspection header is `format=VINIXCH1 operation=show-ciphertext-reference
mappings=1 algorithm=sha256 reference_sha256=HEX`, followed by `disk_bytes=N
sector=N identity=ID slot=N offset=N bytes=N readonly=0|1 sha256=HEX`.
The comparison header uses `operation=compared-ciphertext-references`,
`stable=0|1 changed=0|1`, `before_reference_sha256=HEX` and
`after_reference_sha256=HEX`. Its mapping line ends with `result=stable|changed
before_sha256=HEX after_sha256=HEX`. All integers retain their unsigned width;
SHA-256 values use 64 lowercase hexadecimal digits.

Inspection and stable comparisons return 0; differing recorded digests return
2. Invalid/private-input, geometry or output failures return 1, taking precedence
over a changed finding. Invalid syntax returns 2 without a finding. A late
output failure may leave a partial or complete printed report. Same-path and
hard-link aliases are valid; inputs remain unchanged.

These operations need no credentials and do not access a physical parent,
discover disks, derive keys, import mappings, lock destinations or publish
files. Existing live mappings and their status/counters/descriptors remain
unchanged. Manual, automatic, ordinary-credential and recovery references are
interchangeable when their saved metadata agrees.

Results describe recorded digests, without establishing current disk contents,
authenticating reference replacements, proving an unlock key or inferring time
order. Reference files must remain quiescent during the reads; pins establish
per-file identity rather than a simultaneous two-file snapshot. The existing
trusted-reference rules apply. See [reference query qualification](../tests/storage-volumes/reference.md).

## Identity-based automatic ciphertext checksums

`hash-volume-auto CONFIG PASSPHRASE_FILE REFERENCE` and
`hash-recovery-volume-auto BACKUP RECOVERY_KEYFILE REFERENCE` create a complete
ciphertext checksum reference after discovering the saved physical disk.
`verify-volume-auto` and `verify-recovery-volume-auto` take the same arguments
and verify its complete extent against an existing reference:

```sh
vinix-volume hash-volume-auto /root/data.vcrypt /root/volume.pass /root/data.vchash
vinix-volume verify-recovery-volume-auto /root/data.vrecover /root/recovery.key /root/data.vchash
```

Both credential domains authenticate the saved geometry and erase passwords,
wrapping keys and decoded volume keys before discovery. Recording validates
the signed positioned-I/O bounds, SHA-256 length and native-sector alignment
first. Verification also validates the complete private 128-byte reference,
including its exact geometry and saved read-only mode, before opening `/dev`.

Discovery uses the bounded read-only whole-disk scan described for automatic
scrubbing below: MBR/GPT identity, physical capacity and native sector size
must match; aliases of the same physical ID are accepted, distinct matching
disks are refused. Enumeration failures and unreadable matching-geometry
candidates prevent establishing a unique match. The selected descriptor stays
pinned through streaming, publication and output; its name is never reopened.
The first recheck retains discovery's physical ID and read-only state. Two
additional pre-read rechecks and one post-read recheck detect changes, with a
final recheck under the destination lock when recording.

The fixed 64-KiB reader, exact `VINIXCH1` reference bytes, two-line output and
private no-overwrite publication are identical to explicit-device checksum
commands. Either credential domain can verify manual or automatic references
for the same metadata. Verification scans the complete extent, returns failure
on digest mismatch and never locks or publishes a destination. Success returns
0, authentication/reference/discovery/read/publication/output failure returns
1, and invalid syntax returns 2. Existing inputs and destinations are preserved;
late durability, cleanup or output failures can leave a complete new reference.

Automatic checksums preserve live mapping descriptors, status, generations,
counters and plaintext reads. Trusted-reference and quiescent-write rules from
[checksum references](#encrypted-ciphertext-checksum-references) still apply;
discovery provides no snapshot or ciphertext authentication. See
[automatic checksum qualification](../tests/storage-volumes/ciphertext-auto.md).

## Identity-based automatic ciphertext scrubbing

`scrub-volume-auto CONFIG PASSPHRASE_FILE REFERENCE REPORT` and
`scrub-recovery-volume-auto BACKUP RECOVERY_KEYFILE REFERENCE REPORT` run the
complete ciphertext scrub without requiring a current physical device path:

```sh
vinix-volume scrub-volume-auto /root/data.vcrypt /root/volume.pass /root/data.vchash /root/auto-1.vcscrub
vinix-volume scrub-recovery-volume-auto /root/data.vrecover /root/recovery.key /root/data.vchash /root/auto-2.vcscrub
```

Authentication, full secret erasure and exact reference validation happen
before opening `/dev`. Discovery uses the existing bounded read-only scan of
at most 4096 entries. It matches saved MBR/GPT identity, physical capacity and
native sector size, ignores partitions/logical views, accepts physical aliases
sharing a disk ID, and refuses distinct matching physical disks. Unreadable
matching-geometry candidates or enumeration failures prevent establishing a
unique disk and return failure. It never opens a writable device.

The selected descriptor stays pinned through the entire scan, private
no-overwrite publication and output finalization; the utility never reopens
the selected pathname. The first identity/geometry recheck preserves the
physical ID and mode selected by discovery. Two further pre-read rechecks,
one post-read recheck and one recheck after destination locking follow the
existing scrub rules. Changes or incomplete reads publish no report.

Reports and output are exactly the same `VINIXCS1` findings as an explicit-device
scrub against the same reference and ciphertext. Matching/changed findings
return 0/2; authentication, reference, discovery, scan, publication and output
failures return 1, with operational errors taking precedence. Invalid syntax
returns 2 without a finding. Existing destinations and inputs are preserved;
late cleanup/durability/output failures may leave a complete private report.
Automatic scanning imports no mapping and preserves existing live descriptors,
status, generations, counters and plaintext reads.

Trusted-reference, quiescent-write and historical-report limits still apply.
Automatic discovery does not authenticate ciphertext or provide a snapshot,
repair or encrypted-root boot integration. See
[automatic scrub qualification](../tests/storage-volumes/auto-scrub.md).

## Comparing encrypted ciphertext scrub history

`compare-volume-scrubs BEFORE_REPORT AFTER_REPORT` compares two completed
`VINIXCS1` findings offline. Both exact private reports must validate in full,
and their embedded 128-byte references must be identical, including saved
geometry/mode, expected digest and CRC. Reports produced through passphrase and
recovery credentials are comparable when they used that same reference.
Different references are refused even if their observed digests agree.

```sh
vinix-volume compare-volume-scrubs /root/scan-1.vcscrub /root/scan-2.vcscrub
```

| Observed digests | Before / after finding | Comparison result | Exit status |
| --- | --- | --- | --- |
| Equal | Both match or both changed | `stable` | 0 |
| Different | Match / changed | `new-change` | 2 |
| Different | Changed / match | `restored` | 2 |
| Different | Changed / changed | `changed-again` | 2 |

Status 0 means the observed ciphertext digest stayed equal; a stable changed
finding still differs from the trusted reference. Status 2 means the observed
digest changed, including restoration to the reference. Input, validation,
reference mismatch or output failure returns 1 and overrides these findings;
invalid syntax returns 2 without a comparison. Both files validate before any
successful output. Output failure can leave a partial comparison on stdout.

The two-record output header is `format=VINIXCS1 operation=compared-ciphertext
mappings=1 stable=0|1 changed=0|1 algorithm=sha256 reference_sha256=HEX`. Its row
contains `disk_bytes=N sector=N identity=ID slot=N offset=N bytes=N readonly=0|1
before=match|changed after=match|changed result=stable|new-change|restored|changed-again
expected_sha256=HEX before_sha256=HEX after_sha256=HEX`.

Input ownership, exact length, private permissions, final-symlink refusal and
pinned-reader rechecks follow `show-volume-scrub`. Comparing a file with itself
or a hard-link alias is allowed. The command reads no credentials, performs no
KDF, opens no device, acquires no writer lock and changes no files or mappings.
All workspaces are bounded stack storage containing public metadata and hashes.

The caller supplies historical order; reports contain no timestamps, and this
command does not infer which scan happened first. Keep the input reports stable
while comparing them. This does not take a new disk snapshot, authenticate
report provenance or plaintext, or prove that current contents are repaired.
Trusted references and the original scan's quiescent-write requirements remain
applicable. See [comparison qualification](../tests/storage-volumes/scrub-compare.md).

## Persistent encrypted ciphertext scrub findings

`scrub-volume DEVICE CONFIG PASSPHRASE_FILE REFERENCE REPORT` and
`scrub-recovery-volume DEVICE BACKUP RECOVERY_KEYFILE REFERENCE REPORT`
authenticate saved mapping geometry, read its complete physical ciphertext
extent, then publish a private finding. A SHA mismatch is a complete finding,
so scanning continues through the entire extent before reporting it:

```sh
vinix-volume scrub-volume /dev/vda /root/data.vcrypt /root/volume.pass /root/data.vchash /root/scan-1.vcscrub
vinix-volume show-volume-scrub /root/scan-1.vcscrub
vinix-volume scrub-recovery-volume /dev/vdb /root/data.vrecover /root/recovery.key /root/data.vchash /root/scan-2.vcscrub
```

Each report preserves the exact `VINIXCH1` reference, the observed full-extent
SHA-256 digest and SHA-256 of every reference byte. Metadata, saved mode,
expected digest, observed digest and reference fingerprint appear in two output
records. The header is `format=VINIXCS1 operation=scrubbed-ciphertext mappings=1
matched=0|1 changed=0|1 algorithm=sha256 reference_sha256=HEX`; the row has
`disk_bytes=N sector=N identity=ID slot=N offset=N bytes=N readonly=0|1
result=match|changed expected_sha256=HEX actual_sha256=HEX`. Reports are identical
across credential domains for the same reference and observed ciphertext.

Scrubbing returns 0 for a completed matching report, 2 for a completed changed
report, and 1 for authentication, input, device, read, publication or output
failure. Invalid syntax returns 2 without a finding. A completed scan publishes
before printing; late cleanup, directory-flush or output failure can leave the
complete private report present while returning 1, including for changed data.
No incomplete scan publishes a report. Existing destinations are preserved by
the private no-overwrite protocol, including symlink/lexical/hard-link aliases
of configurations, credentials and references; choose a new report name for
each run. The physical pin and destination lock remain held through output.

The existing ciphertext reader's signed-end/SHA limits, native-sector alignment,
EINTR/short-read handling and exact identity/geometry checks apply. Every decoded
secret erases before reference access, physical reads, publication and reports.
The parent is read-only, nonblocking, no-follow and close-on-exec, with two
pre-read rechecks, a post-read recheck and a final recheck after destination
locking. No decryption, entropy, raw keyfile, mapping import or physical write
occurs. Existing live mapping status, counters, generations and descriptors
remain unchanged.

`show-volume-scrub REPORT` reads an exact private 224-byte report owned by the
effective user and inaccessible to group/others. It validates the complete
report before printing: header/version/algorithm/reserved bytes, whole CRC,
nested reference structure/CRC/ranges, exact reference fingerprint and
agreement between `changed` and both full digests. Invalid input produces no
successful finding. Viewing a valid clean or changed historical report returns
0; input/output failure returns 1. Viewing opens no disk, reads no credential,
performs no KDF, acquires no writer lock and publishes nothing.

`VINIXCS1` version 1 is little endian: magic at 0; version/224-byte size at
8/12; result (0 match, 1 changed) at 16; algorithm (1 SHA-256) at 20; four zero
reserved bytes at 24; whole CRC-32 at 28 with that field zero; the exact 128-byte
reference at 32; observed digest at 160; reference fingerprint at 192. It
contains public metadata/digests and no keys or credential binding.

Keep data writes quiescent and use a trusted reference. This records corruption
findings against that reference, without providing coherent snapshots,
plaintext authentication, malicious-reference authentication or repair. Offline
reports describe their completed historical scan; they do not describe current
disk contents. See [scrub qualification](../tests/storage-volumes/ciphertext-scrub.md).

## Encrypted ciphertext checksum references

`hash-volume DEVICE CONFIG PASSPHRASE_FILE REFERENCE` and
`hash-recovery-volume DEVICE BACKUP RECOVERY_KEYFILE REFERENCE` authenticate an
encrypted mapping, then record SHA-256 over its entire physical ciphertext
extent. `verify-volume` and `verify-recovery-volume` take the same arguments and
compare that extent against an existing reference:

```sh
vinix-volume hash-volume /dev/vda /root/data.vcrypt /root/volume.pass /root/data.vchash
vinix-volume verify-recovery-volume /dev/vdb /root/data.vrecover /root/recovery.key /root/data.vchash
```

The reference binds exact physical capacity, native sector size, MBR/GPT
identity, slot, starting offset, extent length and saved read-only mode. Either
credential domain can verify the same reference when this metadata agrees;
credential rotation preserves it. Changed geometry or mode requires a new
reference. Verification checks format, reserved fields, CRC and every metadata
field before opening the physical parent. SHA mismatch returns failure after
reading the complete extent, without a successful report.

Both paths use the existing private pinned credential readers and canonical
VC1/VR1 authentication. Passwords, wrapping keys and decoded volume keys erase
before reference access, physical opens, streaming reads, publication or output.
Every return erases the complete authentication workspace. No decryption,
entropy access, raw keyfile or mapper import occurs. The parent is pinned
read-only, nonblocking, no-follow and close-on-exec; it must be a whole online
physical disk matching authenticated identity and exact geometry. Rechecks
verify runtime identity and physical read-only state twice before reading and
once afterward, plus once after acquiring the publication lock for recording.
The descriptor stays pinned through output finalization.

One fixed 64-KiB buffer streams the extent in native-sector units. EINTR and
aligned short transfers retry; EOF, I/O errors, oversized or misaligned
transfers fail. Offset and exclusive extent end must fit signed positioned-I/O
limits; the extent length must fit SHA-256's bit-length field. Reference files
are exactly 128 private bytes, owned by the effective user and inaccessible to
group/others. Recording uses the existing locked, flushed, no-overwrite private
publication protocol, so existing configurations, credentials and references
are preserved, including aliases. Temporary ownership and cleanup follow the
key-recovery publisher. A post-publication directory-flush or output failure
can leave the complete reference present while returning failure.

`VINIXCH1` version 1 is little endian: magic at 0; version/size at 8/12;
capacity/sector at 16/24; identity kind/slot at 32/36; offset/length/mode at
40/48/56; 16 identity bytes at 64; 32 digest bytes at 80; twelve zero reserved
bytes at 112; CRC-32 at 124 computed with that field zero. References contain
public geometry and ciphertext digests, without keys or credential bindings.

Complete reports have two lines: `operation=recorded-ciphertext` or
`operation=verified-ciphertext`, `format=volume|recovery algorithm=sha256`, then
`disk_bytes=N sector=N identity=ID slot=N offset=N bytes=N readonly=0|1
sha256=HEX`. Integers keep their unsigned width and digests use 64 lowercase
hex digits. Success returns 0, operational/authentication/data failure returns
1, and invalid syntax returns 2. Output failure can leave partial authenticated
metadata after a completed scan.

Keep all writes to the extent quiescent throughout the scan. Pinning and
identity checks do not provide a coherent snapshot of concurrent data writes.
Use a trusted reference: CRC and SHA-256 detect accidental corruption against
that reference, without authenticating attacker-replaced references or
plaintext, proving the decryption key, or providing authenticated encryption.
Checksums cover ciphertext already stored, including uninitialized encrypted
sectors. Live mappings and their counters, generations and descriptors remain
unchanged. See [ciphertext qualification](../tests/storage-volumes/ciphertext.md).

## Read-only encrypted growth previews

`plan-preview-grow-volume DEVICE CONFIG PASSPHRASE_FILE EXPECTED_BYTES
LENGTH_BYTES` and `plan-preview-grow-recovery-volume DEVICE BACKUP
RECOVERY_KEYFILE EXPECTED_BYTES LENGTH_BYTES` authenticate the saved mapping and
check a complete proposed capacity/extent against a pinned read-only physical
disk, then report the candidate without publishing it:

```sh
vinix-volume plan-preview-grow-volume /dev/vda /root/data.vcrypt /root/volume.pass 33554432 12288
vinix-volume plan-preview-grow-recovery-volume /dev/vda /root/data.vrecover /root/recovery.key 33554432 12288
```

Capacity and extent length are explicit byte counts. Neither can shrink;
capacity and length must remain native-sector aligned. The extent must fit
within `capacity - saved_offset` and the kernel's signed mapping limit
`0x7fffffffffffffff`. Equal capacity/length are valid `keep` actions. Disk
identity, native sectors, mapper slot, starting offset, volume key and saved
read-only mode remain fixed. No publication destination is accepted.

Complete success prints three records: `operation=checked-growth
format=volume|recovery`; `current_disk_bytes=N planned_disk_bytes=N sector=N
identity=mbr:XXXXXXXX` (or canonical `gpt:GUID`) `capacity_action=keep|grow`;
and `slot=N offset=N current_bytes=N planned_bytes=N readonly=0|1
extent_action=keep|grow`. Integer metadata retains its full unsigned width.
`current_disk_bytes` and `current_bytes` come from the authenticated saved
input; `planned_disk_bytes` must equal the currently observed physical capacity.
For example, adopting a disk already expanded from 16 to 32 MiB reports
`current_disk_bytes=16777216 planned_disk_bytes=33554432 capacity_action=grow`.
The mode is the saved mapping's mode independently of the physical parent's
current read-only state.

Canonical format/geometry checks precede credential access. Ordinary VC1
configurations use the existing fixed-profile passphrase loader and complete
KDF allocation/erase/release; recovery VR1 inputs use their independent exact
64-byte private recovery key. Authentication precedes candidate validation,
device access and successful reports. Password, wrapping credential and decoded
volume key erase before opening the disk. Every return erases the complete
stack workspace. No fresh salt/nonce, entropy read, writer lock, configuration
publication, raw keyfile, mapper import or physical write is performed.

The physical parent stays pinned read-only with no-follow, nonblocking and
close-on-exec flags. It must be a whole online physical device with the exact
declared candidate capacity, saved identity and native sectors. Two final
rechecks cover identity/geometry/runtime identity and physical read-only mode
before reporting; the descriptor remains pinned through output flushing and
closes on every exit. Wrong disks, unobserved capacity declarations, shrinking,
misaligned/out-of-bounds extents, invalid credentials and changed disks fail
without a successful candidate report.

These are desired-geometry previews. They preserve source bytes, existing live
mapping status/generations/descriptors and ciphertext. They do not reserve a
slot/extent, preflight live admission, resize a device/filesystem, initialize
new data or guarantee a later publish/unlock. Perform explicit publication and
live application separately; those operations repeat their own checks. Success
returns 0, authentication/geometry/device/output failure returns 1, and invalid
syntax returns 2. Failures can print diagnostics; output failure can leave a
partial authenticated report. See [growth preview qualification](../tests/storage-volumes/growth-preview.md).

## Authenticated encrypted-volume growth

`plan-grow-volume DEVICE CONFIG PASSPHRASE_FILE LENGTH_BYTES NEW_CONFIG`
authenticates an encrypted configuration and publishes a separate private
configuration with a nondecreasing extent length and the observed physical
capacity. It preserves the exact volume key, native sectors, disk identity,
slot, starting offset and readonly mode. The disk may have its original capacity
or a larger one; smaller capacity, changed identity/sectors, shrinking extents,
unaligned lengths and out-of-bounds growth reject. Equal lengths are supported
for capacity adoption or a fresh wrapping salt/nonce.

```sh
# Plan against the current whole physical disk, without a raw keyfile.
vinix-volume plan-grow-volume /dev/vda /root/data.vcrypt /root/volume.pass 16777216 /root/data-grown.vcrypt
# Apply separately to an already active view; held descriptors keep working.
vinix-volume grow /dev/mapper/vinix0 16777216
vinix-volume remove /dev/mapper/vinix0
# Reopen with the new saved capacity/length after removal or reboot.
vinix-volume open-volume-auto /root/data-grown.vcrypt /root/volume.pass
```

Planning authenticates before opening the physical parent or output directory.
It retains one read-only parent descriptor, verifies the saved identity and
native sectors, then validates the proposed extent against the observed
capacity. It rechecks that disk before deriving the new wrapping key and again
after taking the output-directory lock, before publication. Runtime disk
identity, exact observed byte/sector geometry and physical readonly changes
observed during those rechecks reject. The original credential bytes are read
once, retained at their exact authenticated length and used with a fresh salt
and nonce; the old derived key is erased before reuse. After encoding, both
credential buffers and the plaintext volume key are erased before publication
I/O. Normal returns erase the complete workspace and close retained descriptors.

The unchanged 320-byte `VINIXVC1` format authenticates the new geometry and
wrapped key. Publication uses the same directory lock, mode-0600 temporary,
no-overwrite hardlink, cleanup and durability rules. Source, credential and
existing destination entries remain intact. A post-publication cleanup,
durability or reporting failure can leave a complete authentic configuration
with status 1. Complete operation/reporting returns 0 and invalid syntax 2.

Planning changes no live mapping, device data or filesystem, and reserves no
extent. Applying growth or importing the new configuration separately still
requires kernel privilege and mounted/swap/overlap admission. Existing live
growth preserves its generation and held descriptors. The same key, native
sectors and mapping start retain AES-XTS tweak positions, so prior ciphertext
reopens unchanged. Newly exposed bytes need initialization before use; raw
growth does not produce zero plaintext or resize a filesystem. Saved readonly
mode cannot escalate. Old configurations retain their old geometry and still
reject changed physical capacity; keep an independent recovery path and verify
new access before retiring them. Further physical contraction or sector changes
reject the new configuration too. Partition-table identity, sampled recheck,
credential storage, termination and unverified-ciphertext limits remain as
above. See [growth qualification](../tests/storage-volumes/volume-growth.md).

## Changing encrypted-volume configuration credentials

`rewrap-volume CONFIG OLD_PASSPHRASE_FILE NEW_PASSPHRASE_FILE NEW_CONFIG`
authenticates a `VINIXVC1` configuration and publishes a new private configuration
protecting the same volume key with new credential bytes, a fresh salt and a
fresh nonce. The authenticated whole-disk identity, physical byte/sector geometry,
mapping slot, offset, length and saved readonly mode remain exact. It needs no
raw keyfile, opens no physical disk and changes no mapping or volume ciphertext.

```sh
vinix-volume rewrap-volume /root/data.vcrypt /root/old.pass /root/new.pass /root/data-next.vcrypt
vinix-volume open-volume /dev/vda /root/data-next.vcrypt /root/new.pass ro
```

The original configuration's canonical format, bounded work profile and complete
authentication tag are checked before reading the new credential or opening
the output directory. The old passphrase and derived-key buffers are completely
erased before reuse, including the unused suffix when the new input is shorter.
Only authenticated metadata and the unwrapped volume key cross credential stages.
Both derivations use the existing fixed scrypt profile. The new configuration
uses the same 320-byte format, no-overwrite mode-0600 publication, directory lock,
durability and normal-return secret erasure rules described above. Input and
existing destination entries remain intact. Wrong old credentials, invalid
inputs, entropy/derivation failures and publication faults never publish a
partial configuration. Complete output can remain after post-publication cleanup,
durability or reporting failures, which return 1. Syntax errors return 2.

Credential files retain exact-byte semantics, including NUL, newline and
non-ASCII bytes. Using the same credential for both inputs is permitted and
refreshes the salt/nonce. The new configuration requires the new credential;
the preserved original remains usable with its original credential. Changing
credentials does not revoke copies of an old configuration or rotate the volume
key. Retire old copies only after validating new access and retaining an
independent recovery path. Rewrapping is offline: it preserves saved geometry
even if the physical disk has changed; later unlock still verifies that geometry
and rejects mismatches. Disk identity, readonly, credential-storage and volume-data
limitations remain as above. See [configuration rewrap qualification](../tests/storage-volumes/volume-rewrap.md).

## Saved volume plans

```sh
# Use a whole physical disk with a nonzero MBR signature or GPT disk GUID.
# Store the plan on a persistent filesystem available before restoration.
vinix-volume save /dev/vda /root/volumes.vmap
vinix-volume restore /dev/vda /root/volumes.vmap
```

`save` records every managed mapping on the selected physical disk, including
views created through its partitions. The plan stores absolute physical byte
offsets, lengths, slots and read-only flags. It verifies the disk size, logical
sector size and either a nonzero MBR disk signature or the GUID from a
CRC-checked primary GPT header. A protective MBR cannot substitute for an
unreadable GPT header. Supported sector sizes are powers of two from 512 through
4096 bytes. Saving never stamps or changes partition-table identity.

`restore` requires an explicit whole physical device path and verifies its
identity and geometry before creating mappings. Runtime disk numbers and paths
are absent from the saved format. All records are checked for corruption,
bounds, alignment, duplicate slots and overlapping extents. Every occupied
requested slot must already match the selected disk, offset, length and
read-only mode; a conflict fails before creating any missing mapping. Unlisted
managed views overlapping a requested extent also fail preflight. Matching
views retain their generation and open descriptors, making repeated restore
idempotent. Creates retain the kernel's ordinary management privileges, extent
protection and resource limits.

Plans use a bounded little-endian format: a 64-byte `VINIXVM1` version-1 header
with geometry, identity, record count, CRC32 and zero reserved bytes, followed
by up to 64 32-byte version-1 create records. CRC32 detects accidental
corruption; it does not authenticate a plan. MBR signatures and GPT GUIDs can
be duplicated by cloning. Explicit restore still relies on the selected
device; automatic discovery rejects multiple physical matches. Retain backups
of both the plan and its data.

Publication creates an exclusive mode-0600 temporary file in the destination
directory, writes and fsyncs it, renames it over the previous plan and fsyncs
the directory. Directory operations share one opened directory descriptor.
Failure before rename preserves the previous plan. A directory flush failure
after rename reports that publication occurred without confirmed durability.
Loading requires a bounded regular file and rejects a final symlink. These
flushes use the filesystem and device's existing guarantees; ext2 has no journal.

Save and restore are intended for serialized administration. Their status scans
do not lock out other management processes. Kernel creation rechecks each new
extent, but a later quota, I/O or concurrent-change failure can leave a created
prefix. Restore reports the error and keeps those mappings; applying the plan
again resumes from matching entries. It never removes unlisted mappings.
Filesystem mounting remains separate work. A plan stored inside a managed view
must be made available before that view can be restored.

## Discovery and boot restore

```sh
vinix-volume discover /root/volumes.vmap
vinix-volume restore-auto /root/volumes.vmap
# Opt in to restore before the desktop or interactive shell starts:
mkdir -p /etc/vinix
chown root:root /etc/vinix
chmod 755 /etc/vinix
vinix-volume save /dev/vda /etc/vinix/volumes.vmap
vinix-volume boot-restore
```

`discover` validates a plan and scans the top level of `/dev` for its physical
disk, printing the matched path without changing mappings. `restore-auto` uses
the same scan, then applies the ordinary restore checks through the selected
open device descriptor. The disk can acquire a different device name or runtime
number on the next boot. The scan considers block nodes only, skips symlinks,
partitions, logical views and unsupported status backends, and counts at most
4096 directory entries. Invalid table identities cannot match. An unreadable
supported candidate with matching geometry fails the scan because uniqueness
cannot be established. Multiple nodes aliasing one physical disk are accepted;
matching identities on distinct physical disks fail before creating any view.

The packaged ARM desktop init and both architectures' Alpine init scripts, plus
the AMD64 desktop init, run `boot-restore` once before starting applications or
the interactive shell. It loads `/etc/vinix/volumes.vmap` when present, together
with visible `.vmap` files in `/etc/vinix/volumes.d` as one plan set. Missing
configuration or an empty set is a successful no-op. An optional
`/etc/vinix/volumes.vset` bundle joins the same preflighted set. The opened `/etc`,
`/etc/vinix`, enabled plans directory and every enabled file must be owned by
root and not writable by group or others; none of those path components may be
a symlink. Plans must also satisfy the regular-file and checksum rules.
Directory-relative operations pin the configuration and device directories;
all discovered disk descriptors remain open through restore.

A failed boot restore prints its reason and init continues to the desktop or
recovery shell. It does not format, unlock or mount volumes, retry hotplug, or
remove existing mappings. Delete an enabled plan or give it a hidden name or a
different extension to disable its replay. Boot replay does not provide the
root filesystem needed to load its own configuration.

## Multi-disk plan sets

As an alternative to the single default file, enable one plan per disk in a
directory. Do not also leave the same disk's plan enabled as `volumes.vmap`.

```sh
mkdir -p /etc/vinix/volumes.d
chown root:root /etc/vinix /etc/vinix/volumes.d
chmod 755 /etc/vinix /etc/vinix/volumes.d
vinix-volume save /dev/vda /etc/vinix/volumes.d/main.vmap
vinix-volume save /dev/vdb /etc/vinix/volumes.d/data.vmap
vinix-volume restore-set /etc/vinix/volumes.d
vinix-volume boot-restore
```

`restore-set DIRECTORY` reads visible files ending in `.vmap`, without recursion.
Other names, including publication temporaries and backup files, are ignored.
An enabled symlink, directory, device or other nonregular file fails the set.
Explicit restoration uses normal file read permissions; boot replay adds the
ownership and write-permission checks above.

Sets contain at most 64 disk plans and 64 mappings in total. Each directory scan
visits at most 4096 non-dot entries. Files are loaded in bytewise filename order;
the legacy default file comes first during boot. Duplicate disk keys or global
mapper slots fail validation. All plans are decoded before disk discovery, and
all physical disks and existing mapping slots/extents are checked before the
first create. An absent or ambiguous disk, a malformed or untrusted later plan,
or a later mapping conflict cannot leave a restored prefix. Existing matching
views keep their generations and open descriptors. Physical identities are
rechecked through the retained disk descriptors after the final preflight.

These are preflight guarantees for serialized administration, not an atomic
multi-disk transaction. There is no global configuration generation or management
lock. Kernel creation still checks privilege, mounted/swap protection, quota and
current geometry. A failure during creation or concurrent reconfiguration can
leave previously created mappings in place, including an earlier disk's complete
plan. Replay resumes from matching mappings and never removes unlisted views.
Saving several individual files does not publish a set atomically; finish
enrollment before boot or explicit restore, or use the bundle below. Allocation
pools use bundle metadata as described below; spanning volumes and RAID remain
separate work.

## Atomic multi-disk bundles

```sh
# Capture all managed views on these explicitly selected physical disks.
vinix-volume save-set /root/volumes.vset /dev/vda /dev/vdb
vinix-volume restore-bundle /root/volumes.vset
# To enable the same bundle before applications start:
vinix-volume save-set /etc/vinix/volumes.vset /dev/vda /dev/vdb
vinix-volume boot-restore
```

`save-set BUNDLE DEVICE [DEVICE ...]` accepts 1–64 whole physical disks. Each
disk needs the same identity and geometry as a single-disk plan. It saves all
managed mappings on those disks, preserving offsets, slots and read-only mode;
a disk with no managed mappings is also valid. Duplicate disk identities,
physical aliases and duplicate global slots fail before publication. All disk
descriptors remain open until every identity has been rechecked. An unreadable
later disk or invalid snapshot preserves the previous bundle.

The complete bundle uses one exclusive mode-0600 temporary file, file fsync,
atomic rename and directory fsync, anchored to the same directory descriptor as
single-plan publication. Readers opening the destination see the previous or
the new complete file. Write, file-flush, close or rename failures preserve the
old destination and remove the temporary. A directory-flush failure after rename
reports failure with the new file already published and durability unconfirmed.
These guarantees depend on the backing filesystem's existing flush/recovery
guarantees; a checksum does not make an unjournaled filesystem crash-safe.

The bounded `VINIXVS1` version-1 format has a 64-byte header containing version,
disk count, total byte count, total mapping count, CRC32 and zero reserved bytes,
followed by complete `VINIXVM1` disk plans in command-line order. Both inner and
outer checksums are validated, together with global identity/slot uniqueness.
At most 64 mappings are stored across all disks, so the largest version-1 bundle
is 6208 bytes. Bundles with allocation pools use version 2 as described below.
CRC32 detects accidental corruption; it does not authenticate a bundle.

`restore-bundle` reads a bounded regular file without following its final
symlink, discovers all physical disks, then uses the existing plan-set preflight
and idempotent restore. A malformed later plan, missing disk or mapping conflict
fails before any create. Matching views retain their generations and descriptors;
unlisted views are never removed. Boot replay loads the legacy `volumes.vmap`,
then `volumes.vset`, then visible `volumes.d/*.vmap` files into one set and applies
the ordinary root-ownership/write-permission rules to each enabled input. Remove
duplicate individual enrollment before enabling a bundle: overlaps are rejected
rather than giving one configuration precedence.

Atomic publication applies to the saved configuration. Saving still requires
serialized administration: the kernel has no global mapping snapshot or
configuration generation. Restoring remains a sequence of independently checked
creates; a quota, I/O or concurrent-reconfiguration failure during application
can leave an already created prefix. Replaying the same bundle resumes from
matching entries. Filesystem mounting, spanning volumes and RAID remain separate
work.

## Planned capacity growth

```sh
# Slot 2 already exists and has unused physical space immediately after it.
vinix-volume save-set /root/capacity.vset /dev/vda /dev/vdb
vinix-volume plan-grow /root/capacity.vset 2 16777216
vinix-volume restore-bundle /root/capacity.vset grow
# Enroll the resulting live geometry for ordinary boot replay.
vinix-volume save-set /etc/vinix/volumes.vset /dev/vda /dev/vdb
```

`plan-grow BUNDLE SLOT LENGTH_BYTES` edits one existing mapping's desired length
and atomically publishes the complete bundle. It reads the saved configuration
without opening a physical device or changing a live mapping. The disk identity,
start offset, slot and read-only mode stay fixed. The new length must be at least
the saved length, sector-aligned, inside the saved disk geometry and disjoint
from every other mapping on that disk. A missing slot, shrink, overflow,
misalignment or overlap preserves the previous file; repeating the same desired
length is valid. The existing checksummed format and publication guarantees apply.

`restore-bundle BUNDLE grow` explicitly permits existing smaller views to grow
in place when their physical identity, start, sector size, slot and read-only
mode match. It discovers every disk and checks all requested slots and extents,
including unlisted views in the extension, before the first grow or create.
Ordinary restoration and boot replay continue to require exact lengths for
existing views. Missing views are created at the saved desired length in either
mode. Boot replay can therefore recreate the grown geometry after reboot.

Before each grow, the utility opens that mapping and checks the generation and
old length captured by preflight. It uses that same descriptor for the grow
ioctl and verifies the resulting length and generation afterward. A replaced
slot or changed geometry fails without resizing the replacement. Successful
growth retains the volume's generation and open descriptors, and read-only
volumes keep their read-only mode. Replaying an already applied growth is a
no-op for those views. This extends raw block capacity within existing physical
disk geometry; filesystem resizing remains separate work.

Administration must remain serialized. The kernel rechecks privilege,
mounted/swap protection, parent bounds, overlaps and policy-resource limits when
each change is applied. A later failure can leave completed grows and creates
in place; replay resumes from matching entries. The saved desired lengths remain
published even if runtime application fails. An explicit growth replay is needed
to resume a live view that is still smaller than its saved plan.

## Bundle inspection and preflight

```sh
vinix-volume show-bundle /root/capacity.vset
vinix-volume check-bundle /root/capacity.vset
# Preview a plan that explicitly allows existing smaller views to grow:
vinix-volume check-bundle /root/capacity.vset grow
vinix-volume restore-bundle /root/capacity.vset grow
```

`show-bundle BUNDLE` validates the complete checksummed configuration and prints
each disk's size, sector size and MBR signature or canonical GPT GUID, followed
by its mapping slots, offsets, desired lengths and read-only modes. Disk numbers
in this report are indices in the bundle's saved order. Inspection works offline
and opens only the saved file. It accepts the same bounded regular-file format
and rejects final symlinks and corruption without changing the file.

`check-bundle BUNDLE [grow]` discovers the saved physical disks and runs the same
complete-set preflight as restoration, opening devices read-only. It checks disk
identity/geometry, requested slots and existing extents, including unlisted views
in a planned extension. Every retained disk identity is rechecked after the last
disk's preflight. A malformed file, missing or ambiguous disk, wrong existing
mapping or extent conflict returns failure. Action rows are printed only after
the entire set passes.

Each row reports `action=create`, `action=keep` or `action=grow`, the slot and
offset, current and desired lengths, read-only mode and captured generation.
Missing views report zero current length and generation. A final line counts
each action. Growth requires the explicit `grow` token, with the same matching
rules as explicit growth replay; the default check requires existing lengths
to match exactly. Checking creates or grows no mappings and preserves the bundle.
Both report commands return failure if printing or flushing their output fails.

A successful check describes current discovery and geometry. It does not reserve
extents or test mutation-time management privileges, mounted/swap protection or
resource limits. Administration must remain serialized, and applying the plan
still performs the kernel's ordinary checks and generation/length revalidation.
Read access suffices for a check even when the bundle describes writable views.

See [inspection and preflight qualification](../tests/storage-volumes/check-bundle.md).

## Offline mapping configuration

```sh
# Save identities first; disks with no managed views are valid participants.
vinix-volume save-set /root/layout.vset /dev/sd0 /dev/sd1
vinix-volume show-bundle /root/layout.vset
# Add slot 12 on saved disk index 1, at an absolute physical byte offset:
vinix-volume plan-add /root/layout.vset 1 12 4194304 1048576 ro
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
# Stop replaying slot 12 without changing a live mapping:
vinix-volume plan-remove /root/layout.vset 12
```

`plan-add BUNDLE DISK_INDEX SLOT OFFSET_BYTES LENGTH_BYTES [ro]` adds one desired
mapping to an enrolled disk without opening a device or changing a live view.
The disk index is its zero-based saved order, as printed by `show-bundle`;
it is independent of runtime device names. The offset is absolute within the
saved physical disk. Length must be nonzero. Offset and length must align to
the saved sector size, fit its saved capacity without overflow and avoid all
other planned extents on that disk. Slots 0 through 63 are globally unique
across the bundle. An already planned slot is an error even if its geometry
matches. The optional literal `ro` sets read-only mode; omission allows writes.

`plan-remove BUNDLE SLOT` removes an existing desired entry, preserving the
remaining order, disk identities, geometry and modes. A missing slot is an
error. A disk remains enrolled after removing its last entry, and subsequent
checking/replay still requires that disk's identity. A removed slot can be
assigned to a different enrolled disk in the saved configuration.

Both commands decode and validate the complete bounded checksummed bundle
before editing. They publish the entire new set through the shared atomic
publisher with mode 0600, retaining the existing file on validation or
pre-publication I/O failure. As with capacity planning, directory-flush failure
after rename returns an error with the new file visible and its durability
unconfirmed. Reporting failure also returns an error after publication; inspect
the file before retrying. Final symlinks and corrupt/nonregular files are
rejected. Cooperating saved-state writers use the
[directory locking protocol](#saved-plan-writer-locking) below to prevent lost edits.

Removing a desired entry does not remove a live view, invalidate its open
descriptors, erase data or release its physical extent. Replay preserves
unlisted views. Use the separate live `remove` command when removal is intended;
the kernel applies its ordinary mounted/swap/lifetime protections. Reassigning
an omitted slot or extent can therefore fail live preflight until the old view
is explicitly removed. Use `check-bundle` before application: offline validation
checks saved extents, while live preflight also detects unlisted mappings.

This completes add/remove editing of saved linear mappings; RAID,
filesystem resize and encryption remain separate work. See
[offline edit qualification](../tests/storage-volumes/edit-bundle.md).

## Atomic explicit mapping additions

```sh
vinix-volume plan-preview-add-batch /root/layout.vset \
  mbr:12345678 19 8388608 4096 rw mbr:12345679 20 8388608 4096 ro
vinix-volume plan-add-batch /root/layout.vset \
  mbr:12345678 19 8388608 4096 rw mbr:12345679 20 8388608 4096 ro
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
```

`plan-add-batch BUNDLE IDENTITY SLOT OFFSET_BYTES LENGTH_BYTES MODE [...]`
adds 1–64 mappings at explicitly chosen offsets as one saved-state edit.
Select an enrolled disk by its `mbr:` signature or `gpt:` GUID, in the format
printed by `show-bundle`; hexadecimal letters may use either case. Identity
selection is independent of saved geometry and shifting disk indices. The
bundle's current capacity and sector size validate every requested extent.
Offsets and lengths are decimal bytes; modes must be explicit `rw` or `ro`.

Existing globally owned slots are `keep` retries only when the target identity,
offset, length, mode and every saved row field match exactly. Different disks,
geometry or modes never overwrite a desired row. New rows append in request
order within each disk, retaining all existing row order, pending desired edits,
disk order and pool bounds/alignment/priority. Several distinct slots may target
the same identity. Duplicate requested slots, absent enrolled identities,
ambiguous saved identities, invalid/overlapping/overflowing extents and the
64-mapping bound fail with complete rollback and no partial action report.
Matching retries remain safe after an unrelated empty disk is forgotten.

This chooses explicit extents rather than searching a pool. Pool membership,
eligibility and pool alignment do not constrain this editor; ordinary saved
disk/sector/extent rules still apply, and future pool queries account for rows
intersecting their regions. Allocation through a pool remains a separate command.
Existing single indexed `plan-add` retains its duplicate-slot error behavior.

`plan-preview-add-batch` uses the same complete planner and reports every
request's current disk index, identity, slot, add/keep action, offset, length and
mode without physical probes, a writer lock, temporary or publication. A preview
does not reserve the configuration. Publication retains the pinned directory
writer lock through source reads, atomic replacement, report flushing and
cleanup. Every all-keep retry still writes, file-fsyncs, renames and directory-
fsyncs the whole bundle. Before rename failures retain old bytes; afterward only
the complete new set may be visible with durability unconfirmed. Buffered output
failure also returns an error. Repeat the complete request list or inspect the
saved state to confirm durability under serialized administration.

Saved additions do not instantiate live views or write their physical extents.
Later complete-set `check-bundle`/replay still detects unlisted live slot/extent
conflicts before actions. Successful explicit replay creates missing views and
keeps matching generations; desired omission does not remove them. Existing
V1/V2 formats and boot replay persist the rows. See
[explicit addition qualification](../tests/storage-volumes/addition-batch.md).

## Atomic explicit mapping growth

```sh
vinix-volume plan-preview-grow-batch /root/layout.vset \
  mbr:12345679 9 8192 mbr:12345678 2 8192
vinix-volume plan-grow-batch /root/layout.vset \
  mbr:12345679 9 8192 mbr:12345678 2 8192
vinix-volume check-bundle /root/layout.vset grow
vinix-volume restore-bundle /root/layout.vset grow
```

`plan-grow-batch BUNDLE IDENTITY SLOT LENGTH_BYTES [...]` grows 1–64 existing
desired mappings in place as one atomic saved-state edit. Identities use the
MBR/GPT format printed by `show-bundle`, accepting either hexadecimal case.
Every slot must belong to the selected identity. Identity selection ignores
saved geometry and shifting indices; current saved capacity and sector size
validate the requested length. Several distinct slots may select one disk.

Lengths are decimal, nonzero and sector-aligned. Equal-size requests are durable
`keep` retries. Growth preserves offsets, modes, generations of matching live
views, desired row/disk order and pool bounds/alignment/priority. Shrinking,
relocation and mode changes are not growth operations. Missing slots, wrong or
ambiguous identities, repeated requested slots, overlaps, unaligned/out-of-bounds
or overflowing extents reject the complete batch without caller state/results
or partial action reports. A later failure cannot retain an earlier growth.
Identity-based retries stay valid after unrelated empty-disk compaction.

This editor grows explicit extents without requiring pool membership, eligibility
or pool alignment. Ordinary disk sector/bounds/overlap rules apply; pool queries
account for desired rows that intersect their regions. `pool-grow-batch` keeps
its additional eligibility checks. Existing single `plan-grow` stays available.

`plan-preview-grow-batch` uses the same planner and reports every request's
identity, current disk index, slot, offset, previous/requested lengths, mode and
grow/keep action. It opens only the saved file, taking no writer lock and creating
no temporary or publication. Publication keeps the pinned directory writer lock
through source reads, replacement, report flushing and cleanup. All-keep retries
still write, file-fsync, rename and directory-fsync the complete bundle. Before
rename an I/O failure retains the old bytes; after rename only the whole new set
may be visible with durability unconfirmed. Buffered output failures also return
an error. Retry the full list or inspect the saved state under serialized
administration to establish durability.

Published growth remains desired state until explicit `check-bundle ... grow`
and `restore-bundle ... grow`. Their complete live preflight detects extension
conflicts before the first mutation; ordinary replay rejects smaller live views.
Successful growth retains each live generation and its open descriptors, which
can access the new extent, preserving read-only modes. Runtime application can
still fail after earlier mutations; replay resumes from matching views. Removing
desired rows does not remove live views. Boot restoration persists desired
lengths in the unchanged V1/V2 formats. See
[explicit growth qualification](../tests/storage-volumes/explicit-growth-batch.md).

## Atomic pool eligibility contraction

```sh
vinix-volume pool-space /root/layout.vset 5
vinix-volume pool-preview-contract-batch /root/layout.vset 5 \
  mbr:12345678 12591104 mbr:12345679 12591104
vinix-volume pool-contract-batch /root/layout.vset 5 \
  mbr:12345678 12591104 mbr:12345679 12591104
```

`pool-contract-batch BUNDLE POOL IDENTITY END_BYTES [...]` releases the unused
tail of 1–64 existing allocation windows in one atomic edit. Choose enrolled
MBR/GPT identities from `show-bundle` and inspect current bounds with `pool-space`.
Each identity must be a member of the selected pool. Duplicate normalized
identities, ambiguous saved identities, missing disks/members and invalid counts
reject the whole batch. Selection ignores shifting indices and selector geometry;
the current saved sector size validates each requested decimal end.

The end is exclusive, sector-aligned, strictly greater than the unchanged start
and no greater than the old end. Equal ends are durable `keep` retries; a smaller
end reports `contract`. Allocation alignment stays unchanged, and an end need
not align to that larger allocation alignment. Contraction preserves the complete
occupied intersection of every desired mapping with its original window. A row
crossing either window boundary is protected where it overlaps; rows entirely
outside the window do not prevent releasing its free tail. Cutting occupied
bytes, an empty window, expansion, invalid alignment or overflow rejects the
complete edit without keeping earlier contractions or reporting partial actions.

All desired rows, offsets, modes, pending lengths, global slots, disk order and
geometry stay exact. Starts, allocation alignment, region count, other pools and
allocation priority remain unchanged. Identity retries follow unrelated empty-
disk compaction. Future pool queries/allocation/growth use the retained windows;
explicit mapping placement remains independent of pool eligibility.

`pool-preview-contract-batch` uses the same complete planner, reporting each
identity, current disk index, start, previous/requested end, alignment and action
without physical-device probes, writer locking, temporaries or publication.
Publication holds the pinned directory writer lock through source read, atomic
replacement, report flushing and cleanup. All-keep retries still write, file-
fsync, rename and directory-fsync the entire bundle. Before rename failures keep
old bytes; afterward only the whole new set may be visible with durability
unconfirmed. Buffered stdout failure also returns an error. Inspect or retry the
complete request under serialized administration to confirm durability.

This changes saved eligibility without shrinking disks, mappings or filesystems,
moving/erasing data or detaching live views. Unlisted live mappings are not part
of offline occupation checks; their descriptors/data survive even when a window
excludes them. Complete live preflight and the kernel's ordinary protections still
govern later application. Existing V1/V2 formats and boot restoration persist
contracted windows. See
[contraction qualification](../tests/storage-volumes/pool-contract-batch.md).

## Atomic cross-pool window resizing

```sh
# Transfer an unused 4 KiB boundary region from pool 5 to adjacent pool 6.
vinix-volume pool-preview-resize-batch /root/layout.vset \
  mbr:12345679 6 12587008 12599296 mbr:12345679 5 12582912 12587008
vinix-volume pool-resize-batch /root/layout.vset \
  mbr:12345679 6 12587008 12599296 mbr:12345679 5 12582912 12587008
```

`pool-resize-batch BUNDLE IDENTITY POOL START_BYTES END_BYTES [...]` changes both
bounds of 1–64 existing pool members in one atomic edit. Every request selects
an enrolled MBR/GPT disk identity and pool. The same disk may appear in different
pools; duplicate identity/pool pairs, ambiguous saved identities and absent
disks/members reject the complete request. Selection follows current saved
geometry and survives unrelated disk-index compaction.

Requested windows must be nonempty, sector-aligned and within saved disk
capacity. Allocation alignment stays unchanged; bounds need not match that
larger alignment. A resize must retain the entire occupied intersection of
each desired mapping with its original window, protecting both the head and
tail, including mappings crossing either original boundary. Rows outside the
original window do not prevent releasing unused capacity. Newly admitted
desired rows count as occupied in subsequent pool queries and allocations.

Disjointness is checked on the complete candidate, allowing unused capacity
to pass between adjacent pools in either request order. An intermediate
overlap exists only in private planning storage. A later invalid request or
overlapping final window preserves every original field and reports no action
prefix. Desired rows, offsets, modes, pending lengths, slots, disk geometry,
region count/order and allocation priority remain exact. Empty members may
move to other free bounds; existing memberships and alignment are preserved.

`pool-preview-resize-batch` reports every resolved disk/pool, identity,
old/new start/end, alignment and `resize`/`keep` action without physical-device
probes, writer locking or publication. Publication holds the pinned directory
writer lock through source loading, whole-set validation, atomic replacement,
report flushing and cleanup. Equal-bound retries still write, file-fsync,
rename and directory-fsync the whole bundle. Before rename failure leaves old
bytes; afterward only the complete new candidate may be visible with durability
unconfirmed. Buffered stdout failure returns an error. Inspect or retry the
complete request under serialized administration to confirm durability.

This edits saved allocation eligibility. It leaves live mappings, descriptors,
generations and data intact, including unlisted live views outside the new
window. Future pool placement uses the new bounds; explicit placement remains
independent. Complete live preflight and ordinary kernel protection govern
later application. Existing V1/V2 formats and boot replay retain the resized
windows. See [cross-pool resizing qualification](../tests/storage-volumes/pool-resize-batch.md).

## Atomic physical capacity contraction batches

```sh
# Adopt an already observed 20 MiB disk after reducing unused pool eligibility.
vinix-volume plan-preview-contract-capacity-batch /root/layout.vset \
  mbr:12345678 /dev/sd0 20971520 mbr:12345679 /dev/sd1 16777216
vinix-volume plan-contract-capacity-batch /root/layout.vset \
  mbr:12345678 /dev/sd0 20971520 mbr:12345679 /dev/sd1 16777216
```

`plan-contract-capacity-batch BUNDLE IDENTITY DEVICE EXPECTED_BYTES [...]`
adopts the observed smaller or equal capacity of 1–64 enrolled physical disks
as one saved-state edit. Identity selects MBR/GPT participants independently of
their current disk indices. Duplicate normalized identities, ambiguous saved
identities, missing participants and repeated physical disks reject the entire
batch. Every expected size must be positive, sector-aligned, at least two saved
sectors and no larger than the saved capacity.

Every desired mapping, including a pending length, must fit inside its selected
disk's new capacity. Every pool window on that disk must also fit, including
unselected pools. Contract unused pool eligibility first with `pool-contract-batch`
or `pool-resize-batch`; occupied mappings cannot be discarded implicitly. All
mapping rows, modes, slots, pending lengths, disk identifiers/sectors, pool bounds,
region order and allocation priority remain exact. Only selected saved capacity
fields change. The existing growth adoption commands keep their growth-only
contract.

The command opens every named device read-only with CLOEXEC, NOFOLLOW and
NONBLOCK, retaining all descriptors through publication, report flushing and
cleanup. It probes whole physical online devices through status and the first
two sectors. Each observed identifier and sector size must match saved state,
and observed bytes must equal the requested size exactly. A final all-descriptor
pass after complete planning rechecks physical ID and full identity/geometry;
an early disk changing while a later disk is probed rejects the whole batch.
It issues no physical writes, resize requests or live mapping operations.

`plan-preview-contract-capacity-batch` performs the same verification without
a writer lock or publication. Successful reports contain every resolved disk,
identity, old/new capacity, sector size and `contract`/`keep` action in request
order. A later failure emits no partial action list. Publication holds the
directory writer lock through source loading, replacement, report flushing and
device-pin cleanup. Equal-capacity retries still write, file-fsync, rename and
directory-fsync the complete bundle. Before rename, failure preserves old bytes;
afterward the complete candidate may be visible with durability unconfirmed.
Buffered stdout failure also returns an error. Retry the complete request under
serialized administration to confirm durability.

This adopts geometry already provided by a physical backend. Filesystem shrink,
data relocation and physical resizing require separate procedures. Live mappings
and held descriptors remain intact; later explicit replay and production boot
require exact adopted geometry. V1/V2 formats are unchanged. See
[physical contraction qualification](../tests/storage-volumes/capacity-contract-batch.md).

## Atomic desired mapping removal batches

```sh
vinix-volume plan-preview-remove-batch /root/layout.vset 13 12
vinix-volume plan-remove-batch /root/layout.vset 13 12
vinix-volume check-bundle /root/layout.vset
```

`plan-remove-batch BUNDLE SLOT [...]` removes 1–64 distinct desired mapping
slots as one saved-state edit, across any enrolled disks. Slots are unsigned
decimal numbers from 0 through 63. Duplicate requests, invalid counts/numbers
and invalid source bundles fail before publication or action reporting. The
whole request is validated before a private candidate is changed; failure
preserves both the original set and caller action results.

Present slots report `action=remove`, their saved disk, offset, length and
read-only mode in request order. Already absent slots report `action=keep`;
mixed present/absent requests succeed. A matching retry therefore keeps exact
saved bytes while still writing, file-fsyncing, atomically renaming and
directory-fsyncing the complete set. Single-slot `plan-remove` retains its
existing behavior, including an error for an absent slot.

Remaining rows keep their order, geometry, modes and pending desired edits.
Vacated row storage is cleared. Disk identities, capacities, enrollment and
indices are preserved even when the last row is removed. Every pool region,
bound, alignment and allocation priority remains unchanged. Freed desired slots
can be reused by later explicit planning operations.

`plan-preview-remove-batch` uses the same complete planner and reports every
remove/keep action without opening physical devices, taking a writer lock,
creating a temporary or publishing. A preview does not reserve saved state.
Publication retains the pinned directory writer lock from source read through
report flushing and cleanup. Failure before rename retains the old file;
after rename the complete new set may be visible with durability unconfirmed.
Buffered output failure also returns an error. Inspect saved state or repeat
the complete removal list to confirm durability.

Removing desired rows does not detach live views, release their physical
extents, invalidate descriptors or erase data. Replay preserves unlisted views;
live preflight still rejects a reused slot or extent that conflicts with one.
Live removal remains a separate explicit operation with the kernel's existing
mounted/swap/lifetime protections. The existing checksummed V1/V2 formats and
boot replay persist the omissions. See
[removal batch qualification](../tests/storage-volumes/removal-batch.md).

## Offline disk membership

```sh
# Capture another whole disk, then append its saved plan to the existing bundle.
# This example assumes disk 2 has no managed views and the bundle has two disks.
vinix-volume save /dev/sd2 /root/disk2.vmap
vinix-volume plan-enroll /root/layout.vset /root/disk2.vmap
vinix-volume show-bundle /root/layout.vset
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
# An empty participant can stop taking part in subsequent replay:
vinix-volume plan-forget /root/layout.vset 2
```

`plan-enroll BUNDLE PLAN` imports one complete checksummed single-disk `.vmap`
plan into an existing bundle. It appends the disk's saved identity, geometry
and all desired rows in their existing order. Empty disk plans are valid.
Existing desired mappings, including pending capacity changes and mappings not
yet created, remain intact. This avoids rebuilding the whole bundle from live
views with `save-set`. No device is opened during enrollment: physical presence
and identity are checked by the later `check-bundle` or restoration command.
An unavailable but enrolled empty disk also blocks that later replay.

Both inputs must be bounded regular files with valid versions and checksums;
final symlinks are rejected. Repeated disk keys, duplicate global slots,
invalid imported geometry and the 64-disk/64-mapping limits fail before
publication. The source plan remains unchanged and its readable descriptor
stays open alongside the bundle descriptor through publication. Enrollment uses
the existing atomic publisher and the same durability/error rules as mapping
edits. A bundle cannot import itself as a single-disk plan.

`plan-forget BUNDLE DISK_INDEX` removes an empty enrolled disk. First remove each
of its desired mappings with `plan-remove` if any remain. A populated disk, a
missing index or removal of the last enrolled disk fails without changing the
file. The remaining identities, geometry, modes and global slot ownership
survive. Disk order is stable, but indices after the removed disk decrease by
one; inspect `show-bundle` before subsequent indexed edits. Enrollment appends
and keeps all existing indices unchanged.

Omitting a disk stops requiring its identity during subsequent replay. Its
live mappings, data and open descriptors remain usable, and replay keeps those
unlisted mappings. Their physical extents still obey the ordinary runtime
protections. Reenrollment imports the saved desired rows and resumes complete
preflight; matching live views keep their generations. Saved membership edits
use directory locking; live application remains a separate serialized operation.
A disk with pool membership must first have that membership removed before it
can be forgotten; remaining pool disk indices follow the compacted saved order. Spanning volumes
and RAID are still separate work. See
[disk membership qualification](../tests/storage-volumes/disk-bundle.md).

## Atomic disk enrollment batches

```sh
vinix-volume plan-preview-enroll-batch /root/layout.vset /root/disk2.vmap /root/disk3.vmap
vinix-volume plan-enroll-batch /root/layout.vset /root/disk2.vmap /root/disk3.vmap
vinix-volume check-bundle /root/layout.vset
```

`plan-enroll-batch BUNDLE PLAN [...]` imports 1–64 complete single-disk snapshots
as one saved-state edit. Every input must be a bounded regular `.vmap` file
with valid version, checksum, identity, geometry and ordered mapping rows.
Final symlinks are rejected. New disks append in request order, preserving
all existing disk indices, pending desired edits and pool metadata/priority.
Snapshots do not carry pool membership; configure eligibility separately.

An already-enrolled identity is a `keep` retry only when capacity, sector size,
identity kind/value and every active mapping row, mode and row order match.
Matching retries retain the existing disk index and saved plan, including
inactive storage. Conflicting snapshots never overwrite desired state.
Identity means the MBR signature or GPT GUID independently of geometry;
duplicate identities in the request or an ambiguous existing bundle fail.
Duplicate global slots, invalid geometry and the 64-disk/64-mapping limits
also fail without a partially enrolled prefix. Single-plan `plan-enroll`
retains its existing duplicate-key error behavior.

The command retains all read-only, close-on-exec source descriptors through
publication and report flushing. After complete planning it rechecks each
pinned inode against its original checksummed bytes, handling interrupted and
short reads. Observed source changes or read/stat failures abort the whole
operation. Replacing a source path cannot redirect an already-pinned import.
Administration must serialize source edits; the final reads cannot prevent a
write that happens afterward.

`plan-preview-enroll-batch` uses the same validation, planning and source
rechecks without physical-device probes, a writer lock, temporary or
publication. Both commands report every request's disk index, add/keep action,
identity, capacity, sector size and complete ordered mapping rows, after all
inputs succeed. Preview does not reserve the configuration.

Publication retains the pinned bundle directory writer lock from source read
through cleanup. Every matching retry still writes, file-fsyncs, atomically
renames and directory-fsyncs the entire bundle. Failure before rename keeps
the old file; after rename the complete new set may be visible with durability
unconfirmed. Buffered output failure returns an error too. Inspect saved state
or repeat the same snapshots to confirm durability. Enrollment opens no live
views and relocates no data; later complete live preflight/replay still checks
all enrolled disks, including unavailable empty participants. Existing V1/V2
formats and boot replay persist the imports. See
[enrollment batch qualification](../tests/storage-volumes/enrollment-batch.md).

## Atomic disk forgetting

```sh
vinix-volume show-bundle /root/layout.vset
vinix-volume plan-preview-forget-batch /root/layout.vset mbr:1234567b mbr:1234567c
vinix-volume plan-forget-batch /root/layout.vset mbr:1234567b mbr:1234567c
```

`plan-forget-batch BUNDLE IDENTITY [...]` removes 1–64 distinct empty enrolled
disks in one saved-state publication. Select identities exactly as printed by
`show-bundle`: `mbr:` followed by eight hexadecimal digits, or `gpt:` followed
by a GUID in `8-4-4-4-12` form. Hexadecimal letters may use either case; prefixes
are lowercase. Zero identities, malformed tokens, duplicate requests and
ambiguous existing identities fail. Selection uses identity kind/value
independently of capacity and sector size, so an absent-identity retry cannot
accidentally select a disk that acquired a removed disk's old index.

Each present disk must have no desired mappings or allocation pool membership.
Remove those entries explicitly first. At least one enrolled disk must remain.
A later protected participant or invalid request rolls back the entire edit;
no prefix is published or reported. An absent identity reports `keep` and
still participates in durable retries. Existing single-index `plan-forget`
retains its original behavior.

Surviving disks keep their relative order, identities, geometry, mapping rows,
modes and global slot ownership. Every remaining pool reference is remapped to
its disk's compacted index; bounds, alignment, region order and allocation
priority remain exact. Reports list every requested forget/keep action and
every survivor's old/new index and identity. Inspect the resulting indices
before subsequent indexed edits.

`plan-preview-forget-batch` runs the same complete planner without physical
device probes, a writer lock, temporary or publication. Preview does not reserve
the configuration. Publication retains the pinned directory writer lock from
source read through report flushing and cleanup. All-absent retries still write,
file-fsync, rename and directory-fsync the full bundle. Before rename, failures
retain old bytes; afterward the complete new set may be visible with durability
unconfirmed. Buffered output failure also returns an error. Repeating the same
identity list is safe while administration serializes desired-state changes.

This removes saved enrollment only. Live views, extents, generations, data and
open descriptors remain protected by the existing kernel lifetime rules;
separate live application/removal stays explicit. The checksummed V1/V2 formats
and boot replay persist omissions and remapped pool references. See
[disk forgetting qualification](../tests/storage-volumes/forget-batch.md).

## Bounded extent allocation

```sh
# Choose a region reserved for managed raw volumes on saved disk index 0.
vinix-volume plan-space /root/layout.vset 0 8388608 16777216 1048576
vinix-volume plan-allocate /root/layout.vset 0 20 2097152 8388608 16777216 1048576
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
```

`plan-space BUNDLE DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES` reports
the gaps between saved desired mappings within an explicit allocation region.
The end is exclusive. Both boundaries must fit the saved disk and align to its
logical sector; alignment must be a power of two at least as large as that
sector. Gap starts round upward to the requested alignment. Lengths cover the
remaining sector-aligned portion, so alignment constrains placement rather than
size. Gaps appear in physical offset order even when saved rows are unsorted;
the saved row order and bundle bytes stay unchanged. Read-only desired mappings
occupy space too. The summary reports the count, sum and largest eligible gap;
alignment prefixes are excluded, and a region with no eligible gap succeeds
with zero totals. Rounding remains bounded near the unsigned 64-bit limit.

`plan-allocate BUNDLE DISK_INDEX SLOT LENGTH_BYTES START_BYTES END_BYTES
ALIGNMENT_BYTES [ro]` appends one mapping in the lowest-address gap that fits its
nonzero sector-aligned length. It never combines fragmented gaps or spans disks.
The slot must be globally free, and the complete desired set must remain valid.
All existing identities, row order, lengths and modes survive. Invalid ranges,
slots, modes and sizes, full mapping tables or insufficient contiguous space
fail without publishing. The selected offset, length and mode are printed after
the shared atomic publisher completes. Publication has the same permissions,
flush ordering and error rules as `plan-add`, including a visible new bundle
with a failure result if directory fsync fails after rename.

Both commands operate offline on the existing bounded checksummed bundle;
they open no devices and reject a final symlink or nonregular input. The
allocation region is an explicit administrative choice: these gaps describe
saved desired mappings, not filesystem free space. Reserve partition-table,
filesystem, swap and other data extents when choosing the region. Unlisted live
mappings and protected extents may occupy an offline gap. `check-bundle` detects
live mapping conflicts, and live application retains kernel extent protection
and the ordinary partial-failure rules. Planning does not format, discard,
reserve live storage or alter live descriptors. Directory locking makes
subsequent planning read the newly saved row. Live administration remains
serialized. Persistent allocation pools extend this selection across disk
regions below. Spanning volumes and RAID remain separate work. See
[extent allocation qualification](../tests/storage-volumes/space-bundle.md).

## Adopting physical capacity growth

```sh
# Disk index 0 still identifies this whole disk after its backing capacity grows.
vinix-volume plan-capacity /root/layout.vset 0 /dev/vda 25165824
vinix-volume plan-space /root/layout.vset 0 16777216 25165824 4096
vinix-volume plan-allocate /root/layout.vset 0 20 8192 16777216 25165824 4096
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
```

Saved plans normally match the exact physical capacity. If a virtual backing
disk or physical namespace becomes larger, discovery and ordinary/boot replay
continue to reject the old geometry. `plan-capacity BUNDLE DISK_INDEX DEVICE
EXPECTED_BYTES` explicitly adopts a larger **already observed** capacity for
one enrolled disk. It opens the named whole disk read-only, verifies its valid
MBR signature or checksummed primary GPT GUID, and requires the saved identifier
and logical sector size to match. The observed byte count must equal the
explicit expected value, be sector-aligned, and be at least the saved size.
Shrinks, changed identifiers/sectors, partition/volume targets, offline devices
and another enrolled disk with the same identifier fail without publication.
The disk index follows `show-bundle` order; a reordered device path cannot
silently update a different identifier.

The same descriptor remains open through a second identity/geometry probe and
atomic publication. A changed kernel disk identity, persistent identifier or
capacity between probes aborts. Only that disk's saved capacity changes; all
desired rows, their order, pending unapplied edits, modes and other participants
survive. No mapper mutation, disk write, resnapshot, partition-table update or
filesystem resize occurs. Planning and separate complete-set replay preserve
matching live generations and open descriptors. The newly adopted tail can be
allocated with the existing explicit bounded-region commands, and a tail
mapping can subsequently grow with `plan-grow` and explicit `grow` replay.

The command publishes through the shared write/fsync/rename/directory-fsync
protocol. Repeating an adopted size still verifies the disk and republishes
the same desired bytes, completing the durability protocol even after a prior
directory-flush failure. Its result prints `previous_bytes`, `bytes` and
`changed=0` or `1`. A directory-flush or output failure can return an error
after the complete updated bundle is visible; inspect it and retry. Final
bundle/device symlinks are refused. The directory lock covers reading the saved
state, both physical probes and publication. Live administration remains
serialized.

This command does not initiate controller capacity rescanning: the kernel must
already expose the larger geometry, which may require reattachment or reboot
on the selected backend. GPT backup-header relocation, partition resizing,
filesystem growth and RAID remain separate work. Choosing an allocation
region must account for all partition, filesystem, swap and other data or
metadata extents. Disk identifiers retain the existing uniqueness requirement;
cloned signatures/GUIDs do not establish physical provenance. See
[physical capacity qualification](../tests/storage-volumes/capacity-bundle.md).

## Atomic physical capacity adoption batches

```sh
# Both physical disks already expose these exact capacities.
vinix-volume plan-preview-capacity-batch /root/layout.vset 0 /dev/vda 25165824 1 /dev/vdb 33554432
vinix-volume plan-capacity-batch /root/layout.vset 0 /dev/vda 25165824 1 /dev/vdb 33554432
vinix-volume show-bundle /root/layout.vset
```

`plan-capacity-batch BUNDLE DISK_INDEX DEVICE EXPECTED_BYTES [...]` adopts
observed capacities for 1–64 distinct enrolled disks and atomically publishes
the complete saved bundle once. Indices must be below 64. Expected sizes are
nonzero unsigned decimal bytes, at least the saved capacities and aligned to
each saved logical sector size. Every observed MBR signature or primary GPT
GUID and sector size must match its saved disk, and its observed byte count
must equal the requested size. Ambiguous enrolled identifiers and repeated
physical disk identities are rejected, including aliases of one disk.

The complete request list is checked before any device opens. All named devices
are opened read-only with `CLOEXEC`, `NOFOLLOW` and `NONBLOCK`, and held together
through validation, reporting and publication. After every initial probe, a
private candidate applies the existing adoption rules in request order. A
second pass rechecks every pinned descriptor after the complete candidate is
planned. This catches an early disk changing while later disks are opened or
probed. Any detected identity, geometry, offline, read or later-request failure
preserves the entire original bundle and emits no action rows. Every successfully
opened descriptor is closed on both success and failure.

Only selected saved byte capacities change. Disk identities, sector sizes,
desired rows and modes, unapplied growth, pool bounds and member priority are
preserved. Reports contain request index, disk index, `action=adopt` or
`action=keep`, previous bytes, observed bytes and sector size. Mixed adoption
and equal-capacity requests are supported. A complete equal-capacity retry
still probes all devices, writes, fsyncs, renames and fsyncs the directory,
completing durability after a previous directory-flush failure. Before rename,
publisher failure preserves the original file; after rename the complete new
file may already be visible. Buffered output failure also returns an error.
Inspect saved state or retry the same requests.

`plan-preview-capacity-batch` accepts the same arguments and performs the same
complete planning and two-pass physical verification. It prints every action
only after the entire batch succeeds, without publishing, creating a temporary
or acquiring a writer lock. Publication holds the pinned directory lock from
source read through reporting. Both commands preserve the existing V1/V2
formats. A final bundle or device symlink is rejected; a physical mknod alias
is accepted when it identifies the expected whole disk.

Adoption records geometry already exposed by the backend. It does not rescan
controllers, write disks, resize partitions/filesystems, expand pool eligibility
or apply mappings. Expand saved regions and plan allocations/growth afterward,
then run complete-set live preflight and explicit replay separately. Matching
live generations and held descriptors survive adoption, and boot replay uses
the adopted geometry. Administration must serialize hardware and live changes;
descriptor pinning and sequential rechecks do not lock hardware geometry, and
a preview does not reserve saved state. Cloned signatures/GUIDs retain the
existing provenance limitation. See
[capacity batch qualification](../tests/storage-volumes/capacity-batch.md).

## Persistent allocation pools

```sh
# Save each disk's identity first, then enroll explicitly eligible regions.
vinix-volume save-set /root/layout.vset /dev/vda /dev/vdb
vinix-volume pool-add /root/layout.vset 3 0 8388608 16777216 4096
vinix-volume pool-add /root/layout.vset 3 1 8388608 16777216 4096
vinix-volume pool-space /root/layout.vset 3
vinix-volume pool-allocate /root/layout.vset 3 20 2097152 ro
vinix-volume show-bundle /root/layout.vset
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
# Remove disk 1 from pool 3 while retaining its desired and live mappings.
vinix-volume pool-remove /root/layout.vset 3 1
```

`pool-add BUNDLE POOL_ID DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES`
adds an eligible region on an enrolled disk. Pool IDs are decimal 0–63, local
to this saved bundle; disk indices follow `show-bundle` order. There are at most
64 region records in total and one region per pool/disk pair. Regions on the
same disk must be disjoint, including regions belonging to different pools;
adjacent regions are valid. Region-bearing disks cannot share an MBR/GPT
identifier, even with different saved capacities. Bounds, exclusive ends,
sector alignment and power-of-two placement alignment follow `plan-space`.

`pool-space BUNDLE POOL_ID` reports each member's eligible gap count, bytes and
largest gap, followed by their aggregate. Alignment prefixes and saved desired
mappings, including read-only mappings, are excluded. The total byte count uses
full 128-bit decimal arithmetic, so large multi-disk totals cannot wrap at
64 bits. An enrolled pool with no gaps reports zero capacity; an absent pool
fails. Queries validate the full bundle and preserve its bytes.

`pool-allocate BUNDLE POOL_ID SLOT LENGTH_BYTES [ro]` chooses the first member
in saved membership order with a fitting sector-aligned contiguous gap, then
the lowest eligible physical offset in that member. A length incompatible with
a member's logical sector size skips that member. The slot must be globally
free. Each result remains one ordinary linear mapping on one physical disk;
aggregate free capacity cannot satisfy a request larger than every individual
gap. The selected disk, offset, length and mode are reported after publication.
All other mappings, identities and pool regions survive unchanged.

`pool-remove BUNDLE POOL_ID DISK_INDEX` removes only the eligible region.
Previously allocated desired rows and live views remain, including their modes,
generations and open descriptors. Removing then adding a member places it last
in allocation order. Forgetting a disk requires no desired mappings or pool
membership; following disk indices are adjusted together. Pool membership does
not tag or restrict ordinary `plan-add`, `plan-grow` or explicit-region edits.
`plan-capacity` preserves the regions; extending eligibility into an adopted
tail uses explicit `pool-expand` below. `save-set` captures a fresh live
mapping snapshot and emits a pool-free bundle, replacing prior desired edits
and pool configuration. Use bundle edits to retain that configuration.

Pool regions and mappings share one checksummed atomic publication. Pool-bearing
files use a 64-byte `VINIXVS2` version-2 header: the existing counts and CRC remain
at their version-1 offsets, region count is a little-endian u32 at byte 28, and
bytes 32–63 are zero. Complete version-1 disk plans are followed by up to 64
40-byte records: pool u32, saved disk index u32, start u64, exclusive end u64,
alignment u64 and eight zero reserved bytes. The maximum file is 8768 bytes.
Version 2 requires at least one region. Pool-free output retains the exact
version-1 format; removing the last region restores it. Older utilities reject
the version-2 magic. `show-bundle` displays all region records; ordinary restore
and boot replay validate them alongside mappings and retain the saved file.

These commands operate offline on bounded regular files, reject final symlinks,
and open no devices. Membership edits and allocations use the existing
write/fsync/close/rename/directory-fsync protocol, publishing metadata and desired
rows together. Failure before rename preserves the previous complete file;
directory-fsync or output failure can report an error after the complete new
file is visible. Saved edits use directory locking; live administration remains
serialized.

Choose regions that account for partition tables, filesystem data, swap and
other extents. Reported capacity describes saved desired mappings rather than
filesystem free space or a live reservation. Separate complete-set preflight
detects unlisted live conflicts, and application retains kernel extent
protection. Spanning, striping, RAID, filesystem resizing and encryption remain
separate work. See [pool qualification](../tests/storage-volumes/pool-bundle.md).

## Atomic pool membership batches

```sh
vinix-volume pool-preview-add-batch /root/layout.vset 3 0 6291456 6295552 4096 1 6291456 6303744 4096
vinix-volume pool-add-batch /root/layout.vset 3 0 6291456 6295552 4096 1 6291456 6303744 4096
vinix-volume pool-preview-remove-batch /root/layout.vset 3 0 1
vinix-volume pool-remove-batch /root/layout.vset 3 0 1
```

`pool-add-batch BUNDLE POOL_ID DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES
[...]` adds 1–64 distinct enrolled disks to one pool in a single atomic saved
bundle publication. Numeric arguments are unsigned decimal; pool and disk
indices are below 64. Every window must satisfy the existing sector, alignment,
saved-capacity, disjoint-region and unambiguous-identity rules. Existing members
must match their complete saved start, end and alignment. They report `keep`
and retain their original position; new members report `add` and append in
request order. A reverse-order retry never changes allocation priority.

`pool-remove-batch BUNDLE POOL_ID DISK_INDEX [...]` removes 1–64 distinct enrolled
members together. Remaining regions keep their relative order and disk indices.
An absent member reports `keep`, allowing a complete retry after removal;
an absent pool is also a successful all-keep removal. Missing enrolled disks
and repeated indices fail. Removal preserves every desired mapping, including
rows in removed regions, and cannot detach live views or their descriptors.

Both planners use a private candidate. A later invalid window, conflicting
existing member, overlapping region, ambiguous identifier or full table changes
neither the original bundle nor caller results and emits no partial actions.
All-keep additions work at the full 64-region limit. Additions and removals
preserve identities, capacities, mapping rows/modes and unrelated pools.
Removing the last region returns to the existing version-1 bundle format;
otherwise existing version-2 encoding is retained.

`pool-preview-add-batch` and `pool-preview-remove-batch` use the same complete
planners and report actions in request order without publication, a temporary
file, device probes or a writer lock. Reports begin only after every request
passes. Publication holds the pinned directory lock from source read through
report flushing. Every retry, including all-keep, writes, fsyncs, atomically
renames and fsyncs the directory. Before rename, publication failure preserves
the old file; after rename, the complete new membership may already be visible.
Buffered output failure returns an error even after successful publication.
Inspect saved state or repeat the same batch to complete durability.

Membership uses saved disk geometry and provides offline allocation eligibility.
Physical capacity adoption, mapping allocation/growth and live preflight/replay
remain explicit separate operations. Single-member commands retain their
existing behavior. See [membership batch qualification](../tests/storage-volumes/pool-members-batch.md).

## Explicit pool allocation priority

```sh
vinix-volume pool-preview-order /root/layout.vset 3 1 0
vinix-volume pool-order /root/layout.vset 3 1 0
vinix-volume pool-space /root/layout.vset 3
```

`pool-order BUNDLE POOL_ID DISK_INDEX [...]` sets the first-fit allocation
priority of an existing pool. List every current member exactly once, in the
desired order, with 1–64 unsigned decimal disk indices. Pool and disk indices
must be below 64; absent pools, incomplete lists, duplicates and disks outside
the selected pool fail before publication or action reporting. Priority zero
is considered first for subsequent allocations, then priority one and so on.

The planner permutes only the table positions already occupied by that pool.
Each member's disk, bounds and alignment move together. Unrelated pools retain
their exact positions and relative order; disk identities/capacities, desired
mapping rows/modes, unapplied growth, counts and aggregate free capacity remain
unchanged. Existing placements stay on their current disks. Changing priority
does not relocate data, reserve live space, or change live views or generations.
The new priority is preserved by the existing checksummed V2 format and boot
replay. Membership additions still append and matching membership retries keep
this explicitly configured order.

`pool-preview-order` accepts the same complete list and reports each requested
priority, disk, previous priority and `action=move` or `action=keep`. It uses
the same planner without device probes, a writer lock, temporary file or
publication. Reports begin only after the entire list succeeds. A preview does
not reserve the configuration; administration must serialize related edits.

Publication holds the pinned directory writer lock from source read through
report flushing. Every retry, including an unchanged order, writes, fsyncs,
atomically renames and fsyncs the directory. Failure before rename keeps the
original file; after rename the complete new priority may already be visible.
Buffered output failure also returns an error. Inspect saved state or repeat
the same complete order to confirm durability. Allocation and live preflight/
replay remain separate. See [priority qualification](../tests/storage-volumes/pool-order.md).

## Pool expansion and mapping growth

```sh
# Pool 3 already includes saved disk 0, and slot 20 fits inside that member.
# Adopt the larger observed disk first when extending past its saved capacity.
vinix-volume plan-capacity /root/layout.vset 0 /dev/vda 25165824
vinix-volume pool-expand /root/layout.vset 3 0 25165824
vinix-volume pool-grow /root/layout.vset 3 20 4194304
vinix-volume pool-space /root/layout.vset 3
vinix-volume check-bundle /root/layout.vset grow
vinix-volume restore-bundle /root/layout.vset grow
```

`pool-expand BUNDLE POOL_ID DISK_INDEX END_BYTES` increases an existing member's
exclusive end while retaining its start, alignment and allocation priority.
The new end must be at least the saved end, sector-aligned, within the enrolled
disk's saved capacity and disjoint from every other pool region on that disk.
Adjacent regions are valid. Absent members, shrink, overflow, misalignment,
overlap and an unadopted physical tail fail without publication. Existing desired
mappings, including rows inside the added eligibility, remain unchanged and
occupy their usual space. Expansion works even when the region table is full.
It does not add a member, move data or change live mapping capacity.

`pool-grow BUNDLE POOL_ID SLOT LENGTH_BYTES` increases an existing mapping's
desired length in place. Its old and requested extents must both fit entirely
inside this pool's member region on the mapping's current disk. The length must
be nonzero, at least the saved length and sector-aligned, with no overlap with
any other desired mapping. Start, disk identity, slot, read-only mode, row order,
membership order and all other desired state stay fixed. Placement alignment
governs new allocations; growth keeps the existing start. A manually added
mapping wholly inside the selected member can also grow. A mapping outside or
straddling the region fails even for an unchanged-length request. Free capacity
in other gaps or disks cannot bridge the mapping's contiguous extension, and
growth does not relocate it or consume a different member.

Both commands validate the complete saved set and atomically publish the
existing version-2 format without opening devices. Repeating an equal end or
length still writes, fsyncs, renames and fsyncs the directory, completing the
durability protocol after a prior directory-flush failure. Publication and
buffered output errors return failure; after rename, the complete new desired
file may already be visible. Inspection and retry use that new desired state.
Each command publishes separately, so a later failed growth retains an earlier
successful physical-capacity adoption or region expansion. To publish several
mapping growth requests together, use [growth batches](#atomic-pool-growth-batches).
To expand several members together, use [expansion batches](#atomic-pool-expansion-batches).

Apply growth separately with `check-bundle BUNDLE grow` and `restore-bundle
BUNDLE grow`. Ordinary replay still rejects existing smaller live mappings.
Complete-set preflight catches unlisted live extension conflicts before any
action, and explicit replay retains generations and open descriptors, including
read-only ones. Kernel extent protection and the existing partial-application
rules continue to apply. Boot replay recreates the saved grown geometry and
preserves pool metadata. Regions remain an administrative choice accounting for
partition tables, filesystems, swap and other data; expansion does not reserve
live extents. Saved edits use directory locking; live administration remains
serialized. See
[pool growth qualification](../tests/storage-volumes/pool-growth.md).

## Atomic pool allocation batches

```sh
# Every request has a slot, decimal byte length and explicit rw/ro mode.
vinix-volume pool-preview-batch /root/layout.vset 3 20 4194304 rw 21 1048576 ro
vinix-volume pool-allocate-batch /root/layout.vset 3 20 4194304 rw 21 1048576 ro
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
```

`pool-allocate-batch BUNDLE POOL_ID SLOT LENGTH_BYTES MODE [...]` plans 1–64
requests into one pool and atomically publishes the complete bundle once.
Requests run in argument order, each using saved member order and the lowest
aligned contiguous gap. Earlier placements consume capacity for later requests.
Each mapping stays on one disk. Request ordering can affect feasibility; the
allocator does not reorder or backtrack to find a different packing.

Slots must be distinct and below 64; lengths must be nonzero unsigned decimal
bytes and fit a member's logical sector size. Modes are exactly `rw` or `ro`.
Existing desired mappings and all pool metadata remain unchanged. A later
invalid request, absent pool, occupied incompatible slot, fragmented gap or
capacity failure preserves the entire previous bundle, with no placement
report. The implementation builds a bounded private candidate before publication.

A slot already present in the desired bundle is retained only when its length
and mode match and its complete extent fits this pool's current region on its
current disk. This includes a manually added row; pools do not tag ownership.
Matching rows keep their disk, start and ordering, even if an earlier gap has
become free. An incompatible existing row fails the whole batch; allocation
does not grow, relocate or change its mode. New and matching rows may share a
batch. Retrying a complete batch republishes and flushes even when every row
matches, completing durability after a prior directory-fsync failure.

`pool-preview-batch` accepts the same arguments and uses the same candidate
planner. It prints all placements only after every request succeeds, without
writing the bundle or entering the publisher. Reports include request index,
disk index, slot, `action=allocate` or `action=keep`, offset, length and mode.
Preview failure preserves the file and emits no placement rows. Buffered output
errors return failure for both commands. After a publication succeeds, an output
failure can leave the complete new file visible; inspect it or retry the same
requests. Publisher failures retain the existing before/after-rename guarantees.

Both commands operate only on saved state. They do not inspect live devices,
reserve live extents, or apply mappings. Run complete-set `check-bundle` and
explicit replay separately; an unlisted live conflict on a later disk prevents
every action during preflight. Saved writes use directory locking. A preview
does not pin the saved state against another editor, and live application
requires serialized administration and keeps the existing partial-application
rules. Batch metadata uses the unchanged version-2 format and existing boot
restore. Spanning, RAID, encryption and
filesystem resizing remain open. See
[batch qualification](../tests/storage-volumes/pool-batch.md).

## Atomic multi-pool allocation batches

```sh
vinix-volume pool-preview-set-batch /root/layout.vset \
  8 19 4096 ro 7 20 4096 rw
vinix-volume pool-allocate-set-batch /root/layout.vset \
  8 19 4096 ro 7 20 4096 rw
```

`pool-allocate-set-batch BUNDLE POOL SLOT LENGTH_BYTES MODE [...]` plans 1–64
ordered requests across any existing allocation pools in one saved-state edit.
Each request names its own pool and explicit `rw`/`ro` mode. Multiple requests
may use the same pool; slots must be globally distinct across the whole batch.
Complete argument counts and every token are checked before source I/O.

Each new placement follows its pool's saved member priority and aligned first
fit. Earlier placements consume space for later requests, including interleaved
requests to the same pool. Placement remains one contiguous extent on one disk.
A matching existing slot is kept only when length, mode and full containment in
the requested pool still match; retries retain its original disk and offset
even when earlier capacity becomes free. Pool membership, bounds, priority,
disk identity/geometry and unrelated desired rows remain exact. A later absent
pool, exhausted contiguous capacity or conflicting slot discards the private
complete candidate and all caller action results.

`pool-preview-set-batch` runs the same planning without physical-device probes,
writer locking or publication. Reports start after the entire batch fits and
contain request, pool, resolved disk, slot, `allocate`/`keep` action, offset,
length and read-only mode in request order. Publication holds the pinned
directory writer lock through source loading, atomic replacement, report
flushing and cleanup. All-keep retries still write, file-fsync, rename and
directory-fsync the complete bundle. Before rename failure preserves old bytes;
afterward only the full candidate may be visible with durability unconfirmed.
Buffered stdout failure returns an error. Retry the complete request under
serialized administration to confirm durability.

This configures desired mappings offline. Live creation remains a separate
complete-set preflight/replay, with ordinary kernel protection and conflict
checks. Existing views, descriptors and generations remain intact during
planning. The V1/V2 formats and production boot restore are unchanged. See
[multi-pool allocation qualification](../tests/storage-volumes/multi-pool-batch.md).

## Atomic multi-pool growth batches

```sh
vinix-volume pool-preview-grow-set-batch /root/layout.vset \
  8 19 8192 7 20 8192
vinix-volume pool-grow-set-batch /root/layout.vset \
  8 19 8192 7 20 8192
vinix-volume check-bundle /root/layout.vset grow
vinix-volume restore-bundle /root/layout.vset grow
```

`pool-grow-set-batch BUNDLE POOL SLOT LENGTH_BYTES [...]` plans 1–64
existing mapping lengths across multiple pools in one saved-state transaction.
Each request names its own pool; repeated pools are allowed, while mapping
slots must be globally distinct. Complete argument counts and decimal tokens
are checked before source I/O. Each length must be at least its saved length,
aligned to the owning disk's sector size and fit the selected pool's member
on that same disk. Both old and new extents must lie inside that member and
avoid every other desired row. Free capacity or earlier priority on another
member cannot move or extend this mapping.

Every disk identity/geometry, mapping start/mode/slot/order, unrelated row and
pool bound/order/priority remains exact. Earlier growths occupy their extensions
for later interleaved requests. A later missing pool/slot, wrong member, shrink,
unaligned length, overlap or overflow discards the entire private candidate and
all caller action results. Equal-size requests may accompany real growth.

`pool-preview-grow-set-batch` reports the same complete candidate without
device probes, writer locking or publication. Reports contain request, pool,
resolved disk, slot, `grow`/`keep`, offset, previous/requested lengths and mode
in request order. Publication holds the pinned directory writer lock through
source loading, atomic replacement, report flushing and cleanup. All-keep
retries still write, file-fsync, rename and directory-fsync. Before rename
failure preserves old bytes; afterward only the full candidate may be visible
with durability unconfirmed. Buffered stdout failure returns an error. Retry
the complete request under serialized administration to confirm durability.

Planning remains offline. Explicit complete-set growth preflight/replay applies
the desired lengths separately, preserving the ordinary kernel conflict checks
and existing descriptors/generations. Saved formats and production boot restore
are unchanged. See [multi-pool growth qualification](../tests/storage-volumes/multi-pool-grow-batch.md).

## Atomic pool growth batches

```sh
# Slots 20 and 21 already fit inside pool 3's members on their current disks.
vinix-volume pool-preview-grow-batch /root/layout.vset 3 20 8388608 21 2097152
vinix-volume pool-grow-batch /root/layout.vset 3 20 8388608 21 2097152
vinix-volume check-bundle /root/layout.vset grow
vinix-volume restore-bundle /root/layout.vset grow
```

`pool-grow-batch BUNDLE POOL_ID SLOT LENGTH_BYTES [...]` plans 1–64 existing
mapping lengths in argument order and atomically publishes the complete bundle
once. Slots must be distinct and below 64; lengths must be nonzero unsigned
decimal bytes, at least the saved length and aligned to each mapping's disk
sector size. Both the previous and requested extents must fit inside the selected
pool's member on that disk and avoid every other desired mapping.

The planner retains each mapping's disk, start, slot, read-only mode and row
order, alongside all disk identities, other rows and ordered pool metadata.
It builds a bounded private candidate; an invalid or impossible later request
preserves the entire previous bundle and emits no action rows. Growth cannot
shrink, relocate, allocate an absent slot or use capacity on a different member.
A manually added mapping wholly inside the selected member is eligible.

Equal-size requests can accompany growth requests. Reports include request
index, disk, slot, `action=grow` or `action=keep`, offset, previous length,
requested length and mode. Retrying an unchanged batch still writes, fsyncs,
renames and fsyncs the directory, completing durability after a previous
directory-flush failure. Before rename a publisher failure preserves the old
file; after rename the complete new file may already be visible. Buffered output
failure also returns an error, including after successful publication; inspect
the saved state or retry the same requests.

`pool-preview-grow-batch` accepts the same arguments and uses the same planner.
It reports every action only after the whole batch succeeds, without writing,
creating a temporary or acquiring a writer lock. Publication holds the saved
directory lock from source read through reporting. Both commands open no
devices and use the unchanged version-2 format. A preview does not reserve
the saved state against another editor.

Apply growth separately with complete-set `check-bundle BUNDLE grow` and
explicit `restore-bundle BUNDLE grow`. Ordinary replay rejects smaller live
views. Preflight catches an unlisted live conflict on a later disk before any
action; successful growth retains generations and held descriptors, including
read-only ones. Live administration still requires serialization and retains
the existing partial-application rules. Boot replay restores the saved grown
geometry. Filesystem resizing, spanning, RAID and encryption remain separate
work. See [growth batch qualification](../tests/storage-volumes/pool-grow-batch.md).

## Atomic pool expansion batches

```sh
# Both disks already belong to pool 3. Adopt any larger physical capacity first.
vinix-volume pool-preview-expand-batch /root/layout.vset 3 0 25165824 1 33554432
vinix-volume pool-expand-batch /root/layout.vset 3 0 25165824 1 33554432
vinix-volume pool-space /root/layout.vset 3
```

`pool-expand-batch BUNDLE POOL_ID DISK_INDEX END_BYTES [...]` extends 1–64
existing members of one pool and atomically publishes the complete bundle once.
Disk indices must be distinct, enrolled and below 64. Each exclusive end must
be a nonzero unsigned decimal byte offset, at least its previous end, aligned
to that disk's logical sector size and within its saved capacity. Each resulting
region must remain disjoint from other pool regions on the same disk; adjacency
is valid. Expansion works with a full 64-region table.

The planner builds a bounded private candidate in argument order. Any invalid
or impossible later request preserves the entire original bundle and emits no
action rows. It retains member starts, alignment, order and allocation priority,
every disk identity and all desired mappings, including pending growth and rows
inside newly eligible space. Those rows reduce the pool's available capacity.
Expansion cannot shrink, move a region, add a member or adopt observed physical
capacity. Run `plan-capacity` separately before extending beyond saved geometry.

Reports contain request index, disk index, `action=expand` or `action=keep`,
start, previous end, requested end and alignment. Equal-end requests can accompany
expansions. An unchanged retry still writes, fsyncs, renames and fsyncs the
directory, completing durability after a prior directory-flush failure. A
publisher failure before rename preserves the old file; after rename the
complete new file may already be visible. Buffered output failure returns an
error for both commands, including after successful publication. Inspect saved
state or retry the same requests.

`pool-preview-expand-batch` accepts the same arguments and uses the same planner.
It prints every action only after the whole batch succeeds, without publishing,
creating a temporary or acquiring a writer lock. Publication holds the pinned
directory lock from source read through reporting. Both commands open no
devices and use the unchanged version-2 format. Preview does not reserve the
saved state against another editor.

Expanded eligibility describes saved allocation bounds. Plan allocations or
mapping growth afterward, then use complete-set checking and explicit replay
to apply desired mappings. Expansion does not reserve live extents or grow
filesystems. Boot replay preserves the expanded region with its mappings.
Live administration still requires serialization and retains the existing
partial-application rules. Spanning, RAID and encryption remain separate work.
See [expansion batch qualification](../tests/storage-volumes/pool-expand-batch.md).

## Saved-plan writer locking

Every `save`, `save-set`, `plan-*` editor and `pool-*` editor acquires a
nonblocking exclusive advisory `flock` on the destination's directory before
opening the saved source or taking a live snapshot. This prevents cooperating
writers from reading the same old bundle and overwriting each other's changes.
If another writer holds the lock, the command returns 1 before reading the
source, probing a disk or creating a temporary file. Retry after the other
command exits; the retry reads the latest complete saved state.

The lock is on the directory inode, covering all saved destinations in that
directory. Different directories can be edited independently. Path aliases
that resolve to the same directory share the lock. Locking the saved file
itself would be insufficient because publication replaces that inode. No
lock file is created, and closing the last directory descriptor or terminating
the owner releases the lock automatically, including after `SIGKILL`.

The source is opened relative to the locked directory descriptor. Temporary
creation, atomic replacement and directory fsync use that same descriptor's
inode, retaining the lock through publication and command reporting. If the
directory is renamed or its path replaced during the command, the original
directory receives the update and the replacement directory is untouched.
Final directory/source symlinks are rejected; earlier path components follow
normal path resolution. Directory and source descriptors use `CLOEXEC`.

Read-only inspection, extent/pool queries, batch previews, preflight and replay
do not acquire writer locks. Atomic replacement lets readers see a complete
old or new file, but a preview does not reserve that state for later use.
Existing formats, checksums and publication failure rules are unchanged: a
directory-fsync failure can leave the complete new file visible with durability
unconfirmed, and a retry must complete the publication protocol.

These locks coordinate commands from this utility that target the same
directory inode. Old utilities, external file writers, distinct directory
inodes or separately saved configurations for the same physical extents do not
participate in that exclusion. The filesystem must support directory `flock`;
an unsupported or denied lock returns failure. Live snapshots, mapping changes
and replay still require serialized administration because the kernel has no
global configuration transaction. Spanning, RAID, filesystem resizing and
encryption remain separate work. See
[writer-lock qualification](../tests/storage-volumes/plan-lock.md).

## Status ABI

`tools/volumes/volumecli/volume.h` defines the native little-endian ABI shared by
both supported 64-bit architectures. Private ioctls are:

| Request | Value | Argument |
| --- | --- | --- |
| Create on a parent FD | `0x56560001` | 32-byte request, version 1, slot, offset, length, flags |
| Grow on a volume FD | `0x56560002` | Request with version 1 and new length; other fields zero |
| Remove on a volume FD | `0x56560003` | No payload |
| Query block status | `0x56560004` | 128-byte output, version 1 |

Create flags accept only bit 0 (read-only). Status has 16 `uint64_t` words:
version, bytes, logical sector size, flags, reads, writes, read bytes, write
bytes, flushes, errors, last errno, physical disk identity, physical start, slot,
generation, and reserved zero. Non-volume slot is `UINT64_MAX`. Status flags are
read-only (1), offline (2), flush supported (4), logical view (8), and counters
shared with a parent (16).

Counters describe completed backend operations/bytes and successful flushes.
Backend I/O failures increment errors and save the latest errno, including
invalid requests rejected inside a physical driver. Volume validation,
permissions and bad userspace pointers rejected before dispatch leave the
volume counters unchanged. These are request failure counters, not a hardware
diagnostic classification. A partition reports parent counters with flag 16;
a logical view tracks its own forwarded operations and inherits parent
offline/flush/discard capability. Large syscalls can comprise several backend
operations. AHCI, Apple ANS and the development PCI NVMe driver provide the health queries below.
Vendor-specific wear and temperature interpretation, predictive monitoring and
real-hardware qualification remain future work. Unsupported status backends return
`ENOTTY`. Geometry also supports `BLKGETSIZE64`, `BLKGETSIZE`, `BLKSSZGET`, and
`BLKROGET` without allowing destructive ioctl passthrough.

## Periodic storage monitoring

```sh
# Poll once a minute until interrupted.
vinix-volume monitor /dev/sd0 60
# Collect ten samples for a script, with one second between samples.
vinix-volume monitor /dev/sd0 1 10
```

`monitor` opens one read-only descriptor and combines block status with the
existing ATA/NVMe/ANS health query. The interval is an integer from 1 to 86400
seconds, measured after each completed sample. An optional positive sample count
ends the session; the final sample has no following sleep. Every sample prints
one flushed line, so output is immediately available through pipes.

Lines report the physical disk ID, healthy/warning/media-errors/unavailable,
query-failed or offline state, warning bits, query errno, cumulative backend errors and last
errno, new errors, completed read/write bytes and their deltas. ATA warnings
mean the device's threshold status is exceeded; NVMe/ANS preserve all critical
warning bits, including unknown bits. Partitions and volumes can be monitored
through their status capability while health remains unavailable. Shared parent
counters retain the backend's physical meaning described above.

### NVMe and ANS telemetry

Successful NVMe/ANS samples append `telemetry=nvme scope=controller`, temperature
in kelvin (zero is reported as unavailable), spare/threshold percentages and
percentage used, which can exceed 100. All ten standard counters and their
`_delta` fields retain the full unsigned 128-bit value as 32 hexadecimal digits.
Data units stay in the device's reported units rather than being converted to
bytes; these controller totals are separate from namespace/backend I/O counters.

The first successful NVMe/ANS sample establishes `health_baseline=1` and zero
hardware deltas. Historical media errors do not fail it. New media errors set
`health=media-errors` and make the session return 1 even if no critical-warning
bit is set. Growth of the error-log entry counter is reported but does not by
itself imply a media failure. No extra warning thresholds or prediction are
inferred from temperature, spare or wear fields.

A decrease in any of the ten hardware counters sets `health_counters_reset=1`
and starts a fresh hardware baseline with zero deltas. This baseline is independent
of the driver I/O counters. Failed/unavailable queries print `telemetry=unavailable`
without presenting stale measurements; the next successful NVMe/ANS query covers
the gap since the last successful query. A successful ATA report clears the
NVMe baseline. ATA vendor attributes remain available through `health` without
guessing their units. Partitions and linear volumes also print unavailable
telemetry. No hardware counter baseline is persisted across utility invocations.

### Sampling and exit status

The first sample establishes the backend counter baseline, so historical errors do not
fail a fresh session. A decreasing counter sets `counters_reset=1` and starts a
fresh baseline with zero deltas. Device ID, start offset, mapper slot and
generation must remain stable across the session and each health query; an
identity change stops monitoring. Capacity growth can retain the same identity.
Health and status are separate snapshots; status is refreshed after health so
a query's error/offline transition is reported immediately. An offline snapshot
skips the health command and keeps reporting status.

Bounded sessions retain their most serious observation even after recovery:
exit 1 for query/output/status failures, offline state or newly observed backend
or media errors; otherwise exit 3 for any device health warning, 4 for unavailable health,
or 0 for healthy samples. Invalid arguments return 2 before opening the device.
Invalid reports and identity changes stop immediately with exit 1. Monitoring
uses the ordinary read/ioctl access gates and requires no management privilege.
The report and counter snapshots use fixed caller-stack storage throughout the
loop. Warnings come from device reports; vendor-specific interpretation and
failure prediction remain open. See [monitor qualification](../tests/storage-monitor/README.md).

## ATA SMART health

```sh
vinix-volume health /dev/sd0
```

Whole AHCI ATA disks expose a read-only SMART query through ioctl `0x56560005`.
It requires a readable descriptor and ordinary MAC read/ioctl access; it does
not require volume-management privileges. Partitions, logical views and other
backends return `ENOTTY`; write-only and `O_PATH` descriptors return `EBADF`.
Mounted disks can be queried. This interface accepts no command passthrough.

Each query refreshes IDENTIFY, validates its command-set support/enabled words,
then reads SMART data and RETURN STATUS when SMART is available and enabled.
It never enables SMART, starts self-tests, changes attributes or reads sectors
from the disk's data area. A disabled/unsupported ATA device returns its identity
with unavailable health bits. Invalid IDENTIFY capability words also leave the
corresponding bit unavailable. Short transfers, bad SMART checksums, missing or
invalid status FIS replies and driver failures return an error without copying
a partial report. The port uses its existing permanent DMA buffer under its
normal lock and timeout/quarantine policy; report copying occurs after unlock.

The output ABI is 1088 bytes: eight little-endian `uint64_t` words (version 1,
protocol 1 for ATA, flags, runtime physical disk ID and four reserved zero words),
then the 512-byte IDENTIFY response and 512-byte SMART READ DATA response. Flags
are support available (1), enabled (2), SMART data valid (4), threshold status
valid (8) and threshold exceeded (16). Unavailable SMART data is zeroed. Headers
and payload offsets are checked when compiling the packaged utility on both
architectures. There is no cached health state or per-query kernel allocation.

The command prints model, serial and firmware with control bytes sanitized,
the drive's threshold status, and up to 30 raw attributes with ID, flags,
current/worst values and six raw bytes rendered as hexadecimal. Raw layouts,
units and attribute IDs are vendor specific; the utility does not label them
as temperatures, wear percentages or sector counts. A not-exceeded threshold
is the drive's current assessment, not a prediction or a durability guarantee.
Exit status is 0 for a valid not-exceeded status, 3 for exceeded, 4 when the
ATA threshold status is unavailable, 1 for an error and 2 for invalid usage.
SMART queries do not change completed data-read/write/flush counters; failed
backend queries increment the existing error counter. Bad output pointers and
descriptor-policy failures do not increment hardware errors.

Protocol layout references are the
[SMART data definitions maintained by smartmontools](https://github.com/smartmontools/smartmontools/blob/main/include/smartmon/ata.h),
[AHCI received-FIS and transfer-count specification](https://www.intel.com/content/dam/www/public/us/en/documents/technical-specifications/serial-ata-ahci-spec-rev1-3-1.pdf)
and [QEMU's ATA SMART implementation](https://github.com/qemu/qemu/blob/master/hw/ide/core.c).
See [native host and guest qualification](../tests/storage-health/README.md).

## NVMe SMART/Health

```sh
vinix-volume health /dev/nvme0n0
```

Whole native PCI NVMe namespaces support the same read-only health ioctl and
descriptor/MAC policy. The driver retains its existing development-build
activation policy (`PROD=false`); production probing and physical-controller
qualification remain separate work. VirtIO, partitions and linear
views remain unsupported. The query accepts no admin command passthrough.

Protocol 2 uses the existing 1088-byte version-one ABI: its identity payload is
the first 512 bytes of a fresh 4096-byte Identify Controller response, and its
data payload is the complete 512-byte SMART/Health Information log (LID 2).
The log is controller-wide (`NSID=0xffffffff`), including when opened through a
particular namespace; the runtime disk ID still identifies the opened namespace.
Multiple namespaces on the same controller therefore report the same health
scope. The query sets RAE to retain pending asynchronous notifications. It
changes no features, warning thresholds, self-tests or namespace data.

Flags 1/2/4/8 indicate that the mandatory log is supported, usable, returned
and has valid warning status. Flag 16 means the critical-warning byte is nonzero,
including warning bits unknown to this utility. A command failure returns an
error without publishing a partial report. NVMe has no ATA data checksum or
completion transfer-length field; successful command completion is the trust
boundary for the device's returned payload. The identity and log are two
successive commands, rather than an atomic controller snapshot.

Each query uses one zeroed, private, page-aligned DMA page and the existing
controller lock, completion checks and timeout policy. The page is freed after
both completed commands or an ordinary completion error. After a timeout it is
freed only if controller disable confirms DMA has stopped; otherwise that one
submitted page remains quarantined and later queries submit nothing. There is
no per-query kernel heap allocation. Health queries leave completed block I/O
counters unchanged; backend failures increment the namespace's error metric.

The utility prints sanitized model, serial and firmware, the raw critical-warning
byte, temperature in kelvin (zero means unavailable), available spare and its
threshold as percentages, and the device's percentage-used estimate. That
estimate may exceed 100. Ten standard counters are printed as full 128-bit
hexadecimal values, without truncation or conversion of data units to bytes.
Exit status is 0 with no critical warnings, 3 when any are active, 1 for a query
or report error and 2 for invalid usage. No warnings is a current device report,
not a prediction or a durability guarantee.

Protocol references are the
[NVM Express Base Specification](https://nvmexpress.org/wp-content/uploads/NVM-Express-Base-Specification-2.0e-2024.07.29-Ratified.pdf),
[libnvme SMART/Health and identity definitions](https://github.com/linux-nvme/libnvme/blob/master/src/nvme/types.h)
and [QEMU's NVMe controller implementation](https://github.com/qemu/qemu/blob/master/hw/nvme/ctrl.c).
See [native health qualification](../tests/storage-health/README.md).

## Apple ANS SMART/Health

```sh
vinix-volume health /dev/ans0n1
```

Whole namespaces published by the opt-in base-M1 ANS2 driver support protocol 2
and the same controller-wide identity, SMART log, warning flags and utility
output described above. Namespace names use the actual namespace ID. ANS GPT
partitions and logical views return `ENOTTY`. The query requires readable access
and passes through the same descriptor/MAC checks and output-only usercopy.

The ANS operation lock covers both fresh admin commands and both payload copies,
serializing them with namespace I/O and shutdown. Identify uses 4096 bytes of the
existing permanently pinned DMA bounce buffer; Get Log Page uses 512 bytes.
Each transfer is cleared and synchronized before submission, then synchronized
for CPU access after a validated completion. The lowest submission layer permits
only SMART/Health LID 2, controller-wide NSID, RAE=1, exactly 128 dwords, zero
offset/extensions and the driver's fixed bounce address. No passthrough or
write-policy change is exposed.

Ordinary command completion errors return `EIO` without publishing a partial
report and allow a later query to retry. Timeouts, firmware failures and invalid
completions retain the existing failed-controller policy: DMA stays pinned and
later health calls neither clear it nor submit. Stopping/stopped controllers
also reject calls before touching DMA. Reports, command bytes and interface
dispatch use the caller's stack; queries allocate no heap or physical pages and
do not charge completed disk transfers. Failed backend health requests increment
the namespace's block error counter once; successful queries leave I/O counters
unchanged.

The driver still requires explicit ANS boot opt-in and its existing clean
handoff/platform checks. Host transport faults and an isolated ARM kernel model
qualify command encoding, cache ownership, dispatch and 200-query retention;
they do not qualify health-log accuracy or firmware support on a physical M1.
See [ANS boot and hardware acceptance](apple-ans-rw-root.md) and
[native health qualification](../tests/storage-health/README.md). The ANS NVMMU
layout follows the [Linux Apple NVMe driver](https://github.com/torvalds/linux/blob/master/drivers/nvme/host/apple.c).

## Apple ANS block status

```sh
vinix-volume status /dev/ans0n1
vinix-volume status /dev/ans0n1p1
```

Published ANS namespaces and GPT partitions expose the version-one, 128-byte
block status ABI. Capacity and start offset describe the opened view. `disk_id`
identifies its physical namespace; partitions set flag 16 and share that
namespace's counters. Namespace IDs remain distinct, including after shutdown.
The whole namespace stays read-only. Only the boot-selected writable Linux-data
partition clears the read-only flag while the controller is ready and its write
policy remains valid. Failed or stopping/stopped controllers report offline and
read-only; status remains readable without submitting a command or touching DMA.

ANS counters measure successfully completed physical commands and bytes,
including native root/data filesystem traffic. A rounded read counts all sectors
transferred; a partial write counts its boundary reads, written sectors and
implicit flush. A resource sync flushes every namespace, charging each successful
flush to that namespace. Completed prefixes remain counted when a later command
fails. These are physical command counts, rather than counts of userspace calls.
Failed block read/write/sync and supported health requests increment `errors`
once on the requesting namespace and retain their errno in `last_error`.
Validation failures count; zero-byte/EOF success and successful metadata queries
do not. Native filesystem internal failures are not additional block requests.

Snapshots and updates share the ANS operation lock. Eight fixed counter records
require no allocation on repeated paths and preserve the exported transport
layout used by existing controller fixtures. Status metadata does not enable ANS
linear volumes, raw writes, discard or controller reconstruction. ANS volume
management still needs qualification of native filesystem extent protection.

The [V transport tests and ARM kernel fixture](../tests/storage-health/README.md)
cover shared geometry/counters, read-modify-write, completed prefixes, failures,
offline state and 200 allocation-flat I/O/error cycles. QEMU exercises the
software model; physical base-M1 controller and firmware qualification remains
required as described in [ANS acceptance](apple-ans-rw-root.md).

## TRIM/discard

`vinix-volume discard DEVICE OFFSET_BYTES LENGTH_BYTES` submits Linux
`BLKDISCARD` (`0x1277`), whose argument is two `uint64_t` byte values: offset
and length. Status flag 32 advertises backend discard support. Length must be
nonzero; both values must align to the logical sector size, and the full range
must fit inside the opened device. No rounding expands the requested range.

Discard requires a writable descriptor, a trusted MAC domain, `CAP_SYS_ADMIN`
and the initial user namespace. It rejects read-only/offline devices and
unsupported backends. Aliases retain the backing device's capability and
physical identity. Partitions and managed volumes translate only their own
bounds. Mounted/protected filesystems, pending mounts, swap, concurrent raw
writes and geometry changes exclude discard at every securelevel. Securelevel
two also prohibits discard through descriptors opened earlier.

The ioctl reserves the opened device's whole physical extent across batches of
whole logical sectors, up to 64 KiB or one larger sector. Locks are released
between batches; scheduling, signals, exec
cancellation and raised securelevels are checked there. A failure or
interruption may leave an already completed prefix discarded. Errors propagate
to the caller and backend error counters; successful discard does not inflate
read/write byte counters. Discard is a deallocation hint, not secure erasure,
and makes no promise about the contents returned by later reads. It does not
flush data or trigger filesystem free-space trimming; use it only for ranges
whose data can be discarded.

AHCI uses non-queued ATA DSM/TRIM only when IDENTIFY advertises it. NVMe uses
Dataset Management with Deallocate when ONCS bit 2 advertises it. VirtIO
negotiates DISCARD and honors the reported maximum sectors and segment count.
All commands use exact ranges; protocol limits split requests rather than
truncate them. AHCI/VirtIO reuse their permanent DMA buffers. NVMe uses one
fallible range page and frees it after completion or proven controller disable,
retaining it when a failed reset leaves DMA ownership uncertain. NVMe remains
disabled by the existing production-kernel initialization policy.

Protocol references: [VirtIO 1.2 block requests](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html),
[NVMe NVM command set](https://nvmexpress.org/wp-content/uploads/NVM-Express-NVM-Command-Set-Specification-1.0e-2024.07.29-Ratified.pdf),
and Linux's [ATA capability definitions](https://github.com/torvalds/linux/blob/master/include/linux/ata.h)
and [DSM command construction](https://github.com/torvalds/linux/blob/master/drivers/ata/libata-scsi.c).

## Qualification and remaining roadmap work

`tests/storage-volumes` checks the production code on the host and ordinary
kernels on disposable ARM VirtIO and AMD64 AHCI disks. It covers bounds,
read-only policy, aliases, stale FDs/generation reuse, namespace collisions,
mount restrictions, invalid userspace pointers, CLI execution, concurrent
open/remove, discard through aliases/partitions, physical guard sectors,
active-swap exclusion and retained heap after distinct-extent management
cycles. `tests/block-storage` injects
controller completion/flush errors; `tests/mounted-disk-policy` checks
mount/write/swap interleavings.

The native V saved-plan controller also runs host ASan/UBSan checks and two
ordinary-kernel boots on each architecture. Plans stay on a disposable ext2
system disk across an abrupt QEMU stop; the second boot restores mappings and
checks persisted data and read-only policy without a host-supplied plan. The
first boot exercises init recovery from an invalid configured plan, rejects
corrupt files, untrusted configuration, a different disk, duplicated identity
and conflicting slots, checks physical aliases and repeated/partial restore,
then qualifies a two-disk set. Duplicate disks/slots, a missing later disk,
untrusted directory entries, later slot conflicts and unlisted overlaps leave
earlier disks untouched. Directory-only and legacy-plus-directory replay are
both checked. The fixture measures retained heap across 200 save/boot-restore
cycles after warming the same paths. Before the second boot the physical devices
are reordered. Production init restores both configured disks before the test
application starts. Host init policy checks cover missing utility, synchronous
reaping, nonzero utility exits, fork failure and failed exec under ASan/UBSan.
Host plan-set checks also exercise 64 plans, all global slots, deterministic
ordering, ignored filenames and enumeration limits.

NVMe discard and health are qualified with production command/completion code
and mocked MMIO on the host, including 200 successful operations and failed-reset
DMA ownership. NVMe now maps high 64-bit BAR registers and the required doorbells
uncached instead of assuming they are in the initial direct map. Its polled
completion queues leave interrupts disabled. The development-only activation
policy, physical-controller and power-loss qualification remain open. The
development guest also checks healthy/warning NVMe responses and retained heap
across 200 plan cycles, including 200 successful and 200 bad-pointer queries
per namespace after warmup. This measurement exposed heap-promoted read command
temporaries; read and flush commands now stay on the caller's stack while their
DMA payloads retain the existing completion/reset ownership rules.

The encompassing roadmap item stays open: spanning volumes/RAID, full-disk
encryption and recovery, online filesystem resize,
filesystem-aware trimming and predictive health monitoring are not
implemented by this increment. The anonymous pager's encrypted swap remains a
separate feature.

## Data checksum manifests

`hash-bundle BUNDLE MANIFEST DISK_INDEX DEVICE [...]` reads every desired
mapping extent in a saved bundle and atomically publishes a separate SHA-256
reference. The bundle retains its exact bytes, mappings and pool priority.
Provide all saved disk indices exactly once (1–64 participants), paired with
their current whole physical device paths. Participant order may differ from
saved disk order. Each pinned read-only device must match the saved MBR/GPT
identity, logical sector size and exact physical capacity; logical views,
partitions, offline devices, repeated physical IDs and ambiguous saved
identities fail. All devices are rechecked before and after streaming reads.

```sh
vinix-volume hash-bundle /etc/vinix/volumes.vset /root/data.vhash 0 /dev/vda 1 /dev/vdb
vinix-volume verify-data /root/data.vhash 1 /dev/vda 0 /dev/vdb
vinix-volume show-data /root/data.vhash
```

The verification example assumes the two physical devices have been reordered.
`verify-data MANIFEST DISK_INDEX DEVICE [...]` hashes the embedded desired
extents and compares every digest with the saved reference. Complete success
prints `operation=verified-data disks=N mappings=N algorithm=sha256`, followed
by canonical disk/row records with slot, offset, byte length, read-only flag
and lowercase `sha256=`. A read failure, identity/geometry change or mismatch
returns failure before any successful record is printed. `show-data MANIFEST`
prints the saved reference offline (`operation=manifest-data`), with no device
access. Successful creation reports `operation=recorded-data`.

Keep writes to the data quiescent for the whole operation. Descriptor pinning
and identity rechecks do not provide a coherent snapshot of concurrent writes.
Retain a trusted manifest separately: checksums detect accidental corruption
against that reference; they provide no authentication or repair. Geometry
adoption, desired extent changes and legitimate writes require an intentionally
new reference. A verification failure preserves the reference. Inspection and
verification are available while saved-plan writer locks are held.

Creation holds the manifest directory's nonblocking writer lock through
file-fsync/close/atomic-rename/directory-fsync and final report flush. Equal
references still execute both flushes. Before rename, failures preserve the
old manifest; after rename, directory-fsync or report failure can leave the
complete new manifest visible and must be retried. Source and destination
cannot name the same directory entry, including lexical path aliases. Final
symlinks and unbounded/nonregular input files are rejected. Manifest destinations
must be absent or regular; device nodes, directories and FIFOs are rejected
before participants open and rechecked before publication. Hashing uses a
single 64-KiB stack workspace for all rows, accepts interrupted and positive
sector-aligned short reads, and rejects zero/failed/oversized/unaligned
transfers. Extents must fit signed file offsets and SHA-256's byte limit.

The little-endian `VINIXDH1` format is separate from existing V1/V2 bundles.
Its 64-byte header stores magic at 0, u32 version 1 at 8, header bytes 64 at
12, total file bytes at 16, embedded bundle bytes at 20, digest record count
at 24 and CRC32 at 28 (computed with that field zero); bytes 32–63 are zero.
The exact complete encoded bundle follows, then up to 64 ordered 40-byte
records: saved disk index u32, global slot u32 and 32 digest bytes. Records
must match every desired row in canonical disk/row order. The maximum file
is 11392 bytes. Decoding validates the entire manifest privately before
changing caller state; embedded identities, bounds, pools and global slots
retain the ordinary bundle validation. See
[qualification](../tests/storage-volumes/data-checksums.md).

## Offline ciphertext monitor transcript verification

`verify-volume-monitor REFERENCE TRANSCRIPT` checks a saved `VINIXCM1` session
against its entire trusted `VINIXCH1` ciphertext reference. Both `source=volume`
and `source=recovery` sessions are supported without credentials or device access.

```sh
vinix-volume verify-volume-monitor /root/volume.vchash /root/monitor.txt
```

Every sample must contain exactly the canonical monitor prefix and the complete
two-line `VINIXCS1` ASCII scrub view. Samples start at 1 and advance consecutively;
the source label must stay unchanged. Changed-sample counts and the session latch
must agree with every expected/actual digest, including restoration. All native
identity/capacity/sector and slot/offset/length/read-only fields, findings and
reference fingerprints must match the supplied CH1. A complete frame is
reconstructed from the reference and recorded observation and compared byte for
byte, so noncanonical numbers, missing/reordered/extra fields, unrelated geometry
or digests, changed source labels and later diagnostics invalidate the whole file.

The CH1 must satisfy the established private regular-file ownership, permission,
exact-length and post-EOF checks. The public ASCII transcript is an ordinary
readable regular file, including 0644, with a size from 1 byte through 64 MiB.
Both original file/parent descriptor pairs remain pinned through private parsing,
formatting, printing and final stdout checks. Buffered reads retry interruptions,
hash every original transcript byte, require true EOF and recheck its regular
type and original size after EOF. Partial frames, NUL and appended data refuse.
No summary is emitted before all frames validate; an output failure can leave a
partial write. The command takes no directory writer lock, publishes no file,
imports no mapping and performs no KDF, authentication or physical I/O.

The bounded two-line summary starts with:

```text
format=VINIXCM1 operation=verified-ciphertext-monitor source=volume|recovery mappings=1 samples=N changed_samples=C session_changed=0|1 final_changed=0|1 stable=S new_changes=A restored=R changed_again=G algorithm=sha256 reference_sha256=HEX transcript_sha256=HEX
```

Its mapping line includes complete native geometry, saved mode, final match or
changed finding, and expected/final digests. Adjacent equal actual digests count
as `stable`, including unchanged corruption. Expected-to-different observations
count as `new_changes`, different-to-expected as `restored`, and two distinct
unexpected digests as `changed_again`. The first sample has no transition.
The fixed 2048-byte summary covers full-width geometry and counters. Persistent
reader/history workspaces precede the loop; transient sample storage retains
no borrowed pointers after validation.

A valid all-clean history returns 0; any recorded changed sample returns 2 even
if the last sample is restored. Operational input, binding, encoding and stdout
failures return 1 and take precedence over findings; syntax errors return 2.
An exact complete-frame prefix is valid shorter evidence: the format records
neither planned count nor originating command completion. Compare the returned
sample count with an independently known count when needed. The source label
records historical metadata; offline verification does not authenticate that
label or either input, prove present ciphertext/plaintext integrity, provide a
concurrent snapshot or repair data. See
[qualification](../tests/storage-volumes/cipher-monitor-verify.md).

## Offline data monitor transcript verification

`verify-data-monitor MANIFEST TRANSCRIPT` validates a saved plain-data monitor
session against its complete trusted `VINIXDH1` checksum reference. It reads
ordinary files and summarizes every canonical `VINIXDM1`/`VINIXSR1` frame.

```sh
vinix-volume verify-data-monitor /root/data.vhash /root/monitor.txt
```

The transcript must be a nonempty regular file of at most 64 MiB. Samples start
at 1 and advance consecutively using canonical decimal numbers. Every complete
scrub must bind to the entire supplied reference, its native geometry, ordered
rows and expected digests. Each prefix's changed-sample counter must equal the
number of preceding and current scans with any changed mapping; its session
flag must stay set after the first changed scan, including after restoration.
An unrelated reference, inconsistent later counter, diagnostic line, malformed
frame or partial tail invalidates the whole input. The buffered reader hashes
every original transcript byte, requires true EOF and rechecks the transcript
descriptor's regular type and exact initial length after EOF.

Both inputs and their parent directories stay pinned through complete private
validation, formatting, printing and final stdout checks. Ordinary reference
rules allow readable 0644 files and separate hard-linked aliases, and reject
symlinks, directories and FIFOs. No writer lock, authentication, device access
or publication occurs. No successful summary is printed until the entire
transcript validates; output failures can leave a partial write and return 1.

The bounded complete summary begins with:

```text
format=VINIXDM1 operation=verified-data-monitor disks=D mappings=M samples=N changed_samples=C session_changed=0|1 final_changed=F algorithm=sha256 reference_sha256=HEX transcript_sha256=HEX
```

Native disk geometry lines precede each disk's mapping rows. Every row includes
its full geometry and mode, count of changed observations, final match/changed
finding, expected/final digests and counts for four adjacent-sample transitions:

| Field | Adjacent observations |
| --- | --- |
| `stable` | Identical actual digests, including unchanged corruption |
| `new_changes` | Expected digest followed by a different digest |
| `restored` | Different digest followed by the expected digest |
| `changed_again` | Two different digests, both differing from expected |

The first observation has no transition. Row changed counts refer to individual
mappings; the header count refers to scans containing any changed row. A fixed
49152-byte summary workspace covers all 64 disks and mappings with full-width
counters. Parsed history becomes visible only after complete input validation.

A valid all-clean history returns 0. Any recorded changed scan returns 2, even
if the final sample is fully restored. Operational input, binding, encoding or
stdout failures return 1 and take precedence over findings; syntax errors
return 2. An exact complete-frame prefix is a valid shorter transcript: the
format records neither the requested count nor completion of the originating
command. Compare the returned sample count with an independently known count
when needed. This checks historical evidence against a trusted reference; it
does not authenticate the transcript, establish current disk integrity or
supply a concurrent snapshot or repair. See
[qualification](../tests/storage-volumes/data-monitor-verify.md).

## Periodic authenticated ciphertext monitoring

`monitor-volume-auto CONFIG PASSPHRASE_FILE REFERENCE INTERVAL_SECONDS COUNT`
and `monitor-recovery-volume-auto BACKUP RECOVERY_KEYFILE REFERENCE
INTERVAL_SECONDS COUNT` repeatedly hash one encrypted extent's physical
ciphertext against a trusted `VINIXCH1` reference. They use the existing
authenticated configuration/recovery formats and automatic read-only discovery.

```sh
vinix-volume monitor-volume-auto /root/volume.sealed /root/volume.pass /root/volume.vchash 60 10
vinix-volume monitor-recovery-volume-auto /root/volume.vrecover /root/recovery.key /root/volume.vchash 60 0
```

A session authenticates exactly once. Passphrase configuration uses one bounded
scrypt derivation; recovery-key authentication uses no KDF. The passphrase,
wrapping/recovery key and decrypted volume key are erased before opening the
reference or discovering a device. Configuration and credential input files
close after their initial private reads. The reference must match every
authenticated native identity/capacity/sector and slot/offset/length/read-only
field before discovery. Malformed, unrelated or nonprivate inputs fail without
opening a disk. The existing owned private regular-file rules apply to all
inputs, including post-EOF ownership, permission and size checks.

The original reference file and parent directory stay open with the original
selected physical disk descriptor through all samples, sleeps and final stdout
checks. Replacing any input pathname does not reload credentials, change the
session reference or trigger rediscovery. Same-physical aliases retain the
existing discovery rules; missing or ambiguous physical matches fail. The
selected physical ID and physical read-only bit remain exact and independent
of the authenticated mapping's mode. Every sample rechecks the pin before and
after its complete native-sector scan and again immediately before output.

Intervals are decimal seconds from 0 through 86400, measured after each complete
sample. Interrupted sleeps resume the remainder. A positive unsigned 64-bit
count completes after that many samples, including consecutive scans with
interval 0. Count 0 runs continuously and requires a positive interval. Sample
numbers start at 1; sample and changed-sample counters saturate at the unsigned
64-bit maximum. Invalid CLI syntax returns usage status 2.

Each privately encoded sample contains this newline-terminated prefix, then
the ordinary complete two-line ASCII `VINIXCS1 operation=scrubbed-ciphertext`
view with native geometry, mapping mode, original reference fingerprint and
full expected/observed ciphertext digests:

```text
format=VINIXCM1 operation=monitored-ciphertext source=volume|recovery sample=N changed_samples=C session_changed=0|1
```

`source` records the initial authentication domain. `changed_samples` counts
complete changed scans and `session_changed` stays 1 after the first finding,
even when later data is restored. A fixed 2048-byte buffer holds each complete
three-line sample. The transcript is a public ASCII view, not a binary CS1
input for offline scrub commands. No successful sample is printed for an
incomplete scan or failed final pin check. A stdout failure can leave a partial
write and returns 1; earlier completed samples remain visible.

Finite sessions return 0 if every sample is clean, or 2 if any complete sample
changed. Later input, device, encoding or output failures return 1 and take
precedence over findings. Continuous sessions continue after findings until an
operational failure or external termination. Workspaces and owners are created
once outside the loop; no per-sample authentication or secret lifetime remains.

Monitoring takes no directory writer lock, publishes no file, imports no live
mapping and writes no physical data. Keep encrypted writes quiescent when
consistent observations are required and retain a trusted reference. Comparing
ciphertext hashes supplies neither plaintext authentication, repair nor a
concurrent snapshot. See [qualification](../tests/storage-volumes/cipher-monitor.md).

## Periodic pinned data checksum monitoring

`monitor-data-auto MANIFEST INTERVAL_SECONDS COUNT` repeatedly checks every
desired extent in a trusted plain-data `VINIXDH1` reference. The complete
bounded reference is validated once before identity-based read-only discovery.
The source file, parent directory and original selected physical descriptors
remain open through all samples, sleeps and final stdout checks. Replacing the
reference pathname does not change the session's reference or trigger discovery.

```sh
vinix-volume monitor-data-auto /root/data.vhash 60 10
vinix-volume monitor-data-auto /root/data.vhash 60 0
```

The interval is a decimal integer from 0 through 86400 seconds, measured after
each completed sample. Interrupted sleeps resume their remaining duration.
`COUNT` is a decimal unsigned 64-bit integer. A positive count completes after
that many samples; a zero interval permits consecutive finite scans. Count 0
runs continuously and requires a positive interval. Sample numbers start at 1.
Both sample and changed-sample counters saturate at the unsigned 64-bit maximum
in a continuous session. Invalid CLI syntax returns usage status 2.

Each sample reads every saved row, including rows after a digest mismatch.
Every selected physical identity, read-only bit, native identity/capacity/sector
is rechecked before and after streaming and again immediately before output.
Distinct physical matches, missing participants and changed pins fail using the
existing automatic-discovery rules. Mapping read-only flags remain exact and
independent of physical read-only status. The monitor uses the ordinary plain
reference-file policy and takes no directory writer lock.

A complete privately constructed sample starts with this newline-terminated
prefix, followed immediately by the canonical full `VINIXSR1` scrub header and
every row in saved disk/row order:

```text
format=VINIXDM1 operation=monitored-data sample=N changed_samples=C session_changed=0|1
```

`changed_samples` counts completed scans containing any changed row;
`session_changed` stays 1 once any scan has changed. Each scrub retains the
full original reference fingerprint, geometry, mapping modes and both digests.
The fixed 33024-byte sample buffer covers all 64 rows. The combined stream is
a monitor transcript; extract one complete `VINIXSR1` sample for an offline
scrub query. No successful sample is printed for an incomplete read or failed
final pin check. A stdout failure can leave a partial write and returns 1.

A finite session returns 0 if all scans were clean, or 2 if any completed scan
changed, including when later samples show restored data. Any later input,
device, encoding or stdout failure returns 1, taking precedence over findings.
Earlier completed samples remain visible. Continuous sessions run until an
operational failure or external termination; they do not return after findings.

The command creates no file, imports no mapping and writes no physical data.
Use a trusted reference and quiescent writes when consistent observations are
required. Pinning and repeated SHA-256 scans provide neither authentication,
a concurrent snapshot nor repair. See
[monitor qualification](../tests/storage-volumes/data-monitor.md).

## Binding ciphertext scrubs to checksum references

`verify-volume-scrub-reference REFERENCE REPORT` checks a saved `VINIXCS1`
ciphertext scrub against a supplied `VINIXCH1` checksum reference. It requires
no passphrase, recovery key, device discovery or disk access.

```sh
vinix-volume verify-volume-scrub-reference /root/volume.vchash /root/changed-volume.vcscrub
```

Both complete binary records are strictly validated before any finding is
printed. The entire 128-byte supplied reference must match the reference
embedded in the scrub, including native identity/capacity/sector, slot,
offset/length/readonly mode, expected digest, reserved fields and checksum.
The scrub's reference fingerprint, observed digest/result consistency and
complete record checksum must also be valid. A structurally valid unrelated
reference takes precedence over a recorded changed finding.

The bounded complete output starts with
`format=VINIXCS1 operation=verified-ciphertext-scrub-reference`, matched/changed
counts and SHA-256 fingerprints of both original binary inputs. Its second
line includes every saved disk/mapping field, `match` or `changed`, and full
expected/actual digests. The output is a historical view, not a binary CS1
input. No report is published or overwritten.

Each input must be a private regular file owned by the effective user, with
no group/other access and its exact format length. Reads retry interruptions
and short transfers, reject trailing data and recheck descriptor ownership,
permissions and length after EOF. Symlinks, directories, FIFOs and ordinary
0644 files are refused. Both files and their parent directory descriptors
remain pinned through formatting, printing and final stdout checks. Separate
hard-linked aliases work; a same-file reference/report pair has incompatible
lengths. The command takes no writer lock and works under directory writer
contention. It opens no live mapping and performs no KDF or device I/O.

Exit status is 0 for a valid bound clean finding, 2 for a valid bound changed
finding, and 1 on operational refusal. Syntax errors return 2. Input, binding,
encoding and stdout failures take precedence over changed findings. Refusals
emit no binding header or row; established diagnostics may use stdout.

This checks historical evidence against a trusted reference. CRC and SHA-256
do not authenticate the inputs or establish present ciphertext integrity, and
the operation supplies no repair or concurrent snapshot. Current authenticated
checks remain available through `verify-volume-auto` and
`scrub-volume-auto`. See [qualification](../tests/storage-volumes/cipher-scrub-reference.md).

## Binding data scrub reports to checksum references

`verify-data-scrub-reference MANIFEST REPORT` checks a saved `VINIXSR1`
plain-data scrub against its complete `VINIXDH1` checksum reference. It reads
ordinary files without opening disks, discovering devices or changing mappings.

```sh
vinix-volume verify-data-scrub-reference /root/data.vhash /root/scrub.txt
```

Both inputs receive complete strict validation before any findings are printed.
The report's reference SHA-256 must equal the hash of the entire canonical DH1
file, including disk order, identities, native capacities and sectors, mapping
metadata, pool order and allocation windows, and expected digests. Disk and row
counts, each ordered disk index/slot/extent/mode and every expected digest must
also match explicitly. A copied fingerprint alone cannot establish binding.
Any malformed input or incompatible reference takes precedence over recorded
data changes, including a mismatch in the last row.

The complete bounded output begins with
`format=VINIXSR1 operation=verified-data-scrub-reference`, counts all matched
and changed observations, and includes `reference_sha256` and `report_sha256`
for the entire reference and original scrub report. Each saved disk, including
an empty disk, prints its native capacity, sector and identity, followed by its
canonical rows with expected and actual digests and `match`/`changed` findings.
Pool metadata is bound by the reference fingerprint. This output is a view;
the input scrub grammar remains `operation=scrubbed-data`.

Both file descriptors and parent directory descriptors stay pinned until
printing and final stdout flush/error checks finish. Inputs may be ordinary
0644 files or hard-linked aliases. Symlinks, directories, FIFOs, oversized,
truncated and trailing input are refused. The operation takes no writer lock
and remains usable while a writer holds the directory lock. It performs no
KDF, device I/O or report publication.

Exit status is 0 when every historical observation matches, 2 when a valid
bound report records any changes, and 1 on an operational failure. Syntax
errors return 2. Encoding, printing and final stdout failures return 1 even
when the report records changes. Invalid inputs emit no binding header or rows;
existing diagnostics may use stdout.

This verifies a historical report against a trusted reference. SHA-256 does
not authenticate either file, and the observations do not establish current
disk integrity, provide a concurrent snapshot or repair data. Live data checks
remain available through `verify-data-auto` and `scrub-data-auto`. See
[the qualification](../tests/storage-volumes/scrub-reference.md).

## Comparing multi-disk data scrub history

`compare-data-scrubs BEFORE_REPORT AFTER_REPORT` compares complete historical
plain-data `VINIXSR1` reports from `scrub-data` or `scrub-data-auto`. Both reports
must have the same reference fingerprint, saved disk count, complete ordered
mapping rows and expected digests. Every recorded disk index, global slot,
offset, length and read-only flag must agree. A valid later incompatible row
causes an operational error even when earlier observed digests differ.

```sh
vinix-volume compare-data-scrubs /root/before-scrub.txt /root/after-scrub.txt
```

Both complete bounded ordinary files receive the strict SR1 syntax and semantic
validation used by inspection before any comparison report is printed. The
reader rejects final symlinks, nonregular/unbounded files, incomplete reads,
trailing bytes and inconsistent counts/results. Two independent read-only,
no-follow, nonblocking input owners retain their file and parent descriptors
through complete report construction and stdout finalization. Same-path and
hard-linked inputs work, including during saved-state writer contention.
Comparison takes no writer lock, reads no devices or credentials, publishes no
file and preserves existing inputs and live mappings.

Every mapping receives one result, with counts covering the complete report:

| Result | Recorded observed digests |
| --- | --- |
| `stable` | Equal before and after, including an unchanged mismatch. |
| `new-change` | Before matches the expected digest; after differs. |
| `restored` | Before differs from the expected digest; after matches. |
| `changed-again` | Both differ from the expected digest and from each other. |

The complete ASCII output fits a fixed 32768-byte stack workspace. Its header
contains `format=VINIXSR1 operation=compared-data-scrubs`, `disks`, `mappings`,
`stable`, `changed`, `new_changes`, `restored`, `changed_again`, `algorithm=sha256`,
`reference_sha256`, `before_report_sha256` and `after_report_sha256`. The two
report fingerprints cover every canonical input byte, including header counts,
row order, metadata and both recorded digests. Each row contains `disk`, `slot`,
`offset`, `bytes`, `readonly`, `before=match|changed`, `after=match|changed`, the
transition `result`, `expected_sha256`, `before_sha256` and `after_sha256`.
All digests are 64 lowercase hexadecimal characters. Zero-mapping reports still
include the saved disk count and both report fingerprints. Comparison output
is a history view; its different operation and fields are not SR1 input records.

Status **0** means identical observed digests in compatible reports. Status
**2** means changed observations, including restoration. Status **1** means
input, compatibility, formatting or output failure; invalid CLI syntax returns
2. Operational failure takes precedence over findings. Validation failures
emit no partial comparison; existing diagnostics may use stdout. A late stdout
failure can leave text visible with status 1.

Ordering is supplied by the caller and is not inferred from timestamps. SR1
does not carry physical capacities/native sectors or authenticate its text;
the comparison binds all recorded fields without checking an external reference
or current disk contents. Retain trusted reports made with quiescent writes and
use verification or scrubbing for current data. This command provides no repair
or concurrent snapshot guarantee. See
[history qualification](../tests/storage-volumes/data-scrub-history.md).

## Offline multi-disk scrub report inspection

`show-data-scrub REPORT` validates and displays a saved plain-data `VINIXSR1`
report from `scrub-data` or `scrub-data-auto`. It reads no devices or credentials,
takes no writer lock and creates no output file. The complete report is
validated before any report bytes reach stdout; the original canonical text is
then printed exactly, including every clean or changed row and the reference
SHA-256 fingerprint.

```sh
vinix-volume show-data-scrub /root/scrub.txt
```

The input must be an ordinary regular file of 1–32767 bytes. Read-only,
no-follow, nonblocking descriptors pin the file and parent directory through
stdout finalization. Ordinary readable modes and hard links work, including
while a saved-state writer holds the directory lock. Final symlinks, directories,
FIFOs, missing/unbounded files, incomplete reads and trailing bytes fail.

Validation requires exact SR1 labels, spacing and newlines, canonical unsigned
decimal fields and 64 lowercase hexadecimal characters per digest. There must
be 1–64 saved disks and 0–64 complete mapping rows, ordered by saved disk index
with globally unique slots. Extents must be positive, 512-byte aligned,
nonoverlapping within each disk, and within signed-I/O and SHA-256 length bounds.
Every row's `match`/`changed` result must agree with its two digests, and header
counts must agree with every row. Saved slot/extent order within a disk is
preserved; empty saved disks and zero-mapping reports remain valid.

Status **0** means a valid report was displayed, including historical changed
findings. Status **1** means input, validation or output failure; invalid CLI
syntax returns **2**. A late stdout failure can expose text with status 1.
SR1 stores no disk capacities or native sector sizes: inspection cannot validate
those missing fields or bind the recorded fingerprint to a supplied reference.
The text has no authentication or checksum over the report itself. Inspection
checks structural consistency of trusted historical evidence; use verification
or scrubbing to check current disk contents. See
[inspection qualification](../tests/storage-volumes/data-scrub-view.md).

## Offline multi-disk data reference comparison

`compare-data-references BEFORE_MANIFEST AFTER_MANIFEST` compares the recorded
digests in two complete plain-data `VINIXDH1` references without discovering or
reading physical devices. Both inputs must contain exactly the same canonical
saved bundle: disk identities/capacities/native sectors, ordered mapping slots,
offsets/lengths/read-only flags, and all pool windows and allocation priorities.
A metadata change is an operational error, even if some recorded digests differ.
For compatible references the command reports every stable or changed row.

```sh
vinix-volume compare-data-references /root/before.vhash /root/after.vhash
```

Both complete bounded regular files are decoded and validated before any
comparison finding or report is emitted. The ordinary plain-data readers reject
final symlinks, nonregular/unbounded files, short/inconsistent reads and invalid
CRC, embedded bundle or record order. Their read-only no-follow/nonblocking
descriptors and parent directory owners remain pinned through final output
flushing. Same-path and hard-linked inputs work. Comparison takes no writer
lock and remains available during saved-state writer contention; it creates no
destination, reads no credentials and leaves existing files and live mappings
unchanged. These inputs retain plain-data file rules, without acquiring the
encrypted formats' private ownership or authentication requirements.

The complete ASCII report fits a fixed 32768-byte stack workspace. Its header
contains `format=VINIXDH1 operation=compared-data-references`, `disks`, `mappings`,
`stable`, `changed`, `algorithm=sha256`, `before_reference_sha256` and
`after_reference_sha256`. Each disk record contains `disk`, `disk_bytes`,
`sector` and canonical MBR/GPT `identity`; every mapping row contains `disk`,
`slot`, `offset`, `bytes`, `readonly`, `result=stable|changed`, `before_sha256`
and `after_sha256`. All digest/fingerprint values are 64 lowercase hexadecimal
characters. The fingerprints cover each entire canonical reference, including
its exact bundle, pool metadata and every digest. Pool metadata is checked and
fingerprinted, rather than repeated as separate output rows. Zero-mapping sets
still report their saved disks and both reference fingerprints.

Status **0** means compatible references with identical recorded digests,
**2** means compatible references containing changed digests, and **1** means
input, metadata, formatting or output failure. Invalid CLI syntax returns 2
without a finding. Operational/output failure takes precedence over changes;
all complete validation and report construction precede stdout output. A late
stdout failure can leave partial or complete text visible with status 1.

The command compares saved records; it establishes neither current disk content
nor a coherent snapshot of concurrent input replacements, and it does not infer
time order. Retain trusted references made with quiescent extent writes and use
verification or scrubbing to check current data. CRC and SHA provide corruption
detection without authentication or repair. See
[comparison qualification](../tests/storage-volumes/data-reference.md).

## Identity-based automatic data checksums and scrubbing

`hash-bundle-auto BUNDLE MANIFEST`, `verify-data-auto MANIFEST` and
`scrub-data-auto MANIFEST REPORT` select all saved physical disks without
disk-index/device arguments. They use the same validated desired extents,
SHA-256 streaming, canonical `VINIXDH1` references and complete ASCII `VINIXSR1`
reports as the explicit-device commands. Saved disk order and read-only mapping
flags remain exact, including when device names change after reboot.

```sh
vinix-volume hash-bundle-auto /etc/vinix/volumes.vset /root/data.vhash
vinix-volume verify-data-auto /root/data.vhash
vinix-volume scrub-data-auto /root/data.vhash /root/scrub.txt
```

The complete bounded bundle or manifest is decoded before discovery. It must
contain 1–64 unique saved MBR/GPT identities, at most 64 globally unique mapping
rows, valid native-sector geometry and signed-offset/SHA-256 bounds. Destination
validation, source/destination alias checks and the ordinary nonblocking writer
lock precede device access for hash and scrub. Verification needs no writer
lock. The existing plain-file validation applies; these inputs do not acquire
the encrypted formats' private ownership or authentication requirements.

Each saved disk uses the existing bounded `/dev` discovery (at most 4096 directory
entries per participant). Candidates are opened read-only without following final
symlinks and must identify an online whole physical device with exact identity,
capacity and native sector size. Aliases for the same physical ID are accepted;
distinct physical disks matching one identity are ambiguous and fail. Missing
later participants and distinct saved identities selecting one physical ID also
fail. The original selected descriptors transfer directly to the scan owner;
selected paths are never reopened. Every acquired descriptor closes on success
or failure, including later discovery and duplicate refusals.

Every pin retains its selected physical ID and physical read-only bit. Rechecks
before and after streaming require those values and saved identity/geometry to
remain exact. Hash and scrub additionally recheck all participants under the
writer lock immediately before publishing. The physical read-only bit is
independent of a saved mapping's read-only flag. No command imports or modifies
live mappings, writes the physical parents or reads credentials. Existing held
views and their mapping generations remain intact.

Hashing and verification return 0 on success and 1 on an operational failure or
verification mismatch; syntax errors return 2. Verification preserves its
existing fail-fast mismatch behavior and prints no successful records for an
incomplete verification. Scrubbing reads all rows through mismatches and returns
0 for a complete clean report, 2 for complete changed findings, or 1 for an
operational/publication/output failure, which takes precedence over findings.

The ordinary plain-data atomic replacement rules apply to both destinations:
file-fsync/close/rename/directory-fsync with the lock and pins held through final
output flushing. Equal retries still perform both flushes. Failures before rename
preserve the old file; a directory-fsync or output failure after rename can leave
the complete new file visible with status 1. Retry completes the operation.
Keep extent writes quiescent and retain a trusted reference separately; pinning
does not provide a snapshot, authentication or repair. See
[automatic data qualification](../tests/storage-volumes/data-auto.md).

## Complete data scrubbing

`scrub-data MANIFEST REPORT DISK_INDEX DEVICE [...]` scans every desired extent
in a trusted checksum manifest and atomically saves a complete corruption
report. It continues through digest mismatches, identifying all affected
mappings in one scan. The reference retains its exact bytes. Supply every
saved disk exactly once, in any order; the same read-only physical pinning,
identity/geometry checks, pre/post-read rechecks and 64-KiB streaming rules as
`verify-data` apply.

```sh
vinix-volume scrub-data /root/data.vhash /root/scrub.txt 1 /dev/vda 0 /dev/vdb
```

The command returns **0** for a complete clean report, **2** for a complete
report containing changed data, and **1** for a failed scan, publication or
output flush. Invalid CLI syntax uses the utility's existing usage status 2.
An I/O failure or final identity change discards the complete private candidate
and preserves the old report, even after earlier mismatches. No successful
report header or row is printed until the full scan and publication succeed.
Data writes must be quiescent throughout; these reports provide corruption
detection against a trusted reference, without authentication, snapshots or
repair.

The stable newline-delimited ASCII format starts with
`format=VINIXSR1 operation=scrubbed-data disks=N mappings=N matched=N changed=N
algorithm=sha256 reference_sha256=HEX`. The fingerprint is SHA-256 of the exact
canonical encoded reference, binding findings to its disk identities,
geometry, desired rows, pool configuration and saved digests. Every subsequent
row follows canonical disk/row order and contains `disk`, `slot`, `offset`,
`bytes`, `readonly`, `result=match|changed`, `expected_sha256` and
`actual_sha256`; both digests are 64 lowercase hexadecimal characters. An empty
desired set still reports its verified physical identities and zero rows.
The fixed 32768-byte workspace covers the full 64-row format with full-width
decimal geometry.

The report's directory writer lock covers source reads, device scanning,
file-fsync/close/rename/directory-fsync and final stdout flushing. Pins, source
descriptor and lock remain alive through that flush. Exact-report retries still
perform both publication flushes. A publication failure before rename preserves
the old report; after rename, directory-fsync or stdout failure can leave the
complete new report visible with status 1. Retry completes the operation. The
report destination must be absent or regular, is checked before participants
open and before publication, and cannot name the reference entry through a
lexical alias. Verification and offline reference inspection remain available
under report writer contention. See
[scrub qualification](../tests/storage-volumes/scrub-data.md).
