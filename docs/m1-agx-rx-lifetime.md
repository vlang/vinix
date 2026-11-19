# G13 receive ring teardown

Omarchy's pinned Asahi serializes receive polling under its RX mutex.
Vinix now holds the GPU manager lock while copying and acknowledging each
Event, KTrace or Stats entry. Shutdown uses the same lock to stop firmware
and release the channel backing.
[Asahi receive polling](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L472-L486)

Vinix releases the lock before dispatching from the private event copy.
Fault and channel recovery check running state under the manager lock.
A stale worker error preserves stopped state, and a repeated call to the
shared shutdown method returns once teardown has completed.

ARM64 and x86-64 builds, 82 contract files, three sanitizer suites and five
pinned source gates passed for `9b390e1520dd92ce367ef6dd3743cd26850ade15` plus
the archived patch. The failure fixture covers 18 receive/shutdown
interleavings, six stale fatal events, and two copied TVB payloads at ring
reuse. Three negative controls detected an unlocked acknowledgement, a
stale error overwriting stopped state, and repeated teardown. Independent
lifetime review and generated C checks passed. Receive copies stay on the
stack. The allocation scan reported one fewer ARM64 allocation site and
178 existing allowance discrepancies.

At this revision the audit reported `not_equivalent`, with open differences
in RTKit crash-log buffer ownership and G17 worker teardown. No hardware tests
or reboots occurred. [RTKit crash-log follow-up](m1-agx-rtkit-snapshot.md)

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rx-lifetime-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `920780fbce555cf7ee5ee3ef752a031dc60bdc3b6a6fc1f26c2e3cc9932b3a76` |
| `bundle.tar.gz.inventory.txt` | `06e07bf5b10cb94af57ff9d1bdadd71bd70ac4abbad6a54f2ffcc7eac8e0bdc3` |

## ASC mailbox receive during shutdown

The G13 worker now holds the manager lock while checking running state and
reading one ASC mailbox message. Shutdown takes the same lock before it
marks the manager stopped and stops the ASC. The worker releases the lock
before it dispatches the copied message.

The sanitizer fixture reproduced a FIFO pop racing shutdown on
`9fc17b7d32564db6895d7d0fa6a2156c8c246100`. Six cases passed across both
G13 firmware ABIs. Shutdown before a receive preserves both queued messages.
Shutdown after the first receive suppresses its power-state update and
preserves the second message. A later poll on a stopped manager leaves the
FIFO untouched.

AArch64 and x86-64 builds, the job-lifetime suite, 79 local contract tests,
and 122 pinned-reference checks passed. Generated AArch64 C keeps the FIFO
read within the manager lock. The allocation scan matched the 176 baseline
findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-asc-rx-shutdown-20261119.N4nx89/`.
The `bundle.tar.gz` SHA-256 is
`4f12c50cc8e2addfa865aca3652cb981d36f7685707b0db47807c8e76c736af9`.
Native M1 firmware validation remains open.

## ASC stop confirmation before G13 teardown

G13 now reads back the ASC RUN bit after the stop write and its MMIO
barrier. Probe cleanup and runtime shutdown mask both claimed IRQs and
retain firmware-visible backing if the stop write or readback fails.
Runtime shutdown keeps the manager available for a later attempt. It
publishes stopped and retires UAT roots only after RUN has cleared.
A failed probe remains unpublished and retains its backing.

The sanitizer fixture reproduced premature RTKit buffer release on
`5d517cea2b49a21ec9df85a4ed499ad2e06cfa78`. Four cases passed across the
two G13 firmware ABIs with an injected stop failure in probe cleanup or
runtime shutdown. They check backing retention, IRQ masking and lock
release on failure, then verify cleanup after a successful stop.

AArch64 and x86-64 builds, the job-lifetime suite, 79 local contract tests
and 122 pinned-reference checks passed. Generated AArch64 C confirms the
readback and early return before release. The allocation scan matched the
176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-asc-stop-readback-20261119.ErG0D4/`.
The `bundle.tar.gz` SHA-256 is
`936adb04e917cd00455624653cdc132816b364f0bda0da854f82c43968fc7e09`.
Native M1 firmware validation remains open.

## Cleanup retry for an unpublished G13 probe

An unconfirmed ASC stop now returns a distinct probe result. The driver
retains that manager privately and retries its cleanup on shutdown or
before another initialization can replace the UAT. Repeated stop failures
retain the same owner and backing. A confirmed stop runs the probe cleanup
and clears the driver's private reference. Only a successful probe
publishes the GPU manager and registers DRM.

