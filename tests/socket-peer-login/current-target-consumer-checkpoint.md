# Compiler-consumer checkpoint

## Original compiler recovery, 2026-11-11

`verify-original-host-candidates.v` (with its missing `fsync` declaration and
deprecated `usize` casts fixed, built `-prod`) compared both retained
`vinix-waitpid-width-20261026` toolchain copies against the 4,636-entry
historical loader map. It returned 1: three original files are in neither
copy (`vlib/v/diagserver/diagserver_linux.c.v`,
`vlib/v/driver/instance_check_nix.c.v`, `vlib/v/gen/fastc/unit_compile_nix.c.v`)
and strict metadata is incomplete. The receipt is
R/original-host-recovery-01/coverage-receipt-01.json, SHA256
`3ccd2654deb54147dc61750a7d28fe15ebf57f56fdeba675564fa818b2401f78`.
Nothing was restored. The historical compiler controls cannot resume from
retained copies; only a separately qualified current-input route remains.

## Continuation, 2026-11-08

Work resumed at `a8e4f7d68` with about 375 GiB available. The strict stager
build passed, including nine original source seals/postchecks, complete HOST
checks and exact tool/header comparisons. Independent SDK/C-ABI review passed.
Stage02 returned 0 and captured 65 producer entries plus eight helpers in a
fresh source02 tree. The failed original capture remains untouched.

The opt-in sampler/module capture APIs now pass six ordinary controls in both
normal and production builds. One supplied owner handles selection and C
emission; existing callers retain their original contracts. Selection/emission
refusals, successful normalization and temporary-project cleanup pass. The
production C retains explicit failure branches. Assertion-based `_test.v`
companions were not run; the ordinary fixture supplies both build-mode results.

Complete evidence is under T below. `resume-bootstrap-01` retains a refused
runner build with an incomplete module path; `resume-bootstrap-02` passed after
the path correction. `bootstrap-04` and `stage-02` retain stager commands,
environments, original audits, generated C and the exact-count/inverse proof.
`bootstrap-05-callback-normal` and `bootstrap-06-callback-prod` retain both
six-case runs, strict compiler outputs and complete SRC/header/HOST pre/post
audits. All four native manifests per build use canonical SDK26.5. Builds and
fixture runs use GNU timeout and endpoint accounting; they make no nativeguard
typed cleanup claim. The later source03 consumer-driver invocation is recorded
below. TARGET compilation, native sampler, rename, kernel and VM checks have
not started. Section 14 remains open.

| Artifact under T | SHA256 |
| --- | --- |
| source-02-stage.json | `67cb4f6083b4f61f4d67a9ac6ad4f0c162fbcb34a1ceaa2563e29025aa05b2db` |
| source-02-comparer-derivation.json | `5211ab9d66b9e09cded73fec20538685232771c867192310bda59620da46bf8a` |
| bootstrap-05-callback-normal/controls-status.json | `7275e533fedb541f5351c8d18d825cc0d6b5235b35d15ae04f476088b7a3acfc` |
| bootstrap-06-callback-prod/controls-status.json | `e93e3bc001027e491533828f19fa496181a885cbb7838f787cec2c85fd314f34` |

Review found that source02 omits the original checker used by a relative
embed, although its declared 73-entry filesystem capture passed. The pinned
compiler may compile a missing embed without its payload, so source02 is not
a complete embedded-input closure. Source03 now includes that template;
source02 remains unchanged. The revised plan keeps the
80 MiB working subtotal, full 16 MiB tail and 96/512 MiB caps unchanged.

The source03 correction captures all 65 producers and nine helpers, pins the
10,200-byte original comparer, and verifies the exact complete 74-entry set.
`bootstrap-07-closure-fix` passed the strict main build, nine source postchecks,
complete HOST/header checks and SDK/C-ABI review. `stage-03` returned 0; a
repeated stage returned 1 with the exact freshness refusal, leaving sources and
receipts unchanged. `bootstrap-08-captured` and `bootstrap-09-comparer` then
passed strict production builds from source03. Independent review found all
14 embed occurrences have payloads and every native manifest uses SDK26.5.
Complete source03, source02, HOST and resource-header postchecks passed.

