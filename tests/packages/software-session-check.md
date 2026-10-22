# Ordinary-account broker and framebuffer transport

The session broker and external framebuffer clients share the numeric runtime
`/run/user/<uid>/vinix-session.<uid>` for ordinary accounts. The account service
prepares `/run/user/<uid>` before dropping privileges. Both transports validate
the private leaf and its trusted parent chain with `lstat`, refuse symlinks and
unsafe ownership or permissions, and ignore an inherited `XDG_RUNTIME_DIR`.
Root retains `/run/vinix-session.0`; explicit `VINIX_SESSION_RUNTIME` and
`VINIX_WINDOW_SOCKET` development overrides retain their existing behavior.
Generic private service log directories retain their previous leaf policy.

`desktop/tools/test-session-runtime.v` runs eight host tests: three shared-path
and directory-policy tests, two broker/framebuffer integration tests, and three
existing framebuffer protocol tests. They cover missing, foreign, insecure and
replaced directory components, two numeric account defaults, override
compatibility, actual listener/client refusal and connection, and protocol
regressions. Its retained report includes the generated C proving that each
owned `stat` allocation is freed. Run from the repository root:

```sh
v -o /tmp/test-session-runtime desktop/tools/test-session-runtime.v
V=/path/to/pinned/v VINIX_SESSION_RUNTIME_KEEP=1 /tmp/test-session-runtime
```

`tests/desktop-session-runtime/check.v` boots a fresh production compositor and
fresh session, time and runner services from the same frozen desktop build.
PID 1 creates two standard accounts and starts the compositor through
`vinix-session run --seat alex`. An independent UID-1000 client must connect to
the actual default broker, verify its peer credentials, receive `ok` for `ping`,
and present three frames through the actual default framebuffer socket. Each
frame must receive the compositor's acknowledgement. A separate UID-1001 client
must select its own numeric paths and fail to connect to either victim socket.
The guest checks socket type, owner and private permissions, and refuses any
ordinary `/run/vinix-session.<uid>` directory. The forged XDG path must have no
effect. The compositor must publish its own UID-1000 readiness marker in the
account runtime without a precreated fixture marker or global ready file.

Build a matching compositor with `software-graphical-build.v` as described in
[the graphical acquisition check](software-graphical-check.md). Supply an
unbooted staged production root, the matching kernel, a reviewed V compiler,
static musl C compiler and the [hardware controller requirements](../hardware-platform/README.md).
For example:

```sh
mkdir -p build/software-session-runtime-tools
v -prod -path '@vlib|.|tests/hardware-platform|@vmodules' \
  -o build/software-session-runtime-tools/check tests/desktop-session-runtime/check.v
V=/path/to/pinned/v CC_AARCH64=/path/to/aarch64-cross-wrapper \
VINIX_AARCH64_SYSROOT=/path/to/aarch64-musl-sysroot \
  build/software-session-runtime-tools/check --arch=aarch64 --out=/build/new-runtime-arm \
  --desktop=/build/frozen-desktop-arm/vinix-desktop \
  --kernel=/build/arm-kernel --rootfs=/build/native-arm/guest/root \
  --cross-driver=/path/to/aarch64-linux-musl-gcc
v -prod -path '@vlib|.|tests/hardware-platform|@vmodules' \
  -o build/software-session-runtime-tools/retain tests/desktop-session-runtime/retain.v
V=/path/to/pinned/v CC_AARCH64=/path/to/aarch64-cross-wrapper \
  build/software-session-runtime-tools/retain /build/new-runtime-arm \
  /build/frozen-desktop-arm/vinix-desktop /build/arm-kernel \
  build/software-session-runtime-tools/check /build/retained aarch64 \
  /path/to/aarch64-linux-musl-gcc
```

Repeat with `x86_64`, its matching root/kernel/compositor and `CC_AMD64`; ARM
sysroot and wrapper variables are unnecessary for a direct x86 musl compiler.
Each run directory must be new. The controller uses ARM HVF where available
and x86 TCG with `q35,smm=off`, `-cpu max`, standard VGA and 1 GiB RAM.
The guest redirects only stdout and stderr to the architecture's serial channel;
stdin remains the real console inherited by the ordinary seat compositor.
Account creation uses the production password hash; the native bound is
1,200 seconds to accommodate two account hashes under x86 TCG.
Compiler fallback and automatic compiler reports are disabled.
The frozen x86 kernel predates gzip initramfs support. This fixture uses the
V `plainiso` helper to assemble UEFI media with a plain USTAR archive; production
image scripts retain their compression policy. Limine 12.9.3 loaders and
`xorriso` are hashed inputs; `VINIX_PLAIN_ISO_LIMINE` can name another loader
directory explicitly. The ISO, generated configuration and exact assembly
arguments are retained with the native evidence.

The controller embeds its own and imported harness sources, rejects source
changes after compilation, admits the complete frozen compositor build receipt,
and repeats admission after QEMU exits. Receipts bind the compiler, C compiler
and declared underlying driver, kernel, QEMU, firmware, fixture sources, exact
build arguments, generated C and ELFs, boot archive/media, serial/QMP logs and
result. The retention tool independently rehashes them, requires all six exact
native markers once, rejects panic/failure markers, and checks the current
runtime production sources against the qualified frozen build.

The 2026-10-22 qualification passed on both architectures with the fresh
ordinary compositor. Retained [ARM evidence](results/2026-10-22/software-session-runtime-aarch64.json)
binds 85 artifacts and [x86 evidence](results/2026-10-22/software-session-runtime-x86_64.json)
binds 87. Their adjacent `.serial.txt` and `.commands.json` files preserve the
actual six native markers and build arguments. The separate
[host report](results/2026-10-22/software-session-runtime.txt) records all eight
host checks and the generated-C lifetime review.

This gate covers ordinary-account local broker and framebuffer transport.
Graphical package acquisition and persistence have their own framebuffer gate;
the transport test does not replace installed-system, graphical-login, device,
foreign-runtime or whole-catalog acceptance.