Sanitizer cases for both firmware ABIs cover an initial stop failure,
another failed cleanup attempt, successful release and an idempotent
subsequent call. A negative control that dropped the private reference
after a failed retry was detected. Both kernel builds, the job-lifetime
suite, 79 local contract tests and 122 pinned-reference checks passed
against `83ba6486d5111364333a58d298a4cde22206d4f3` plus the archived
patch. The allocation scan matched the 176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-asc-probe-cleanup-20261119.8UnNGo/`.
The `bundle.tar.gz` SHA-256 is
`e74e764202e8af6375c28f44530cbd936a6fb61e21330ba90e35d624446af028`.
Native M1 firmware validation remains open.

## Cleanup after DRM registration failure

The AGX driver publishes the global manager after DRM registration succeeds.
If registration fails after firmware startup, the driver runs the normal
GPU shutdown path. An unconfirmed G13 ASC stop leaves the unregistered
manager under driver ownership. Shutdown or the next initialization can
retry before a new probe replaces the UAT.

Six sanitizer cases across both firmware ABIs cover registration success,
failure cleanup, and a failed stop followed by successful cleanup. Three
negative controls detected early publication, missing cleanup and shutdown
that skipped an unregistered manager. Both kernel builds, the job-lifetime
suite, 79 local contract tests and 122 pinned-reference checks passed
against `41c9ed349e0ad7f148a074723e3990afb5a83ba4` plus the archived patch.
The allocation scan matched the 176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-agx-drm-registration-20261119.YnIjzc/`.
The `bundle.tar.gz` SHA-256 is
`763ee40f2c3608a19a10328fcfea00e5659078bf5407e70d4356f7c14209e5d8`.
Native M1 firmware validation remains open.

## DRM node readiness

DRM publishes readiness after installing the driver context, requested
card and render nodes, and registry entry. An open that reaches a node
before publication or after unregister returns `ENODEV`. Successful opens
return the resource already installed in devtmpfs.

The DRM wire sanitizer fixture covers card-only and card-plus-render
registration, opens during node creation, unregister, and an injected
render-node creation failure. Negative controls caught early publication
and an open that skipped the readiness check. The AGX file-close and G13
failure sanitizer suites, both kernel builds, 79 local contract tests
and 122 pinned-reference checks passed against
`51094f779c9777e828a90088fc215835d85e0547` plus the archived patch.
The allocation scan returned 176 findings. Its only change was the
existing node interface allocation classified as an explicit cast.
Generated AArch64 C confirms there is no allocation in the open callback.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-node-readiness-20261119.tR6HXk/`.
The `bundle.tar.gz` SHA-256 is
`91b99cd17e3be58222a84513e5eb1e7b3207f936fb4a2fc3cdf3b2a428bf0270`.
Native M1 validation remains open.

## DRM device name removal and slot reuse

Unregister marks the device inactive, detaches its card and render names,
and releases its slot under the registry lock. A stale unregister checks
the device pointer against the slot's current owner. Old open files keep
their original device identity. A failed render-node creation detaches
the staged card node, and DRM activity reports the number of live slots.

The DRM wire sanitizer fixture filled 64 active slots and reused a freed
slot 70 times while retaining the old card and render objects. It checked
that stale unregister leaves the replacement active and existing opens
cannot address it. Negative controls caught missing teardown, missing
registration rollback and a missing owner check. Both AGX sanitizer
suites and kernel builds passed, along with 79 local contract tests and
122 pinned-reference checks. The allocation scan matched the 176 baseline
findings. The tested base was `a7da85a72ebcc34c753f3942b5f5168c362e6e52`.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-slot-reuse-20261119.qpJ3ja/`.
The `bundle.tar.gz` SHA-256 is
`cc7c683c3b7fd6f3abb052b45935e671867559d2ce72ff6e874c8abc4db0b5ef`.
Native M1 validation remains open.

## DRM mapping admission after unregister

DRM core now rejects a new mapping with `ENODEV` after its device is
unregistered, including the path for drivers without an admission callback.
It also rejects expansion of an existing mapping on the inactive device.
Existing mappings retain and release backing through the original device
when the slot is reused.

