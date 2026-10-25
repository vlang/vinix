# Signed Wine Win64 native qualification

Current status: **runtime qualification is incomplete**. The retained
[checkpoint](wine-native-checkpoint.md) records the previous failed guests.
The [nested bridge qualification](wine-nested-bridge-check.md) adds private
native child bridges and an adjacent ordinary musl copy so Wine can discover
its loader, server and data through its own executable-directory rules. Both
prepared architectures pass independent layout and source-binding controls;
these host checks do not establish a passing signed Wine launch.

The current production retainer verifies the x86-9 input/output provenance and
then refuses its failed outcome, leaving no retained success directory. The
control runner also refuses that baseline before any mutations. Its full
resealed refusal matrix remains unqualified until there is a real passing
native baseline. AArch64 additionally fails in QEMU's translated fork path;
the separate [translated-fork fixture](wine-translation-fork-check.md) records
that boundary without claiming Wine qualification. No Calculator UI or
ordinary graphical Wine execution has passed.

This fixture is designed to run an actual AMD64 PE32+ console program through Wine 9.17-r1
under an ordinary Vinix account. The runtime and application are separate signed
packages with an explicit runtime dependency and only the `process` permission.
The probe uses Windows file APIs, checks that an out-of-scope write is refused,
and exits naturally. This is a local qualification fixture, not Calculator UI,
a production catalog, or redistribution approval.

The producer requires `--local-qualification-only` and a strict partial-source
record. Its signed runtime includes that complete supplied record. The input
closure has Wine, QEMU where needed, and many dependent APK origins; captured
recipes and notices do not constitute complete corresponding source. The
producer refuses a claim that this source closure is complete.

The PE is built by [wine-pe-check.v](wine-pe-check.v). Before and after preparing
the runtime, `wineadapter.admit_local_pe_proof` verifies its exact source,
generated C, executable, link map, literal commands, environment, and complete
recorded V/MinGW input inventories. The runtime producer and native retainer
bind the packaged executable to that admitted PE; READY/PASS text alone is
insufficient.

The fixture uses its own PID1 and creates an ordinary UID/GID 1000 account.
It invokes the installed package CLI through its ordinary-account isolation
boundary. The controller builds that CLI from its captured current package and
account-module sources and retains generated C, ELF, literal V/Clang commands,
and compiler logs. The staged CLI must equal that built ELF. Account/session
tools remain separately pinned archived-stage inputs. This distinction avoids
using the archived stage's older package sandbox policy while attributing it
to current source. During the real PE's bounded wait, it requires actual Wine client and
server processes with four UID/GID values equal to 1000, a private mode-0700
prefix and server directory, an ordinary-owned server socket, and a held
generation lease. It checks exact Windows-created file bytes and ownership,
absence of the forbidden host file, natural CLI exit, both observed process
entries gone after reaping, and successful exclusive lease acquisition after
retirement. The host harness stops the guest after its final PASS; this fixture
does not prove guest poweroff or normal-init startup.

The lease checks cover READY and retirement after both observed processes
exit. They do not establish that the package generation remains leased after
the client exits while a detached wineserver remains alive. Plain
`wineserver -w` also requires separate lock-error, prefix-replacement and
startup-race qualification before it could close that gap.

On AArch64 the same guest first runs real x86 BusyBox `true` as UID/GID 1000
with the original and patched translators. The original must fail and the
exact split-WX patch must succeed, with `VINIX_ALLOW_WX` absent. The signed Wine
execution then uses that same patched translator. See
[wine-prefix-check.md](wine-prefix-check.md) for the pinned Wine private-prefix
and QEMU instruction changes, host refusal tests, disassembly, and measured
descriptor/allocation lifetimes.

The independent retainer requires a production build so its embedded source
bytes are fixed, and uses explicit error returns that remain active in that
build. It verifies the native result, exact ordered markers and forbidden
failures, source/input inventories, PE proof, producer outputs, generated
C/ELF/argv/logs, staged account/package/sandbox bytes, and translator patch and
smoke bindings before creating output. Disposable refusal controls first
require both original and copied evidence to pass, then mutate and reseal one
boundary at a time; refusal must leave the requested retained output absent.

Compile the V host tools with the pinned compiler settings used by
[wine-prefix-check.md](wine-prefix-check.md). The runner and guest deliberately
use explicit checks; host unit tests need assertions enabled. The production
retainer and evidence controls require `-prod` for embedded source binding.
The tools' positional interfaces are:

```text
wine-build ARCH TRANSLATION_STAGE NEW_PREPARED V MUSL_SYSROOT GCC_RUNTIME NOTICES PE_PRODUCER --local-qualification-only
wine-native-check ARCH NEW_RUN PREPARED KERNEL ASSEMBLED_STAGE MUSL_SYSROOT GCC_RUNTIME SANDBOX
wine-native-retain RUN PREPARED ARCH NEW_RETAINED
wine-evidence-check RETAINER RUN PREPARED ARCH NEW_CONTROLS
```

Keep the source tree and all captured producer inputs unchanged from producer
capture through native verification and retention. The receipts name local
absolute artifacts; they are qualification evidence, not a hermetic or
reproducible-build assertion. Local signing keys remain outside the guest and
are never production trust inputs.
