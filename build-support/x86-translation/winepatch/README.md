These five host commands now run V directly through their extensionless
launchers. They retain the byte signatures and offsets of the removed Python
tools from source `5b750ff8186a145f2d54ad742ea9e4fe6613dc4e`.

| Command | Preserved patch |
| --- | --- |
| `patch-wine-x86_64-qemu` | Infer negative QEMU trap numbers from delivered signals; retain the execute-fault adjustment when RIP equals the fault address. |
| `patch-wine-i386-qemu` | Infer negative QEMU trap numbers through the original PIC helper and signal table. |
| `patch-wine-x86_64-context` | Keep FXSAVE for aligned contexts; retain the unaligned path, MOVDQU jump-buffer saves/restores and MOVUPS local store. |
| `patch-msxml-unicode` | Repurpose the ISO-8859-16 handler as `UNICODE`, copying both UTF-16LE converter pointers and retaining the UTF-16LE name. |
| `patch-wine-service-timeout` | Extend the default service-pipe timeout from 10 to 60 seconds, preserving the other adjacent globals and registry override behavior. |

The fixed-site commands accept each site's old or already-patched bytes, so
partly patched inputs remain valid. Unknown bytes and changed region lengths
fail. MSXML supports PE32 and PE32+, requires unique handler strings and pointer
references, and checks patched converters on repeat runs. The timeout tool
requires one unique old or new globals signature. Their success text and repeat
behavior are retained; argument errors return 2 and patch/read errors return 1
with native diagnostics. Truncated headers, converter spans and overflowing
addresses fail before publication.

All sites are validated before a private image is changed. A same-directory
`mkstemp` file is fully written and closed, receives the actual source mode, and
replaces the exact destination with POSIX rename. Every failure closes the
descriptor and removes the temporary file. As in the originals, replacement
breaks hard links and replaces a symlink itself; its former target is unchanged.
Already-patched MSXML and service images return without replacing their inode.

Run module tests with `v -cc cc test build-support/x86-translation/winepatch`.
Set `VINIX_WINEPATCH_BIN` to a directory containing all five compiled commands
to include CLI checks. Set `VINIX_WINEPATCH_REPO` to the repository to include
the cached Alpine payload comparisons: system tar extracts seven original
Wine 9.17 images, each native result matches the previously staged patched
image in full, and a second run preserves the bytes. `reference_hashes.json`
records both input APK hashes and all seven pre-existing reference hashes.
Tests fail if those qualification inputs have changed.

ARM and Rosetta x86 builds and tests passed, along with ARM ASan/UBSan checks.
Native PE fixtures cover both pointer widths, ambiguous signatures/references,
truncated headers and converter arrays, address overflow and repeat-run errors.
File tests cover modes, hard links, symlinks, failed publication and 100 repeated
success/already-patched/error cycles with flat descriptor and temporary-file
counts. No Python was run for qualification. Host byte equivalence is established;
this stage does not claim new Wine guest boots or Office execution. Local build
and test logs are under `/tmp/vinix-python-zero-20261010/continuation/wine-*`.
