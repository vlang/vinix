# Maps descriptor exhaustion, r88

Following 70c34e195, fresh r88 ran the diagnostic JNI adapter
29fbace1c1f5f91c3a74281edc2094c6c75bab7eb200448ef8d6c925be331553
and imageless ART candidate d33dfac4adadddf8642927dd798a94e15e713bd3a63e65bac01b22a830ad7ba7.
The [full signed ARM API regression passed](maps-art-imageless-runtime-20261114.md).
The selected persistent data volume was mounted and checked before provisioning
and independently checked by the private-copy terminal.

Maps rendered onboarding and Add account. The first Google account window
showed a server communication error; the private broker log records
CheckinHelper's 10000-ms timeout. Later CheckinOperation completions report
SUCCESS. Closing only the account window returned to the same Maps process.
A second Add account reached redemption, then the explicit single-use
accountuifd.Controller refused UI begin and returned error 6. This is its
documented retained-mapping policy, not a newly diagnosed lifecycle regression.
It remains intact; supporting a second attachment needs safe native graphics
teardown and a fresh authorized attachment, not clearing the used flag.

At 16:02:18 the private Maps log starts reporting APK opens failing with
"No file descriptors available". Further file opens report EMFILE, including
framework-res.apk and dynamic GMS module APKs. AssetManager.destroy() also
logs its existing STUB. After Skip, the process exited at 16:03:08 on an
uncaught AccountManager.vinixAccounts/getAccountsByTypeForPackage exception:
"account broker connection failed". It did not enter the new query wait loop.
Descriptor exhaustion is observed before that connection failure, but the
exact failing socket/setup syscall and the ownership of the accumulating
descriptors were not captured. Repeated asset loading is a candidate, not a
measured leak attribution. No descriptor limit or query deadline was raised.

The storage watch completed 600216 ms, minimum data-volume free space
7937298432 bytes, minimum guest MemFree 2734400 KiB. Checked stop returned
user-stopped-no-authentication-claim, empty controller error, one survivor.
The complete public export finished before private-copy operations; its
empty-removal diagnostic reconstruction passed without byte repair. Private
results were copied to the verified ext2 disk, synced, and observed at the
prompt before stopping owned QEMU22922. PID and open-image checks confirmed
it stopped before read-only debugfs extraction. Private log digests match
private-log-sha256.json; the extracted receipt equals the exported receipt.
Read-only e2fsck passed 0/0 with complete guard cleanup under the original caps.

Evidence below is relative to /Users/alex/.local/state/vinix/android:

| Artifact | SHA256 |
| --- | --- |
| maps-query-account-uart-20261114-r1/full.log | 889b47c18c5a1a013acf99c2a68fb3d9794ca45e96bc5e805ad8e3d04d7a31d3 |
| Same snapshot, interval.log | d163fb058bad09cf925fb45bb2b912a9e56f7c8ea4f78e2c367a1a015d3729e1 |
| maps-query-account-readback-20261114-r1/archive.json | 354d06c58fda12179c2ef768b4c887629d3f2f9a2de74ee56ad894b05db70369 |
| Same readback, exported-receipt.json | 6c0e6ffafd17b71fd9779434b699d8e84896e73644216e310dc6772cc7d9f584 |
| maps-current-20261114-r88/private-readback/results/maps.log | 56729962b642bd5104af1716b7e370c6cceca0a254edfd818a89d05dbaadc9b7 |
| Same private results, broker.log | 2abb02a9cc5229fec55d9636aa4a99ead3adf429e7f579620928ca6ffbaf6b90 |
| maps-current-20261114-r88/private-readback/storage-watch.log | 47b755045bf1d027bf0a9834a7c0d94021d56852f9ce354504666bf9b553b473 |

The V storage observer now supports
`--descriptor-snapshot PID FRESH_OUTPUT`. It retains status, limits, start-time
brackets and bounded fd/target inventories in a private directory, including
failed readlinks. It explicitly reports a non-atomic snapshot and rejects a
changed process identity. Bounds are 4096 descriptors, 4095 bytes per target,
4 MiB combined targets and 64 KiB per proc metadata file. Existing storage
watch and memory snapshot modes remain available. Capture several snapshots
of the selected live Maps process to identify growing duplicate handles.

Host tests exercise real symlink reads, duplicate APK targets, an unavailable
entry, JSON escaping, canonical PID rejection, private-directory mode and
overwrite refusal. maps-fd-watch-tests-20261114-r1 passed 0/0 with complete
cleanup. The static ARM64 observer build maps-fd-watch-arm-20261114-r1 passed
0/0 under the original caps: 8643 ms, sampled RSS 326549504 bytes, shared growth
173711360 bytes. Executable SHA256 is
d908359f38fc80e0258d0df88db102ce8bb0d0843617ecae5879154858187d81.
It has not yet captured descriptors in Vinix. Google authentication, sustained
responsive Maps and the descriptor lifetime fix remain pending. r87 and r88
are stopped.

The subsequent [r89 inventories and framework APK cache candidate](maps-framework-apk-cache-20261114.md)
retain seven stable-process snapshots. Maps rendered tiles and ended at the
original session deadline; its descriptor exhaustion did not recur in that run.
