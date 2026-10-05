# Clean private EXT2 pages

`V=/path/to/v tests/private-pages/run-host.sh` runs production page-source,
installation and COW code against a faulting page-map/resource fixture.
It actually frees a VMA and global while acquisition is in progress, checks
replacement serial/offset/flag races, optional device pin failures, surplus
pages, ELF partial-page isolation and COW allocation/PTE failure rollback.
Callbacks assert that the page-map lock is released. Ordinary fork-private
pages still drop PMM references when their resource has no cache callback.

`tests/mapped-writeback/run-host.sh` runs actual EXT2 acquire/release/writeback
code and checks cache-owner/private/fork references, clean pages without I/O,
mixed private/shared references and failed dirty-page retry. Either host runner
accepts `VINIX_HOST_SANITIZE=1` for AddressSanitizer and UndefinedBehaviorSanitizer.

Run `python3 tests/mapped-writeback/run.py --arch aarch64 --steps=private` or
`--arch amd64 --steps=private` against a built kernel (worktree environment is
documented in the mapped-writeback README). Eight live mappings touch the same
8 MiB file. Seven additional aliases must use less than 2 MiB of physical
memory, including page tables and mapping metadata. The test checks mprotect
without eager copying, first-write isolation, pread into a private page before
any fork, descriptor/shared writes reaching clean aliases, fork isolation,
MADV_DONTNEED reload and concurrent private readers/writers on two CPUs.
Dirty locked private pages also survive remap growth without changing cached
aliases; locked discard fails, and unlock permits a clean reload. Then 500
private map/remap/unlink/close/unmap operations run beside global sync;
post-grace slab deltas are checked and allocation sites are printed when
tracking is enabled. After power cut, every byte of the 8 MiB file is verified
against the intended shared/descriptor writes: private changes never persist.

EXT2 owns one reference per cached file page, and each private global owns a
PMM reference. Fork retains another; COW/unmap returns it through the resource.
Cache ownership ends only after private references, shared mappings and failed
shared writeback are gone. ELF edge zeroing copies a shared clean source before
changing bytes outside that segment. Fault acquisition independently pins the
handle/resource and optional device range, so raced unmaps return every page
without retaining a freed range pointer. Global serials and effective file
page/flags prevent a replacement mapping from accepting an old acquisition.

This sharing capability currently applies to EXT2. Other filesystems retain
their existing private-page policy; clean cache pages are not kept after the
last mapping, and mapped-page eviction under memory pressure remains open.
The VM4 conservative shared-page writeback and separate failed inode-reclamation
limitations still apply.
