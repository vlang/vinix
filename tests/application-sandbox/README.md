# Application sandbox regression

Run portable parser and fail-closed tests on the host:

```sh
sh tests/application-sandbox/test-host.sh
sh tests/application-sandbox/test-ui.sh
```

The injected syscall tests verify that every setup failure prevents exec,
including an operation returning success without actually dropping privileges.
They cover numeric identity overflow, duplicate options and environment keys,
absolute command paths, permission parsing, and literal shell metacharacters.
The UI test compiles the actual desktop and drives its Calculator through the
compositor pipe protocol, including startup, rendering, arithmetic and close.

The independent host oracle is maintained in `hostfixture/core.v` and links
the unchanged production V launcher. It preserves the original 22 assertion
sites, all 15 invalid argument vectors, five lying syscall cases, and failure
injection at every captured setup-call position. Its fixed argv arrays stay
on the stack; callbacks borrow literal strings and copy only their pointers.
The private header contains native declarations and layout checks.

Keep generated sources, objects, executables and full diagnostics, or compare
an immutable original C fixture using the same launcher and compiler flags:

```sh
sh tests/application-sandbox/test-host.sh --keep-dir /tmp/new-sandbox-v
sh tests/application-sandbox/test-host.sh --source /immutable/host.c \
  --keep-dir /tmp/new-sandbox-c
sh tests/application-sandbox/test-host.sh --arch x86_64 \
  --keep-dir /tmp/new-sandbox-x86-v
```

On macOS, `--arch x86_64` compiles and executes the x86 host control through
Rosetta. Other hosts require their native architecture. Host builds use
AddressSanitizer and UndefinedBehaviorSanitizer; leak detection is disabled
by default. These injected callbacks model syscall outcomes, so this fixture
does not establish real kernel sandbox enforcement.

The port passed paired C/V host sanitizer controls on ARM64 and Rosetta x86,
strict static C/V builds with both native musl SDKs, and four separate native
guest controls on ARM64 and x86_64. The native controls used the unchanged
`kernel-gaps` serial constructor and fixture driver, the original 180-second
allowance, and previously qualified kernel binaries whose tracked sources
were unchanged. Actual boot-image kernels and archived init executables
matched the selected immutable kernels and SDK artifacts. This validation
does not claim fresh kernel builds or real syscall enforcement by the
injected callbacks.

Boot the userspace launcher regression against independently built kernels:

```sh
python3 tests/kernel-gaps/run.py --source tests/application-sandbox/guest.c \
  --arch aarch64 --kernel-dir kernel --expect 'APPLICATION SANDBOX GUEST PASS' \
  --fail 'APPLICATION SANDBOX FAIL'
python3 tests/kernel-gaps/run.py --source tests/application-sandbox/guest.c \
  --arch x86_64 --kernel-dir build-amd64-kernel --expect 'APPLICATION SANDBOX GUEST PASS' \
  --fail 'APPLICATION SANDBOX FAIL'
sh tests/application-sandbox/run-native.sh aarch64 kernel
sh tests/application-sandbox/run-native.sh x86_64 build-amd64-kernel
```

The real guest executes its static test binary through the launcher. It checks
credentials and capabilities after exec, `no_new_privs`, cleared inherited
descriptors and environment, permitted reads, hidden paths, refused writes,
locked unveil, promise narrowing, refused network/executable memory, and fatal
pledge violations. Invalid promises, unavailable paths and failed execution
must stop the launch. These checks establish the exercised boundaries; they
do not establish security of every syscall or application.

The native regression compiles the production Calculator profile directly,
then verifies capability and root-identity removal, `no_new_privs`, anonymous
memory allocation, preservation of nonadjacent compositor pipe descriptors,
closure of another inherited descriptor, and fatal network/path violations.
The same profile remains active in a private UTS namespace, where Vinix's
Linux-compatible uname retains the kernel-owned `-vinix` release suffix.
