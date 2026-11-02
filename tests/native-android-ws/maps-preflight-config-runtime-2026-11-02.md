# Account worker configuration probe

This second credential-free probe repeats the check-in timeout and account
error. Its selected configuration warnings already occur before Maps sign-in;
the selected logs establish no new resolution failure or actual worker result.
No framework fix, network cause or successful authentication is claimed.

Baseline `5a02cdb82` and the exact pair/APKs/prepared image are unchanged; see the
[first diagnostic](maps-preflight-runtime-2026-11-02.md) for shared input proof.
No fixture, credentials, Next click, account creation or trust bypass was used.
Artifacts are under `S=/Users/alex/.local/state/vinix/android`: audit
`maps-preflight-runtime-audit-2026-11-02-r2` (`A`), stopped guest
`maps-preflight-vm-2026-11-02-r2` (`VM`), matching live controls (`E`), and
`gms-preadd-preflight-method-2026-11-02-r2` with its matching controls.

The UART preserves baseline 1,819 broker lines at 00:45:40 and 3,667 after sign-in
at 00:47:48. Both selections show the same config-read prefixes at private
765/775/795/853/983 and get-config prefix 985, all before the baseline count.
No selected service-start-failure template occurs. These finite selections do
not establish config validity, null resolution, scheduling or callback success.
`Checkin timed out` at 3131, result=false at 3147 and `RESULT_ERROR` at 3151 recur.
The three-class IntentOperation/aeac/aehl audit identifies config-first target
resolution without an immediate PackageManager query. Its note hash is
`621f359ccce856ca014e1289c74e4ceb12583626a3fa67052718737b1bbfbcc1`;
all three selected members pass readback. Original complete bundles remain.

The operator issued SIGQUIT (signal 3) to owned broker 1058 at 00:49:09 for a thread probe.
The preceding BusyBox `ps -p` command was unsupported; READY identity and the
kill command are retained. No thread-dump marker appeared in the selected
projection. The controller then records exit 131, status `failed`, finishing
00:49:12 after starting 00:44:28. This intervention prevents an unprompted-crash
claim. Its `auth_pump` failure list is empty; drain EOF=true, status=1, 182,532 bytes,
errno=0 and two unknown-state cleanup survivors are retained. Receipt SHA-256:
`0a4193ddc5f46796f3e727db34c7527a7db70fd9ef212fe8179cc17bdeef82f7`.

`E/early-launch-refusal.md` is the operator's record of a premature start at
00:43:15, CLI exit1/staged-media refusal and no VM. No standalone failure receipt
was created; this transcription is not machine timing proof. Original clone/
kernel guards passed in 6.421/38.482 seconds and the admitted fresh-launch artifacts
record VM 19321 at 00:43:54. No compiler ran during this exclusive
12 GiB/four-CPU guest. One SIGTERM at 00:50:46 led to a post-signal ownership race;
absence, reconcile-stop returning 0 and gone.json at 00:50:53 followed without another signal.

Unchanged strict import passed 24 entries/2,835 chunks/1,451,061 archive bytes, SHA-256
`e98dfc7c004c8c6ecb1982a3432c75d6c7b41fa60c4ddf5eec20dd6485f064a8`.
Linked snapshots and final UART agree. Detailed validation hash is
`5fee1d29e928daa5a0738911dd15baa5a7d0bb13d6bca9c39f55024a2ea5134c`;
notes hash is `a1c07a97d4afe20289155193fbabd7c03da641ccc3b7243e8705e0074b579d53`.
All nine new roots are closed. Complete seal and separate fresh readback pass
470 typed entries, manifest `S/maps-preflight-runtime-sealed-2026-11-02-r2/sealed/manifest.json`:
`77e53020d3e9aaa1545777ec654b00a9779608a0f9c8ae10eb3f12bf06bee36f`.
Seal/readback took 4.202/1.736 seconds, both exits 0/cleanup complete/zero swaps under original
600 MiB/900-second/64 MiB-growth/1 GiB-reserve/file caps. Raw private logs remain
excluded except hashes/bounded projections. Earlier evidence stays unchanged.
