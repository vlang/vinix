# Application restrictions compatibility, 2026-10-28

Commit `2d246cd78efdf511d968a889992186aa362dbe0e` supplies the missing
`UserManager.getApplicationRestrictions(String): Bundle` method found by the
[Maps account-pump run](maps-account-pump-runtime-2026-10-28.md). Every query
constructs a fresh, non-null empty `Bundle`, so a caller's mutation cannot
affect another query. The single-user guest has no application restrictions
policy backend. This implements the unmanaged, no-saved-restrictions case;
managed policy storage and enforcement remain absent.

[Android 10's UserManager contract](https://android.googlesource.com/platform/frameworks/base/+/android10-release/core/java/android/os/UserManager.java)
specifies an empty bundle when no restrictions are saved. The V provider is
[framework_application_restrictions.v](../native-android-tools/androidtools/framework_application_restrictions.v),
source SHA-256
`6ab292b53310c9cbd4451c96490f707867f997fcc687a4fd2f716583d32448b4`.
It accepts the exact six-method baseline `UserManager`, appends one method and
rejects already transformed or structurally unexpected classes.

Artifact paths below are relative to `/Users/alex/.local/state/vinix/android/`.
The producer output is
`combined-account-webview-application-restrictions-framework-2026-10-28-r1`,
with `sha256.json` SHA-256
`8907c1f11d8886b47358b458a8026d8351c6feac44d78346d6d426208b8ffe15`.
Its `build.json` pins source revision, exact compiler/tools and retained source
closures. The baseline is
`combined-account-webview-onboarding-framework-2026-10-27-r1`, inventory
`bfd56090052ec6612179741c5ad88ecfe7fad83027a38cc5949c13892abd1c42`.
The successor preserves all 2,104 classes, fields and existing methods; the
only change is the new `UserManager` method. Output identities are:

- `api-impl.jar`: `d4e8678bf5deda99358defd912e64e4fcba92fec4ad3b87b39fc9f7e9f6ebf32`
- `classes.dex`: `45c25a081702f299ae3f8a883347d624cae6ab4bda3b5f2538be89421cdf32ab`

The retained host `builder` and `checker` are under
`application-restrictions-host-build-2026-10-28-r1`. Their compile guards,
the checker, builder self-test and full framework producer all passed with
zero child/guard exits and complete cleanup. The
[checker](../native-android-tools/check-application-restrictions.v) verifies
the exact new method, preservation of the six original methods, real Bundle
constructor/query APIs and rejection of nine invalid inputs, then assembles
the changed class to DEX. The producer additionally checks the complete
class/JAR delta and DEX roundtrip. These are host assembly checks; ART and
runtime Bundle isolation have not been exercised by this evidence.

Receipts and logs are adjacent
`application-restrictions-{host-compile-builder,compile-checker,check,builder-self-test,framework-build}.{json,log}`.
The full producer took 65.055 seconds, peaked at 501,465,088 bytes sampled
process-tree RSS (490,389,504 bytes from `/usr/bin/time`) and used zero swaps.
Its limits were 600 MiB RSS, 900 seconds, 1 GiB disk reserve, 700 MiB growth
and 4 MiB command output. Host checks peaked below 556 MB sampled RSS.
The retained ARM run now has a public fixture PASS receipt from diagnostic
reconstruction, as detailed below. Google authentication and usable map tiles
remain unverified.

Commit `4a8af78a2` adds the
[signed ARM regression fixture](application-restrictions-fixture.v), exact
[runner profile](onboarding-api-run.v) and pinned
[fixture transfer](service-query-transfer.v). The fixture obtains the real
`UserManager` through its own context and package, checks fresh non-null empty
bundles and a missing string array, then mutates caller-owned bundles across
32 repeats while checking another result stays empty. It performs no account
or network operation.

Use corrected `application-restrictions-fixture-2026-10-28-r2`, inventory
`18908b725aa4c124e3bb7add998b7263d0812834082cfd89fdbb2c1aa672500b`;
APK SHA-256 is
`1fcd38978709198743aa9127b14f02bbebbf55e1f4d7793cd03270f3c3c25a07`.
The static ARM runner in `application-restrictions-run-2026-10-28-r2/run` has
SHA-256 `1079d41f4df536e7a14c468e22a6e8021449dd2f36d563ed40e108f4e11abd53`.
The older fixture/checks `r1` used a `-prod` builder and are superseded; their
success does not validate assertions that compilation mode removed. The r2
builder keeps assertions, rejects `-prod` and records an intentional failing
assembly assertion when supplied a non-assembling Java executable. That
negative check exits one with complete cleanup. Corrected signed APK/DEX
roundtrip, host/ARM runner compilation, 65 runner rejection checks and transfer
self-test pass under `application-restrictions-checks-2026-10-28-r2`.
These checks establish fixture readiness; they do not establish an ART pass.

Kernel installer commit `162167810` adds the exact
`--maps-application-restrictions` profile. Its production self-test checks the
five-input delta, six-file overlay inventory, twenty inherited modules,
twenty-one final modules and forty dependency seals, including historical
profile rejection and FAT cases. Explicit errors preserve these checks under
`-prod`. Source and binary are retained in
`maps-application-restrictions-kernel-profile-build-2026-10-28-r1`, inventory
`c8790f6dd20bbddc7d04494142680f7b155be3b33127f01f72759201d5b60dde`.
Compile/self-test guards passed with complete cleanup, 13.129/23.724 seconds,
560,644,096/43,417,600 bytes sampled RSS and zero swaps.

Stager commit `f1216488c` prepares `maps-application-restrictions-r2` from
`maps-account-pump-r2`; the complete stage inventory is
`d8507cb61499306398adecaae7fb9e1fe34ac9f1ccc9c9e42f1232b29c49623a`.
Its source closure and compile/self-test evidence are retained under
`maps-application-restrictions-stage-build-2026-10-28-r1`.
`prepare-r2.guard.json` and its log record a successful 279.565-second run,
71,647,232 bytes sampled RSS, zero swaps and complete cleanup. The guard
kept 600 MiB RSS, 900 seconds, a 1 GiB disk reserve and a backed 2 GiB
shared-volume growth limit; the stager kept its 512 MiB charged-write budget.
The earlier prepare `r1` stopped safely during its initial read-only audit
when shared-volume free space fell beyond its 512 MiB outer limit, before
creating output media. That observation does not attribute the drop to
the stager. Staging and kernel installation remain separate from ART
execution and Maps authentication.

The fresh `maps-application-restrictions-vm-r1` guest displayed
`ONBOARDING-API-RUN-PASS` and exit status zero for corrected fixture r2.
`restrictions-arm-result.png` has SHA-256
`3e9583950b301a5ce2f8fbdb6c81e69ec4a8144746140f9f45484e24f5758b5d`.
The GUI observation was later corroborated by the public fixture receipt below.
The clone and kernel guards passed under
`maps-application-restrictions-vm-prepare-2026-10-28-r1`.

Runtime collection is retained in
`maps-application-restrictions-runtime-audit-2026-10-28-r1`.
Its `tool-identities.sha256` is
`21a22a7b700c377cc1deb976e9ef31ec2def399c6d1d76e4d24541a6e0d4cf1f`.
`uart-after-fixture/receipt.json` is
`704174f88bd1a39cc0a27bb4431e7edac0787f44d458ef3f4e92096a9f287144`;
it pins the preceding snapshot, a 77,036-byte full snapshot
`00047a146a6a861774b8019ec25c97160bc856810da39518c233c24d6a75923c`
and the exact 25,647-byte fixture interval
`4399f82d2b63d955561076e8d9e1e91af90048a9e364acc628cf5b20e4d0885d`.
The canonical two-entry SERVICE-QUERY export is 15,682 bytes in 31 chunks,
SHA-256 `609cf19b7af87861c2987145b21b4620a964b1ead957d181eb5c6a430f212baf`.
Later diagnostic reconstruction preserved this archive without removing data
and produced a public fixture PASS receipt with a clean exit. The reconstruction
tool makes a diagnostic derivation claim; the existing strict collector has no
SERVICE-QUERY selector, so this is not a strict SERVICE-QUERY import.
`fixture-plan-work-r2/plan.json` is
`9285a6e9f1a1589c84fc1f340bd368e6bb8f7aca54d5844427bcd3c923453da5`;
`fixture-diagnostic/diagnostic.json` is
`2a8a8322351509d3abed208ff438f9848294c91799305d4f231117339820041a`.
`fixture-diagnostic/exported-receipt.json` is
`4d450ba9d57064211112421028c1567d8eda4ed9521d8daeb75d6966f6ace9c1`;
it records the application-restrictions profile, wait status zero, exactly one
PASS and `native-ws-ready` marker, EOF drain, clean exit and unchanged pinned
inputs. The later plan/reconstruction guards both exited zero with complete
cleanup, 3,883,008/4,390,912 bytes `/usr/bin/time` RSS and zero swaps.

`fixture-plan-execution.json`, SHA-256
`badb8070d37efb3508fc209cf2800af036582fcc548eb1180fd8e9e884ac50df`,
refused before launching a child: disk reserve, exit 125, PID zero and child
exit -1. Only 506,806,272 bytes were free against the unchanged 1 GiB reserve;
the receipt's cleanup flag is false despite no child being started. That initial
attempt produced no plan, diagnostic import or public fixture receipt. The
later reconstruction above completed after disk space recovered.

After the fixture exited, its dedicated runtime attachment remained read-only.
Broker preparation could not create its SQLite replacement alias, before GMS
started or Maps launched through the account session. The desktop's earlier
automatic Maps launch had already exited before the fixture.
`broker-start-01.png` has SHA-256
`00539ade23c159810853ffeed492ec807e2b213693faba3c7e9aecd5d17cff81`.
Commit `484b7305b` documents the required
[fixture-to-broker handoff](onboarding-api-run.md); that corrected handoff
was not exercised in this stopped run. The final serial file is 79,708 bytes,
SHA-256 `ba473fa182d4ecdf8b8ae1081c78c5dd6b93712c1ea3eac558f66bc79cdc0cb9`.
It contains a small canonical MAPS export, 1,523 bytes in three chunks,
SHA-256 `20c7f444fd365297913669ec6f92e17a7b4cec6282274767976ee49d923df7b1`.
Strict `--maps-account` collection accepted this failure archive and records an
exclusive-create error for `.maps-account-fresh` before broker spawn.
`maps-strict-results/import.json` is
`ad29b03368361c5a04eaf20a2ad16a0b79da7b11aebe2ad880d9036a07f99a4a`;
its public `results/receipt.json` is
`6172019ecf8270e795fa212e0f4fa87e57201efc03b793740eca8e78656561f7`,
recording failed preparation, broker PID zero and service not ready.

Owned VM PID 85197 received SIGTERM and was reconciled absent. Its `stop.json`
is `55952ce518a7b5a1087d85e971c7ebc5de5fe28c06a62f5f71b886ad10c7c16d`;
`gone.json` is
`e3eee3a0b6d0688b8ac2907888e2d14bd44804923b0c806bece50bbb0d9dbadb`.
The final closed snapshot receipt `uart-closed/receipt.json` is
`6709ea149400d1d78206fd1f7e26e231d6cfc7e22f83fe4aefe93a166251e7d1`;
it pins that 79,708-byte serial file and its exact 2,672-byte Maps suffix,
`c623e4856f005760f028bac25b4a09684566f15fb64787b9d1addcae5b2be904`.
Closed snapshot and strict Maps collection guards exited zero with complete
cleanup, 4,554,752/4,915,200 bytes `/usr/bin/time` RSS and zero swaps.

The external seal `maps-application-restrictions-runtime-sealed-2026-10-28-r1/manifest.json`,
SHA-256 `33c3b95d37df65f9323fa0bb56f94d875a2bff791901b140100fba8c97df38d8`,
binds both complete runtime/VM roots and 287 entries, including screenshots,
raw UART, stop/gone receipts and explicitly post-run boot media. Its inline
readback and later separate full check passed, at 23,887,872/13,336,576 bytes
sampled RSS and zero swaps. All six completion commands kept 600 MiB RSS,
300 seconds, 1 GiB disk reserve, 64 MiB growth and 4 MiB output limits; each
exited zero with complete cleanup.

A fresh Maps attempt used `maps-application-restrictions-vm-r3`
without running the fixture first. The preceding r2 kernel preparation stopped
when shared-volume free space fell by 1,091,342,336 bytes, exceeding its 1 GiB
growth guard; no VM was launched from that attempt. Fresh r3 preparation used
an authorized 4 GiB shared-growth ceiling while retaining the 600 MiB RSS,
300-second wall, 1 GiB reserve and 8 GiB file limits and unchanged inner kernel
checks. Under `maps-application-restrictions-vm-prepare-2026-10-28-r3`,
`clone.json` is `603b3aca77ea880bbb154b0bb040470809b91dce3ae9c7608c3bd98c41d4d9a2`
and `kernel.json` is
`e3a0e2d5d36077b459f8b6b9802c24af1a9a64b1079865fa8dfe18bf16729e86`.
Both exited zero with complete cleanup and zero swaps, taking 14.043/103.450
seconds at about 37.3/30.9 MB sampled RSS.

In r3, direct broker preparation reached `MAPS-ACCOUNT-READY`. Paris and Eiffel
searches returned live results, and the route settled at 24 minutes (6.1 km).
Preview instructions advanced from Pont d'Iéna to a left turn onto Pont de
l'Alma in 750 metres. The map background remained beige, with no street tiles
or place photos. Closing the native Maps window to reopen it for authentication
ended the controller with `Maps launch app host ancestry changed`; no account
click was tested in this run.
Its UART export failed strict collection on one noncanonical CHUNK. The bounded
metadata audit found no admissible contiguous deletion matching the archive
digest, so no diagnostic result receipt or strict pass was produced. Under
`maps-application-restrictions-runtime-audit-2026-10-28-r2`,
`maps-frame-audit/report.json` is
`a768667ea75dab0412d568906b76aaca0f73c337abb1d43a77bfe23f32e4a351`.
The complete r3 VM and audit seal is
`maps-application-restrictions-runtime-sealed-2026-10-28-r2/manifest.json`,
SHA-256 `f906c276d7b85344fa73b05508acd700028f728695147518512ea00c9ec1608c`
(two roots, 346 entries). Seal and separate full readback passed with complete
cleanup and zero swaps under the same 600 MiB/300-second/1 GiB reserve/64 MiB
growth limits.

Fresh `maps-application-restrictions-vm-r4` reused the same immutable inputs and
tested authentication first. Sign in opened the Add account selector; choosing
Add account returned to onboarding, which stayed unchanged for about 60 seconds.
No Google login window appeared and no credentials were supplied.
`signin-click-01.png` is
`9e1fea4e7091d480d5928125cf236ead6ac71e8115aa42e75eb472a05dd96002`;
the later `add-account-02.png` is
`d093400783a36511292479c4f64dd4af6de1090d259a0df30e85d0a80c4549d4`.
Collection is under `maps-application-restrictions-runtime-audit-2026-10-28-r3`.
Its strict `maps-strict-results/import.json` is
`058b37c0fc72dd6bc993fd2b49cd9e93b6d1a759256c8fc025a5c08aea544c29`,
and public `results/receipt.json` is
`43cb968da1f950f84d4d2e5caaf1a424bb064272f18821a29e3eaf4ef0f02db5`.
The requested stop records `user-stopped-no-authentication-claim`, service ready,
broker exit 137, two cleanup survivors, empty auth/browser initialization failure
arrays and an empty error. These diagnostics identify no next missing API and
do not establish authentication success.

The r4 VM and audit are sealed by
`maps-application-restrictions-runtime-sealed-2026-10-28-r3/manifest.json`,
SHA-256 `49cbaa194fd0be93276829043a10041582524781eb496a3364f9a36b6517764e`
(two complete roots, 295 entries). Seal and fresh-process readback passed with
zero swaps and complete cleanup; retained guards kept 600 MiB RSS, 300 seconds,
1 GiB reserve and 64 MiB growth. The stopped VM's ownership was reconciled absent.

Progress remains 4 of 6 milestones; this is not an estimate of remaining
effort. Google sign-in and usable map tiles remain unverified.
