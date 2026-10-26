# Signed native audio qualification: preparation

The controller builds signed `tone` and `noaudio` packages, real
account/session/package CLIs and an isolated payload. Three scenarios cover
ordinary active-seat playback, refusal controls, process cleanup and seat
changes. Every guest check remains active in production builds.
**Real guest audio acceptance is pending.**

Production base: `df766e9e446ffe0cbe6f5fa446c1c0278a789da9`;
strict socket-address C boundary fix: `f50041955`.
Wave oracle: `7c15b7aa3e196f9fdf85fa75c212af63a9ab63bd`.
Initial evidence tools: `32a97777573dcfa49992d642362c1ea2cc1a01b0`.
Initial guest fixtures: `20b2bdd26`.
Frozen-sysroot evidence tools: `829c5532f9d545e359ef6f08777217345ca98dfb`.
Frozen-sysroot controller: the commit containing this update.

| Preparation check | Result |
| --- | --- |
| Current input checker and retainer/evidence tools, host `-prod` | PASS |
| Current controller host rebuild | PASS, explicit C backend / LLVM clang |
| Historical guest and payload `-prod` Linux C generation | PASS, both architectures; four translations |
| Rooted capture, selected-input refusal and adapter controls | PASS, 36 controls |
| Current V probe and tone, actual AArch64 static target links | PASS, 2 further controls; selected-input traces admitted |
| Current evidence matrix, synthetic AArch64 | PASS, 34 controls |
| Current evidence matrix, synthetic x86_64 | PASS, 34 controls |
| Native admission of current synthetic receipts | Refused, both architectures |
| Stereo waveform oracle | PASS, 19 controls |
| Real playback, refusal, cleanup and seat scenarios | Pending |

External evidence is retained at
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal`.
Historical `validation-final-01.txt` contains the initial evidence-tool commands,
hashes and complete result paths; SHA-256
`d2ce8f2e5a01797b71a3fa6cec398d4cced0903783fa38c86dec086ceee757ae`.
Earlier commands and hashes are in `validation-sysroot-02.txt`, SHA-256
`9e3b3c5be9739d3e8ac150a4127fa0e047356455e20d5ad4d5da908f4857e570`.
The two `retainer-sysroot-{arm,x86}-02/proof/evidence-controls.json`
SHA-256 values are respectively
`5c932011da8346e469c23a8f6fba8238f87b200cfea8642d68863dfa58821719` and
`ae57a83015eae285e1cfc827aa631073cb6d90d798af2fb5ddc8630702cec648`.
`input-final-01/result.json` SHA-256:
`f06243f9dc0a08478c9f688a92fd4b5f86a7ca3001ba22b174243be8919bd981`.
`wave-final-01/result.json` SHA-256:
`1774a8eedf0cc685e3421245eba624a81b41a08f34c7198417b79763cd0915f5`.

Historical controller logs and generated translations are under `controller-build/`:
`compile-frozen-04.log`, `cross-cc-compile.log` and
`{guest,tone}-final-{arm64,amd64}.log` all passed.
Historical controller source SHA-256:
`85ec1d2ae8e62de1ed2c8009014912b19867beb2e62f41ea3f0cdac35832b538`.
Historical compiled `audio-portal-runtime-check-frozen-vprobe` SHA-256:
`2ed99169cb3b7f8701cbbd7990063182224f8dd5b73ed6e72b98afd902c3e5b6`.
The guest supervisor's timeout path kills and EINTR-safely reaps its direct child.

Run `audio-portal-runtime-check --arch ARCH --kernel ELF --state-dir NEW`
with the pinned V environment from `validation-final-01.txt`. The compiler is
`/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v`, SHA-256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`.
For AArch64, use absolute paths from the main checkout:
`CC_AARCH64=build/package-launch-transport-work/cross-cc`,
`VINIX_AARCH64_SYSROOT=build-aarch64-userland/staging`,
`VINIX_AUDIO_CC_SOURCE=build/package-command-ownership-work/cross_cc.v`.
The historical adapter is retained as provenance. Both architectures now build
through the maintained `audio-cross-cc.v` adapter, which invokes the selected
musl GCC with the captured sysroot. The legacy receipt key `clang` does not
imply an LLVM target compiler. Set `VINIX_AUDIO_BACKEND_CC` to the absolute
matching musl GCC executable.

