# Current evidence checker host build

The current-profile evidence checker compiled successfully with the qualified
wait-status overlay and existing bounded consumer owner. This is a **host build
result only**. All 89 evidence-control executions remain unrun; they require
positive native evidence. No import, public API, guest or final supervisor
acceptance is established.

The repository revision before this report was
`b8eadb0a8ef4624c1db3deb5ba154bb759f24310`. Complete evidence remains at
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/native-consumer-tools-01`.
The exact checker source was prepared in the preceding source-only phase:
only three expected refusal messages changed; the 69 plus 20 case bodies did not.

`evidence-check-01.argv.json` retains the literal production, no-cache, keep-C
compile with clang. Its diagnostic flags are
`-Werror=incompatible-pointer-types -Wno-error=incompatible-pointer-types-discards-qualifiers`.
The compiler log contains ordinary unused/shadow notices. The build receipt and
exit file report actual compiler exit 0. No separate persisted parent-observer
exit file is claimed.

The real child PID and observed PGID were both 26450, under UID/EUID 501.
Barrier, cleanup and monitor receipts agree on exit 0, reaped leader, absent
group, final wait -1/ECHILD 10 and zero kill attempts. All 21 sampled df helpers
also exited 0 and were reaped with absent groups and ECHILD. The largest sample
gap was 1,082,925,167 ns, peak sampled allocation was 37,990,400 bytes, and minimum
sampled free space was 26,125,340,672 bytes. The completed consumer allocation was
34,557,952 bytes (32.95703125 MiB), within the unchanged 40 MiB bound.

The five complete imported-module source maps match before and after. The owner
also compares its complete compiler input map in a deferred check; it does not
write separate compiler-before/after manifest JSON. The completed frozen-tool
postcheck reports unchanged metadata, paths, contents and links. Independent
review checked the actual argv, build, exit, barrier, cleanup, compiler log,
module comparison and frozen postcheck receipts.

| Artifact relative to the consumer root | SHA-256 |
| --- | --- |
| Private checker and captured prepared source | `dd67796f3273fec73730d6c41957d5ebb5eea1c68942daed29d3ffc62377b921` |
| `evidence-check-01` (687,408 bytes) | `ce1fa4ed606b1dba977b91f0e6c5ae6a540a3daea1f4bc976150584051c0dae9` |
| `evidence-check-01.build.json` | `f479ea563a4d37b0aabf940ead7805bf3d0efb947d4f3136ed92214830d94ccc` |
| `evidence-check-01.argv.json` | `5bca2f80748cd89ebc97605202de2bdba12e928f8f400cbe2b0bc62842e8be31` |
| `evidence-check-01.log` | `7c2cf278bd0ab45bff2fb363bc978a42ba8218b6ef5de5a9dc33c60062343571` |
| `evidence-check-01.exit.json` | `e81bc160c0843ee56f31f12997bb3aff50528d596002d4866676cb8a1b19195a` |
| `evidence-check-01.monitor/result.json` | `f2ec1c7e05085984a410f7d6bee9ab2b991f61e3bccd13d89ddabd675ff44295` |
| Both module maps | `710351295e1be60a49b75f84348493ee85cf1f0777991a8b457ac3f4b83201d4` |
| Retained generated C (1,730,376 bytes) | `622ffc635d63294aa0a2a2798fb36747b81ab4d7f818e878e6aebc7d59d173c1` |

The generated C is retained at
`scratch/evidence-check-01.26450.14700509250.4545687536.tmp.c`.
`current-evidence-bootstrap-01/frozen-after-build.log` retains the completed
frozen-root PASS marker. Historical tools, failed attempts and source captures
remain preserved. The next consumer compilation is held because the complete
retained-C and final-control forecast does not fit the existing admission budget.
