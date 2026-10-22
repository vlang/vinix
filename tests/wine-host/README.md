# Authenticated hosted X11 checks

Hosted X11 applications use a fresh private surface and a securely generated
MIT-MAGIC-COOKIE-1 authority. Ordinary accounts use
`/run/user/<uid>/vinix-hosted-x11/<exclusive-leaf>/Xauthority`; the surface is
0700 and the authority is 0600. The root legacy wrapper uses
`/run/vinix-hosted-x11/<exclusive-leaf>`. Xvfb receives `-auth`; the server,
bridge and child receive the same validated `DISPLAY` and `XAUTHORITY`.

The shared V `x11auth` module opens and checks directory chains without following
symlinks, refuses existing surface leaves, checks authority ownership and bounded
binary contents, and validates the selected socket beneath the trusted sticky
`/tmp/.X11-unix` directory. Init prepares that system directory. Package launch
allows only the exact selected socket and authority, after validating them for
the effective user; ambient authority paths are not forwarded.

Software routes display-capable foreign signed packages through the bridge with
literal arguments: `/usr/bin/vinix-package run ID [DOCUMENT]`. The signed launcher
still validates the installed generation and document, holds its launch lease,
and applies its sandbox. The account transport forwards only the validated
display/authority pair to the isolated child. Closing a signed hosted window
stops and reaps Xvfb first and waits briefly for the launcher without signaling
it. A child which continues running retains its lease until it exits naturally.
Generic signed hosting requires an ordinary compositor account; legacy root
wrappers remain available.

`auth-check.v` checks fresh/private surfaces, cookie independence, malformed
authority files, replaced or insecure parents, symlinks, hardlinks, ownership,
exact displays and permissive-umask socket-directory creation. The package
module tests cover exact unveil/environment grants, forged or missing pairs,
short embedded-NUL display strings, literal argument preservation and refusal
without mutation. `desktop-check.v` stages the real desktop and runs an
AddressSanitizer/UndefinedBehaviorSanitizer fixture for literal child arguments,
request ownership, Software routing and translations/font coverage.

Build V tools with the C backend, `-gc none -manualfree`, and an explicit module
path containing the repository, `tools/accounts` and `tests/hardware-platform`.
The native controller, retainer and corruption controls require `-prod` so their
source admission uses embedded bytes. Disable compiler fallback and compiler
error reports during qualification. The native commands are:

```text
native-check --arch=ARCH --out=NEW_RUN --kernel=KERNEL --rootfs=STAGED_ROOT \
  --sysroot=X11_SYSROOT --userland=USERLAND_STAGING --x11=X11_STAGING \
  --shell=BUSYBOX --host-tool=COMPAT_TOOL
retain RUN ARCH KERNEL CONTROLLER COMPAT_TOOL NEW_RETAINED_DIRECTORY
evidence-check RETAINER RUN ARCH KERNEL CONTROLLER COMPAT_TOOL NEW_PROOF_DIRECTORY
```

The compatibility tool is built from `build-support/native-compat-tools/main.v`.
Its `x11-build` command compiles the V bridge against the staged target X11 and
userland libraries. The native controller builds fresh account, session,
authorization, package and fixture executables from frozen account/package
sources; stages Xvfb, its libraries, XKB data/compiler and a shell; and publishes
a locally signed fixture package. The signing seed remains outside the guest.

The real QEMU guest checks an ordinary account with supplementary groups, the
isolated signed child with no supplementary groups, a literal document containing
spaces and shell metacharacters, correct-cookie access, wrong/missing-cookie
refusal, a second-account refusal, live colored-window framebuffer damage,
server reaping on bridge closure, and lease retention until natural child exit.
The final seven exact markers are emitted only after the client and authorization
service have been reaped. The host stops QEMU after these markers; this scenario
does not claim guest shutdown. The native fixture exercises the bridge, account
transport and actual signed package CLI. Software compositor routing is covered
by the host sanitizer fixture and both target desktop builds, without a native
compositor click in this fixture.

Receipts retain input/output hashes, exact compiler and image commands, generated
C, ELF bindings, boot media and serial output. The validator requires a passing
uninterrupted outcome, each exact native marker once and no forbidden marker.
The corruption runner accepts the real baseline and refuses twelve private,
resealed corruptions before creating any retained output. It does not mutate the
real run. The V executable and relevant runtime helper headers are pinned; the
entire imported vlib/thirdparty tree is not inventoried, and source additions
during compilation are not inventoried a second time. Generated C and ELFs are
bound before boot. This is a runtime qualification, not a reproducible build or
complete toolchain qualification.

The x86 fixture uses the existing `plainiso` V helper with raw USTAR initramfs and
the admitted older kernel, Limine and xorriso. It does not qualify the release
gzip image path. Audio, arbitrary foreign applications and a full supported
application catalog remain separate gates.

Retained results live in `tests/packages/results/2026-10-22/hosted-x11-*`.
Focused host checks and both architecture bridge/desktop builds passed. An
earlier broader desktop launcher runner stopped in the existing mirror-details
expectation (`package_launcher_test.v:558`); that invocation is retained as a
failure and is not counted as a full-suite pass.
