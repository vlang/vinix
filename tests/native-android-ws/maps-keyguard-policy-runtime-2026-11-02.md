# Keyguard-policy ARM pass and broadcast-overload linkage failure

The signed keyguard-policy regression **passed on ARM**. GMS advances beyond
the previous missing policy query, then exits after an uncaught missing
`Context.sendBroadcast(Intent,String)V` overload. No manual Maps launch,
Sign in, credentials or imagery check occurred; current map rendering and
authentication remain unverified.

Core `0a6d6d564`, producer `d8b6cf50b`, fixture `775607ca3`, delivery `9397257d7`,
[SDK/native pair](keyguard-policy-pair-2026-11-02.md) `0e4b72c43` and
[media profile](maps-keyguard-policy-stage.md) `1d2a4cab5` are committed.
The sole new DPM method returns zero disabled-feature bits for the absent
backend; all ten retained methods and all 70 native-consumed classes remain
unchanged. Prepared image manifest is
`2732a540e40cb95b944eee58ee17c18dc5c20d4fa7909960c19a9d724c1576de`.
Preparation passed in 283.725 seconds at 90,767,360 bytes sampled RSS; clone and
frozen-kernel installation passed before boot, under the original limits.

Complete evidence remains below `/Users/alex/.local/state/vinix/android`:
`maps-keyguard-policy-runtime-audit-2026-11-02-r1` (`A`), matching live controls,
prepared `maps-keyguard-policy-r1`, stopped
`maps-keyguard-policy-vm-2026-11-02-r1` with clone sidecars, and
`keyguard-policy-api-transfer-live-2026-11-02-r1`. `A/runtime-result.md` closes
the pending operator checkpoint without changing original notes or validation.
Historical complete bundles and original auditors remain required.

Unused UID/GID 10145, fresh output and protected read-only runtime were verified.
Child 36728 exited zero with six exact input identities and eleven unchanged
checks. Runtime receipt SHA-256 is
`31aa085577ed2f6b6223a1eb05e6284f876d7e327b67c61563d92620bb3197c5`.
The complete 9,656-byte, 108-line child hashes to
`9fd0ff1152a4847925a650ad1be75e2bbee74ba49ad675945bfaafffbb687d6c`:
one full PASS at 93, readiness at 102 and normal teardown through 108.
Independent `A/fixture-validation.md` hashes to
`05007dd6ecc81ccf578bd68cb2961356e35cad0919c23aa92e2b1d89ae104318`.
It confirms public-int reflection, real cached DPM lookup, null/actual admin
arguments, zero bits, preserved ComponentName state and unmanaged-device
controls. The same loaded Main executes the zero-mask branch before its dormant
missing trust-configuration call; no trust-agent or nonzero continuation is
qualified. No platform APK stub, fabricated policy or health whitelist was
supplied. Unchanged zero-removal diagnostic import preserved 31 chunks of the
15,642-byte fixture archive, without new strict fixture-protocol qualification.

After releasing the fixture mount, the GMS controller ran from 15:40:07 to
15:41:00 UTC. Receipt
`fb583f06e0483ed6639dc08a9437a82cec4ab73c12e47610b6357ac39ba79581`
records broker 58654, service readiness true, failed/exit 1, drain EOF true,
status 1, 296,912 captured bytes, errno zero and zero cleanup survivors.
The new uncaught NoSuchMethodError reaches `bohg.b` source 38 → `bohg.a` 463 →
`bnyi.b` 150 → `bnyh.apply` 14 → `bptb.t` 12 →
`PeriodicConsentChecker.onHandleIntent` 285. GMS then calls System.exit(10),
recording native VM status 10. Readiness alone does not establish successful
startup or Google authentication.

Guest input stayed idle through automatic export END before the separate manual
private-log export. This run's immutable `after-maps/interval.log` contains both
outputs, SHA-256
`ec3980985bb1875d26eb6966c7d971beefcb1547e21b8f40652d86ba3e77d5d4`.
The unchanged strict collector passed against that complete interval before VM
stop: 21 entries, 2,831 chunks, 1,449,110 bytes, archive
`45047073a865f4a47d4ce5088c39c6cbb80fd3b0329e628f9742e4f22f52eada`.
Both import exits are zero with complete cleanup, 287 ms elapsed and 32,456,704
bytes sampled RSS. The full exact private broker log is separately retained at
`A/broker-log-diagnostic/child.log`, 296,912 bytes, SHA-256
`2cebdacdd8230606e0bc7557e7cad47cdee22008c40252e91da25a3fe4946452`.
The existing guest-pinned canonical-base64 decoder and separate fresh readback
passed using the same interval. No after-private-log snapshot, UART repair or
collector change was needed. Private logs remain outside the strict archive
apart from hashes. Failure cleanup removed the live broker session required by
the supported desktop Maps launcher.

Owned exclusive 12 GiB/four-CPU VM 68724 started at 15:36:44 UTC and stopped
cleanly with one SIGTERM at 15:42:51. Stop/gone receipts, QEMU signal 15 and an
independent empty exit-1 ps query confirm absence. No compiler or Java ran while
it was live. Final UART equals the immutable after-maps full snapshot, both
SHA-256 `18ae37fb8b0f36ab90574dc4aeb74235179337eac420fe1b36e0fb628aa63b05`.
Image and import checks retained their original resource limits. The nine-root
complete evidence seal and separate fresh-process readback passed all 665 entries.
The manifest at `maps-keyguard-policy-runtime-sealed-2026-11-02-r1/sealed/manifest.json`
hashes to `8ee2ce3467bae3910f74268e7cc07c8c4c04e843de1f7dd8d3504f29a74a595c`.
Both guard/child exits are zero with complete cleanup under the original
600 MiB RSS, 900-second, 64 MiB shared-growth and 1 GiB reserve limits.
