# Anonymous paging

Anonymous private and shared mappings can leave RAM and refault from a compressed
block or an encrypted raw swap device. `MADV_PAGEOUT` requests best-effort eviction.
The pressure worker also evicts anonymous pages after clean-cache reclaim, in
bounded passes; sleepable allocation recovery tries pageout before process OOM
recovery. Foreground recovery waits for an active reclaimer and completes an
address-space scan, yielding between bounded chunks, before reporting no progress.
Locked and immutable mappings are excluded.

Compressed pages use a bounded LZ codec. Blocks larger than 2 KiB go to disk when
swap is active. Compression reserves at most one eighth of physical RAM, charging
2 KiB per compressed page; backing metadata is additional kernel heap memory.
Without room in either store, pageout restores the original frame. A failed
allocation, short write or device error never substitutes a zero page.

## Swap activation

`swapon(2)` accepts one registered raw block device or partition with a version-one
Linux `mkswap` header made with a 4096-byte page size and no bad-page list. The
kernel never formats a device or activates swap automatically. Activation requires
trusted initial-user-namespace `CAP_SYS_ADMIN` and a ready secure random source;
entropy not yet ready returns `EAGAIN`. Linux priority flags are accepted for the
single device; discard flags and regular swap files are unsupported.

The device must be separate from mounted/protected filesystem extents. Its
physical extent is claimed for the activation, excluding overlapping mounts and
userspace raw writes, including writes through whole-disk aliases and already
open descriptors. Reads expose ciphertext. Slots use the native VM page size
(4 KiB on x86-64, 16 KiB on AArch64), starting after the first native page; the
maximum is 1,048,576 slots.

Each activation creates independent 256-bit encryption and authentication keys.
ChaCha20 encrypts each slot with a unique sequence nonce; HMAC-SHA256 authenticates
the ciphertext, nonce and slot index before decryption. Keys, nonces and tags stay
in RAM. Keys are erased when swap is disabled, and temporary plaintext/key
workspaces are explicitly wiped. Swap contents cannot be resumed after reboot.

`swapoff(2)` drains disk slots into retained resident frames before releasing the
device and erasing keys. Mappings with `PROT_NONE` are preserved. Insufficient
memory or read/integrity failure leaves the activation available for retry.

## Mapping lifetimes

Nonresident pages belong to the anonymous object, keyed by object offset rather
than a process virtual address. Shared aliases therefore refault one common
shadow page, including after `fork` and a moving/growing `mremap`. Pageout revokes
all resident aliases and completes TLB maintenance before reading the frame.
Busy aliases are skipped rather than waited for under another address-space lock.

Private fork children retain independent references to immutable backing. Their
refaulted writes remain private; retained physical fallback frames use COW.
Full-page private `MADV_DONTNEED` drops backing and returns zero-filled memory;
translated partial-page discard first restores the host page and preserves the
other subpages. Unmap, exit and replacement release backing only after independent
fault and pageout pins are gone. I/O holds no VM or backing spinlock.

Ordinary pending signals do not cancel page-in completion. AArch64 user faults
permit device interrupts and explicit event waits while keeping timer preemption
stopped until translation and instruction-cache updates finish.

## Observability and limits

`sysinfo(2)` and `/proc/meminfo` report actual disk capacity/free space.
`Zswap` reports compressed payload bytes and `Zswapped` their uncompressed size;
`VinixPageouts`, `VinixRefaults` and `VinixSwapErrors` count completed stores,
loads and storage failures. These global counters do not provide per-process
swap accounting. Compression/backing metadata is not yet charged to cgroups.

This covers anonymous memory. Hardware reference/dirty aging, active/inactive
queues, mapped-file page eviction, multiple swap devices, swap files, hibernation
and persistent encryption keys remain separate work.

See [paging tests](../tests/paging/README.md) for host fault injection, cipher
vectors, both architecture guests, pressure tests and slab measurements.
