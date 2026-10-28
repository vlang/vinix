# Maps account-handoff staging checkpoint

Source commit `e45378929b964546ad8b2630369b71359b766268` adds
`maps-account-handoff-stage.v` and a strict broker verifier with negative tests.
It preserves `maps-application-restrictions-r2` and its framework, native,
browser and kernel inputs. The four-file overlay replaces the broker, the
controller and its alias, and the deployment receipt. Only the three corresponding
deployment input hashes change. Original inode ancestry, exact TAR contents and
all 21 inherited modules are checked; the diagnostic overlay becomes module 22.
Historical producer and patcher profiles remain unchanged.

No complete diagnostic stage was produced. The first two attempts reached the final
complete-input recheck after successful media readbacks, then an outer guard
stopped them. Neither retained output contains `stage.json` or `sha256.json`;
both remain incomplete staging attempts. A third attempt stopped during the
initial input audit before creating its output directory. No VM or Google login
is validated by this checkpoint.

Artifacts are retained under `/Users/alex/.local/state/vinix/android` (`S`):

- Evidence, tools and frozen source/compiler closure (`A`):
  `S/maps-account-handoff-stage-build-2026-10-28-r1`.
- Failed outputs, preserved unchanged:
  `S/maps-account-handoff-r1` and `S/maps-account-handoff-r2`.
- Base: `S/maps-application-restrictions-r2`, manifest
  `d8507cb61499306398adecaae7fb9e1fe34ac9f1ccc9c9e42f1232b29c49623a`.
- Broker: `S/current-account-broker-build-2026-10-28-handoff-r1`, manifest
  `b06d4aadb661eb1ba13ac07e9033d88db1db731d54d2b1685df6dba1e69cd8f6`.
- Controller: `S/maps-account-guest-build-2026-10-28-handoff-r2`, manifest
  `1cf0e472fb977e705204f06fcad806f0c1ea16d213d469d0174c658c27fb041d`.

The initial full input audits passed, including the complete broker/controller
manifests. The final rechecks did not finish. Each failed output retains its
payload, TAR, inode-mode plan, Limine files and command receipts for all 21 base
modules and all 22 candidate modules. These partial outputs must not substitute
for a successful producer and complete manifest verification.

| Check | Result | Guard seconds | Peak sampled aggregate RSS, bytes | Observed shared-volume growth, bytes |
| --- | --- | ---: | ---: | ---: |
| Host stager compile | Pass | 11.183 | 487,833,600 | 55,828,480 |
| Exact-profile, payload, receipt and disk self-tests | Pass | 0.278 | 1,245,184 | 286,720 |
| Broker retained-input and ELF negative tests | Pass | 3.945 | 355,385,344 | 49,893,376 |
| Prepare r1 | Stopped: 300-second wall limit | 300.108 | 56,623,104 | 122,261,504 |
| Prepare r2 | Stopped: 4-GiB shared-volume growth limit | 256.624 | 54,837,248 | 4,326,821,888 |
| Prepare r3 | Stopped: 2-GiB shared-volume growth limit | 86.593 | 38,813,696 | 2,161,033,216 |

The first two prepare guards record exit 125, child exit 137 and completed process-group
cleanup. Their RSS limit was 629,145,600 bytes, disk reserve 1,073,741,824 bytes
and shared-volume growth ceiling 4,294,967,296 bytes. Both launches also set
`ulimit -f 16777216` (8 GiB in zsh); this launch setting is outside the guard
receipts. The r2 wall allowance was 900 seconds. Its free-space measurement fell from
11,589,111,808 to 7,262,289,920 bytes. Global `df` changes cannot attribute growth
to this process; the internal 106,655,744-byte charged-write value is also not an
isolated allocation measurement. The internal 512-MiB growth limit was retained.
Host compile/test time reports record zero swaps.

Five historical package tests passed. Earlier new-fixture failures (array
construction and noncanonical temporary paths) were corrected before the passing
broker test; original logs and guard receipts remain in `A`. The first package
check also hit its shared-volume growth guard. Independent source review
approved the exact producer pins, closure checks and media contract; independent
report review matched the measurements, artifact hashes and incomplete outputs.

