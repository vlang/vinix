# Wine private-prefix and translator boundary checks

These checks qualify the adapter's host-side prefix ownership and two exact
local-only binary patches. They do not qualify Wine application execution,
Calculator, a production publisher, or complete redistribution/source closure.

`wineadapter.prepare_prefix` accepts a non-root effective UID/GID and a private
SDK data directory, captures every ancestor without following links, and keeps
the prefix and server directory private to that identity. It prepares only
Wine's fixed prefix structure and builtin file names from an immutable signed
generation. Retained descriptors are rechecked before use and are closed on
refusal and repeated `close()` calls. Ancestors use `O_PATH` on Linux, so capture
does not request directory read access beyond the sandbox's signed path grants.

The Wine 9.17-r1 server and Unix client patches accept only their two exact
SHA-256 inputs. Each changes one unique format string from `/tmp/.wine-%u` to
`.wine-%u`, retaining UID and prefix device/inode binding. In the pinned Wine
source, both processes enter the prefix before constructing and using these
relative paths. This permits an exact private-prefix sandbox grant; it does not
grant shared `/tmp` Wine directories.

The AArch64 Alpine QEMU 9.1.2 input has no `-split-wx` CLI option. Its exact
four-byte patch replaces `ldr w1,[x19,#0x2c]` with `mov w1,#1` at `0x85c64`,
immediately before `tcg_init`: the other arguments and call remain unchanged.
Upstream's positive split-WX value requires separate writable and executable
aliases and refuses a failed split mapping. No `VINIX_ALLOW_WX` or writable and
executable mapping exception is used. This is explicitly a local qualification
patch, with partial source evidence rather than a complete source offer.

On 2026-10-23 the assertion-enabled checks passed:

- 1,000 actual prefix captures, identity rechecks, and double closes normally
  and another 1,000 with ASan/UBSan: zero retained tracked V bytes and unchanged
  descriptor availability. The cases also refuse linked, permissive,
  replaced, and malformed prefix components.
- A negative compiler-lifetime control restores three ordinary `&stat` calls.
  It retains exactly 165,888 bytes across 64 cycles; generated C shows three
  promoted `stat` locals. The fixed stack borrows retain zero bytes and have no
  corresponding promotions. Each borrow is used only by synchronous `fstat`.
- 64 actual translator patch/refusal cycles normally and another 64 under
  ASan/UBSan: zero retained tracked V bytes. Wrong, corrupt, already patched,
  and duplicated-site inputs refuse. The retained disassembly checks the
  `x0`, `w1`, and `w2` setup and the unchanged `tcg_init` call.

Sanitizers check address and undefined behavior; allocation results concern the
tracked V allocator, not all libc or guest kernel allocations. New descriptor
and borrowed stack-value lifetimes received independent review before commit.

Small dated receipts are retained in
[wine-prefix-host.json](results/2026-10-23/wine-prefix-host.json) and
[wine-translator-host.json](results/2026-10-23/wine-translator-host.json), with
[original](results/2026-10-23/wine-translator-original.disassembly.txt) and
[patched](results/2026-10-23/wine-translator-patched.disassembly.txt) disassembly.
The receipts identify the exact compiler, source, generated C, executables,
literal command arguments, and logs. Full local build artifacts remain at the
absolute build paths named by those receipts; they are not source distribution
artifacts.

The measured test modules copy only `prefix.c.v`, `patch.v`, and their focused
tests. These receipts do not cover the later PE proof reader, source-offer
admission, or every file in `wineadapter`, and do not claim hermetic builds.

Use the pinned compiler and its inherited-child settings, with assertions
enabled (omit `-prod`):

```sh
export V="$PWD/build/package-https-runtime-work/toolchain/v"
export VEXE="$V" V_MACOS_V3_CALLER_VEXE="$V"
export V_MACOS_V3_CALLER_VEXE_PRESENT=1 V_MACOS_V3_CALLER_VCHILD_PRESENT=0
export V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1
"$V" -backend c -cc clang -nocache -gc none -manualfree \
  -path '@vlib|.|tools/accounts|@vmodules' \
  -o build/wine-prefix-check tests/packages/wine-prefix-check.v
build/wine-prefix-check "$V" "$PWD" build/wine-prefix-fresh
"$V" -backend c -cc clang -nocache -gc none -manualfree \
  -path '@vlib|.|tools/accounts|@vmodules' \
  -o build/wine-translator-check tests/packages/wine-translator-check.v
build/wine-translator-check "$V" "$PWD" \
  "$PWD/build-aarch64-x86-translation/staging/usr/bin/qemu-x86_64" \
  build/wine-translator-fresh
```

Both drivers require new output directories and invoke assertion-enabled
tracked and sanitizer tests themselves. Prefix checks require an ordinary host
account. A native translator smoke check is a separate boundary; these host
receipts make no native execution claim.
