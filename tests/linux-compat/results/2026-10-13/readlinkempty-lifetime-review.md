Independent empty-path readlink lifetime review: PASS

The read-only `/root/readlink_lifetime_review` review approved the final
source, generated kernels/fixtures, source pins and measured retention.
Both kernels evaluate readlink_node before releasing the retained FD/Handle.
Every reachable handler return frees its pathname exactly once, and every
helper return releases owned dynamic target text exactly once.

The Handle pins the node and retains its resource through unlink. The orphan's
parent pin keeps ancestry valid during policy checks. Fixture arrays and
Handles/Slabs storage remain bounded stack/alloca, without generated allocation
or promotion helpers. Setup failures, child returns, temporary aliases,
control opens and observer returns close their descriptor references.
Each cohort has 38 descriptors; aliases share open-file descriptions. The
parent retains 35 references while each child adds three executable-link aliases.
Child cleanup leaves the parent's bank valid across forks. Real AB queue bytes
are drained, compared and replenished. The successful parent pauses until
guest teardown.

All six preview/before/after fixture C captures match the receipt source hashes.
Both architectures pass 7,296 checks each; all measured slab classes stay flat
over 200 cycles and large pages remain 70/70 ARM and 181/181 x86.

| Reviewed artifact | SHA-256 |
| --- | --- |
| Kernel vfs.v source | `3a05de6873dd9e1b5dd6b134a91030d0e8a9c4a1bc04e14d5a30e6e92d2477df` |
| Fixture source | `74522b89af4e20681afa090682ae3b165dc6e79a1c71852d9e7213a4338ba1c7` |
| All six preview/before/after fixture C captures | `729e595ff5245096ae01e63fadad0d872c33cc12f169584f37fb99bb4fae46aa` |
| ARM candidate kernel C | `8006326551b868d7d2e0f730dd4308876eced739a972ec35149612b21c853ce4` |
| x86 candidate kernel C | `1ffbcc6577e160d62a69b1d80986081deb3b527220e7eaf27bc7d2f87da5dbfb` |
| ARM fixture serial log | `2753a3fe72b5160aa31fcf16566fd85f08f3d227b55e60152157b23806e85a7e` |
| x86 fixture serial log | `7fb1f0e4bf83444eae655f08c8110f3c5d219fc203095b95307d5796b3eac8aa` |
