# DRM syncobj eventfd notifications

The 24-byte `DRM_IOCTL_SYNCOBJ_EVENTFD` request registers a counter for
point-zero binary work or a point in a cumulative timeline. Availability
registration increments the counter when a fence exists. Completion
registration transfers to the captured fence and increments the counter on
successful or failed completion. An already retired prefix increments the
counter immediately. The handler validates flags and padding before handle
lookup, then distinguishes a missing descriptor from a descriptor of the
wrong type.
[Packaged syncobj eventfd handlers](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_syncobj.c#L1459-L1559)

Names, opaque descriptors and in-flight output publishers hold object
references. The final release cancels registrations for points still
awaiting submission. A captured registration holds its original eventfd
through descriptor close and numeric reuse. Each registration frees its
owned record and releases the counter on completion or cancellation.

Kernel notification saturates at UINT64_MAX and exposes POLLERR at
overflow. Blocking character-device I/O samples the counter event's
generation before releasing the counter lock. The generation check covers
completion between unlocking and enrolling. Wrong-type descriptor
validation sets EINVAL after releasing its lookup reference.
[Packaged eventfd implementation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/fs/eventfd.c)

The ASan/UBSan fixture passed 100 cycles covering allocation failure,
availability, completion, aliases, descriptor reuse and object cancellation.
Separate cases passed for overflow, blocking enrollment and both output paths.
Independent lifetime review found the missed wake during blocking reads
and a fake AGX submit path that could leave a fence pending after partial
output publication. The fixed fake path signals the published fence with
the submission error after dropping the file lock. A control omitting that
signal failed the callback-retirement assertion.

AArch64 MP and x86_64 builds, 82 contract tests, five pinned protocol checks,
and the AGX async, file-close and DRM wire suites passed. The compiler
reported 377 AArch64 and 289 x86_64 allocation sites and the same 178 existing
allowance findings after including both new source modules.

The host checks used Vinix `e8d884026` plus this patch and the packaged
Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`. Eventfd point
lookup uses cumulative timelines. The legacy per-point map, timeline
capability reporting, WAIT deadline propagation, fence metadata reclamation,
scheduler behavior and matched Mesa validation remain open.

The captured sources, binaries, logs and restored evidence are under
`/Users/alex/.local/state/vinix/omarchy-m1-syncobj-eventfd-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `b1b95b4a1d4702eb5c675f742e7b86c9672bee56a5c6f2cb825d779189d55bea` |
| `bundle.tar.gz.inventory.txt` | `b5a52eedae380d67255fa64a0912440e2e531ec42e5a76277af7b57e6fad6569` |
