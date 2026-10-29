# Maps Service lifecycle runtime, 2026-10-29

The fresh Service lifecycle image passed its standalone ARM regression. Maps
then opened its Add account chooser and a real Google account window. The window
was black; GMS failed during account activity creation, and Maps exited.
The unchanged strict collector accepted the complete controller export. No
credentials were supplied. Google authentication and map imagery remain unverified.

Artifacts are relative to `/Users/alex/.local/state/vinix/android` (`S`):

- Prepared image (`P`): `S/maps-service-lifecycle-r1`.
- Preparation controls (`E`): `S/maps-service-lifecycle-prepare-2026-10-29-r1`.
- Guest clone, now stopped (`VM`): `S/maps-service-lifecycle-vm-r1`.
- Runtime controls and imports (`A`): `S/maps-service-lifecycle-runtime-audit-2026-10-29-r1`.
- Completed fixture transfer (`T`): `S/service-lifecycle-api-transfer-live-2026-10-29-r1`.

The [framework successor](service-lifecycle-framework-2026-10-29.md) applies the
three Service callback changes from `e550944d5`. The
[matching native producer](service-lifecycle-native-2026-10-29.md) contains the
terminal observer from `fc0c44be97a26a027679aef7fe70a10d815ef9a5`. The
[stage implementation](maps-service-lifecycle-stage.md), committed as `f45e3fae1`,
checked all 53 dependency seals, seven overlay files and 25→26 modules. Clone
verification rechecked 89 files with source/copy/source inventories and exact
inode kinds, modes and sizes. Frozen kernel installation preserved all 26 modules.

| Artifact | SHA-256 |
| --- | --- |
| `P/sha256.json` | `8886ba277d9cb8b834bceaa2cf36dd2b8ee00dadb2589e52edb97a7cc62a0f92` |
| Framework manifest | `9453286e07d3bd727782355413d4fa8059bd1332e89850748fb4db02680c9488` |
| Framework JAR | `7017b4845f91cb1c37057f6e8da07476b9b1b44c523827acaf00baad2432fe74` |
| Native manifest | `2c61783de1aab68bbf8177329215b27881e95afaa87d16272f03ba7fda98c401` |
| Native DSO | `ea8b899971ac96335c1f53a32eb3dee8e5e8f87600c0bcd5b7edaa683b9a8136` |
| `VM-clone.json` | `e45bedfba7a0067aa7baac0cac927135795cd5584304afc02e8f0bac05400743` |
| `VM/kernel-patch.json` | `a38ab25d44e209a8b4b18b7ee3ce560f37d5c8699d674fd449fcaad8b7c52038` |
| Installed boot before guest execution | `35a35cfde7f32b21fcdc5b558d893c923c5e471f06881dec60770bdbbb6f46f1` |

One 12 GiB, four-CPU VM used default QEMU user networking, runner
`06cdf596adae105d363a99792b732808deb611db72fe4d87af1a5bc8500fb0fd`
and frozen kernel
`a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`.

| Host phase | Seconds | Peak sampled aggregate RSS, bytes | Observed global growth, bytes |
| --- | ---: | ---: | ---: |
| Prepare | 178.998 | 67,780,608 | 269,148,160 |
| Clone | 6.658 | 32,768,000 | 0 |
| Kernel install | 36.401 | 39,649,280 | 51,277,824 |

All three guard/child pairs exited zero with complete cleanup under the original
600 MiB aggregate RSS, 900-second, 4 GiB observed-growth and 1 GiB-reserve caps.
These sampled and shared-volume measurements do not establish process peak RSS,
swap counts or isolated producer allocation.

Kernel installation used the freshly qualified serial patcher at
`S/maps-service-lifecycle-patcher-serial-2026-10-29-r1/project/patch-kernel`,
SHA-256 `0374c3757e0a386819a7336f7b28f09085a237b881e6911bf917fafe311f31ae`.
Its fresh generation, C compilation and selftests passed; time-reported maxima
were 361,644,032, 326,221,824 and 37,142,528 bytes, with zero swaps. The earlier
R1 split generation actually peaked at 659,423,232 bytes, above the unchanged
600 MiB cap, despite its lower sampled value. That overage and the earlier
one-shot memory failure remain retained. R2 kept production flags and native C
inputs; generated C differed in typedef order, while its fresh binary matched R1.

## ARM Service regression

The [maintained Service fixture](service-lifecycle-fixture-run.md) ran as UID/GID
10117 against the exact JAR/native pair above. Its exported receipt records
`wait_status=0`, one exact pass marker and one native readiness marker. The
fixture checks constructors, attachment, create/destroy, callback write absence,
thread-policy identity, duplicate/null attachment, a real-write positive control
and restoration of the original policy. This establishes the synthetic Service
regression on this ARM pair.

The unchanged zero-removal SERVICE-QUERY planner, historical reconstructor and
child extractor all passed on the 25,483-byte pinned interval. No strict
SERVICE-QUERY import was claimed. Complete proof is in
`A/service-derivation/validation.md`, SHA-256
`c5d69c3aa9fc6e0d9f71918c066130e98d1a520fe0be45d8df4d418e345c2d34`;
the exported fixture receipt is
`8557a1c5da1cf83d78c138c35256ceeb88d569b56b99fede8219f3b9c2c9084f`.
The dedicated fixture mount was released before broker startup.