Set `VINIX_AUDIO_KERNEL_EVIDENCE` to
`/Users/alex/Library/Caches/vinix-codex/section14/audio-peer-login-20261026/kernel-evidence`
and select its matching `kernel-ARCH/bin/vinix`. Reviewed seal SHA-256:
`839ad75dd1ec376a8cae4e75dc1cfbddc913406dc3e136e8d4f4a412657f9b73`.
This pins observed kernel inputs and focused socket-login tests; it is not
a clean-release or reproducibility claim. Older kernels lack the required
cached socket login identity and fail closed.

The controller freezes sources, V library/stdatomic inputs, target tools,
publisher, kernel evidence and generated translations, then checks unchanged
bytes after execution. Absolute guest symlinks are resolved inside the selected
sysroot; literal link chains and flattened regular files are captured, and
their original inventories are checked again. Every target link receives that
captured sysroot. A maintained V probe generates a target C translation and
retains its ELF and GCC `-v` search trace. Original GCC internals execute at
their pinned paths; this does not establish a fully hermetic toolchain.
The retainer binds the captured files and producer-observed link declarations;
it does not independently resolve the link graph. The
generated-C dependency guard covers the pinned backend's quoted absolute
thirdparty includes. Immutable copies are hardlinked between attempts.
Complete native output must pass both maintained evidence tools, including
two-channel waveform/frequency/amplitude checks, quiet gaps, ordered markers,
guest shutdown and exact source/kernel/input inventories. Preserve and seal
the complete final bundles before recording acceptance. Cleanup claims are
limited to healthy devices; stalled hardware drain is unqualified.

Native execution remains pending after shared disk reclamation. The preserved initial
`/Users/alex/Library/Caches/vinix-audio14/prep-arm1` diagnostic stopped during
input capture on an unused recursively copied TCC directory; it produced no
guest ELF or boot. The preserved `a1` diagnostic then refused the guest-absolute
musl loader link before any target link or boot; the rooted capturer and
16 controls address that refusal. Both diagnostics remain outside Git.
The controller retains C-backend stdatomic inputs and original compiler
snapshot metadata, refusing additional uncaptured quoted thirdparty includes.
The preserved `a2` attempt reached the real AArch64 GCC14 compiler and
linked the V probe, then stopped at an incompatible SDK `connect` argument
before boot. Inspection also showed that `--sysroot` alone left original
headers and startup libraries ahead of the captured copies. The production
fix covers both `bind` and `connect`. The adapter now forces captured include
and library directories and saves each generated object; independent admission
requires all eight target traces to select their exact retained object and
captured startup/runtime inputs. Selected optional `libm.a` and `libpthread.a`
must also be regular captured files. Original/relative/foreign selected inputs,
missing captures and forged header origins are refused. Exact generated-source
warning/note locations are admitted; errors and malformed locations are refused.
Detached positive controls rebase only recorded paths and exercise the exact
generated-source warning case without changing original evidence.
The preserved `input-trace-02`, `03` and `04` diagnostics refused missing
origin metadata, a symlink command path and GCC's LTO-plugin lookup before
target linking. `input-trace-05/actual-links/` then linked the current V probe
and tone into AArch64 ELF executables. The probe's selected-input trace passed;
the tone trace refused generated-source diagnostic text before a final result
was published. Its raw GCC warnings remain retained, including V runtime macro
redefinition, const-discard and inlined scalar-push `memcpy` diagnostics. No
audio guest was booted.

