# Performance harness report and initializer builds

The host report suite and both retained guest initializers build again after
the [procfs builder qualification](linux-procfd-builder-lifetime.md). The report
declares `strtod` through `<stdlib.h>`; three test fixtures now populate empty
maps instead of using the explicit nonempty map syntax rejected by the selected
V parser. All original assertions remain in place.

Both adapters generate PID1 through the maintained freestanding V module
generator. Native-width libc calls replace the full `os` runtime dependency;
the shell argv stays on the stack. Console selection, ext2 device selection,
mount errno/presence diagnostics and shell arguments are preserved. Diagnostics
are flushed before exec or failure. A failed mkdir now emits a bounded
`PERF-ERROR` and returns failure; EEXIST proceeds to mount. The ARM initializer
links libc without requesting the unused pthread/math libraries. The sampler's
link recipe and all format/type warning errors remain enforced. Prepared input
pins include the module frontend, copied initializer source and generation logs.

With frozen V 0.5.2 `cbfc1be`, the public host suite passes, including controller,
report, saved-runner and 100-PTY-owner checks with flat descriptors. The actual
V report test file also passes. Both staging adapters compile and pass their
18 ARM / 37 x86 host controls, including 22 x86 refusals. Both standalone PID1
and wrapped probes compile/link with `-Wall -Wextra -Werror`, excluding only
unused generated functions/parameters.

Fresh native guests pass 11 cases and 113 assertions per architecture. Cases
exercise console open and each dup failure, mkdir failure and EEXIST, failed
mount with present/missing devices, failed exec, successful handoff, and console
descriptors equal to stdout/stderr. The mount check deliberately changes errno
to establish preservation of the original failure. GNU linker wrappers check
the exact paths, order, flags and null-terminated shell argv. They simulate
mount/exec; these results do not establish an actual disk mount, shell execution
or desktop performance. The final rebuilt probes are byte-identical to the
ELFs executed by those fresh processes. Transcript checks pass one positive
and 36 negative controls per architecture.

The native guests reuse the previously qualified isolated kernels from
`vx-ec-1115/fixed-build-{arm,x86}`; this tooling change introduces no kernel code
or lifetime changes. Source baseline is
`b7cce04eb3fd5b7cd0bc3a28a8dad5a956ec1aeb`, with the exact qualified source,
compiler, generated C, ELF, argv, receipts, logs and earlier failed attempts
retained in the evidence bundle. The compiler uses its configured local standard
library; the selected toolchain/SDK inventories do not claim a hermetic build.
Concurrent unrelated checkout commits are outside this change.

Remaining broader checks stay open. The ARM production staging command now
passes initializer generation/link and reaches the sampler. Sampler generation
with both retained `7d74206` and `cbfc1be` compilers refuses the existing
deprecated `usize`/`isize` aliases under `-prod`. Separately, the observer's
explicit 4 KiB / 14-class contract does not qualify the current ARM kernel's
16 KiB / 18-class schema. The selected cached x86 root's missing curl and the
inherited allocation allowance failures remain recorded in the earlier complete
bundle. No full ops/churn/cache or idle/apps/drag performance pass is claimed.
Historical evidence/checkers and broader section 15 acceptance gates are
unchanged.

Complete evidence remains at `/Users/alex/.cache/vx-hv-1115/bundle`, archived as
`/Users/alex/.cache/vx-hv-1115.tar.gz`, SHA-256
`52bbb9e2a4c2f3f0d0eacc2233a51b0d66cf9fec84afc88e3629a5b41f5de389`.
The maintained `tests/ios/swift-staging-archive.v check-archive-root` decodes the
complete archive and passes comparison of all bytes, paths, types, modes and
literal link targets against the retained bundle. Originals remain intact.
The initializer transcript checker and reproduction commands are documented in
`tests/desktop-perf/README.md`.
