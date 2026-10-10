# Limine compatibility patch test

Run `tests/limine-aarch64/test-patch` with V, a C compiler, Bash and Git
available. The native command builds a small V command fixture, copies the
maintained loader builder and patch into private scratch trees, and exercises
the real Git patch logic. It checks fresh patching before build/install,
idempotent reruns with identical source bytes, and rejection of incompatible
source before build without modifying it.

Configure, make and tool-discovery substitutes are native V. An unexpected
download fails the fixture. No source is downloaded and no real UEFI loader is
compiled or deployed. Private fixture trees are removed on success and ordinary
errors. The copied builder retains its existing configure/make log locations.

`VINIX_LIMINE_FIXTURE` can select a prebuilt `commandfixture` binary for host
qualification. `VINIX_LIMINE_FAIL=configure` or `make` forces a command failure
to check the builder's error path and scratch cleanup.

ARM, Rosetta x86 and ARM ASan/UBSan builds pass all three patch scenarios,
both forced command failures, help and argument status checks. Qualification
logs are `/tmp/vinix-limine-{arm,x86,asan}-final.log`.
The cold launcher builds fresh native fixtures from an unrelated working
directory and leaves no private temporary files after success or a forced make
failure. Its log is `/tmp/vinix-limine-cold-final.log`. No Python was run.
