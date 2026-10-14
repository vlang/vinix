# Security event producer allocation and authorization

The existing security-event ring holds at most 256 records by value, but its
producers passed local mutable `SecurityEvent` values to helper functions. The
kernel compiler promoted each local to a 112-byte heap allocation that was never
freed. Each event therefore retained one slab128 object even after its ring slot
was overwritten.

Both producers now use explicit stack storage and initialize the full record.
The label helper synchronously copies at most 40 bytes into its inline array;
the store copies the complete pointer-free record into the ring under the
existing lock. Neither helper retains the producer pointer. No heap release,
grace period, event schema, counter or authorization change is needed.

The maintained V depth fixture emits 600 mount-authorization events and 200
permitted service reports per batch. Two batches require total growth of at
least 800, correct capacity/retained/dropped relationships and copied labels
truncated to 40 bytes after the caller overwrites its buffer. A UID/GID 1000
child inherits a descriptor opened by root and must receive `EPERM` when writing
a report. The parent checks immediately that the forbidden label is absent,
before later records could overwrite it. Call-site allocation diagnostics are
read only by root; the fixture adds no authorization bypass.

Evidence is retained under `build/development17-20261013`:

| Artifact | Result |
| --- | --- |
| `protected3-arm-trace-a`, `protected3-trace-named.log` | The earlier 600-mount batch retains 600 objects at `security__event <- security__permitted <- fs__syscall_mount`. |
| `protected4-{arm,x86}-events-before-b` | The saved producers pass functional/report-authorization checks but retain exactly 800 slab128 objects per reporting batch. |
| `protected4-arm-after-f`, `protected4-x86-after-g`, `protected4-{arm,x86}-all-b` | Both final kernels pass all report checks and the unchanged strict phases 70/71 allocation gate. All 19 ARM and 15 x86 live class/large counts match, with zero writes after free. |
| `protected4-allocation-audit-a.log` | Both producer promotion sites disappear. The remaining 181 baseline file/kind failures match the previous audit; the allowlist is unchanged. |
| `protected4-lifetime-review.md` | Independent review binds stack lifetime, complete initialization, synchronous copies and unchanged live authorization to source and generated C hashes on both architectures. |

The isolated final trees are `kernel-protected4-{arm,x86}-tree`; they include
the separately committed [copy-up protection](protected-copyup.md) and
[stacked population](stacked-population.md) fixes. `protected4-evidence.v` checks
compiler/source/C/fixture pins, saved negative controls, final receipts,
allocation samples and clean read-only filesystem checks. Failed preliminary
builds and shorter-wait socket runs remain separate artifacts.

This closes the measured event-producer leak. General tracing, process sampling,
core dumps, authorized crash/hang reporting, concurrent producer stress and the
wider capability/user-namespace policy matrix remain open in roadmap section 17.
