Bounded native06 host supervision, 2026-10-26. The final production host build
and13 focused controls passed. No native06 target staging, image creation or
guest execution occurred. Native launch-options acceptance remains pending
under `native06-plan.md`; the failed historical guest attempts supply no
acceptance.

Source baseline is worktree revision
`6e6cf3bb68ed1dbdc08ccf5dda5194bfefd244f9` plus these maintained support paths.
The separate frozen production/guest prerequisites are identified in the plan
and were excluded from this support change. Source and executable bytes, rather
than this baseline revision alone, identify the host checks:

| Source relative to this directory | SHA-256 |
| --- | --- |
| `nativeguard/guard.v` | `c110210c813b62b735ce498db197f8af4582647f818e72ccdfd3729e4fd5f3a3` |
| `supervise.v` | `cd879181f0de1d4fee74a21e091e254bec590f68fef5d6d31d5aea8e37ede1ac` |
| `supervision-check.v` | `12918b84ac3c095615379f28bb73f808c696e541b00d334368a02ef8a48fa6e8` |
| `build-supervision.v` | `b781fd48ecc6f2c34ba265af0982ea2eb4818250bde42ac5557787e81d6ee2d1` |
| unchanged `diagnostics/recoveryguard/recoveryguard.v` | `85859c002c42ba44e944ca7b80d1894c27150669e89fa98bd0f4438ae5fa8517` |

The fixed supervisor admits only four exact native06 architecture/mode profiles.
It binds their wrappers, controller/retainer/checker, compiler, foreground
executables, source and process-spawn paths, and a whitelisted environment.
Those frozen paths use inherited groups without detached descendants. Each
child waits behind a pipe gate until the parent observes its own PGID; the
parent records that barrier before releasing the executable. Output is drained
with bounded nonblocking reads and complete raw log writes. SIGINT/SIGTERM/
SIGHUP remain sticky. The separately owned `df` helper has its own gate,
five-second deadline, output bound and actual cleanup receipt.

Both successful and refused children require actual positive-PID wait/reap,
a further wait yielding ECHILD, and process-group ESRCH. Group and direct
SIGKILL observations are retained; no signal result establishes cleanup. A
positive PID is never signalled after its leader has been reaped. Cleanup
retries are bounded to five seconds. PGID probes are trusted-host numeric
observations, without a guarantee against hostile identity reuse. Arbitrary
commands and detached-daemon profiles remain outside this admission.

The native profile samples direct `/bin/df -k` and allocated `st_blocks` every
second. Admission is at least2,202,010KiB available, the shared floor1GiB, and
the per-architecture namespace cap1GiB including sequential refusal controls.
An8MiB reserve bounds the final records; final df and allocation are checked
again after writing them. The outer deadline is30minutes for native and
20minutes for retention/refusals. Allocation follows no symlinks, checks the
filesystem, and counts sparse blocks rather than logical size. APFS shared or
hardlinked blocks may be counted twice. These are sampled bounds, not a
continuous-space or exclusive-physical-usage guarantee.

All host evidence is retained outside Git at:

```
/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a/native-supervision-host-01
```

| Artifact relative to that directory | SHA-256 |
| --- | --- |
| `build-supervision-10` | `eb9b006b1f1bfeb19269f5e9bbc35f94763fe215931e064d0a78feeee99a7348` |
| `supervise-07` | `a7b3e5b14ed762b81a2c5263601fa1cf062a4abfa7f5b223dc6fc1161db1df4c` |
| `supervise-07.build.json` | `dfdac130bd55efc63d08561564fc173901b1b11d84cc76440809087afa8a864b` |
| `supervision-check-06` | `7749815a18abaf6b15f195da167c9288070c812b4f8665672a857f1bf9881b10` |
| `supervision-check-06.build.json` | `88fd0fb65f3bc3ffa74442e7bad284048bd1c70416b9ba845c4b43a52a4439ab` |
| `controls-05.run.json` | `bcb46fd41f1bfdd887ea748516d89ace670b98181bc3cbf9cab2a84a1ccb1685` |
| `controls-05/results.json` | `f6de9e44c957dfc3bc3336830d6b9629c16d621423497769e887d21f5d303a10` |

Build/run receipts retain exact argv, source/tool hashes, logs, exit codes,
direct df observations and namespace sizes. `inspection.json` binds the final
bootstrap10 source, executable, working directory, TMPDIR, argv and empty
compile log; earlier inspection observations were superseded. The retained V
compiler is
`/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v`, SHA-256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`.
The builder uses `-prod -enable-globals -nocache` and a fixed module path for
the supervisor and controls. Its bootstrap uses the normal host compiler.
These runs use the default host collector; there is no ASan, allocation
tracking or manual-free host qualification.

The final invocation was
`build-supervision-10 --check supervision-check-06 supervise-07 05`, exit0.
It passed exactly13 control categories: actual direct-df cleanup; malformed/
other-volume/overflow df refusal; exact budget/deadline boundaries; actual
prelaunch-space refusal; actual prelaunch-allocation refusal; sparse and
external-symlink block accounting; ten fast literal-argument executions;
512KiB exact loud output; actual live-child deadline; actual256KiB write
against a64KiB cap; early leader exit with an observed live inherited-group
descendant and held pipe; actual parent SIGTERM with no final df helper; and
the real supervisor's arbitrary-mode refusal. All actual children have group
barrier/reap/absence records. The descendant receipt is atomically published.

The host namespace, including all failed attempts and scratch, occupied
33,173,504 allocated bytes after the final receipt, below the separately
authorized40MiB small-host cap. Final matrix direct df was62,197,208KiB before
and62,194,596KiB after, above the550MiB small-host admission/floor. The final
builder uses guarded pre/post df helpers and one-second monitored compile/
control samples with a64KiB receipt reserve. Bootstrap compilation itself has
explicit before/after observations, without a continuous guard claim.

Earlier compile and control failures remain intact. Matrix01 exposed an APFS
seek/write fixture that allocated the sparse file; `ftruncate` now produces
the intended logical8MiB file with zero allocated blocks. A compile was
correctly refused at the old20MiB cap; later explicit scope increases permitted
retaining all failures. Matrices02/03 refused an immediate group-kill error.
The accepted matrix04 observed group SIGKILL0, direct SIGKILL0, then group
SIGKILL-1/EPERM and direct SIGKILL0, followed by actual exit137, ECHILD and group
ESRCH. The child recorded uid=euid501 and PGID=PID. This establishes the syscall
ordering; a dying/zombie explanation remains unproven. Final matrix05 repeated
all13 controls with the final supervisor/builder. Bootstrap08's C-macro field
name compile failure is also preserved; no failed run is counted as acceptance.

Independent review covered the final four V sources and the actual matrix
receipts. Historical archive/checker gates, diagnostic siblings and external
referents remain untouched. No support command automatically deletes failed
native output or supplies a native qualification.
