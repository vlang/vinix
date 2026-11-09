# Native epoll control and creation integer words

Epoll_ctl now decodes epfd, op and fd from the signed low 32 bits of each
register. Epoll_create1 applies the same conversion to flags, and the x86 legacy
epoll_create adapter decodes size before checking that it is positive. Event
pointers remain full-width. Allocation, ownership and registration code is
unchanged. See [Linux's syscall declarations](https://github.com/torvalds/linux/blob/v6.12/fs/eventpoll.c).

The V `epollctlwordsfixture` runs static musl ELFs unchanged on Linux 6.12.51
and native production kernels. Root and UID1000/GID2000 cohorts use canonical/
sign-extended words, zero extension and upper words 1, 0x7fffffff, 0x80000000
and 0xffffffff. Control trials decorate one integer argument at a time.

ADD/MOD/DEL cover pipes, a duplicate at fd 70 or above, O_PATH, regular files,
self and missing descriptors, with original/duplicate epoll descriptors. Valid
operations use readable and unreadable event inputs; DEL must ignore its event
pointer. Unknown operations use readable input. Tests check exact errors,
unchanged event inputs, retained/replaced/removed one-shot payloads, pipe data,
status/descriptor flags, regular-file cursors and final registration cleanup.

Creation trials cover valid/invalid lower-word flags, CLOEXEC, signed boundary
sizes and legacy positive/zero/negative sizes. Every successful descriptor is
queried, used to register/receive/remove an event, closed and checked for EBADF.
Unexpected successful baseline creations are also closed.

All 10,440 ARM and 10,872 x86 checks pass on the candidate and final Linux
runs. Matched originals fail exactly 688 and 764. Initial full probes expose
the separate unknown-operation/unreadable-event precedence gap: Linux imports
every operation except DEL, while the original Vinix code imports ADD/MOD only.
Those initial sources and failed Linux logs are retained. That combination is
outside this integer-word qualification.

Two hundred warmed native cohorts per credential group exercise decorated
control calls, transient aliases and successful creation/close cycles. All
18 ARM / 14 x86 live slab classes stay flat; large pages remain 68/68 and
177/177 respectively, with zero write-after-free counters.

Maintained replays cover wait integer words, output ranges, event-count bounds,
negative timeouts, O_PATH/ordinary-file epoll refusals, asynchronous notifications
and masked waits on both architectures. A standalone ARM replay uses the same
probe ELF. Its initial transcript lost a case through interleaved random-reseed
output and was rejected; the original log and fresh replay are retained. The
first ARM baseline stopped in UEFI; a fresh boot of the same kernel supplied
the complete baseline results.

Isolated kernel worktrees start at `d87acd209`; only integer decoding changes
in `kernel/file/epoll.v` and `kernel/syscall/table/linux_table_amd64.v`. Other
sessions' pending edits are excluded. Production builds use private V
`0.5.2 395d574`, LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42. ARM uses 16 KiB
pages with HVF; x86 uses 4 KiB pages with TCG. Baseline kernels and their complete
preceding receipts remain under `epollwords-20261109`.

The external bundle is:

`/Users/alex/.cache/vinix-linux-compat/epollctlwords-20261109`

It preserves source snapshots/worktrees, generated C, probe/kernel ELFs,
compiler/build receipts, boot images, raw logs and failed attempts. Final
compilations and native/reference/baseline runs use `*-{arm,x86}-r2`; builds
are `build-{arm,x86}` and replays are `regression-*-{arm,x86}`. The standalone
receipt is `standalone-arm-r2`.

`epollctlwords-evidence.v BUNDLE` verifies complete manifests, recorded input/
output hashes, probe/kernel identities, baseline failures, flat storage and
maintained replays. The parser passes six positive and 834 sampled rejection
controls. Historical checkers are unchanged; restore the original complete
bundle and its referenced dependencies before auditing. The auditor writes
`epollctlwords-artifacts.json` beside the receipts. The complete audit passes
both architectures, including all eight maintained suites. Manifest SHA-256:

`15b62388513583ebc99079f79ac48288eff0efa1d10fdfabb037cb60995f0967`

For fresh native runs, compile `run-epollctlwords.v` with native guest tool
modules on V's module path, then supply `--arch`, `--kernel-dir`, a fresh external
`--state-dir`, and optionally `--init PROBE-ELF`. The reference controller accepts
the identical probe, a Linux kernel and optional launcher; `--self-test` exercises
the parser.

Unknown-operation import precedence, canonical output-copy faults and their
one-shot effects, concurrent close/reuse, GNU libc, cancellation and foreign/
32-bit paths remain separate. Section 15's broad compatibility gates remain open.
