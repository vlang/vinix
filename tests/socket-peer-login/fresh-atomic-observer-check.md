# Fresh atomic native observer host check

The fixed V observer passed its 30 host controls on 2026-10-27. This qualifies
the observer's host policy and lifecycle checks; fresh kernel build03 remains
pending separate review. The production kernel source base is
`9acefa77bee69247c837e97987a2377536aa41cc`; no kernel source changed here.

The complete external state is
`/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026/native-observer-01`.
The adjacent `native-observer-plan-01.json` and `native-observer-plan-02.json`
retain literal argv, cleared environment and source/tool pins. Plan02 SHA256 is
`e97a9182d797db298f2a6e951b45ebcfeb9a95d27b0103129ea62175598250de`.

Bootstrap01 refused unsupported V array addition and a mutable primitive
parameter before C compilation. Its log and source maps remain intact.
Bootstrap02 uses array append and a mutable counter struct with the same policy;
it returned actual exit0 with matching source maps before and after compilation
and controls. Its private generated C, compiler state, log and binary remain in
`bootstrap-02`. SHA256 pins are:

- Observer source: `355f4a710f7238d1659e719814810e6e266ed977da089c18123b9147f16d65c3`.
- Binary: `55e20a38c3145a27d404fd1513fa8a32b168e110bad1552c91366cf4d41cd4d1`.
- Generated C: `c0bf05a3c372ea83caabc396e69a42c7467af2bcb3e3031cc792beb8d9d8fe50`.
- `controls-01/controls.json`: `88eeba8823b56d5a4a237c4f5427a98a8a67bce4da8b5551be91bdc3d84067c0`.
- `controls-01/status.json`: `ce6484a4f231d407d94afa49eddaeae690dcc669b04f05e359df2ad818c8aa8e`.
- `controls-01/observations.jsonl`: `56e1715d0d4d04f349b963c0dcb7610806aa7aed41cff93dde5b0e763d19e940`.

The controls returned actual exit0 and `PASS 30`. They cover malformed probe
output, resource/time boundaries, transient and persistent probe failures, raw
streams, native sampling, a quiet deadline, fast-exit log flooding, independent
status retention after journal refusal, and cooperative nested ownership. The
main native watch recorded five samples, maximum gap 1006ms and maximum sample
duration 659ms. Quiet and flood cases retained their expected refusal receipts.
Direct and nested checks actually observed `waitpid=-1/ECHILD` and original
process-group probe `-1/ESRCH`; nested cleanup requires its own receipt. These
checks do not establish cleanup for arbitrary descendants or missing controller
receipts.

The observer charges allocated and apparent bytes across the fixed donor,
worktree, raw state and seal roots without following symlinks. Its inclusive
512MiB ceiling reserves 1MiB for its own output tail; admission/live free-space
floors are 2GiB/1GiB. Native sample starts and durations must stay within 5s,
including final samples. The expected full-phase projection is 504884KiB,
rather than a worst-case guarantee; observed policy breaches refuse the phase.
After controls the combined roots measured 241796KiB allocated/266734KiB
apparent, with 7849868KiB free. Observer state used 3592KiB allocated/3499KiB
apparent, inside its 12MiB allowance. Scoped `pgrep` returned 1 with no matches.

Bootstrap used direct `gtimeout` with admission and completion measurements
only. No continuous bootstrap sampling, sole-reap or descendant-cleanup claim
is made. Earlier tool-loop build01/build02 refusals and all original refused
bundles remain preserved; no fresh kernel qualification, seal or guest result
is claimed by this report.

The approved build03 invocation subsequently returned actual exit1 during its
initial native admission sample: free space had fallen to 1664132KiB against
the unchanged 2097152KiB floor. The controller never started; build03 and all
worktree kernel output directories remained absent. The sample charged
241824KiB allocated/266755KiB apparent and retained its raw probes in
`run-01/observations.jsonl`, SHA256
`94c9ca8e3c68a48b10a64036650a934a13aa25d9e4e76e6461898c5347fd6606`.
The external `build-03-outer-status.json` SHA256 is
`a91a80f762607ac44d9c210a517e1ee12199577d4978d2a82444e58ab2f55a14`.
Initial admission precedes the native command-status writer, so no native
`run-01/status.json` was produced. The external status records that limitation,
actual refusal and no-controller scope. Source maps matched after return and
scoped `pgrep` returned1. The consumed run01 is preserved; execution remains
held pending capacity and review of a fresh fixed route.

## Fresh retry and audit routes, 2026-11-04

The fixed `--build-03-retry02` route preserves consumed run01 and uses fresh
run02 with the same guarded controller and budgets. Closed `--seal-01` and
`--check-01` modes invoke the unchanged original complete-state auditor. Their
journals, logs, probes, module/cache/temp paths and new bootstrap state stay
under the adjacent `matched-peer-frame-atomic-fresh-20261026-seal-01` directory
(S), outside frozen raw state (R). All four roots remain charged together.

