# Native CPython smoke controller

`scripts/build-python-aarch64.sh` stages `/root/python3-smoke`, a V executable,
alongside the existing Alpine CPython runtime. Run that executable in the guest
as root. The amd64 staging script selects an x86 ELF; the original smoke's
`uname().machine == "aarch64"` assertion is deliberately retained, so an amd64
build does not establish an amd64 runtime pass.

The controller exercises CPython through its C API. It contains no Python source,
evaluation strings or first-party Python adapters. It retains filesystem and
fork/subprocess checks; eight `threading.Thread` workers with a lock and an Event;
select/poll/epoll; Unix sockets and the SCM_RIGHTS stream barrier; clocks,
credentials, allocation and entropy; all eleven extension imports; zlib/SHA;
positioned/vector/sparse I/O; eventfd; sendfile offset semantics; resource and
scheduling queries; and the 100-row SQLite transaction. The original check labels
and `PYTHON3 SMOKE PASS/FAIL` summary remain. CPython and its standard library
remain the third-party runtime being tested.

The binding resolves 36 exports from `libpython3.12.so.1.0`. Set
`VINIX_CPYTHON_LIBRARY` for another compatible SDK library. C integer slots and
the method flags use `i32`; ssize_t and long-long slots use their 64-bit types.
Owned references retire in reverse order. Tuple insertion transfers a separately
incremented reference; sequence reads return tracked owned references. Retired
arenas reject SDK calls. Callback capsules retain their definitions and strong
SDK references until the last callable closes, including failed creation and
join paths. The API remains live through interpreter finalization.

Build the controller independently:

```sh
V=/path/to/qualified/v CC=/path/to/clang \
  build-support/python-smoke --arch aarch64 --output /fresh/python3-smoke
```

`--sysroot` selects headers, CRT and compiler-support archives. `--libc` or
`VINIX_PYTHON_MUSL` selects the already built shared musl loader. Defaults use the
ARM userland SDK/staging or amd64 desktop SDK. V emits Linux C for the target;
Clang links it with that SDK rather than V's bundled x86-only cross linker.
`-gc none` permits SDK-created threads to enter native callbacks. The V-specific
segfault handler is disabled; CPython retains its ordinary signal setup.
The producer verifies ELF machine and interpreter, records source/compiler/
runtime/executable hashes, and preserves the existing output on compiler failure.

Nine cold ARM, Rosetta x86 and ARM ASan/UBSan host builds pass the native V
reference/callback model, signed C error results, Unicode/NUL handling, method
layout, retired access and failed capsule/function creation. Each profile also
generates and links both real guest ELFs, checks every required export in both
staged CPython libraries as ELF data, and verifies compiler failure preserves
an existing output. These checks execute no interpreter, SDK Python modules or
Vinix guest. They establish build and ownership contracts; a new full guest
runtime result is still required separately.

```sh
build-support/run-v-tool.sh tests/native-python-smoke/qualify.v \
  /path/to/qualified/v /fresh/evidence arm # also x86 or san
```

The reference rules are checked against the primary CPython 3.12
[tuple implementation](https://github.com/python/cpython/blob/3.12/Objects/tupleobject.c)
and [callable implementation](https://github.com/python/cpython/blob/3.12/Objects/methodobject.c),
including definitions retained by a callable's `self` object. The
[C API structures](https://docs.python.org/3.12/c-api/structures.html) document
the method layout and calling convention.