The fixed consumer driver returned 1 at `00-tools-before`, before invoking
TARGET. Four direct children ran: the original complete TARGET check and
postcheck returned 0, while both selected-tool comparers returned 1 with
ENOENT. All four have observed private groups, natural reap, empty groups,
final wait/ECHILD and zero cleanup kills. The top status is FAIL. The pinned
historical loader map names three absent paths: main's
`build/package-https-runtime-work`, its `toolchain`, and `toolchain/v`.
The checker and baseline are unchanged; no substitute files were created.
The consumed action/status namespace remains preserved. This does not qualify
relocated TARGET compilation, sampler execution or guest behavior.

T measured 37,152 KiB allocated / 33,932 KiB apparent after the consumer's
external postchecks. Space admission recovered to about 373 GiB; disk space
is no longer the blocker. Future execution needs a fresh complete forecast
and namespace plus restoration/audit of the original missing inputs or a
separately qualified current-input route. The pending rename helper and
sampler-only CLI are retained source drafts; neither was executed. The
rename README records the older source02 proposal, superseded by the current
plan's source03 closure. Before eventual success, also enforce a final exact
81-action count alongside the current upper bound.

| Further artifact under T | SHA256 |
| --- | --- |
| source-03-stage.json | `0fb54dd365d19ae74aa636d32232ad74e6c403f839b7a277c756ddba793cd7c7` |
| stage-03/actual-status.json | `4283d090894bf05e2c5b5e219fae4cc00e6059b3f6eda790a40e2aa747f1e2d1` |
| stage-03/repeat-status.json | `c56cebbf797689babdbd14c6fc837ca77bf539a608a2ab992dd22e6d808b8d9f` |
| bootstrap-09-comparer/actual-status.json | `c3f32a5d4ad7b12877b1e0d7ad147dfc793014b6d96b20153bbacb8b0f71b2e5` |
| qualify-launch/actual-status.json | `7bb660b18cbe62b45ea42652ca57d71da7ca3caf478fc37a2deacc60dc73bccc` |
| status.json | `8d110c7d51c4cd4cd48fd0c702409297b91f0045b7f4d8c7a1755d06a0ced8c8` |

Qualified captured artifacts: qualifier C/executable
`09d46f52593b32c474b8844fe15d76686ce67a87fb5b6cb85246e4a82ef839f6` /
`a8c9f500ec4d153c4bdc426ef39c5f10335266085d3ac830a8eacc53c0981dbe`;
comparer C/executable
`3702e1bea38d143d9e4f420c88cf07a89e534f73e299b052b335112d125adece` /
`e4de38b76849da610d1b80020954f6e4d5fed926dd05fc8e2611a8208e4192f0`.

The complete retained T bundle is sealed at
R/target-consumer-retained-20261108-01/inventory.json, SHA256
`8176439fe7d49b6ea9f61c4e89f177cf84eee5edfa1426bcebd94198b8e643c8`.
The unchanged original auditor's separate check passed. The missing-input
diagnosis and direct stat refusal are retained in T/qualify-launch. The local
`vinix-waitpid-width-20261026-01` candidate is partial: its original copy hit
the namespace cap and omitted library subtrees. The complete `-02` HOST copy
is patched. Neither is a verified restoration of the historical original.
Sources resumed from `a8e4f7d68`; callback API qualification is committed in
`b1a2e5e92`. This checkpoint adds the capture fix and pending consumer sources.

## Earlier checkpoint

2026-11-05. Work resumed after checkpoint `900d8fa50` when disk admission
recovered. SDK03 compiled successfully and passed its actual SDK/C-ABI/input
checks; source stage01 then refused an exact-count rule. The latest root
observation is 279,808 KiB available, below both the 2 GiB start and 1 GiB
live floors. All owned producers retired. No TARGET compiler consumer,
native sampler, rename controls, kernel build or VM started. The new APIs and consumer
feature remain unvalidated drafts. Only this checkpoint report is committed.

R is `/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01`;
T is R/target-consumer-host-01. The bounded refusal receipt is
T/admission-refusal-01/refusal.json. Earlier owned sources and their hashes
are preserved at T/draft96-01; the final source-only correction is preserved
at T/draft96-02. No historical input or completed profile was
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

