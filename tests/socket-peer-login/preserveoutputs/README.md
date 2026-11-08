# Rename-only kernel output preservation

Source-only draft, 2026-11-05. No compiler, filesystem flag operation or
control has been run for this helper. The historical guarded controller and
all retained build states are unchanged.

`preserveoutputs.preserve(root, step, arch)` moves only `kernel/obj`,
`kernel/bin` and `kernel/cc-runtime-ARCH`. The caller must first retire every
build writer and provide a new owned attempt directory on the same device.
Sources and their parents must be canonical non-link directories; literal
links inside `obj/vsrc` are allowed and never traversed by preservation.

The helper uses `C.rename` directly, saving its 32-bit errno before journal
I/O. It has no `os.mv`, copy, removal or rollback path. After any failure,
previously renamed objects stay in the preserved step and pending objects
remain live. A later call refuses the existing journal rather than moving
pending entries. Plain rename is replace-capable: this is a trusted quiescent
namespace contract, not atomic protection against hostile concurrent writers.

The exclusive-create append-only `preserve-outputs.jsonl` contains typed
admission, ready, rename, complete or failed/refused snapshots. Item states
retain planned, absent, pending, moved or failed outcomes and the actual
syscall errno. It is bounded to twelve snapshots / 64 KiB. A journal write
failure stops subsequent moves; no crash-durability guarantee is claimed.
The caller must honor the returned status: a final close failure can follow a
flushed complete snapshot and still returns a failure.

The maintained control entrypoint is `../preserve-outputs-controls.v`. Its
fourteen base cases cover both architecture names, inode/device/mode/owner/
link-count/data preservation, literal internal links, optional absent output
semantics, existing or dangling destinations, parent/root/output aliases,
non-directory output, overlapping scopes and invalid architecture. Three
repeat controls verify sticky journal and unchanged source/destination data.

The required partial-failure control sets `UF_IMMUTABLE` only on its freshly
created `bin` directory. `obj` must rename successfully, the real second
`C.rename` must return EPERM, and the runtime must remain pending. The control
records flagged source/destination/journal evidence before restoring precisely
the original fixture flags, recording that subsequent ctime/flag transition
separately. A failure to arm, observe or restore the flag fails the control.
It never changes a shared source, historical artifact or frozen compiler input.

The reviewed execution proposal uses one fresh namespace, denoted N:

```text
/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01/target-consumer-host-01/rename-01
```

T denotes N's parent; SRC is T plus `/source-02`. The main source stage captures this
README, `core.v` and `../preserve-outputs-controls.v` as independent ordinary
files under SRC/tests/socket-peer-login, retaining their relative layout.
These are three of the eight helpers accompanying the 65 producer entries:
73 files/links total. Check bytes, modes, ownership, nlink=1, distinct
original/copy inodes and source identities before and after. Do not make a
second N/source capture. No fixture is created until the compiler and all
required input postchecks pass.

The exact HOST bootstrap argv, represented below with one quoted value for
each `-cflags` and `-path`, is:

```text
/opt/homebrew/Cellar/coreutils/9.12/bin/timeout --signal=TERM --kill-after=10s 300s
 /usr/bin/sandbox-exec -f N/compile/policy.sb
 /Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v
 -new-compiler -no-retry-compilation -b c -gc none
 -prod -nocache -no-parallel -showcc
 -cc /opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23
 -cflags "-Werror=incompatible-pointer-types"
 -cflags "-Werror=incompatible-function-pointer-types"
 -cflags "-Werror=format"
 -cflags "-isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
 -path "SRC/tests/socket-peer-login|/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/vlib"
 -o N/bin/preserve-outputs-controls
 SRC/tests/socket-peer-login/preserve-outputs-controls.v
```

Expand N and SRC to their full fixed literal paths before invocation.
`-showcc` is supported by the pinned driver and retains the actual
clang compile/link argv; do not invent a second manual C build. Retain both
published OUTPUT.c and any compiler-retained scratch C. Explicit `-b c`
retains OUTPUT.c without `-keepc`; the older duplicate-copy allowance below
remains conservative for retained failures. Preserve all compiler outputs and
failed states. This initial GNU timeout invocation has actual status, log,
absence/retirement and size endpoints; it has no typed nativeguard cleanup or
continuous sampling claim.

