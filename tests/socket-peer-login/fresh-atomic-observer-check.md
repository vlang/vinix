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