The source base is `8ebc4454a3cf4c049432df590d31ff5d15a4b464`. The reviewed
source SHA256 is
`a473233234928cc68a5a6d87e432c2dc34ff5ecb6d5037dfe9bd1cc4e181a006`.
S retains literal plans03/04, source/tool maps and every attempt. Bootstrap03
returned actual1 at strict C compilation: V emitted a `Watch**` ordering
snapshot for the later inline grace expression. Bootstrap04 hoists the same
0/10-second grace into a local, preserves the strict pointer warning and returns
actual0. Its generated call passes the `Watch*` context correctly. Plan04 SHA256
is `6f00d0cb87852705934c87b12dc2222cdd7047725bc497a4b0d11619f920630b`.
The executed cleared environment has 19 keys; historical plan prose saying
18 was a count error, and its literal bindings remain preserved.

Bootstrap04 binary SHA256 is
`0e4a23a4299087c43782c8a2a50e1e07b5ff2d7c5478d72577913cbf63ca1c14`;
generated C is
`ebdb619765554fd435d7de1eb2ce313d5ea8cb7553acf2bc00fd38dd061c283a`.
Fresh S `native-controls-02` returned actual0 and `PASS 61`: the original30
cases run at the fresh closed route, followed by31 controls for retry/audit
routes, S environments, exact argv/markers, pinned-input mutation and symlink
refusal, freshness, provisional status and separate wall/final-sample deadlines.
Its main native watch recorded five samples, maximum gap1008ms and duration485ms.
Quiet-deadline and fast-exit flood refusals retain their independent status.
Direct and separately owned nested groups actually observed ECHILD/ESRCH;
the nested worker's distinct PID/PGID is41322 and outer controller is41321.

Controls receipt SHA256 pins are:

- `controls.json`: `d5bac4af5d8eaaf5a4da5dfe3e2dd1cf902ffb6a2b74bc264da3d5bcdbea8282`.
- `status.json`: `785802563a1e670d874fcc52448836a1c57c0a69c48eea7fa02cce38a6d563b0`.
- `observations.jsonl`: `bf22f7c349abbd3aecc62b169745d599977611f934a8a7d70a44cd895ea9dbb0`.

Source/tool maps matched after bootstrap and controls; scoped `pgrep` returned1.
Completed roots measured116000KiB allocated/272098KiB apparent with9893232KiB
free. The updated expected projection including failed03 is510255KiB, below
the unchanged523264KiB measured ceiling within512MiB; this remains an expected
size, not a worst-case guarantee. Direct bootstrap has only admission/completion
observations and supplies no continuous-sampling or process-cleanup claim.

Audit PASS requires an external actual0, the exact original marker and native
observer PASS, with the 600/300-second deadline and final observation gap checked
after provisional status writing and again after original marker/input checks.
Refused cleanup can exceed its deadline and remains refused. These host controls
do not claim a fresh kernel build, full raw audit or guest qualification.

## Fresh build03 and original complete audits

The fixed retry02 subsequently returned actual0 for both architecture builds
and the native observer. The kernel source base remains
`9acefa77bee69247c837e97987a2377536aa41cc`. Source, compiler, module and seven kernel-input maps
matched before and after. The unchanged controller retained its complete
input inventories, generated-C checks (18 frame and 29 peer mutations per
architecture), ELF/symbol checks and each make group's successful cleanup.
Its qualification SHA256 is
`c0e3942385c75abb45bb24615f35a6bd154fc54fd12ca88a8e21bf3189c7b4b5`.
The retained `build-03` ELF pins are:

- x86_64: `2a7973b2dcb21c7b40aa4fb0fd1de6c9c29c8c6c246a4353445f5698b5150eac`.
- AArch64: `a9d79c09a0d575facafc23b2f65be8e94ffa423cb92e183b5d4c73719f13a469`.

The native build watch recorded306 samples, maximum gap1016ms and sample786ms,
with peak430922KiB apparent and285768KiB allocated, and minimum7863492KiB free.
Its direct leader83083 and both separately owned make groups have their own
completed cleanup observations. Worktree outputs were moved into retained
state and remain absent from the worktree. S retains the final actual status
and freeze receipt as `native-build-03-retry02-outer-status.json`, SHA256
`fd37e64fd5427374282916be19784d6bd16e520e5d4c310386c23fad39a6ef74`.
All owned writers to R have exited; subsequent owner state stays in S.

The original complete sealer then returned actual0 through the native600s
owner, followed by a separate original check returning actual0 through its
native300s owner. Both exact original and observer markers, final wall/tail
guards and unchanged checker/source pins pass. The complete manifest is
S `complete/inventory.json` (2930169 bytes), SHA256
`e82671ca13c4d46b18d1d9762d661f4f392be0ee888d0fb20d1de21f540c54f0`.
Seal sampling recorded124 samples/max gap1018ms/sample908ms; the separate
check recorded32 samples/max gap1012ms/sample694ms. Each direct leader has
actual ECHILD/ESRCH observations and independent raw status/journal receipts.

Root's independently executed original check remains required before retained
consumers. The first derived independent-owner profile compiled successfully
but its fresh controls03 refused at the quiet-control expectation: admission
and phase clocks were misaligned, so a valid sample-window refusal preceded
the expected wall message. Its complete failed state is preserved in S;
it supplies no independent-check qualification. Original build/seal/check
results remain scoped as above. Guest/runtime/performance gates and production
kernel integration remain open; no historical refused bundle is restored.
