# Native iOS VM controller

Run the maintained standalone controller with the original options:

```sh
tests/ios/run --no-build --with-2048
tests/ios/run --with-cxx --with-gles --with-ppsspp --ppsspp-muted --ppsspp-cube
```

The V controller builds the existing fixtures, stages the disposable filesystem,
creates the ARM64e, truncated and universal images, compiles the unchanged three
C guest-init components and starts the existing AArch64 boot script. `--no-build`
skips the runtime build and still rebuilds the fixtures. All nine switches retain
their dependencies and optional verdict markers. The four PSP fetches use the
qualified native commands in `examples/ios-ppsspp`.

`VINIX_IOS_BUILD_DIR`, `VINIX_IOS_TEST_SYSROOT`, `CC` and
`VINIX_VM_RUNNER_ROOT` retain their staging, compiler and runner selection.
The alternate runner root supplies `scripts/run-aarch64.sh` directly. It no
longer supplies an imported Python module or Python callbacks. Networking,
clipboard, audio and host-source mounts are disabled for this disposable run.
Private disks and the package archive remain inside the temporary work tree.

Copied fixtures follow source links and preserve file metadata. GLES dependency
trees preserve their links. Verified PSP assets use hard links, with a metadata-
preserving copy fallback; their directory metadata is copied after the children.
The archive retains USTAR paths, bytes, permissions and link targets. Native gzip
uses level 1 without a filename or timestamp header; archive member ordering and
terminal padding can differ from the original host tar program.

The PTY owner reserves the leader until it kills descendants and performs the
sole reap. The guest loop keeps the original poll-before-read ordering, 64 KiB
reads, 250 ms waits, exact-once marker requirements, pass/failure-triggered
Ctrl-A x, ten-second shutdown deadline and forced-stop failure. Cleanup tries
Ctrl-A x for five seconds, TERM for two seconds and KILL before owner retirement.
Raw serial output is bounded at 64 MiB, streamed with complete writes and saved
before reporting errors. Stop detection scans each new chunk with a 63-byte
overlap; a borrowed view expires before the next buffer append. The final
verdict checks the whole captured log. SIGINT/SIGTERM stop and reap the child before returning
130/143. Fast failed execs also retain their reserved identity while Darwin
publishes the exit record after removing the process group.

Qualification cold-builds the controller, workflow checker, staging checker,
PTY regression and existing VM regression suite on ARM, Rosetta x86 and ARM
ASan/UBSan. It covers all 512 switch combinations, every missing/duplicated
marker, exact universal-image bytes, all valid original build plans, copy/link
metadata and fallback behavior. Each profile compiles the real static ARM64 C
init, then checks eight full controlled workflows and eleven failure, output,
signal and descendant cases, plus 100 failed-exec boots and 1,000 fast PTY exits.
The existing browser/activity/pointer regression suite exercises shared owners.
The fixtures use retained real Calculator and 2048 Mach-O inputs alongside
controlled staging files, builders and VM processes. These checks do not
establish a new Vinix guest or graphics result. No Python is executed.

```sh
build-support/run-v-tool.sh tests/native-ios-run/qualify.v \
  /path/to/pinned/v /fresh/evidence arm # also x86 or san
```

The separately staged `tests/ios/run.py`, `_native.py` and `ioscontroller` object
bridge belong to another active session and remain intact. This standalone
controller adds no Python-file retirement credit until that bridge closes.