The DRM wire sanitizer fixture reproduced new mapping admission on
`929db3aa5fc9cb4b043238d9fa57703aecd3db3c`. A regression control that
removed the growth check caught expansion after unregister. The revised
fixture checked three callback configurations across slot reuse, including
retaining and releasing old backing and admitting mappings on the new
device. Both AGX sanitizer suites, both kernel builds, 79 local contract
tests and 122 pinned-reference checks passed. Allocation findings matched
the baseline.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-mmap-unregister-20261119.N5W8ab/`.
The `bundle.tar.gz` SHA-256 is
`d9e54898d0e15072a308b69801dd6f211b8e353701373160015c592835bbdb96`.
Native M1 validation remains open.

## Metadata-only DRM handles across unregister

A still-reachable DRM node can be opened with `O_PATH` before device
publication or after unregister. Data opens still require registration and
return `ENODEV` on the inactive device. VFS returns `EBADF` for ioctl calls
on path-only descriptors before dispatch. Closing a DRM path handle drops
its node reference. Data handles retained across unregister still close
through their original driver and release their syncobj owner.
[Linux path-only open](https://github.com/torvalds/linux/blob/v6.12/fs/open.c#L855-L872),
[ioctl descriptor lookup](https://github.com/torvalds/linux/blob/v6.12/fs/ioctl.c#L844-L857),
[descriptor filtering](https://github.com/torvalds/linux/blob/v6.12/fs/file.c#L1044-L1059).

The DRM wire sanitizer fixture verified both open modes, minor-number reuse
and close callbacks. The original open gate and a control with unconditional
close callbacks both failed. The six descriptor-flags cases passed in
AArch64 and x86-64 QEMU guests. The linked-file and directory cases verified
that `fstat` succeeds on `O_PATH` and ioctl returns `EBADF`. An AArch64
kernel with the VFS check omitted failed the new assertion.

Both kernel builds, both AGX sanitizer suites, 79 local contract tests
and 122 pinned-reference checks passed. The allocation scan matched the
176 existing findings. The tested base was
`fcaa2b8cf58560e99657202159539d5e2ad9577b` plus the archived patch.
Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-path-handles-20261119.yFoXLl/`.
The `bundle.tar.gz` SHA-256 is
`a4d39ddcfb411d9552c710d06d2a0b09a043b33729dca991826bbc69693ee9b3`.

## DRM name collisions during registration

Devtmpfs checks the card name and any requested render name under one
writer lock before publishing either DRM node. An occupied name returns
`EEXIST`. A non-directory `/dev/dri` returns `ENOTDIR`. Rejection releases
the unpublished device, nodes and resource boxes, leaving the registry
slot available. Data opens become available after the names and registry
entry are installed.

The DRM wire sanitizer fixture covered an unavailable devtmpfs, a
non-directory `dri`, collisions at each leaf, card-only registration
beside an occupied render name, and registry slot reuse. Two controls
caught missing collision checks and card publication before the render
check. The independent lifetime review confirmed that all recoverable
failures precede publication. Generated ARM64 code confirms that the
failure path releases each unpublished allocation.

Both kernel builds, both AGX sanitizer suites, 79 local contract tests
and 122 pinned-reference checks passed. Both QEMU guests passed the
descriptor-flags suite, and the ARM64 guest logged creation of the
simple DRM card. The allocation scan matched the 176 existing findings.
The tested base was `ac5698ad846ad3bcfdc7051e77f924c65b0db8ac` plus
the archived patch. Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-name-publication-20261119.ImjujQ/`.
The `bundle.tar.gz` SHA-256 is
`9f0be0a75fe94380a6f0da660d7d1c0420a55a0320662aabd1646251ceba73ea`.

## DRM registration allocation failures

DRM allocates the device record, each node record and each resource box
with the fallible allocator. Failure returns `ENOMEM`, releases every
allocation made for the unpublished registration, and leaves the names
and registry slot available. Successful devtmpfs publication transfers
ownership before the device starts accepting data opens.

The DRM wire sanitizer fixture injected 64 failures at all five sites
across card-only and card-plus-render registration. Each case checked
the live allocation count, empty namespace and successful retry. Two
controls caught a missing free after box allocation failure and missing
cleanup after a partial construction. The independent lifetime review
and generated ARM64 code confirmed the allocation and cleanup order.

Both kernel builds, both QEMU descriptor-flags suites, both AGX
sanitizer suites, 79 local contract tests and 122 pinned-reference
checks passed. The ARM64 guest logged simple DRM card creation. The
allocation scan found three fewer implicit DRM sites on each
architecture, with 174 existing allowance findings. The tested base
was `29d22abfad57f54834f2c0f01caee9f06ee55a44` plus the archived patch.
Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-registration-oom-20261119.fYrPl6/`.
The `bundle.tar.gz` SHA-256 is
`ce232a872e853cca35a24d006040391e2d1ed57e420bf436a2fee64e2d552204`.

## Driver metadata after rejected registration

Native AGX, fake G17, simple DRM and VirtIO GPU transfer their heap driver
descriptors and ioctl tables to DRM registration. Rejection frees the
table and descriptor before returning to the caller. A registered
device keeps both available to files that survive unregister. Driver
private context stays with its caller, so AGX can retain a manager across
an unconfirmed firmware stop.

