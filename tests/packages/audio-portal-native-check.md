# Signed native audio qualification: preparation

The controller builds signed `tone` and `noaudio` packages, real
account/session/package CLIs and an isolated payload. Three scenarios cover
ordinary active-seat playback, refusal controls, process cleanup and seat
changes. Every guest check remains active in production builds.
The [paired QEMU recording checks](#finalized-qemu-waveform-capture) pass.
Full sealed qualification remains open.

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

## Unsealed master-kernel runs (2026-11-19)

`SO_PEERLOGIN` is on master (`9a5ab3a60`), and the sealed kernel bundle and
pinned compiler named above no longer exist. `VINIX_AUDIO_KERNEL_UNSEALED=1`
lets the controller boot a kernel built from a source tree that carries
`SO_PEERLOGIN`; it writes `kernel-unsealed.txt` and never a qualification
receipt. Other inputs for current tools: `V` a compiler whose
`vlib/os/process_nix.c.v` passes waitpid an `i32` status (clang 23 and GCC 14
refuse the `i64` one), `VINIX_AUDIO_HOST_CC=/usr/bin/cc` (Homebrew LLVM 23
refuses the same C), `VINIX_AARCH64_SYSROOT` the musl-cross sysroot, and
`VINIX_AUDIO_BACKEND_CC` its GCC.

On AArch64 every program now builds and links, the guests boot, and setup
(accounts, authd, signed `update` and `install`) passes. Getting there took
fixing strings freed after an array push or by `[]string.free()` while the
array only borrowed them (`6efe4d0c8`, `1d4785f41`, `8ae9a5865`, `e024ff011`;
see `tests/push-ownership`), and a V fix for `os.Process` under a program's
own `waitpid` declaration (vlang/v#32595, needed until it is in the compiler
used).

On 2026-11-20 all three scenarios passed on both architectures against
kernels built from `9a5ab3a60`, with `CC_AARCH64` a small front that drops
clang-only flags before calling the musl GCC (the `build/` adapters named
above are gone). Recordings, measured by zero crossings and peak per second
(AArch64) or per audible run (x86_64):

| Scenario | AArch64 (HVF) | x86_64 (TCG) |
| --- | --- | --- |
| basic | 440, 660, 880 Hz, 1.00 s each, both channels, peak 12000 | 440, 660, 880 Hz, about 1 s each, silence between |
| lifecycle | 440, 660, 880, 440 Hz, 1.00 s each | 440, 660, 880, 440 Hz, about 1 s each |
| seat | 440, 880 Hz, 1.00 s each | 440, 880 Hz, about 1 s each |

Real playback is shown on both architectures. The x86_64 column is from a
kernel with `e385b64b3`: before it, the HD Audio driver replayed old ring
contents whenever the portal paused between tones and queued the next tone a
whole ring later, which garbled every tone after the first.

`audio-portal-retain` still refuses these runs, for three reasons outside the
portal:

- QEMU no longer finalizes the WAV header, and on AArch64 records no silence
  between streams, so the one-second gap and quiet checks cannot hold.
- On AArch64 the payload's own `AUDIO PAYLOAD` lines never reach the serial
  log. The guest writes to `/dev/console`, a seat device, and the payload runs
  in its own isolated login, which does not hold the seat, so the kernel refuses
  its writes as designed. AArch64 has no serial node outside the seat; x86_64
  writes to `/dev/com1`, which is not one. The guest's marker files still prove
  each step.
- The runs are unsealed, so there is no qualification receipt to admit.

## Isolated payload serial relay

At `14e7ca67e`, the guest captures each ordinary package session's stdout and
stderr in a private root-owned file. PID 1 relays the bounded output after
the session is reaped, preserving the payload's actual lines and the seat
permission checks. C generation writes `generate.log` and target linking
writes `build.log`, so the existing link-input verifier receives a clean trace.

The basic, lifecycle and seat scenarios passed on both architectures with
the retained `7c10afe81` kernels and QEMU 11.1.3. All six runs initiated their
own shutdown. The exact ordered serial checker passed on the raw logs,
including the payload identity and direct-device refusal markers. The 37
diagnostic host controls passed, including five altered serial refusals.
All 14 hardware harness host test files passed.

Run `audio-portal-retain --diagnostic-serial basic SERIAL_LOG` to reproduce the
serial check. Substitute `lifecycle` or `seat` for the other scenarios. The
full qualification still requires sealed kernel evidence and finalized audio
recordings. All six recordings have unset RIFF lengths. The strict raw basic
diagnostic reached waveform admission and refused the unfinished recording.

The raw scenario outputs, checks and selected source, kernel and tool digests
are in `~/.local/state/vinix/r14-audio-serial-rB8qLx/qualification.tar.gz`.
Its SHA-256 is `22be99a5cf96f64f3ca06e1b801d4d20dbaab21a3cc98d9ac782cf1e8c1fa0d2`.
The extracted tree passed every entry in its `qualification.sha256` manifest.

## Finalized QEMU waveform capture

At `d8f27b46c`, the controller starts QEMU's monitor capture at the guest
start marker and stops it after the final pass marker, while QEMU can still
finish the WAV header. QEMU 11.1.3 exposes these monitor commands as
deprecated. The signed tone fixture submits 1.25 seconds of silent PCM on
each side of every tone through the ordinary audio portal. The controller
requires a finalized WAV and the retainer checks its original stereo samples,
ordered serial markers and guest-initiated shutdown.

All six final recordings from the basic, lifecycle and seat scenarios pass
the strict checker on AArch64 VirtIO sound and x86-64 HD Audio. It verifies
the expected tone sequences, frequency, amplitude, duration and quiet
intervals. The checker still refuses both earlier basic recordings because
their RIFF lengths are unset. The host checks passed 19 waveform controls
and 40 diagnostic controls. The strict evidence matrix passed 35 controls
per architecture. Native qualification still requires an independently
reviewed seal for the retained `7c10afe81` kernels used in these runs.

Run `audio-portal-retain --diagnostic-recording basic SCENARIO_DIRECTORY`
against the original scenario directory, or select `lifecycle` or `seat`.
The raw WAVs, QMP and serial logs, verdicts and selected input digests are in
`~/.local/state/vinix/r14-audio-waveform-nlujq3/qualification.tar.gz`.
Its SHA-256 is `477675c493322ecbc372d246c5f5ca0bbfe8db826d4f6f839a80f313eedf7fc3`.
The extracted files passed every entry in `qualification.sha256`.

## HD Audio stall and close recovery

At `52ea5d1fc`, HD Audio waits for playback with a two-second monotonic
stall deadline that renews when audio makes progress. A write that already
queued bytes returns that count. A write that queues nothing and an
explicit drain report the timeout. The OSS layer also carries errors from
the existing VirtIO and Apple speaker drain checks. Closing a stream still
stops and resets the driver before releasing the device owner.

The `hda-stall` scenario ran with `VFLAGS=-d hda_stall_test` on x86-64.
Suppressing playback completions at 44.1 kHz produced an exact 1 MiB
partial write, a write timeout at 2.000 seconds and a drain timeout at
2.001 seconds. Close returned, a new 48 kHz stream drained a short buffer,
and the guest shut down. The fault injection is absent from the ordinary
kernel build.

Ordinary AArch64 and x86-64 kernels passed all six signed audio guest and
strict waveform checks. Both package audio host suites and all fourteen
hardware harness host suites passed. The stalls exercised here are
emulated HD Audio playback completions. VirtIO stall recovery, physical
Apple speaker faults and independently reviewed kernel seals remain open.

The raw logs, waveforms, build logs and selected digests are in
`~/.local/state/vinix/r14-hda-stall-yBvEPW/qualification.tar.gz`.
Its SHA-256 is `a2826aabe3e03479429b8c5ffd5c45738aea6909f3f39fd9e464f3a201023b02`.
The extracted files passed every entry in `qualification.sha256`.

## VirtIO sound stall recovery

At `38e65d19f`, a VirtIO sound control timeout blocks further requests on
the shared control page. If STOP or RELEASE fails, or RELEASE leaves PCM
descriptors outstanding, the driver waits for an acknowledged device reset
before rebuilding both queues in their existing DMA storage. If the reset
also times out, a subsequent open can retry it on the first write.

The AArch64 `virtio-sound-stall` guest completed two cycles with
`VFLAGS=-d virtio_snd_stall`. Both stalled writes preserved the queued
16 KiB prefix. The following writes and explicit drains returned
`ETIMEDOUT` in 2.003–2.006 seconds. In the first cycle, the withheld STOP
and reset requests timed out during close. The next stream recovered on
its first write. In the second cycle, close reset the device after the STOP
timeout. Both fresh 48 kHz streams accepted and drained more than one
ring of PCM, and the guest shut down.

The ordinary AArch64 kernel passed basic, lifecycle and seat playback
with the strict waveform and shutdown checks. Its logs showed no
recovery resets. The x86-64 HD Audio stall fixture and all fourteen
hardware harness host suites also passed. Physical Apple speaker faults
and independently reviewed kernel seals remain open.

The raw scenario outputs, build logs and selected digests are in
`~/.local/state/vinix/r14-virtio-sound-stall-HAaRJd/qualification.tar.gz`.
Its SHA-256 is `fa04a042e05e17a5ad5fa404ad82f9f45eb1f328e40bf01f19ad65b76a708b16`.
The extracted files passed every entry in `qualification.sha256`.

## Apple speaker drain fault reporting

At `47865336e`, the Apple OSS stream checks for a latched protection fault
before returning success for an inactive stream and again after the final
drain wait. A detected fault returns `EIO`. The protection shutdown stays
latched when the stream stops or a caller tries to configure it again.

The `apple-speaker-drain` scenario runs the real kernel drain path on
AArch64 QEMU with `VFLAGS=-d apple_speaker_drain_fixture`. The fixture
provides a simulated amplifier shutdown pin and injects a fault before
drain and at the end of the 20 ms drain wait. Both drains returned
success on the `514bc9a65` baseline with the same injection. The fixed
kernel returned `EIO` in both cases, drained healthy idle and empty
streams, kept the shutdown pin asserted, and refused reconfiguration
after the fault. Both guests powered off normally.

The ordinary AArch64 kernel contained no fixture symbols and passed the
`devices` scenario. All fourteen hardware harness host suites passed.
The existing J313 model passed its original/V goldens, C ABI, ASan/UBSan
and allocation checks. Physical Apple speaker qualification and
independently reviewed audio kernel seals remain open.

The raw build and boot logs, kernel ELFs, generated C, model results and
source patches are in
`~/.local/state/vinix/r14-apple-speaker-m40hNS/qualification.tar.gz`.
Its SHA-256 is `93cc72d9f7c97b0ebcf7471924e2844b7464859f61d51082bb3de1ebbbe1094b`.
The extracted files passed all 42 entries in `qualification.sha256`.
