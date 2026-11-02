# Autofill query ARM pass and keyguard-policy linkage failure

The signed autofill-service regression **passed on ARM**. GMS no longer reports
the previous missing AutofillManager component query, but its next uncaught
failure is missing `DevicePolicyManager.getKeyguardDisabledFeatures(ComponentName)I`.
No manual Maps launch, Sign in, credentials or imagery test occurred; current
Maps rendering and authentication remain unverified.

Core `eff7b719a`, producer `4fb48d93d`, fixture `c58ed4fc0`, delivery `427e3b7b3`,
[SDK/native pair](autofill-service-pair-2026-11-02.md) `6c0f1b3d2` and
[media profile](maps-autofill-service-stage.md) `def8812a8` are committed.
The sole new AutofillManager query returns null for the absent backend; all
seven retained methods, AutofillValue behavior and 70 native-consumed classes
stay unchanged. Prepared image manifest is
`07771e1494d1ef834246c2d9c5f919af1c39043c75086af9e3a218e8e2fc8661`.
Preparation passed in 276.583 seconds at 87,474,176 bytes sampled RSS; clone and
frozen-kernel installation then passed before boot, under original limits.

Complete evidence remains below `/Users/alex/.local/state/vinix/android`:
`maps-autofill-service-runtime-audit-2026-11-02-r1` (`A`), matching live controls,
prepared `maps-autofill-service-r1`, stopped
`maps-autofill-service-vm-2026-11-02-r1` with clone sidecars, and
`autofill-service-api-transfer-live-2026-11-02-r1`. `A/runtime-result.md` closes
the historical pending operator checkpoint; original notes and independent
fixture validation remain unchanged. Complete historical bundles and original
auditors remain required.

Unused UID/GID 10144, fresh output and protected read-only runtime were verified.
Child 40300 exited zero with six exact input identities and eleven unchanged
checks. Runtime receipt SHA-256 is
`6d14ca64d0aea1c45e61a33d1e35ffba110cef7f88b4dd7be3a3965afd01f1c2`.
The complete 10,375-byte, 126-line child hashes to
`c0a34471c4e8d0713efdf95f10ffd682a29cdf1f82b6d9451f3a6847d7c3401f`:
one full PASS at 111, readiness at 120 and normal teardown through 126.
Independent `A/fixture-validation.md` hashes to
`337e078400d6e1b198a6c904e435a4fd45aff70318028d05eca985c839c43d1e`.
It confirms public component-query reflection, real null-result branches,
notifications/callbacks, ordinary AutofillValue controls and repeated
Activity/application probes while retaining the guarded ComponentName
continuation. No enabled provider, platform APK stub or health whitelist was
supplied. Unchanged zero-removal diagnostic import preserved all 33 chunks of
the 16,635-byte fixture archive; no new strict fixture-protocol claim is made.

After releasing the fixture mount, the GMS controller ran from 15:13:17 to
15:14:11 UTC. Receipt
`ba6f72132dd7d453dd68869b503452e605336af96b9ef028694b1ae29720fad2`
records broker 49328, service readiness true, failed/exit 1, drain EOF true,
status 1, 272,189 captured bytes, errno zero and zero cleanup survivors.
The new NoSuchMethodError cause reaches `fgup.b` source 26 → `fgup.a` source 15 →
`fhbx.a/e/h/g/d` →
`com.google.android.gms.trustlet.onbody.internal.ModuleInitializationIntentOperation`
constructor source 8. The enclosing exception reaches the uncaught handler;
GMS then calls killProcess and System.exit(0). Native VM status zero does not
establish successful startup: the account broker records input disconnected
and the controller fails with exit 1.

The automatic account export completed while guest input remained idle. Before
stopping the VM, the unchanged strict collector passed 21 entries, 2,831 chunks
and 1,449,127 bytes, archive
`a242176c662f052bca34cd017537ba7e36e184b88509b8ad092a0afa103e9043`.
Both import exits are zero with complete cleanup, 284 ms elapsed and 28,082,176
bytes sampled RSS. The separate full exact broker log,
`A/broker-log-diagnostic/child.log`, is 272,189 bytes with SHA-256
`77d4c2aaa823e6d36bf472f191641deb90c2d63eca49a17b1b47a63b63e6b211`.
The existing guest-pinned canonical-base64 decoder and fresh readback passed;
original UART and payload bytes remain unchanged. Private logs stay outside the
strict archive except their hashes. Broker failure removed the live session
required by the supported desktop Maps launcher.

Owned exclusive 12 GiB/four-CPU VM 28926 started at 15:10:25 UTC and stopped
cleanly with one SIGTERM at 15:15:19. Stop/gone receipts, QEMU signal 15 and an
independent empty exit-1 ps query confirm absence. No compiler or Java ran while
it was live. Final UART equals the immutable after-private-log full snapshot,
both SHA-256 `897abcdee69b70addd68156f9eec4d2306abbae80fd4854ad456d8a97e4a6e40`.
Image and import checks retained their original resource limits. The nine-root
complete evidence seal and separate fresh-process readback passed all 661 entries.
The manifest at `maps-autofill-service-runtime-sealed-2026-11-02-r1/sealed/manifest.json`
hashes to `0b9b89056f4a7b85771d5e27586cc9fd4a7b035c238c7641afae3db72f0dce8c`.
Both guard/child exits are zero with complete cleanup under the original
600 MiB RSS, 900-second, 64 MiB shared-growth and 1 GiB reserve limits.
