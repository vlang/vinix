# Atomic peer-login native runtime qualification

The maintained V controller and PID 1 fixture qualify repeated connect,
failed-retry, peer-close and 32-round concurrent-connect tuple behavior on the
fresh AArch64 and x86_64 kernel ELFs. Both guests exited naturally with status 0
and emitted each of the four required markers once. This does not qualify
cross-login provenance, performance or production integration.

The kernel source revision is `9acefa77bee69247c837e97987a2377536aa41cc`,
with patch SHA-256 `c1891d5ffe3823d9d7bfe9b3b47ba14fab590f8e8e12f2afb0d47b28cc2bb5f6`.
The full original manifest SHA-256 is
`e82671ca13c4d46b18d1d9762d661f4f392be0ee888d0fb20d1de21f540c54f0`;
its reviewed length is exactly 2,930,169 bytes. The original complete checker,
source and manifest are pinned and remain required before and after every run.

Raw evidence remains outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/peer-login-atomic-runtime-20261026`.
The qualified execution is `attempt-02`, using `fresh-runtime-plan-04.json`;
the controller bootstrap is `bootstrap-05`. Earlier refusals and their complete
partial output remain preserved and refused. `attempt-01` stopped before any
guest boot because its generated init argv was `u8**`. The explicit `&char`
annotation fixes both target builds without disabling the strict pointer check.

Validation:

- Production host controller: pinned V `ff75a301…c4c5`, `-prod -nocache`, clang 23
  with incompatible-pointer diagnostics treated as errors. Controller source
  SHA-256 `150c50ecb705d9db1b43ab6acf1b5982972defd56cd8b25fbd97d8a7289ca399`;
  binary `f442f7a16026b1427cf10799ac3aa3cb78c599d926c722b39edba6052d8e1514`.
- Target fixtures: V `-nocache -os linux -arch arm64|amd64 -gc none`,
  `no_backtrace` and `no_segfault_handler`; no target V `-prod`. Static musl GCC
  `-O1 -Werror=incompatible-pointer-types`, followed by ELF64 architecture and
  no-INTERP/no-NEEDED admission, passed for both programs on both architectures.
  Generated C confirms fixed `char*` vectors are constructed before `fork`.
- Both complete original audits returned actual 0 with the exact marker.
  Complete before/after input maps matched byte-for-byte: 6,019,604 bytes each,
  SHA-256 `6aecaef500b8f6a049c8e45fa891516811a96cbbc02f69b34cc063ece8daa53e`.
  The maps include tool/loader closure, fixed sources, sysroots, firmware,
  kernels and selected native ARM64/ARM64e headers. The unchanged closure
  helper retains its original limits; unfamiliar or changing headers refuse.
- Host cases passed: 15 budget, 12 timing, three exact manifest-length,
  15 native-header and six guest-root loader cases; actual status, pipe cap,
  timeout, TERM-ignoring descendant, sole-reap and absent-group controls.
- Runtime observation retained 100 samples, maximum actual start gap 1,024 ms
  and measurement/journal window 150 ms, within the unchanged 5 s bounds.
  The inclusive phase/worktree cap is 512 MiB with 400 MiB projected body and
  2 GiB admission/1 GiB live free-space floors. The global 1,800 s guard includes
  final result writing; the external timeout is 1,860 s. Guests run sequentially
  in one reserved slot, each with a 240 s/8 MiB command bound.

`attempt-02/result.json` SHA-256 is
`bbc5a22d302fc0140716a13a8d5306bd22be5f1cfd4bbfb9e7023e06db58d3e9`.
The external actual-exit receipt is
`bootstrap-05/attempt-02-outer-status.json`, SHA-256
`e0ea7b47e1bb704da2096b6e487486e71dde69b53705c80f9363180cb4e11e30`.
It records actual outer status 0, exact final PASS, both guest statuses and log
hashes, the complete input comparison and source/tool pin comparison. The whole
runtime directory has not been sealed; these are scoped execution receipts.
