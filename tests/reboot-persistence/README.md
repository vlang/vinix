# Reboot persistence

The V fixture runs as PID 1, writes and closes `/root/hello.txt`, calls
`sync(2)`, and resets the guest with `reboot(2)`. The second boot reads the
same 27-byte payload, removes the file, calls `sync(2)`, and powers off.
Both boots run in one QEMU process with the same attached disk. The test
requires two START and SYNCING markers, the write marker, and PASS within
240 seconds; any failure marker rejects the run.

Build the ARM musl sysroot once with `scripts/build-userland-aarch64.sh`,
then run:

```sh
tests/reboot-persistence/run.sh
```

The default architecture is ARM. To reuse an existing private kernel, set
`VINIX_KERNEL_DIR` and `VINIX_REBOOT_PERSISTENCE_NO_BUILD=1`. The x86 runner
uses an existing kernel, the musl cross compiler, QEMU, Limine, and e2fsprogs:

```sh
VINIX_REBOOT_PERSISTENCE_ARCH=x86_64 \
VINIX_AMD64_KERNEL=/absolute/path/to/x86/kernel \
tests/reboot-persistence/run.sh
```

`VINIX_V_COMPILER` selects the V compiler; `CC` selects ARM clang and
`CC_AMD64` selects the x86 musl GCC. Set `VINIX_REBOOT_PERSISTENCE_STATE_DIR`
to a fresh path to retain the generated source, payload, disk and serial log.
`VINIX_QEMU_TIMEOUT` overrides the default 240-second deadline.

`persistfixture/core.v` owns the test logic. Its native header supplies libc
declarations and scalar width checks. The read buffer stays on the stack,
the payload stays in permanent literal storage, and the optimized fixture
objects import no allocators. The original buffered write, close, error
branches, sync brackets, and absence of `fsync` and `O_SYNC` are preserved.

The immutable C reference is the 90-line `tests/reboot-persistence/test.c`
at `bb26e71deb05913c617fdf3c47483041064f3fd7` (blob
`7d17c5b1b176ea2f147096c98f02a356997c5b19`). ARM uses that reference unchanged.
Its `/dev/console` is serial on ARM; x86 uses `/dev/com1` because its console
writes to the framebuffer. The independent x86 C control changes only that
one path literal. It retains every payload and error check and every disk,
sync and reboot operation. The initial unadapted x86 control failed the
serial marker gate and is retained as a capture failure in the receipts.

Validation receipts and the frozen references are under
`~/.cache/vinix-c-to-v/firstparty-only-20261006-011023/reboot-persistence-fixture/`.
Both architectures use immutable kernels from the preceding CPU-mask storage
stage; these fixture checks do not claim a new production-kernel build.

Strict ARM LLVM and native x86 musl GCC builds passed for the C references
and V fixtures. The native results were:

| Architecture | Control | Result |
| --- | --- | --- |
| ARM | Untouched C reference | PASS |
| ARM | Maintained V runner | PASS |
| x86 | C reference with the serial path adapter | PASS |
| x86 | Final V fixture | PASS |

Every passing run produced exactly two START and SYNCING markers, one write
marker and one PASS, within the original 240-second limit. The final ARM V
ELF matches the tested payload byte for byte. The reused ARM kernel SHA-256
is `05ce36f10282f9ed7263d560fc60b5a4b057e3fdf0158fb07d3fa41a27f048ed`;
the x86 kernel is
`b871254e8493566beb5b2e4436a06765a05db7d0f8fae561bb448d135f9c4199`.
