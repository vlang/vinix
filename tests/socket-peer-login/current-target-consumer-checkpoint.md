# Compiler-consumer checkpoint

2026-11-05, working sources based on
`0c627c794b5c0699dfe30eb0f50514fe5a139cc4`. Admission stopped with
1,836,452 KiB available, below the required 2,097,152 KiB start floor.
No bootstrap03, source stage, TARGET compiler consumer, native sampler,
rename controls, kernel build or VM started. The new APIs and consumer
feature remain unvalidated drafts. Only this checkpoint report is committed.

R is `/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01`;
T is R/target-consumer-host-01. The bounded refusal receipt is
T/admission-refusal-01/refusal.json. Pending owned sources and their hashes
are preserved at T/draft96-01; no historical input or completed profile was
rewritten.

## Retained attempts

Bootstrap01 returned 1 before C or binary generation. It exposed global-name
collisions and two unsupported V syntax forms. Its complete inputs passed
nine original source seals/checks and the original HOST before/after checks;
326 resource headers, direct tools/SDK settings and the kernel header matched.
An independent source copy passed the original complete seal and separate
check. Status: T/bootstrap-01/actual-status.json, SHA256
`e9cd18f9be544d922e80fdc6aad7d002f1c2a1cd2173f5fc6f0a30179b252602`.
Its source inventory is
`a23fc88e9a3f0efc607000f782c7458b044e2cb0a4de7e84d1d59002209401b7`.

Bootstrap02 compiled with status 0 after the independently reviewed syntax
corrections. Qualification refused: its native link manifest resolved SDK27.2
headers despite recorded SDKROOT26.5. No stage or consumer ran. Both generated
C copies, the executable, all object/manifest files and the independent as-run
source tree remain retained. Original source/HOST postchecks and tool/header
comparisons returned 0. Initial GNU timeout execution has endpoint evidence;
no typed nativeguard cleanup is claimed.

| Bootstrap02 artifact | SHA256 |
| --- | --- |
| actual-status.json | `dbd101a9b0138a6c40b18556eb610416b02ca6491dc1a3e216c3a9c3e5671045` |
| stage-profile | `5b5014d2c36f3e9c80a2b3914d5a1a936b1849d6a3a7c8df318ba4b5c5b2b03b` |
| Both retained C copies | `38f35c08f69f772b8895a7b1a23e0664df4c94cd6f7bfadeb9672b8d8213f89e` |
| Native link manifest | `afb17ad38cb39baa1d7e2877e585159af1b872a4cc8e23dd521ea70a9c9406ee` |
| As-run source inventory | `32c7839a930f3611806fa901c154d09c91653d99828b5ab205f64ed601be3d27` |

## Pending sources and next gate

The source-reviewed revision adds explicit `-cflags '-isysroot SDK26.5'` to
all V C-emission routes, preserving strict manual clang sysroots and the
existing nativeguard owner. No C-only or sampling-cadence rewrite was made.
The phase umbrella is 96 MiB inside the unchanged 512 MiB kernel cap:
80 MiB working, including 4 MiB reserved for main-index/Git transactions,
and a full 16 MiB final tail. Producer endpoints retain the Git reservation
and enforce 76 MiB. Historical failed states remain charged.

| Draft source | SHA256 |
| --- | --- |
| qualify-current-target-consumer.v | `61eb028a268408b61a0bd477b362cd385c3d43fb5fc5c9f65b571946df90b45c` |
| current-target-consumer-plan.md | `6b4a4a7f7446619911608c9abf0a75098a4432b9b61dd6fdf2bfca9ce8a94ec3` |
| current-target-consumer-sources.txt | `4dcd8e747972d385aba2ece885a075fdeec33844aae0996545b2f9c94c73c8f5` |
| currenttargetrecord/core.v | `64e573abf61802d67381c99914ea77afe5425b2a45a8fb63c3040d7076e0685f` |
| currenttargetprobe/main.v | `aea18d488144844ede18dedda7ce3dc78e28cd2b06d37aa16074e0923a087367` |
| generators/core.v | `24f27359c414c7124ce1e994207a00d74e17f8832eb4a9d0deaef1d694ce0739` |
| hosttest/module.v | `5842a82733b29c2a40aa952799913f1b17041971fbcfd171ff74470c6c292327` |
| callback-controls.v | `16b86b22e81c06231c0949a5a8bc2beee712e3ff8a0f4796824f0cc235d1c15a` |
| preserveoutputs/core.v | `ffc04263138c29c1c8dbaef7a65113283ad753968546e42cad331f06893bf437` |
| preserve-outputs-controls.v | `d61c643cd05824f0605c0a0127d270017956ed2e9bf500a0aee21280cfcb28e7` |
| preserveoutputs/README.md | `296bfc07eb55b1e8b7b68bc96891833d91ecba2fbc0e119cce6a99f7ccca43bd` |

Also pending are the sampler-only/ordinary-failure changes in
tests/native-generators/test-generators.v and the two ordinary-build callback
test files. Four unrelated LinuxKPI callback files were restored exactly.
The complete pending-path list and byte hashes are in the external snapshot.

Resume only after fresh 2 GiB admission, exact source/tool pins, both-space
96 MiB/512 MiB projections and the selected SDK's actual native dependency
proof pass. Then run the five SDK-corrected host builds, normal/production
explicit callback controls, 81 direct owned consumer actions, complete original
C checks and the separately bounded 14-case rename route. No 80 MiB future
copy-fallback saving is claimed before actual rename qualification and
selective integration review. The frozen compiler and complete input inventory
still match `482d0c3b...d907d40` and `e9fc44d9...9a0e5cf` respectively.
Section 14, generated-C mutation guards and kernel/runtime qualification remain
open.
