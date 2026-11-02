# Nonfatal broker thread samples and repeated check-in timeout

The existing JNI sampler emitted nine selected complete GMS broker thread
samples without a process diagnostic signal or a new build. Check-in still
times out and returns false. Seven selected samples precede method entry and
the two exported frame blocks follow the timeout; none overlaps the critical
request window. Their idle frames therefore identify no check-in stall, HTTP
result or framework defect. Google authentication remains unverified.

Baseline `ba6b79d58` and the [prior configuration probe](maps-preflight-config-runtime-2026-11-02.md)
identify the unchanged prepared image, SDK/native pair and Google APKs. The root
operator explicitly prefixed the controller command with
`VINIX_ANDROID_TRACE_THREADS=1`; ordinary `--trace-onboarding` only selects Maps
diagnostics. The admitted native bootstrap starts this existing service sampler
after ART creation, using a separate JNI environment, at most ten 30-second
samples. Actual deployed launcher/controller/broker source preserves the flag.
No framework/app patch, fixture, credentials, Next or trust bypass was involved.

Artifacts are under `S=/Users/alex/.local/state/vinix/android`: audit
`maps-preflight-threads-runtime-audit-2026-11-02-r1` (`A`), stopped guest
`maps-preflight-threads-vm-2026-11-02-r1` (`VM`), matching live controls, and
`gms-preadd-preflight-method-2026-11-02-r3` with matching controls. The latter
retains eight selected source classes/five passing guarded disassemblies.
Its dispatch/callback/transport boundaries establish no actual chosen worker
or HTTP result. Later r4 source work is separate from this closed bundle.

The immutable UART preserves selected BEGIN/END broker line ranges 22–74,
2090–2319, 2326–2544, 2576–2794, 2795–3013, 3014–3232, 3233–3451,
5051–5280 and 5281–5510. Only the two later samples were exported as public
class/method frames, with arbitrary thread names and source arguments removed.
They show Looper/queue/pool waits and Object.wait/aefp.run. Method entry at 4486,
callback registration at 4490, timeout at 4514 and result=false at 4530 are separate exact
tokens. One finite token projection contains no selected worker/HTTP/completion
prefix; absence from that selection proves no general absence or network health.

Actual controller receipt SHA-256 is
`33f76a526c52cc01efb648e793d81cec1bafb1d6d0242fd7c9572831818ac3fc`.
It runs 07:13:41–07:22:45 UTC, readiness true, status failed, GMS broker 45857
exit 1 before the later operator stop request. The later auth-pump failure is
stage=1/status=-1/pending=0; native service decision is phase=3/reason=5/status=1.
Drain EOF=true/status=1/319,584 bytes/errno=0 and two unknown-state cleanup
survivors are retained. This is not a user-stopped successful run, and the
earlier check-in timeout is not assigned as the cause of that later exit.

Unchanged strict account import passes 24 entries/2,835 chunks/1,451,105 bytes,
archive `eab520a369c384f49aed1c8dd1ecd976727751e392db1932ec1abaface170ed8`.
Linked snapshots agree with the stopped final UART. Detailed `A/validation.md`
hash is `15c7fbb93a34cbd3f43116196ee16817a540298a2b33533fa4dbf80c6b0c20d5`;
notes hash is `7ba39b1fd26dc6fca8d9546902d2fef9d2aa1e6cd3081c1a364ad8823fc2832b`.
Import took 302 ms at sampled RSS 28,721,152 bytes, both exits 0/cleanup complete
under original 600 MiB/300-second/64 MiB-growth/1 GiB-reserve/file caps.

Owned exclusive 12 GiB/four-CPU VM 70001 received one SIGTERM at 07:26:04;
the post-signal ownership race, absence, reconcile-stop returning 0 and gone.json
at 07:26:16 remain recorded.
No compiler ran during the guest. All nine new roots, including four clone
sidecars and the r3 audit pair, are closed. Complete seal and separate fresh
readback pass 505 typed entries, manifest
`S/maps-preflight-threads-runtime-sealed-2026-11-02-r1/sealed/manifest.json`:
`013ab67e848b27c11f9ee60e5df024d92b028269675a68bab026e3de62edcc1f`.
Seal/readback took 4.186/1.751 seconds, both exits 0/cleanup complete/zero swaps
under original 600 MiB/900-second/64 MiB-growth/1 GiB-reserve/file caps. Raw
private logs remain excluded except hashes/bounded projections. Keep earlier
complete bundles and unchanged auditors; integrity is not authentication.
