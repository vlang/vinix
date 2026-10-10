# Native fixture compiler drivers

The ANS, SPI, speaker, Wi-Fi, SMC and ACPI fixture compiler commands run V
directly. They share option parsing and temporary-source staging in this module,
then use the existing freestanding V module producer. No Python import adapter
or Python runtime is needed for these commands.

Commands retain their original output argument and flags: `--arch`, `--kind`
where supported, `--entry`, `--guest`, and SPI's `--reference`. Architecture
defaults to the host except for ACPI, which requires an explicit `--arch`.
Temporary source trees are removed on success and compiler failure.

Qualification at the Python-to-V zero-percent stage checked all 46 combinations
of supported fixture kinds, both target architectures, ordinary and guest entry
profiles, and both SPI reference entries. Every generated C file matched the
original Python driver's output byte for byte. A Rosetta x86 host driver also
matched the ARM host, and the maintained command generated the same file with
`python` and `python3` replaced by deliberately failing executables on PATH.

The SMC host integration reached the existing strict-build failure: the current
V compiler emits undeclared `memdup` calls in its fixture. Its original Python
driver produces the identical failing C, so this stage does not claim a passing
SMC execution or any fresh guest/hardware validation.
