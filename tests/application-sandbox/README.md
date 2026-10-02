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
