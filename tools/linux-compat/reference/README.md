# Linux number baseline

These are the unchanged `arch/{aarch64,x86_64}/bits/syscall.h.in` files from
[musl 1.2.5](https://git.musl-libc.org/cgit/musl/tree/arch?h=v1.2.5).
The accompanying COPYRIGHT applies. The coverage generator records their hashes
and rejects duplicate, malformed and out-of-range numbers. Updating the baseline
is an explicit reviewable change; report generation does not fetch the network.

This is the native ELF64 namespace. Linux i386 and x32 are separate ABIs;
instruction translation does not establish support for their syscall layouts.
