# Graphical account login qualification

The graphical session manager runs the initial registration screen exclusively
as root, imports the first administrator, starts or verifies the root
authentication service, and launches the login screen as the ordinary `greeter`
account. Login, switch and logout go through the root manager's inherited fd 3
channel. The client verifies the root peer before sending a bounded password;
ordinary applications lose that descriptor on exec. The login screen provides
name, masked password and Sign in controls. Desktop account controls provide
switch and logout; desktop power requests also use the manager.

Both default image staging paths install the account tools/actions and session
manager. ARM `initcore.desktop_start()` and AMD64 `desktop-init` now invoke
`vinix-session graphical --desktop …`. A missing GPU desktop selects the
software desktop. The existing recovery shell remains available when the
manager exits unsuccessfully. Executable GPU files that fail at exec are a
separate fallback follow-up; this qualification does not cover that case.

## Accepted native evidence, 2026-10-22

The final frozen compositor pair 5 and native graphical pair 10 passed on
AArch64 and x86_64. Each controller exited 0 after eleven ordered, exact guest
markers. Independent retention admitted the full captured input inventories,
account C/ELF/action outputs, compositor C/ELF, literal compiler and QEMU argv,
guest C/ELF and eight decoded 1024×768 PNGs before publishing these records:

| Architecture | Native GUI receipt | Refusal controls | Native fd 3 channel receipt |
| --- | --- | --- | --- |
| AArch64 | [receipt](results/2026-10-22/aarch64/receipt.json) | [baseline + 24](results/2026-10-22/aarch64.controls.json) | [receipt](results/2026-10-22/channel-aarch64/receipt.json) |
| x86_64 | [receipt](results/2026-10-22/x86_64/receipt.json) | [baseline + 24](results/2026-10-22/x86_64.controls.json) | [receipt](results/2026-10-22/channel-x86_64/receipt.json) |

The guest starts with no person account. All registration credentials, wrong
passwords, login and account actions enter through real compositor keyboard and
pointer input. It verifies:

- Root registration precedes an ordinary UID 101 greeter; a wrong password
  creates no person session.
- Correct login creates UID 1000's actual compositor, owned home, private
  runtime directory and ready marker, and a kernel login-session identity.
- Switching stops the prior session and revokes its seat before the greeter
  appears. Reauthentication resumes the same PID and kernel session.
- Logout reaps the old compositor and descendants before the new greeter.
  Another login uses a fresh PID/session and preserves the account home.
- Manager shutdown retires its remaining session and owned authentication
  daemon. The observer reaps actual adopted zombies rather than ignoring them.

The separate channel pair 4 uses real root-created socketpairs inherited across
the UID drop on both kernels. It checks root peer credentials after the drop,
exec descriptor loss, HUP failure without closing the borrowed fd, forged
ordinary peers refusing the password, regular/arbitrary descriptors, and a
bounded incomplete reply. Each of its eight exact markers occurs once between
START and PASS. `channel-retain.v` independently verifies its captured sources,
manifests, output hashes, result, argument bindings and serial markers before
copying logs, generated C and ELF.

Each GUI control reseals a disposable copy. Missing, duplicated or reordered
markers, panic, failed result, missing/extra PNG, changed artifact, altered
controller/QEMU/guest argv, substituted frozen fixture, jointly omitted source,
V library, sysroot or account action, omitted frozen desktop manifest entries,
and changed desktop/account compiler bindings must all refuse before creating
an output directory. The original runs are never edited.

Representative images: [registration](results/2026-10-22/aarch64/01-registration.png),
[greeter](results/2026-10-22/aarch64/02-greeter.png),
[ordinary desktop](results/2026-10-22/aarch64/04-ordinary.png),
[x86 greeter](results/2026-10-22/x86_64/02-greeter.png), and
[x86 ordinary desktop](results/2026-10-22/x86_64/04-ordinary.png).

## Reproduction

Use the repository's qualified V compiler with its explicit no-fallback caller
environment. The final run used
`build/package-https-runtime-work/toolchain/v`, UI2 at
`/Users/alex/code/ui2`, LLVM at `/opt/homebrew/opt/llvm/bin`, and the staged musl
sysroots. Receipts record the complete literal arguments and captured SHA256
inputs. Compile the builder and all controllers/retainers with `-prod`; they
embed and verify their own source. `-path` also needs the local module directories
shown below (and `desktop/tools` for the builder):

```sh
$V -prod -cc clang -nocache -path '@vlib|.|desktop/tools|tests/linuxkpi|build-support|@vmodules' \
  -o build/login-build tests/graphical-login/build.v
build/login-build --arch=aarch64 --ui=/path/to/ui2 --out=/new/desktop-build

$V -prod -cc clang -nocache \
  -path '@vlib|tests/graphical-login|tests/hardware-platform|tools|build-support|@vmodules' \
  -o build/login-check tests/graphical-login/check.v
$V -prod -cc clang -nocache \
  -path '@vlib|tests/graphical-login|tests/hardware-platform|tools|build-support|@vmodules' \
  -o build/login-retain tests/graphical-login/retain.v
```

Stage the actual five account executables with the `-prod` account staging tool,
`--include-session --evidence /empty/owned0700/proof`, retaining its literal
`--cc-argv`. Then run:

```sh
build/login-check ARCH KERNEL DESKTOP_BUILD ACCOUNTS_STAGE ACCOUNT_PROOF NEW_RUN SHARED_CHECKOUT
build/login-retain RUN DESKTOP_BUILD ACCOUNTS_STAGE ACCOUNT_PROOF KERNEL CONTROLLER NEW_OUTPUT ARCH
```

The evidence control helper takes
`RETAINER RUN DESKTOP_BUILD ACCOUNTS_STAGE ACCOUNT_PROOF KERNEL CONTROLLER NEW_WORK ARCH`.
The channel controller takes `ARCH KERNEL NEW_RUN SHARED_CHECKOUT`; its retainer
takes `RUN NEW_OUTPUT ARCH`. Set the corresponding `CC_AARCH64`/`CC_AMD64`
compiler, staged sysroot and ARM cross-driver pin as recorded in the receipts.

Host checks also passed: actual greeter scene/state tests with ASan/UBSan;
production manager preparation/attendance extracted into a controlled launcher
with forked secret storage and a real delayed child; a negative replacement of
blocking wait with the old `WNOHANG` cleanup; repeated channel/root-peer checks;
and digest/serial admission tests. [Collected host logs](results/2026-10-22/host/checks.json)
record these commands' observed successful exits. The parent independently
reviewed the new production lifetimes and root-peer boundary before commit.

## Scope

The native fixture is a minimal PID 1 observer that invokes the actual manager
and real staged programs. It proves graphical registration/login/switch/logout,
not a boot through the complete normal image init or an installed VJFS root.
The host explicitly stops and reaps its owned QEMU after PASS; it does not claim
guest poweroff. The minimal image has no Files executable, so its default Files
startup diagnostic is expected. This is not signed Software maintenance,
installed application acceptance, X11/Wine, or production catalog qualification.
Those gates retain their own evidence and release-owner inputs.

Desktop receipts cover the complete captured source, V library, UI2 and sysroot
inventories. Account/channel receipts describe their narrower captured inputs;
they do not imply a complete underlying wrapper compiler or account sysroot
inventory. Historical paths and repository HEAD are provenance metadata,
while frozen source/content digests bind the qualified bytes.
