# Unmanaged query ARM pass and missing StatsManager type

The signed unmanaged-query regression **passed on ARM**. Real service lookups,
null device owner, false managed-profile state, application-restriction defaults,
repeated queries and snapshot isolation passed. GMS then reached readiness and
exited on `NoClassDefFoundError: android.app.StatsManager` before Maps opened.
Current imagery and authentication remain unverified.

Provider `40cd4ae84`, producer `b0db8a64a`, fixture `1c4794ab3`, delivery
`121427a43` and media `cd3ace6de` are committed. The
[SDK/native pair](unmanaged-queries-pair-2026-11-02.md) preserves all 70 native
raw/canonical classes and retains the locale DSO. The
[media qualification](maps-unmanaged-queries-stage.md) records complete audits.
Prepared image manifest is
`7d1d1caf97b5f86d88fc8b18812c56fe9a6679c4c18460fe366ce438ece2dd54`.

Evidence is under `/Users/alex/.local/state/vinix/android`:
`maps-unmanaged-queries-runtime-audit-2026-11-02-r1` (`A`), matching live controls,
stopped VM and four clone sidecars, prepared `maps-unmanaged-queries-r1`, and both
`unmanaged-queries-api-transfer-live-2026-11-02-r1`/`r2`. Original complete bundles
and historical auditors remain required.

The unused UID/GID 10141, fresh output and protected read-only runtime were
verified. The first transfer stopped on 71,630,848 bytes observed shared growth
before downloads; no fixture ran then. The retry submitted an already-typed
download command immediately after the server started, finishing in 597 ms
under unchanged limits. Runner/APK hashes matched before the sole fixture run.

Actual child 40700 exited 0, with all six exact input pins and eleven checks.
Receipt SHA-256 is
`e34090b76b89b38f96ea34183c3e1e5316bc209c13a9a0731bc06c4120a9314f`.
The complete 10,955-byte, 130-line child log hashes to
`f7159d83967547055eb0cb135893119868676b4be495556462eb48258d6349a0`:
one full PASS at 115, readiness at 124 and normal teardown through 130.
Independent `A/fixture-validation.md` hashes to
`7b62a00f6a35948ccf7c26fe0273265cd1184876b7323dc7d6fe7880c2dc3dc2`.
Unchanged zero-removal diagnostic tools preserved all 34 chunks of the
17,355-byte fixture archive. This is diagnostic import, without new strict
fixture-protocol qualification. The fixture mount was released before GMS.

The complete controller receipt
`af8c7bc1aa8e19f41cdd0fe8e6e11112d258786551bfbb44a775ee6414af482b`
records 12:23:21–12:24:20 UTC, broker 55157, readiness true, failed/exit 1,
drain EOF true/status 1/167,000 bytes/errno 0 and zero cleanup survivors.
The bounded public stack reaches `fojo.e` source 1 and Westworld
`InitOperation.b` source 393; native VM exit status is 10. No manual Maps launch,
Sign in, credentials or Next action occurred. Broker readiness is not
authentication proof. Private app logs remain excluded except their hashes
and the bounded public stack projection.

The automatic export completed with guest input idle. The unchanged strict
account collector passed before VM stop: 21 entries, 2,831 chunks and 1,449,136
bytes, archive
`4c54b099dcacb5d9e3f0d62e97c53930d593c4eb7a177fe5f2b9cbf7c4fa8921`.
It took 308 ms at sampled RSS 27,803,648 bytes; guard/child exits 0 and cleanup
complete. No repair or collector relaxation occurred.

Owned exclusive 12 GiB/four-CPU VM 95970 ran 12:17:23–12:28:04 UTC. One SIGTERM
stopped it cleanly; stop 0, `gone.json` and independent absence were verified.
No task-owned compiler or Java ran while it was live. Final UART equals the
immutable full snapshot,
`9b485367020dd87db0b847f3f66bed0b2d856ad1bc76a15b3d20075572478c66`.
Preparation, clone and kernel checks passed unchanged guards. Ten closed roots
passed sealing and a separate fresh readback for 662 typed entries, both exits
0/cleanup complete. Manifest:
`maps-unmanaged-queries-runtime-sealed-2026-11-02-r1/sealed/manifest.json`, SHA-256
`a81481577195e7d3c4038a7f0891bfba872d80d2047882ec1fba30415591a2bf`.