SDK03 returned 0 with explicit sysroot26.5. Independent review confirmed all
four native manifests use canonical SDK26.5, actual C uses private HOST inputs
and i32 wait statuses, and selectors/environment/sandbox match the plan.
Original HOST and nine source postchecks returned 0; 326 resource-header and
seven direct tool/SDK rows matched before/after. The status at
T/bootstrap-03/actual-status.json is
`fb656b982ee02de2c9473887818aa35b18da1aab80fadcfdac37720b46ce44eb`;
C is `b67a107f6263d0993281c9431155be22262d110ead53211a104ad485f94d3350`
and the executable is
`62bf6d0889fdc7f768f8afc4c5c23343bc861cdef5f1b7ec17638b1109eb9707`.

Stage01 returned 1: `fixed comparer derivation exact count`. Its untouched
T/source contains 61 regular files and four literal module links; all regular
copies compare equal to main. Helpers and the stage receipt were not completed.
No matching owned producer remained. T/stage-01/actual-status.json is
`ef2d088160c7a3c982667fd4f64d070bc9fe24a4415579788a87139929b760d2`.

## Pending sources and next gate

The source-reviewed revision adds explicit `-cflags '-isysroot SDK26.5'` to
all V C-emission routes, preserving strict manual clang sysroots and the
existing nativeguard owner. No C-only or sampling-cadence rewrite was made.
The unrun correction uses explicit per-rule counts `[1,1,2,1,1,1,1]` and fresh
source-02 capture, receipt, derivation and endpoint names. The failed source
tree remains untouched. Future HOST builds omit only `-keepc`: the matched
driver's explicit `-b c` path retains OUTPUT.c; all older duplicates remain.
The phase umbrella is 96 MiB inside the unchanged 512 MiB kernel cap:
80 MiB working, including 4 MiB reserved for main-index/Git transactions,
and a full 16 MiB final tail. Producer endpoints retain the Git reservation
and enforce 76 MiB. Historical failed states remain charged.

| Draft source | SHA256 |
| --- | --- |
| qualify-current-target-consumer.v | `8b896e359c40bc847d05cf32c043c716ec565916617e624a3383c4d84e4b2fdc` |
| current-target-consumer-plan.md | `eb099f639321287640c734ea0dd545184fdfd5f5ae2715653468f719767fdafc` |
| current-target-consumer-sources.txt | `4dcd8e747972d385aba2ece885a075fdeec33844aae0996545b2f9c94c73c8f5` |
| currenttargetrecord/core.v | `e5d57cb19b503096bde194f43a8e9fef4242bdba0b9dfeff7cff674d2ca4c407` |
| currenttargetprobe/main.v | `aea18d488144844ede18dedda7ce3dc78e28cd2b06d37aa16074e0923a087367` |
| generators/core.v | `24f27359c414c7124ce1e994207a00d74e17f8832eb4a9d0deaef1d694ce0739` |
| hosttest/module.v | `5842a82733b29c2a40aa952799913f1b17041971fbcfd171ff74470c6c292327` |
| callback-controls.v | `16b86b22e81c06231c0949a5a8bc2beee712e3ff8a0f4796824f0cc235d1c15a` |
| preserveoutputs/core.v | `ffc04263138c29c1c8dbaef7a65113283ad753968546e42cad331f06893bf437` |
| preserve-outputs-controls.v | `d61c643cd05824f0605c0a0127d270017956ed2e9bf500a0aee21280cfcb28e7` |
| preserveoutputs/README.md | `7faf6f4f367e30b24c2a49f7df5120532c2017f61809835c5ba9598cea07f389` |

Also pending are the sampler-only/ordinary-failure changes in
tests/native-generators/test-generators.v and the two ordinary-build callback
test files. Four unrelated LinuxKPI callback files were restored exactly.
The complete pending-path list and byte hashes are in the external snapshot.
Two independent source/reverse checks passed for the correction; it has not
been compiled or run. Current complete T occupies 15,272/14,208 KiB in
allocated/apparent space before the small final receipts. Its 14 MiB future
HOST forecast totals 29,608 KiB allocated, leaving 1,112 KiB within the 30 MiB
bootstrap row; every next actual launch must remeasure all named rows.

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