| Retained artifact | SHA-256 |
| --- | --- |
| Stager source | `000b87388e036335ea26b6c028887eb25a2861f087354a6f1c8fd92d55717799` |
| `A/tools/maps-account-handoff-stage` | `fca605d07bbe8eba5de8d7c4616bca7e135811ed8ea3e8b2fad24cd18ebf66c8` |
| `A/tool-inputs.sha256` | `c570a0c0acbd3cfdee57966e971b956b2c9f5ea7cceb79dc8e7f8745cb0b07c7` |
| `A/stager-compile.guard.json` | `8bba2eacec437442f2a4d344a6558a171a97eb8f2997257d2a19e33f8d47f678` |
| `A/stager-selftest.guard.json` | `0fff4fbe715255b99834842014afd7e8e4e4ac81ef17f5042d4a599c5fa6de2e` |
| `A/broker-test-r3.guard.json` | `666110548028a11d0e1829b0a7b5389169b1fd36c3b04f6ed3bf3418d6a89f5a` |
| `A/prepare-r1.guard.json` | `03767244aeb77363d4971f4c7eb994a71c2e4a6288477a20e60436ab43a00677` |
| `A/prepare-r1.log` | `41a2890fe82760aade16d742171dffca695ec6811551e248ef7229ea386392b3` |
| `A/prepare-r2.guard.json` | `6f28b1f1b3b8d0cc5be7f2b87068ec1d9f9be45a9e6e0f31129a8a86d323ee9c` |
| `A/prepare-r2.log` | `e9c26794ef5d7eae0c61482920d1c44fd5cd7eb2048f22bb6c085433a16213c9` |

The quiescent build-evidence root `A` and both failed outputs are also bound in
place by `S/maps-account-handoff-stage-failed-audit-2026-10-28-r1/sealed/manifest.json`,
SHA-256 `c06fbff50155915eaaf3a91a08e34bb54241d0e49b7816fd898168cfeadf43bf`.
The existing streamed evidence tool and a fresh-process complete readback both
passed: three roots, 707 entries. This preserves the incomplete attempts without
qualifying either as a completed stage. Seal/check guards exited zero with
complete cleanup and zero swaps, taking 14.497/8.965 seconds with peak sampled
RSS 22,937,600/22,953,984 bytes. Limits were 600 MiB RSS, 900 seconds, 64 MiB
shared-volume growth and a 1 GiB reserve. Their receipts remain beside `sealed/`:
`seal.guard.json` SHA-256
`126bbdd2e4cdbebabb42c6994a8aa87d60d949e0275491cf51783b92b83c8ea6`,
and `check.guard.json` SHA-256
`252ac99f583af242c14c182432eed47d3d4434e8d76abf9ef6ba23a5f584f215`.

The single tighter r3 retry started with 3,925,180,416 free bytes, backing its
2-GiB growth ceiling and 1-GiB reserve. It retained the 600-MiB RSS, 900-second,
internal 512-MiB growth and inherited 8-GiB shell file limits. The outer guard
recorded a minimum 1,764,147,200 free bytes and stopped with exit 125, child 137
and complete cleanup. The log contains only the initial immutable-input-audit
message. `S/maps-account-handoff-r3` was not created. As with r2, the global
free-space change cannot be attributed to this producer.

Its quiescent evidence directory is
`S/maps-account-handoff-stage-prepare-2026-10-28-r3`:
`prepare.guard.json` SHA-256
`c506e8c13add2df299642ba9a16252ae0260473f6c295073d490575c215442b7`,
and `prepare.log` SHA-256
`882c7056614955494fd86a077cdeee2262dd91949502ddae4ca92a7da42f0cd0`.
Both were independently rehashed after producer cleanup. No further retry or VM
was started. The completed [GMS caller audit](gms-npe-three-class-audit.md)
separately identifies the r5 NPE as a caught logger failure; it does not establish
the account failure's cause.

Resume with a fresh output and the existing fully checked producer when stable
free space backs the complete outer growth allowance plus reserve. Preserve the
failed evidence. A successful prepare, independent manifest readback, frozen
kernel installation and live Maps/account-flow checks remain required.