The completed `input-trace-06/result.json` records all 38 controls passing,
including two actual links; SHA-256:
`a52b9ece0568a809d1f9a32c8d4d7ae506271d5736cc8d022a724b16feaa7748`.
The current AArch64 34-control evidence receipt at
`retainer-trace-arm-06/proof/evidence-controls.json` has SHA-256
`c199ed1eec595b59973bb14f0d74bc85810ca1e2f4f21e99f9871abf5f3ff28f`.
The matching x86_64 receipt at
`retainer-trace-x86-06/proof/evidence-controls.json` has SHA-256
`0910cb08c8110b7176b35c2290b6c9bb78042e954b7abef27bc9aa502e741d9a`.
These results supersede the earlier 16/26-control receipts for the changed
input and trace admission; the historical waveform oracle is unchanged.
Current commands, source/tool hashes and complete receipt paths are in
`validation-selected-inputs-06.txt`, SHA-256
`d218bebe4c362b1d8f6453cef3324eae55c44f67d2764d88a3ecb6f8e9867f9f`.
Current controller source SHA-256:
`5923add3e34ff0da48ed4ec8ac5a67fab8604f077863aa09e17fa8aa1dbebb7e`.
The successfully rebuilt `controller-build/audio-runtime-trace06` SHA-256 is
`39ed1ad8922d7ecd55e374d36efb784f750959077679144c3321078ae8bd1ea5`.
`input-trace-06/actual-links/commands.json` preserves literal generation/link
arguments. V flags match the native producer: Linux AArch64, `-prod -gc none`,
without `-manualfree`. The bounded diagnostic uses static `-O1` links with
warnings enabled and does not build all eight native programs. Its source
inventory includes the PCM module, SDK, tone and producer helpers. Captured
target bytes are hardlinked read-only from `vinix-audio14/a2`. Original V
library and stdatomic inputs must match those captured bytes before generation.
All selected source, tool and input hashes are equal before and after both
links; both inventory files have SHA-256
`950e182a17dc4805c8e07e4ece03d349bc3ab200faae4c92481d750d4a12caa3`.
`actual-links/outputs.json` pins C, preprocessed `.i`, assembly `.s`, objects,
ELFs, literal arguments and raw logs; SHA-256:
`f61354ff47d261fec132ff13043d2bf343f5ed20780b87d8c45714e56be8c223`.
No target pointer-error suppression is applied. Retained original V header
paths bind exact captured keys and hashes without requiring live originals
during an archival audit. Full native execution remains pending.
This report makes no roadmap completion claim.

## Single ARM basic diagnostic

`audio-portal-retain --diagnostic-basic RAW_RUN NEW_OUTPUT aarch64` inspects
the raw `run/packages-audio-basic` outcome, exact ordered serial controls,
guest-initiated QMP shutdown and actual stereo WAV. It calls the same
per-scenario checks as complete admission, including all three expected tones,
both channels, amplitude/frequency, one-second gaps and leading/trailing quiet.
The new output contains only `basic-diagnostic.json`, explicitly marked
`diagnostic_only: true` and `qualification: false`. Its architecture field is
the requested architecture, not independent hardware provenance. It records
the inspected raw artifact digests, checker/source digests and detected regions.
It does not admit the kernel, publisher, source/build inputs, lifecycle or seat
behavior. The normal command still requires a complete qualification receipt
and all three scenarios; no admission requirement is relaxed.

`audio-portal-basic-check RETAINER_PROGRAM NEW_CONTROL_OUTPUT` exercises a
synthetic representative raw basic positive and focused refusal controls.
These controls do not represent a guest run. Both tools must be built with
`-prod`; generated output stays outside Git. Independent source review passed.
On source base `27a05e7172f03c3b944f7f6a7a0cf3f8628481e7`, both pinned host
builds passed, all 31 focused controls passed, and the existing strict AArch64
34-control synthetic admission matrix passed with the changed retainer. The
matrix also refused its synthetic receipt in native mode. No audio VM, target
staging or image was created for this change; real guest execution is pending.

Complete external evidence is under
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/`.
`basic-diagnostic-01` preserves the initial old-V argv-concatenation compile
failure; `basic-diagnostic-02` preserves the corrected builds, generated C,
source copies, literal arguments/environment, raw logs and all control inputs.
Its `controls/basic-controls.json` SHA-256 is
`44f2c53d52b18d261588e612204d1086604546610977dc216f5eed07e96be33d`;
`strict-arm/proof/evidence-controls.json` SHA-256 is
`96fc02deadde07f4091b3737f468c5ac7c87b817c1c9a8821fcbb7e423548965`.
The complete regular-file/literal-symlink inventories are `bundle.sha256`:
`basic-diagnostic-01` SHA-256
`dbcfb07714ce214edc90ac8d70fa60f541a9b2b016539c567383a0da2ac2826c`;
`basic-diagnostic-02` SHA-256
`dec3da6499fbf061809f97674b7dec8c65ca9c2fd3a07ad5b20fe5068b9c1b2a`.

The selected source/tool maps before and after validation are equal, with
SHA-256 `fefedd98b16e8c278c7be7ef45aa6edc82a7555061a0baf9f77d82dc5b161156`.
The host builds used V SHA-256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`
and LLVM 23 clang SHA-256
`4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8`.
This pins observed selected inputs, not a hermetic host toolchain closure.
The tested retainer source SHA-256 is
`25ed785df391d2dd574b76a1a49833856c8484df900e5252b236f6256636d2d0`;
the focused runner source SHA-256 is
`ec95d77ad5a4c657fbbb23397d0727ab1b4e82d28b9f506c5de233b658feee8c`.
