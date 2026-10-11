# ANS and classic ext2 fixture controller

Run `tests/apple-ans/run.sh` for the native V command. `--state-dir FRESH-PATH`
retains artifacts; the default owner creates a private directory in `/tmp` and
retires it on success, failure or interruption. `--fixture ext2|ans` selects the
native model. `--arch aarch64|x86_64` requires `--kernel-dir` and
`--guest-state-dir`; `--build-only` stops after strict native objects and ELF.

`run.v` calls `applehost.copy_provider` and native module/serial producers.
Immutable C originals, compiler flags, allocator guards, exact output parity,
provider-call audits, guest markers and deadlines retain their existing policy.
The independent C/V fixture bodies and assertions have not changed.

The current isolated ANS provider copies only `core.v`, whose accounting calls
now depend on omitted `status.v`. ARM generation rejects `a_count_transfer` and
`a_count_flush`; the x86 backend also rejects the retained ARM assembly. The
original provider API uses the same native copy policy and has these same input
limitations. They remain errors, with no passing ANS fixture or guest claim.

See [runner qualification](../apple-protocols/runners.md).
