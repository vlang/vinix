# Unmount with writable regular-file descriptions

Ordinary unmount now returns `EBUSY` while the selected attachment has existing
regular-file writer pins. These already cover writable shared descriptions,
in-flight writable opens and truncation, and descriptions retained by mappings
after the last FD closes. Duplication and fork share the existing pin; this
change adds no reference counts, resource ownership or freeing.

The unmount path closes writer admission under the same mount lock used to
retain a writer. An earlier pin prevents shutdown; a later attempt refuses
before copy-up/truncation. Backend shutdown failure reopens admission, while
ordinary detach leaves it closed. `MNT_DETACH` preserves existing writable
descriptions and writable opens through retained routes. Authorization,
child-mount refusal and backend flush/error propagation keep their order.

Run `--case unmount-writers`, or select `uw-0` through `uw-8` using the
[V mount controller](README.md). Native `all` and the portable Linux suite
require all nine cases. The [descriptor busy checks](unmount-descriptors.md)
close the read-only/O_PATH accounting gap; `uw-8` now requires ordinary unmount
to refuse until both retained descriptions close.

| Case | Qualified behavior |
| --- | --- |
| `uw-0` | Both write-only and read/write regular-file opens keep the mount busy. |
| `uw-1` | A duplicate retains the writer pin after the original FD closes. |
| `uw-2` | An inherited description retains the pin after the parent closes its FD. An ordinary account receives `EPERM` for unmount while keeping its inherited FD rights. |
| `uw-3`, `uw-4` | Private and shared mappings retain the writable description after FD closure. Unmapping releases the pin. |
| `uw-5` | A writer pins its selected bind attachment in both directions. The sibling alias can unmount independently. |
| `uw-6` | A copied namespace's attachment starts without the inherited description's pin. Removing that copy leaves the original mount busy until the child releases the original description. |
| `uw-7` | Lazy detach permits retained writers and new writable opens through a saved directory route. |
| `uw-8` | An O_PATH directory and a read-only file keep the mount busy. Closing one leaves the other pin; refusals leave writer admission usable. |

Each busy scenario repeats 200 refusals while checking mount identity and file
contents. Each refusal is followed by another writable open/close, requiring
admission to remain usable. Ordinary removal succeeds after the final writer
or mapping releases its pin. The retained-descriptor case repeats 200 refusals
before and after closing its directory, checking unchanged contents and fresh
writer admission each time.

The [persistent Services cold-boot gate](../development/README.md) additionally
checks rollback after the ext2 backend refuses shutdown for deferred orphan
cleanup. Every `EBUSY` retry must permit a fresh writable open and write to an
existing linked probe file; successful shutdown still requires clean read-only
filesystem checks. The probe is reused across boots and creates no orphan of
its own. No credential or schedule state is stored in it.

Historical writer-admission evidence is retained under
`build/development-unmount-writers-20261015`. That version of `uw-8` qualified
stale-route refusal after ordinary detach and was native-only. Current `uw-8`
and same-executable Linux evidence are documented with the descriptor checks.
Frozen kernels use the existing isolated `e42b3946c` worktree, saved typed-null
adaptation and the four unmount/policy sources matching this change. Other
sessions' kernel edits are excluded. Builds use V `be2eb40`, clang, LLD and
`KERNEL_LINK_RANDOMIZE=0`. Source snapshots, generated C and compiler hashes
are recorded by `audit.log` and `source-pins.json`.

| Architecture | Kernel SHA-256 |
| --- | --- |
| AArch64 | `5c3b382d0fdf9727247ecd5df3c1cbc7505cfaedc0dfdee7e747c32f1893973c` |
| x86_64 | `6731310cd593bebb36e2e50360bc62f8a037a4db6d997c2fec036ae409ecd5f8` |

`before-arm-b` and `before-x86-b` reproduce premature success with the previous
kernels at site 2901. The earlier `before-arm`/`before-x86` directories retain
fixture compilation failures before explicit C pointer types were corrected.
`after-arm`/`after-x86` run the complete new group; `all-arm`/`all-x86` run the
full native regression. `linux-arm`/`linux-x86` use the identical probe ELFs on
Linux 6.12.51-0-virt. `cold-arm`/`cold-x86` retain the persistent-volume rollback
checks. Individual-case and stale-cache checks are retained separately.

Both native full suites pass 314 verdicts; both same-ELF Linux reference suites
pass 284. Each architecture also passes three persistent Services cold boots,
eleven validated job/service/shutdown receipts and three clean read-only
filesystem checks. Every boot exercises writable-open rollback after actual
ext2 refusals. `before-admission` separately reproduces the old kernel accepting
a stale-route writer; `single-x86` passes the corrected `uw-8` selection, and
`stale-cache` refuses the pre-change probe before image construction or boot.

The original change qualified existing regular-file writer pins and writer
admission only. Retained descriptors, mappings, executable images and cwd/root
now have separate checks. Full concurrent namespace behavior, mount reclamation
and OCI/rootless acceptance remain open. Mount objects and
cached filesystem trees keep their existing permanent lifetimes.
