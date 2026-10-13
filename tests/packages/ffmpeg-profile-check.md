# FFmpeg local media package qualification

`ffmpeg-catalog` produces a pinned FFmpeg 8.0.1 catalog for both supported
architectures. FFmpeg and FFprobe share an explicitly versioned musl/FFmpeg
runtime. The [SDK profile](../../tools/packages/SDK.md#ffmpeg-local-media-publisher-profile)
defines the payload, licenses, source archive, build tools and media subset.
The existing signed release/store workflow acquires and maintains it without
adding libraries or executables to host-global paths.

The V input builder [ffmpeg-build.v](ffmpeg-build.v) verifies the reviewed
[source archive pin](ffmpeg-source.json), snapshots it, checks archive member
paths, and builds unmodified upstream sources with the target musl compilers.
The archive was retrieved from the official upstream HTTPS release URL; the
retained pin identifies those bytes and does not verify the upstream PGP
signature. Public publishers must authenticate upstream delivery separately.
The runtime includes that complete archive, FFmpeg/musl/V/Vinix notices, the V
runner source, V build tool, source lock and build command vectors.

The build disables automatic external libraries, network, hardware acceleration,
assembler optimizations and GPL/nonfree configure options. Its local media
subset enables AVI/MPEG-4, WAV/PCM, raw video, generated test video and sine audio,
scaling, format conversion and resampling. This qualification covers the tested
video and WAV/PCM audio workflows, not every enabled filter combination or arbitrary FFmpeg
configuration. The first ARM guest found the missing `wrapped_avframe` decoder
needed by the generated-video input; the final configuration includes it.
The corresponding initial x86 run was stopped while the shared inputs were
being rebuilt. A later decode fixture required explicitly selecting the enabled
raw-video encoder for null output. Earlier diagnostics remain in the local build
work directory. The terminal fixture drains the remaining version banner while
waiting for exit; otherwise the x86 guest's PTY can fill and block the writer.

The additive SDK commands `run-args` and `run-terminal-args` append literal
arguments after the fixed signed manifest vector. `--file` separately grants
existing documents and never appends a path. Arguments grant no filesystem
access by themselves. Ordinary-account handoff, trust/policy checks, payload
verification, generation leases and terminal admission remain in force.
The old document-appending commands and signed formats remain compatible.

The distribution driver passed all **22** signing/core/protocol/registry assertion
runners, complete CLI lifecycle/refusal checks, the host PTY fixture, Software
worker/UI checks and both target package-service staging builds. Command-input
tests cover literal empty/newline/option/shell-punctuation values, count/byte
limits, NUL refusal, explicit file permissions, trust revocation and exact
credential-handoff vectors. Profile tests cover declared runtime closure and
notices, wrong targets/types/interpreters, incompatible versions, missing notices,
source-pin refusal, architecture-root links, existing output and staging cleanup.
SQLite's existing profile assertions also pass through the shared ELF validator.
Separate clang ASan/UBSan runs exercise the command and profile assertion paths;
leak detection is disabled and these runs do not establish leak freedom.

The V guest controller [ffmpeg-runtime-check.v](ffmpeg-runtime-check.v) copies
both architectures as publisher data, installs only the matching signed closure,
and invokes the production service, account session runner and native sandbox.
It checks:

- Canonical repeated profile inventories, the pinned complete catalog and signed
  release, explicit trust enrollment and offline installation of both tools.
- Actual ordinary-account version banners and a real PTY `run-terminal-args`
  launch with clean exit; redirected terminal execution is refused.
- Encoding ten 64x48 MPEG-4 frames into an AVI named with spaces and shell
  punctuation, decoding it through the packaged libraries and inspecting it with
  the separately installed FFprobe.
- Generating a 1 kHz sine wave into a WAV/PCM file and inspecting its 44.1 kHz,
  single-channel audio stream through an explicit FFprobe file grant.
- FFprobe refusal without a document grant, successful inspection with the exact
  grant, ordinary file ownership and refusal of output outside private data.
- Retention of the shared runtime when only FFmpeg is removed, launcher removal,
  removal of the last dependent, rollback, cached reinstall after hiding the
  repository and preservation of the ordinary user's media file.

Retained evidence records 50 artifact hashes per guest, including the kernel,
init, service, sandbox, account/session tools, input build record, all 42
architecture input files and serial log. Both guests have a 600-second functional
deadline. The retained kernels/sandboxes are previously qualified cached inputs;
this increment changes no kernel code.

- [AArch64 receipt](results/2026-10-13/ffmpeg-aarch64.json) and
  [serial log](results/2026-10-13/ffmpeg-aarch64.serial.txt): 43.7 seconds.
- [x86_64 receipt](results/2026-10-13/ffmpeg-x86_64.json) and
  [serial log](results/2026-10-13/ffmpeg-x86_64.serial.txt): 54.7 seconds.
- [Input build record](results/2026-10-13/ffmpeg-input-build.json),
  [catalog lock](results/2026-10-13/ffmpeg.catalog.json),
  [host results](results/2026-10-13/ffmpeg-host.txt) and
  [toolchain/evidence ledger](results/2026-10-13/ffmpeg-toolchain.json).

This is qualification of the retained binary/compiler/kernel tuple and local
media subset. It does not qualify performance, device crash/power-cut behavior,
the complete Alpine FFmpeg catalog, graphical display brokerage or every
compatibility runtime. The fixture key is not a release publisher enrollment.
Public publisher enrollment, ordinary-user graphical sessions and the remaining
advertised native/Linux/Windows/Apple catalog remain roadmap acceptance work.
