# Fresh native wait fixture builds

The selectempty and maskwait fixtures now compile from current V sources on
both native architectures. State borrowed by signal handlers and the empty-wait
observer is explicitly allocated in each fork child's entry frame and passed
to the suite/storage helpers. The frame survives helper return, worker join,
result reporting and `_exit`; helpers initialize the entire State before
publishing its pointer. The generator no longer heap-promotes local State
values into unavailable `memdup` calls.

The empty-wait observer also now uses `i32` fields and matching C declarations
for `entered`/`done`. Previously, generated C loaded a shared 64-bit field into
a C-int temporary, performed an atomic operation on the temporary and wrote
the temporary back with a plain store. Both architectures now generate three
direct atomic loads and two direct atomic stores on the shared fields, with
the original sequentially consistent ordering. The join, observed-sleep and
ignored-signal handshake requirements are unchanged.

## Evidence

Fixture source baseline: `381c7cf0984f882f49d1cd327df52306da9036cb`, plus the
three retained fixture patches. The original sources fail fresh compilation
on both architectures at all three State-promotion sites. Original generated C,
compiler diagnostics, frozen source bytes and failure receipts are retained.

V 0.5.2 `f9ebca4` generates the fixed fixtures through the maintained generic
guest runner. Every fixture, assertion, case and storage loop is freshly
compiled; no retained probe ELF substitutes for these checks. The isolated
production kernels from the preceding [nfds/output qualification](linux-select-nfds.md)
are reused unchanged, with identical original/fixed kernel hashes and complete
build receipts. This is a fixture/tooling change; it does not qualify newer
unrelated kernel changes in the shared checkout.

| Fixture | AArch64 checks | x86-64 checks | Native failures | Same-ELF Linux failures |
| --- | ---: | ---: | ---: | ---: |
| Empty select waits | 2,176 | 2,752 | 0 | 0 |
| Masked-wait handler masks | 1,256 | 1,256 | 0 | 0 |

Both root and UID1000/GID2000 run the original contracts: raw/musl empty
select/pselect waits, observed indefinite sleep across an ignored signal,
handled EINTR, SA_RESTART, masks, guarded bitmaps and finite timeout controls;
and six mask-transition/wait controls, nested SA_NODEFER, action masks, saved
handler masks and restoration. Identical newly compiled musl ELFs pass against
Linux 6.12.51. No case counts, conditions or parser expectations are relaxed.

The empty-wait storage loops warm 64 cycles and then execute 200 interrupted
waits per cohort. Every live slab class, large-page count and allocator taint
stays flat. AArch64 large pages are 87/87 for each cohort; x86-64 is 218/218.

Complete generated-C comparison limits differences to State storage,
helper signatures/calls, the explicit allocator header, the two atomic field
widths and the affected observer code. Check/print/worker-create/join counts
remain unchanged. Four positive generated-C controls and 18 mutation controls
verify stack storage, direct atomic addresses, worker joins and scope. Existing
empty-select parser controls pass 4 positive/6,072 negative cases; additional
masked-wait controls pass 4 positive/794 negative cases. Independent lifetime
and atomic-access review passes on both final generated C files.

## Reproduction and archive

Run `tests/linux-compat/run.v --cases selectempty,maskwait` with the normal
architecture, isolated kernel and fresh state-directory arguments. The existing
`selectempty-reference.v` and `maskwait-reference.v` controllers accept these
fresh `init` binaries for the Linux comparisons. Existing historical checkers
and archived failure profiles remain unchanged.

The external complete bundle is `/Users/alex/.cache/vx-ws-1114/bundle`. It
contains original failures, fresh native images/ELFs/generated C, Linux
kernels/initramfs/launchers, source snapshots, kernel build receipts, review
notes and serial output. Its 273-file manifest has SHA-256
`36c0ed80f60b7574a9148c6ec20ef49ca8ffb8c6a96ff5f3889eff051e8bf2a7`.

Build `waitfixture-evidence.v` without `-prod`, using `-cc cc -cflags -O2`, then
run its `self-test`, `generated CASE BEFORE-C AFTER-C` and `BUNDLE` modes. The
auditor requires both original failures and all four fresh native/Linux case
pairs; it rejects missing artifacts or replacement binaries.

This closes the fresh-fixture build blocker recorded by the preceding
checkpoint. Broader §15 semantics, installation/integration and translated
runtime gates remain open.