The DRM wire sanitizer fixture measured the releases across 80 injected
allocation failures, 16 name collisions and a full registry. It also
verified a successful retry and access to its table after unregister.
Two controls caught missing frees. The independent lifetime review and
generated ARM64 code confirmed ownership at each caller.

Both kernel builds, both QEMU descriptor-flags suites, both AGX
sanitizer suites, 79 local contract tests and 122 pinned-reference
checks passed. The allocation scan matched the 174 existing findings.
The tested base was `7ecf4b9787e98eda28b366e681f28ce0dbcf209b` plus
the archived patch. Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-owned-driver-20261119.L80oKk/`.
The `bundle.tar.gz` SHA-256 is
`1e942eece7c13d2d70e6b1d94f80aecc9c24990b1daaf7c6ee8015c18bce4212`.

## Static ioctl tables and fallible driver definitions

Native AGX, fake G17, simple DRM and VirtIO GPU use fixed ioctl tables.
Each registration borrows its table through an allocation-free view and
allocates a private copy of the driver definition with the fallible
allocator. A failed definition allocation returns `ENOMEM`. A later
rejection releases the definition. The fixed table remains available
to other registrations and to files that survive unregister.

The DRM wire sanitizer fixture injected 48 failures across the
definition, device, node and box allocations. It checked live storage,
absence of published names, the static table during retry and table
access after unregister. Two controls caught a leaked definition and a
view missing `.nofree`. The independent lifetime review compared all 48
ioctl entries and confirmed their storage in generated ARM64 code.

Both kernel builds, both QEMU descriptor-flags suites, both AGX
sanitizer suites, the ARM64 modern dispatch checker, 79 local contract
tests and 122 pinned-reference checks passed. The allocation scan found
eight fewer implicit sites on AArch64 and two fewer on x86-64, with 173
existing allowance findings. The tested base was
`8f25fccef5cb2b37a8ac046ad7e71e3c2eb461f7` plus the archived patch.
Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-driver-definition-20261119.Gpl3ZL/`.
The `bundle.tar.gz` SHA-256 is
`923255fd53c319b74b103cfe225de8f58b4699264ca299d1414276f91e137a01`.

## Fallible DRM device leaf publication

DRM formats temporary device names on the stack. Devtmpfs prepares each
requested leaf record and its owned name with fallible allocations before
publishing either entry. An allocation failure returns `ENOMEM` and
releases the prepared storage. The `dri` directory and VFS child map
retain their existing allocation paths.

The DRM wire sanitizer fixture passed 336 injected allocation failures
across the registration entry points. It checked that failed registrations
released their storage, kept the namespace empty and allowed retry. Two
controls caught missing cleanup after a name allocation failure and after
render leaf preparation failed. The independent lifetime review confirmed
ownership through publication and detach. Generated ARM64 code confirmed
stack storage for all three temporary name buffers.

Both kernel builds, both QEMU descriptor-flags suites, both AGX sanitizer
suites, 79 local contract tests and 122 pinned-reference checks passed.
The ARM64 guest logged simple DRM card creation. The allocation scan
matched the 173 existing findings. The tested base was
`b2c1a7765a6b0b5c404dc5c3da5d46985a874167` plus the archived patch.
Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-leaf-staging-20261119.F7Tz4Q/`.
The `bundle.tar.gz` SHA-256 is
`dce6e82d93b18e965c01de043dcf75460c0a757341d74f9abccb4ec0cd3cf031`.

## Paired DRM directory publication

Devtmpfs initializes both DRM leaves before inserting them under one
directory lock. Path lookups and directory snapshots take that lock, so
a reader observes the pair together. Data opens become available after
DRM installs the registry entry.

The DRM wire sanitizer fixture inspected the directory at each unlock.
A control that released the lock between insertions exposed a partial
pair. Generated ARM64 code showed both map insertions between one acquire
and release. The allocation scan matched the 173 baseline findings.

Both kernel builds, the QEMU descriptor-flags suites, both AGX sanitizer
suites and all 79 local contract tests passed. An ARM64 QEMU boot with
the fake G17 driver enabled logged publication of `card0` and
`renderD128`. Native M1 validation remains open.

The tested base was `a77430d795afe96188f9c8283aa70e7e48bd646c` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-paired-publication-20261119.NtAk6Z/`.
The `bundle.tar.gz` SHA-256 is
`c49fc226b8057fc0594c07ec3e7038934fa115e90a2ba2e52ede92418c3dc3ae`.
