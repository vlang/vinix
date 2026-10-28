# Maps account pump runtime, 2026-10-28

The new account-pump diagnostics expose the next Google account blocker:
command dispatch fails with `stage=4 status=1 pending=1`, and the preserved Java
exception identifies the missing framework method
`android.os.UserManager.getApplicationRestrictions(String): Bundle`.
Authentication and usable map tiles remain unverified. Progress remains four
of six milestones; this finding does not complete another milestone.

Artifact paths below are relative to `/Users/alex/.local/state/vinix/android/`.
The run uses native producer `current-native-build-2026-10-28-account-pump-r1`
from diagnostic commit `9e6a3cb3383323e103913ebdf7ba810550cfe8dd`, with native
DSO SHA-256 `cce3eb926d3bc8b2b3c9e9a4f0d42cc4ab6bfdc23b0532beb2c42f5f9b384791`.
Host checks and the producer inventory are retained in
[the diagnostic report](account-service-pump.md).

Stage `maps-account-pump-r2` preserves the browser polling fix and nineteen
earlier modules. Its inventory SHA-256 is
`d432d4cf4fa1522b07cb2b7ada498a32d375d44cf7830e50858681fcf118035c`.
The corrected stager is commit `04a491c54`; its retained source digest
`54495acee0895d67494e4fefcbf8f523206fff48b8de2b59e5955a4cccffbf28`
matches that commit. It preserves executable modes across historical native
overlays. The fresh clone `maps-account-pump-vm-r1` used 12 GiB and four CPUs.
Its post-kernel stage SHA-256 is
`625e60c89e349101b0cfa68c247b8ce1682cd9871df3447b12fd595e4b4926f3`;
`launch.json`, the adjacent clone proof and
`maps-account-pump-vm-prepare-2026-10-28-r1/kernel-patch.json` pin media, runner,
firmware and the frozen kernel. No subsequent checkout change was deployed.

The public controller receipt records 10:42:27–10:44:51 UTC,
`status=failed`, `service_ready=true`, `broker_exit=1`, `cleanup_survivors=2`
and empty authentication/browser initialization failure lists. The cleanup
count does not establish living workers. Unlike the prior run's disconnected
input marker, the new numeric record locates the failure in command dispatch
and confirms a pending exception before cleanup. The private capture
`pump-method-01.png`, SHA-256
`98657482a7ba6c81261ceab9e3c3e93c531254db334b10e1b13a96ba19c2eaba`,
retains the missing-method evidence outside Git. No credentials were supplied.

Audit `maps-account-pump-runtime-audit-2026-10-28-r1` retains exact UART and
unchanged strict-import results. Both initial and closed collections passed
with 24 entries, 1,441,584 archive bytes and 2,816 chunks, archive SHA-256
`0087d377aa1eef52b7dff4696083520f75c029d172fe988ab0352d8a9ba31cfb`.
The closed 2,286,539-byte full UART exactly equals the initial snapshot,
SHA-256 `b20182ce49d709a2b2ed081d5e23e4506dcf04e98a407c840a9d3b105a4aa933`.
The exact 2,237,574-byte suffix has SHA-256
`31526478b2f7341e9e32be29a519ad40899788797c8b2e894cbffb5cb0af9ffe`;
the closed snapshot receipt has SHA-256
`0826f18bda8a6e646055a0cded7bb5a08c4ed213aa4b9140a148dfcab0d722b6`.
The closed snapshot/import guards and children exited zero with complete
cleanup, 383/565 ms elapsed, sampled RSS 12,189,696/28,606,464 bytes and zero
swaps. Limits were 600 MiB RSS, 300 seconds, 1 GiB reserve, 512 MiB growth and
4 MiB command output. The producer excludes private Maps/broker logs from its
public archive; none are reproduced here.

Host SIGTERM was requested at 10:50:00 for owned PID 10282. Initial stop observed
a transient ownership mismatch; owned reconciliation then succeeded. The
VM's `stop.json` and `gone.json` preserve the request and absence check at
10:50:19. Closed collection found no UART growth through stop. Exact receipts
and artifact hashes are preserved externally; this report claims no new
complete-root seal for this run.
