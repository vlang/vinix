# Signed native audio qualification: preparation

The controller builds signed `tone` and `noaudio` packages, real
account/session/package CLIs and an isolated payload. Three scenarios cover
ordinary active-seat playback, refusal controls, process cleanup and seat
changes. Every guest check remains active in production builds.
**Real guest audio acceptance is pending.**

Production base: `df766e9e446ffe0cbe6f5fa446c1c0278a789da9`.
Wave oracle: `7c15b7aa3e196f9fdf85fa75c212af63a9ab63bd`.
Initial evidence tools: `32a97777573dcfa49992d642362c1ea2cc1a01b0`.
Initial guest fixtures: `20b2bdd26`.
Frozen-sysroot evidence tools: `829c5532f9d545e359ef6f08777217345ca98dfb`.
Frozen-sysroot controller: the commit containing this update.

| Preparation check | Result |
| --- | --- |
| Controller host `-prod`, explicit C backend / LLVM clang | PASS |
| Current guest and payload `-prod` Linux C generation, both architectures | PASS, four translations; no target links or boots |
| Rooted sysroot capture `-prod` controls | PASS, 16 controls |
| Evidence tools `-prod`, synthetic controls | PASS, 26 per architecture |
| Native admission of synthetic receipts | Refused on both architectures |
| Stereo waveform oracle | PASS, 19 controls |
| Real playback, refusal, cleanup and seat scenarios | Pending |

External evidence is retained at
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal`.
Historical `validation-final-01.txt` contains the initial evidence-tool commands,
hashes and complete result paths; SHA-256
`d2ce8f2e5a01797b71a3fa6cec398d4cced0903783fa38c86dec086ceee757ae`.
Current commands and hashes are in `validation-sysroot-02.txt`, SHA-256
`9e3b3c5be9739d3e8ac150a4127fa0e047356455e20d5ad4d5da908f4857e570`.
The two `retainer-sysroot-{arm,x86}-02/proof/evidence-controls.json`
SHA-256 values are respectively
`5c932011da8346e469c23a8f6fba8238f87b200cfea8642d68863dfa58821719` and
`ae57a83015eae285e1cfc827aa631073cb6d90d798af2fb5ddc8630702cec648`.
`input-final-01/result.json` SHA-256:
`f06243f9dc0a08478c9f688a92fd4b5f86a7ca3001ba22b174243be8919bd981`.
`wave-final-01/result.json` SHA-256:
`1774a8eedf0cc685e3421245eba624a81b41a08f34c7198417b79763cd0915f5`.

Controller logs and generated translations are under `controller-build/`:
`compile-frozen-04.log`, `cross-cc-compile.log` and
`{guest,tone}-final-{arm64,amd64}.log` all passed.
Controller source SHA-256:
`85ec1d2ae8e62de1ed2c8009014912b19867beb2e62f41ea3f0cdac35832b538`.
Compiled `audio-portal-runtime-check-frozen-vprobe` SHA-256:
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
This report makes no roadmap completion claim.
