# Init policy fixtures

`run-vm.py` boots the production ARM shell, full and desktop init policies
with independent native applications from `guestfixture/core.v`. The shell
driver checks command input through a pipe and `execv`. The full application
checks PID 1, arguments, environment and console descriptors. The desktop
application checks its parent and process group, reload forwarding, restart,
and termination and reaping of an orphaned child before the next restart.

Build an ARM kernel and musl sysroot, then run:

```sh
python3 tests/init-policy/run-vm.py \
  --kernel-dir /absolute/path/to/kernel \
  --state-dir "$(mktemp -d /tmp/vinix-init-policy.XXXXXX)"
```

Use a fresh, short state path: QEMU's Unix monitor socket is limited to
104 bytes on macOS. The default allowance remains 600 seconds per policy.
`VINIX_V_COMPILER` selects V, `VINIX_AARCH64_SYSROOT` selects musl headers
and libraries, and `LD_AARCH64` selects the freestanding policy linker.
`--reference-guest=/path/to/original-guest.c` builds the independent C
control with its original three mode defines and every original assertion.
`compile-guest.py` can emit either ARM or x86 fixture artifacts for SDK checks.
The production policies use the raw ARM syscall ABI; x86 evidence is compile
validation only.

The native header contains declarations and scalar constraints. Its volatile
`sig_atomic_t` member preserves the reload word; native `signal` receives the
actual V callback addresses. Pipes, descriptors, four-byte child PID records,
fixed stack buffers and permanent command literals retain their original
lifetimes. The closing callback uses the original `open`/`write`/`close`/`_exit`
operations. Optimized fixture objects import no allocators.

The immutable reference is the 78-line `tests/init-policy/guest.c` at
`320172dfefc2c0fd5f849da73e1443fe0b982660`, blob
`0c733b6574fa59f6d61aadb65af6c1fcbb80f357`. All 30 requirement messages and
their conditions are preserved. Strict ARM LLVM and genuine x86 musl GCC C/V
builds passed for all three modes. Original and maintained V applications
each passed all three actual ARM policy guests within the unchanged limit.
Production policy generated sources, objects, syscall ABI objects and ELFs
were byte-identical between the C and V controls. Source, ABI and lifetime
peer review and native volatile/callback checks accompany these results.

Receipts and frozen payloads are under
`~/.cache/vinix-c-to-v/firstparty-only-20261006-011023/init-policy-guest-fixture/`.
The first control attempt was rejected before boot because its cache path
exceeded the monitor socket limit; that receipt is retained. The successful
controls used fresh short paths and the immutable ARM kernel SHA-256
`05ce36f10282f9ed7263d560fc60b5a4b057e3fdf0158fb07d3fa41a27f048ed`.
These are fixture checks with a reused kernel. The separate host policy suite
in `run.py` has its own validation.

`python3 tests/init-policy/run.py` tests the raw syscall policy against the
independent recorder in `hostfixture/core.v`, with AddressSanitizer and
UndefinedBehaviorSanitizer for both normal and busybox echo variants. On
macOS, `--arch=arm64` and `--arch=amd64` select the native host executable
architecture; x86 runs require host support for that architecture. Use
`--work-dir=/fresh/path` to retain build artifacts, or
`--reference-fixture=/path/to/original-test.c` for the untouched C fixture.
The existing `--reference-dir` option retains its historical C policy control
adapter; those generated C control bodies receive no V algorithm credit.

The host reference is the 178-line `tests/init-policy/test.c` at
`8fd0f13a90d87e2841608a46f83142a252534757`, blob
`884c399f152f1ecf5440a9d2571f163618d4b1bf`. All 72 assertion call sites and
their predicates remain. The fixed 4,096-entry trace and 32,768-byte output
banks, borrowed strings and synchronous stack arguments retain their
lifetimes. Native `setjmp` remains directly in four live test frames, and
`longjmp` returns to those frames. Native by-value time records, signal action
records, volatile 32-bit control words and callback address comparisons are
checked against their original layouts and exported functions.

Original C and V fixtures each passed both echo variants on actual ARM and
x86 host executables under ASan/UBSan. Strict ARM LLVM and genuine x86 musl GCC
fixture objects and both SDK links passed; those Linux SDK executables were
not run. Generated fixture code and optimized SDK objects introduce no V
allocator calls. Separate optimized IR checks preserve native `returns_twice`
on all four `setjmp` calls, volatile control accesses and callback addresses.
Source, ABI and lifetime peer review accompanies these results.

Host receipts are under the adjacent `init-policy-host-fixture/` cache.
An exact repeat of the earlier ARM guest production build reproduced all
three policy sources, objects, ABI objects and entire ELFs byte for byte.
The prior ARM guest evidence remains applicable to that unchanged production
policy; no new guest or kernel run is claimed for this host fixture port.
An initial repeat using the current default Apple Clang instead of the prior
Homebrew Clang produced different object metadata and was retained; the final
identity check uses the original compiler and source basenames. A supplemental
x86 IR check first selected an absent sysroot, then passed with the genuine
GCC sysroot; the genuine GCC SDK object checks passed independently.