The earlier authenticator and TLS-v3 passes belong to the
[previous Binder image](maps-binder-identity-runtime-2026-10-29.md). They were not
repeated on this changed framework/native pair and do not qualify its networking.

## Maps account handoff and failure

Both terminal windows were created before the fixture and broker. The broker
became visibly ready at 19:02:13 UTC and remained alive through a 77-second
input-free hold. Maps launched at 19:04:17. Saved captures show its Add account
chooser at 19:05:37 (`VM/service-signin-dialog-01.png`), a black Google account
window at 19:05:53 (`VM/service-add-account-01.png`), and Maps' stopped/exited
screen at 19:07:14 (`VM/service-google-account-02.png`). These are GUI observations;
the black window did not show a usable Google login form.

The imported finite public controller receipt records start/end times
19:00:13/19:05:55 UTC, `service_ready=true`, `status=failed`, `broker_exit=1` and
`cleanup_survivors=2`. It reports one account-pump failure with stage 2, status 3
and one pending request. Its untruncated handoff records include add-account
admission, dispatch, interaction receipt/delivery, redemption, UI begin/readiness
and launch queuing (stages 1–8). The separate redeem operation has a terminal
result record (stage 9, operation 3, event 1, code 0). These finite records have
no request correlation keys; that result does not establish account creation or
authentication. Cleanup's two recorded survivors remain a failure finding; the
guest was subsequently stopped in full.

Private screen capture `VM/service-account-create-npe-private-03.png`, SHA-256
`de7c508be577e96e7dce7d3fb6ea0aecfae8db8ee2d9c2abead6dd88a328939c`,
shows the original `NullPointerException`: `Object.getClass()` on null in
`pdo.onActivityCreated(...:22)`, reached through `VinixLifecycle.notify/dispatch`,
`Activity.onCreate`, `AccountIntroChimeraActivity` and `bjbq.onCreate`. A subsequent
CheckJNI message reports `JNI Throw` called with a pending exception. The original
GMS callback NPE and secondary JNI abort are separate findings. This run does not
establish which callback input or GMS state caused the null dereference; it does
not prove a lifecycle argument defect. The runtime operator's manual private-log
check found no `ANDROID-SERVICE-EXIT` marker. Absence does not identify the
observer branch or establish why no marker appeared.

## Accepted export and closure

The immutable after-Maps snapshot links to before-Maps receipt
`8efd233329abeac6c97c4c303f5b86c4d3b91e395c110490565e2fdabf446961`.
Its complete interval is 2,239,576 bytes, SHA-256
`a80d84cfd6010cafd76f00a052cebb949957f1e61ca76f53b7c2896b7fb1f104`.
The unchanged strict collector accepted 24 entries and 2,819 chunks in 0.285
seconds, with exit/child zero and complete cleanup. No reconstruction or archive
repair was needed. Private app and broker logs remain excluded from the public
archive by its producer.

| Imported artifact | SHA-256 |
| --- | --- |
| `A/strict/archive.json` | `8472b8d5c0272ff1ad1f6c82c978c60616232b203d474eda334296aff1640ec1` |
| `A/strict/import.json` | `1c0b10908a95729fbeac1b95b578afbbf603913a4a5676efe967b3ebf8adbb00` |
| `A/strict/results/receipt.json` | `bb2bb57ff3d15fa14da35a4863486751b1c4297d6b60073841d7e4e14382f454` |
| `A/after-maps/receipt.json` | `6cf3fff366a03e179abdb1845e274d5e002d0d1cd650d59ac84aa8f39e9ebee1` |

The runner requested SIGTERM for its owned VM PID 39748 at 19:17:02 UTC and
recorded its absence at the same timestamp. `T/result.json` records both fixture
asset downloads completed successfully. The runtime owner explicitly closed all
nine roots before sealing.

The complete seal covers `P`, `E`, `VM`, `A`, `T` and the four original clone
sidecars `VM-clone.json`, `VM-clone-tool`, `VM-clone-source.v` and
`VM-clone-sources/`, including regular-file roots directly. Its nine roots and
542 entries are bound by
`S/maps-service-lifecycle-runtime-sealed-2026-10-29-r1/sealed/manifest.json`, SHA-256
`c75bf339097fd029198159fa7b79810e590b97e4c25a55ee26530cd8822af2bb`.
Seal/inline check and fresh-process full readback passed in 6.677/3.289 seconds,
with sampled aggregate RSS 14,024,704/13,156,352 bytes, exits 0/0, complete cleanup
and zero swaps. Caps remained 600 MiB RSS, 900 seconds, 64 MiB observed global
growth and a 1 GiB reserve. A first guard invocation refused before child launch
because the enclosing control directory was absent; that refusal is retained in
`preflight-refusal.txt`. Creating that parent did not alter any input root or cap.
Keep the complete original bundles unchanged; this report does not replace them.