Bootstrap uses a cleared environment with V, VEXE, VINIX_V_COMPILER and caller identities
set to HOST, both no-fallback markers set, empty VFLAGS/CFLAGS/CPPFLAGS/LDFLAGS,
CC set to the exact clang above, SDKROOT set to the canonical 26.5 SDK, and
DEVELOPER_DIR=/Library/Developer/CommandLineTools. HOME, VMODULES, V3CACHE,
XDG_CACHE_HOME, VTMP and TMPDIR all name private directories below N.
V1_FALLBACK_CACHE_DIR=T/fallback-forbidden remains absent. N/compile/policy.sb reuses
the main profile's fixed policy: deny network, reads from both baked compiler
trees, writes to frozen C/CA, writes to the full HOST toolchain and writes to
T/fallback-forbidden. No frozen 2f91 compiler is executed in this phase.
The control mode creates its own fresh N/policy.sb; bootstrap must not occupy
that filename.
The control mode uses the main profile's cleared runtime environment; the
controls invoke no compiler and write only their fixed new fixture paths.

The unchanged original complete HOST check runs before and after compilation,
with actual zero statuses, using the already pinned full HOST inventory.
Selected direct tools, canonical SDK metadata and the existing complete
326-header resource map must also compare before/after. Reuse qualified maps;
do not duplicate their large historical source inventories inside N. Compiler
and audit logs enter the 10 MiB row, with complete combined child output at
most 128 KiB. Every launch needs fresh 2 GiB admission; endpoints require
1 GiB. No automatic retry follows a refusal.

The proposed main-profile mode is `--rename-qualify`. It invokes the existing
`nativeguard.supervise` API exactly once, with this finite command:

```text
/usr/bin/sandbox-exec -f N/policy.sb
 N/bin/preserve-outputs-controls --controls N/controls
```

Use cwd=N, df_root=N, the existing full charged root list, N/native/child.log,
N/native/df, sample_ms=1000 and wall_ms=60000. The mode has a separate
90-second entry-through-PASS bound including source and receipt checks; it
does not change the 81-action consumer's 600-second wall. Set cap_bytes to the
lesser of the existing full-root 76 MiB producer projection and the full-root
projection with at most 10 MiB in N. The owner algorithm remains unchanged.
Require actual exit 0, observed private PGID, natural reap, empty group,
final_wait=-1, final_errno=ECHILD and zero cleanup kills. Check actual native
sample gaps, entry and final work against the same five-second rule. The
standalone controls start no children; all fixture operations are direct
filesystem calls in that one owned process.

Require the exact stdout `KERNEL OUTPUT RENAME CONTROLS PASS 14\n` and the
complete controls.json with fourteen cases, three repeat refusals, the real
second-rename EPERM and original owned-flag restoration evidence. These checks
use ordinary failure branches and remain active in the production build.
The optional second-device argument is omitted: the receipt must say real
cross-device admission is unavailable. No mount or unrelated device is probed.

The parent explicitly revised its internal consumer suballocation to 96 MiB,
with 80 MiB working and the full 16 MiB reserve. Four MiB of working space is
reserved for the Git transaction, leaving 76 MiB for producers. The kernel
ceiling remains 512 MiB with its existing 1 MiB final tail. This rename attempt occupies at
most 10 MiB inside that 80 MiB working allocation. The complete N namespace is
checked in both allocated and apparent bytes after its own final receipts;
the general endpoint must enforce this local limit whenever N exists before
the proof scanner excludes it. All old compiler copies, failures and other
consumer artifacts remain charged by the full root list.

| Rename category, including every failure | KiB |
| --- | ---: |
| Source identity receipts and conservative source/Git allowance | 128 |
| Two kept generated C copies, each at most 2 MiB | 4096 |
| Executable | 512 |
| Private compiler objects and transient scratch | 1024 |
| Fourteen fixtures, journals and complete evidence | 2048 |
| At most 72 native DF sets, three rounded 4 KiB files per set | 864 |
| Other metadata, selected input maps, logs and regular-file rounding | 512 |
| Namespace allowance, at most 192 directories at 4 KiB each | 768 |
| Unspent final receipt headroom within the row | 288 |
| Complete rename row | 10240 |

The retained freezer supplies sizing evidence: its C was 1,602,117 bytes,
binary 379,808 bytes and private third-party objects 448 KiB. These older
outputs do not qualify this helper. Their sizes support the new forecasts
with explicit allowance for two C copies and transient objects. Fourteen
base controls produce at most 44 journal rows; the bounded journals are also
retained inside their evidence. The 2 MiB fixture allowance includes these
duplicates, recursive identities, literal links, flag-restoration evidence
and regular-file rounding. A 60-second child has at most 62 initial/periodic/
final samples; ten more DF sets are reserved for phase endpoints. These are
admission forecasts and successful endpoint limits, not filesystem quotas.
The independent SRC copies and main owned sources are also included in the
parent's 6 MiB Source/Git row; the 128 KiB rename forecast remains conservative.

Before removing the previous 80 MiB copy-fallback projection, require strict
compilation, all applicable actual controls, exact source/compiled-C review
showing the sole output mutation is rename, unchanged frozen inputs and an
independent review of the new controller integration. This draft alone does
not authorize a kernel build, VM, cap increase or historical checker change.
