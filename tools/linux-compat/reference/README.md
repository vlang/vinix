# Linux number baseline

These are the unchanged `arch/{aarch64,x86_64}/bits/syscall.h.in` files from
[musl 1.2.5](https://git.musl-libc.org/cgit/musl/tree/arch?h=v1.2.5).
The accompanying COPYRIGHT applies. The coverage generator records their hashes
and rejects duplicate, malformed and out-of-range numbers. Updating the baseline
is an explicit reviewable change; report generation does not fetch the network.

This is the native ELF64 namespace. Linux i386 and x32 are separate ABIs;
instruction translation does not establish support for their syscall layouts.

`glibc-packages.json` separately pins Debian Bookworm's unmodified GNU libc
2.36-9+deb12u14, matching development files, Linux headers and libgcc for arm64,
amd64 and i386. The SHA-256 values come from Debian's HTTPS Packages indexes.
The V SDK tool verifies every archive before extraction and runs no maintainer
script. It uses these checked-in pins without resolving newer versions.
These packages are build and disposable-guest qualification inputs; extraction
does not establish an installed system's package lifecycle or Debian service
integration. The linked CRT/library/loader hashes are recorded by the builder.
