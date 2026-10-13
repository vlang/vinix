# Overlay node and backing ownership

Repeated replacement left both merged aliases and upper backing nodes allocated
indefinitely. The aliases never entered the orphan queue, and every backing
node acquired a permanent `overlaid` flag. Their entries and cloned destination
names remained allocated with them.

Committed entries now count each backing-node pin and retain the exact resource
pointer acquired with it. A backing alias may later copy up and expose a
different resource; releasing its earlier snapshot must not release that newer
resource. Copy-up adds only the new upper pin. Removed merged aliases enter the
existing descriptor, process, cwd, parent-reference and grace checks. Releasing
the alias's entry lets unlinked backing nodes begin their own retirement.

Backing directories keep their namespace resource until node retirement.
Merged directories own dot/map storage and their entry pins. A rename drops
obsolete lower pins after grace and transfers complete typed array headers to
the retirement queue. V's array destructor frees the managed allocation, whose
original pointer can differ from `.data`. Queue transfer and reaper locals have
no generated-C cloning, boxing or heap promotion.

UNIX socket binding creates its placeholder and adopts the endpoint's namespace
reference in one VFS writer transaction. It transfers the overlay entry's
separate resource pin and retires both old references after grace. A competing
unlink cannot retire the placeholder between creation and adoption. Generic
creation continues to enforce socket policy, ownership, ACL and namespace
checks; failed creation consumes no incoming endpoint reference.

Run the [V controller](README.md) with `--case retention`, matching isolated
kernel builds and fresh state directories. Root prepares the private mounts;
workers clear supplementary groups and run as UID/GID 1000. Networking is
disabled. The workload checks:

- A removed directory through its descriptor past grace, then through its cwd
  after descriptor close; creation inside it fails and `..` remains usable.
- A closed/unlinked socket through a retained `O_PATH` descriptor past grace.
- A stacked alias whose backing resource changes through copy-up, followed by
  rename of a lower-backed entry and removal; an old descriptor keeps its data.
- Two batches of 1,000 replacements and 100 repetitions each of ordinary file,
  hardlink, symlink, empty-directory and UNIX-socket creation/removal.

Both batches wait 25 seconds for alias, backing and socket queues, including
the TCG writeback worker. The host independently requires equal live objects
in every slab class and equal large-allocation counts. Functional `PASS` output
cannot override this memory gate. The default `all` case includes this workload
alongside concurrent readers/listings, disk namespace errors, durable whiteouts,
directory opacity, private-work invalidation and remount checks.

## Evidence from 13–14 October 2026

Inputs, receipts and serial captures are retained in
`build/development17-20261013`:

| Run | Result |
| --- | --- |
| `retention-arm-before-f`, `retention-x86-before-f` | Matched saved kernels pass functional checks but retain 3,400 size-256 nodes, 1,500 size-96 entries, 3,200 size-16 objects, 600 size-32 objects, 200 size-64 objects and 600 size-192 objects across the second batch. Both host memory gates reject them. |
| `retention-arm-after-f`, `retention-x86-after-f` | Every live slab class and large count stays flat across the second batch. Directory FD/cwd, socket `O_PATH`, stacked copy-up and managed-array rename checks pass. |
| `retention-arm-all-b`, `retention-x86-all-b` | Concurrent replacement, backend refusal, memory gates, whiteouts, opacity, work invalidation and remount/recreation pass. Both read-only filesystem checks are clean. |
| `retention-arm-full-b`, `retention-x86-full-b` | Actual storage exhaustion, repeated rollback, exact block/inode recovery, rename refusal, statfs memory gates and remount pass. Both read-only filesystem checks are clean. |
| `retention-arm-http-b`, `retention-x86-http-b` | Authenticated HTTP/account/job/build gates pass with 19 independently validated native records each. |

The pre-fix tracked run `retention-arm-before-tracked-a` identifies 2,011
backing nodes, 2,011 merged nodes, 2,011 entries and two groups of 2,002 cloned
destination names. After the same 2,000 replacements and grace periods,
`retention-arm-after-tracked-d` has no allocation group with 50 or more live
objects; both trackers report zero dropped records. The symbolized inputs and
reports are retained in each state's `sites-input.log` and `sites-named.log`.

| Input | SHA-256 |
| --- | --- |
| Before ARM kernel | `855b421cb8120bf55d97ad726feb1ff22de4945992fa3898e55b8b6128791b9b` |
| Before x86 kernel | `8a2559e0365a398f7eac77d6823e699c2884896d06c3d3824d4cc7449f5d2654` |
| Final ARM kernel | `0a50867b0edc60ff75380a184b4ee83b0dfbad8c52ac85d082bd05cac268d227` |
| Final x86 kernel | `b16c2beba3f24680db4d35c9acc3d50b04f243e27bc8d608096db978f16df81b` |
| Retention fixture | `5456965371fab0c89f2304ba32cb08106b4b753235fac6391a498640a9012fe1` |

The isolated kernels retain the earlier `9b01dbca2` baseline and filesystem
patches through `d1cf55595`, plus this ownership correction. They use the
preserved `compiler-f6358ec/v-from-bootstrap` compiler and link-shuffle seed 17.
`retention-lifetime-review.md` records independent source/generated-C approval
for both architectures. The checker accounts for the three per-open creation
tracking changes committed concurrently in `73f513e79`, outside the ownership
functions, when comparing the shared checkout with these isolated inputs.

`retention-evidence-checked.log` validates fixture and immutable binary hashes,
control growth, final slab equality, four filesystem checks, native receipt
counts and tracked allocation groups. Checkers are compiled without `-prod`;
`retention-assert-probe.log` records the deliberate failed-assert control. The
allocation allowlist audit still reports exactly the same 182 baseline file/kind
failures. Its allowlist was not expanded; the owned snapshot-array allocation
is annotated `@[freed]` after checking its destruction.

The ARM full regression completes 36 batches of 200 syscall operations and
four batches of 300 process runs, with zero retained bytes and no additional
live objects or slab pages. The cache workload writes 32 MiB and records 16 MiB
cached. Idle, application launch and drag pass their process-count and duration
checks. `retention-desktop-perf-c.json`, `retention-desktop-shots-c`,
`retention-desktop-serial.log` and `retention-perf-evidence-checked.log` retain
the report, screenshots, capture and validation. Kernel selection for this
full run is inferred from the stable `VINIX_KERNEL_DIR` invocation and inspected
runner, which copies that directory's binary. The current harness removes its
boot disk on completion, so an independent extraction is unavailable. The
native-controller runs retain their kernel inputs and verify the hashes above.

The first combined candidate fails with `Slab: invalid free alignment` because
it retired raw managed-array data pointers; both failed `all-a` receipts remain.
The typed-header correction and stacked rename check address that failure.
An early x86 sample retained queued objects at the shorter settling interval;
the passing controls and final runs use the same 25-second interval. A diagnostic
retry failed while copying firmware after host disk exhaustion; its receipt is
retained as `retention-arm-after-tracked-c`, and the fresh `-d` run is the passing
trace. Superseded/interrupted full runs remain separate from the final `-c`
report. Completed firmware/staging scratch is retired, and identical immutable
kernel files share storage after hash checks; their paths and bytes remain.

Permanent mount/root/namespace pins remain. This does not qualify repeated mount
reclamation, persistent UNIX-socket inode removal, crash recovery or a mainstream
rootless OCI runtime. Roadmap section 17 acceptance remains open.
