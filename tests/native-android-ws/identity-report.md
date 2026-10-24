# Explicit native Android credential regression

The real Unix credential module passed its seventeen-case ARM64 Vinix
regression on 2026-10-24. The checkout revision when recording the result was
`b682240eef9d24cae6fd2c79aadd5dae021fbb4f`, with the credential change in the
working tree. The runner saved source copies before compiling the fixture.
Exact tested module, fixture, runner, base image and firmware-variable hashes
are in the preserved bundle's `inputs.json`.

Evidence bundle on the build host:
`/Users/alex/code/vinix/build/android-maps/identity-check5/`.
It contains the private boot image, firmware variables, fixture executable and
overlay, frozen sources, `inputs.json`, `serial.log` and `result.txt`. The serial
log was hashed after stopping and reaping QEMU; its SHA-256 is
`6fc8d5d7b233c4a9cce2987a22f8c9004afc156b918730858de55b88900064bc`.
Generated evidence remains outside Git.

The tested runner snapshot has SHA-256
`71d68d790a486acb87ef8602b4665354ec64ee6da7d56f4241f5dec4ae6bff93`.
The maintained runner subsequently added execution metadata. The bundle's
`execution-supplement.json` records compiler, QEMU and read-only firmware
identities collected after this run, with compile/QEMU argument arrays
checked against that preserved snapshot. These tool hashes describe the
later capture, rather than proving a historical tool freeze. Original
`inputs.json`, source copies and results are unchanged. Future runs record
`execution.json` before compiling. Only the host runner used `-prod`; the
guest fixture was compiled with assertions enabled.

Two successful child launches verified the real, effective and saved UID/GID
were all 10000 after exec, supplementary groups were empty, all five capability
sets were empty, `no_new_privs` persisted, and a root-regain attempt failed.
They also checked target-owned writes, readable APK/runtime fixtures, HOME/XDG
environment and application data working directory. Both a fresh surface and
an existing target-owned surface were accepted.

Fifteen cases rejected an unprivileged caller, an absent Unix account or group,
incorrectly owned data/home, unwritable data, inaccessible APK/runtime content,
an unexecutable runtime
entry, unsafe surfaces, a data symlink, a relative runtime and an unwritable
surface parent. The parent checked APK bytes and root ownership after every
case. The private guest overlay supplied a UID/GID 10000 account and group;
the host account database was untouched. The final marker was
`ANDROID-IDENTITY-SUITE PASS cases=17`.

Host configuration tests and `androidhost/runtime_test.v` also passed, and the
production native launcher cross-compiled for ARM64 musl. The fixture exercises
credential activation and an independent exec; it does not establish that a
real Maps launch succeeds.
That additionally requires the administrator-approved runtime `wxallowed`
mount and inherited compositor transport. Reproduction instructions are in
the [credential option documentation](../../build-support/android/nativeidentity/README.md).
