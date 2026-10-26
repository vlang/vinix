# Signed application PCM portal host qualification

The output-only PCM portal retains the signed generation lease before account
isolation, binds the handoff to the package ID, generation and canonical manifest
digest, and exposes one private socket to the isolated application. The account
service requires the launch transport and worker's immutable cached kernel login
labels to match the current seat. Missing `SO_PEERLOGIN` support fails closed.
Applications receive no DSP path or direct audio pledge. The fixed stream is
S16LE stereo at 48 kHz, with acknowledged chunks of at most 4096 bytes.

`audio-portal-host-check.v` passed **52 checks** on 2026-10-26 from a retained
source/compiler snapshot based on `4e378889d`, with the `ca68e994b` Wine ABI
prerequisite applied as `298b37dbf`. This report's accompanying production and
test sources are pinned individually in the retained input manifest; the base
revision alone does not identify the modified source.

- Six portal, three transport and two launch tests use explicit checks that
  execute in normal, `-prod`, and ASan/UBSan builds.
- Portal checks cover private descriptor/inode/mode admission, peer-label ABI and
  seat matching, bounded identity parsing, framing and refusal acknowledgments,
  caller lease death, complete bootstrap binding, and 1000 warmed proof cycles
  with zero retained V storage.
- Transport checks cover exact version 1/2 byte compatibility, canonical version
  3 parsing, all truncations, integer overflow, field/selection mismatches,
  ambient authority refusal, and 1000 decode/close cycles with zero retained V
  storage. Every truncated input also retires its tracked V storage.
- Historical protocol, display, ownership, client ownership, stream, application
  launch ownership and session launch ownership suites passed normally and with
  sanitizers. Historical assertion-based suites are not counted as `-prod`
  validation.
- The actual package and account-session entrypoints generated production C for
  AArch64 and x86-64. These checks do not claim target linking or guest playback.

The retained bundle is
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal-20261026/host-02`.
It contains the selected V executable (`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`),
its complete vlib/thirdparty sources, application/account sources, test binaries,
literal command arrays, compiler/test logs and generated C. The runner hashes
every retained source/compiler input before and after qualification. Host Clang
is identified and hashed; the host SDK/linker/runtime are not a hermetic snapshot.
ASan leak detection is disabled; the V allocation tracker supplies the stated
retention checks, and ASan/UBSan cover invalid memory access and undefined behavior.

Receipt SHA-256:

- `inputs.json`: `44b77ff710deee1ad7b22cff7da6addf82297bae63aec7464abce28a4c8bd534`
- `qualification.json`: `226c205fe82c47fef23508147f4896d195271eb4565b120dc40be7851fe3d075`

An earlier `host-01` diagnostic completed its checks but rejected its receipt
because source changed during execution. It was not qualified and was removed
under disk pressure. Only the frozen, successfully rehashed `host-02` is retained.

Socket waits and nonblocking output retries observe the caller lease and bounded
deadlines. Hardware drain and final close retain the existing driver's interrupt
semantics; this host run does not qualify stalled hardware. A forced startup kill
before the parent records the endpoint inode can leave one fresh private nonce
socket; normal portal closure removes only its recorded inode. Actual healthy
VirtIO/HDA output, seat switching and launch cleanup require the separate native
guest qualification. Mixing, capture, ALSA/Pulse compatibility and Wine audio
translation are outside this fixed PCM transport.

The native compiler exposed incompatible socket-address pointers at the C
boundary. Revision `f50041955e6f68b8464503c357b30e89abd77d1e` adds
module-specific bind/connect aliases with explicit `const struct sockaddr *`
casts. The maintained portal test now binds, listens, connects and accepts a
real pathname socket. Independent review found no descriptor lifetime issue.
All six focused normal, production and ASan/UBSan compile/run checks passed
with tracking enabled, including the existing 1,000 proof cycles.

The complete delta evidence is retained at
`/Users/alex/Library/Caches/vinix-codex/section14/audio-connect-delta-20261026-02`;
`qualification.json` SHA-256 is
`c9eb7f31728406c251ab7bb028f666bdb82e5dec68f5ffafd4c82ca8eeb92ecf`.
Its source inventory binds the four changed files. These host checks reuse the
previous frozen standard library without independently rehashing it and tolerate
its historical waitpid pointer warnings. Target compiler diagnostics remain
enabled; a corrected target link and guest playback remain pending.
