# Native desktop bootstrap checks

Run `tests/desktop-bootstrap/run.sh` with the repository's selected V compiler.
The launcher, preparation and recovery suites execute the current production
bash scripts or their current function bodies in private fixtures. Every fake
builder, source fetcher, compiler and linker is a V executable. No binary layer
downloads or QEMU boots are needed.

The launcher checks help side effects, cold dependency ordering, warm reuse,
no-build behavior and compiler selection. Preparation retains all eight
original scenarios: fresh and warm checkout, reassembly of an image missing
X11, incomplete custom staging, invalid custom ui2, reuse of a complete custom
layer, a rebuilt package layer and a builder that returns incomplete output.
Firefox is not a desktop layer: images leave it to the first-run app page.
System tar independently checks generated archive entries and file contents.

Recovery checks a fresh init, a preexisting executable or archive, failure in
generation/compilation/linking, retention of a previously published executable,
full-image fallback and temporary cleanup. The current production build has
two clang steps: the generated V translation unit and its assembly syscall ABI.
The real-tool case invokes `build-support/init-aarch64/compile-init`, cross-links
an executable AArch64 ELF and verifies its entry point, executable archive mode
and exact archived bytes. It skips only when clang or ld.lld is unavailable.

Qualification on 2026-10-11 uses isolated rebuilt V 0.5.2 `c6bb06f`, with native
ARM, actual Rosetta x86 and ARM ASan/UBSan test executables. All preparation and
recovery scenarios pass, including the real AArch64 ELF in every profile. Cold
launchers also pass from `/tmp`. Local logs are
`/tmp/vinix-bootstrap-{prepare,recovery}-{arm,x86,san}.log` and
`/tmp/vinix-bootstrap-all-cold.log`.

No Python was run, no real workspace images were pruned, and no new guest boot
is claimed. The older init-policy Python runners and their `compile-v.py`
generator remain counted pending their complete workflow translation. The
desktop cache now fingerprints the native init producer and its entrypoint.
