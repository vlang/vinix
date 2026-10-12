# Signed package runtime qualification

The V controller builds the production native `vinix-sandbox`, builds the
package/account/session tools for the selected target, and boots the accounts
guest as init in QEMU. It uses real kernel pledge/unveil enforcement throughout
`packages-enforced`; the ordinary accounts `packages` scenario retains its exec
observer for separate identity diagnostics.

From the checkout, with the matching kernel and the toolchains described in
[the hardware test documentation](../hardware-platform/README.md):

```sh
v -path '@vlib|@vmodules|tests/hardware-platform' run tests/packages/runtime-check.v \
  --arch aarch64 --kernel /build/arm/kernel/bin/vinix \
  --state-dir /tmp/package-runtime-arm
v -path '@vlib|@vmodules|tests/hardware-platform' run tests/packages/runtime-check.v \
  --arch x86_64 --kernel /build/x86/kernel/bin/vinix \
  --state-dir /tmp/package-runtime-x86
```

The usual hardware controller options, including `--list`, `--qemu`, `--timeout`
and `--failures-only`, apply. State directories must be new or empty. The kernel
is copied before staging so later worktree removal cannot alter the boot input.
The native sandbox's ELF class, byte order and machine are checked before it is
placed in the image. No desktop process, release key or network repository is
needed: the guest generates a throwaway signing key and enrolls its local fixture
repository.

The guest checks:

- Signed installation and root-to-ordinary-account launch, with no supplementary
  groups and user-owned private data. Literal document arguments survive the
  handoff; another user cannot acquire access by adopting `launch_user`.
- Missing launch identity and revoked publishers fail; uninstall retains personal
  data. The ordinary child rechecks the configured publisher.
- Private-data writes and declared document reads work. Reads of a same-user
  file outside the grants and of the package service are hidden by unveil.
  Installed application and runtime files cannot be written by the app.
- Creating an Internet socket requires `network`. Fork/wait requires `process`.
  Undeclared operations kill the confined app with status 134, which reaches
  the package CLI. Supplying a document without `files` fails before execution.
- Changing application or explicit runtime payload bytes makes launch fail.
  The signed runtime is resolved as an implicit dependency and supplies the
  runner and `PATH`, rather than a host-global installation.
- A running app retains its version-1 application and runtime while both update
  to version 2, are uninstalled and become older than the rollback slot. Garbage
  collection preserves their leased generation. After the runner exits with
  status 37, collection deletes that generation and preserves private data.

A passing run with `--state-dir` writes `qualification.json`, containing target,
SDK, scenario and SHA-256/size records for the kernel, sandbox, signed native
payload, package service, session runner and retained serial log. Failure never
produces a passing receipt. Keep the serial log alongside the receipt to inspect
the assertions and final `HWTEST PASS packages-enforced` marker. Retained images
contain only fixture signing keys; they are not publisher credentials.

The full scenario passed on 2026-10-12 on both targets. Input/output hash
receipts: [AArch64](results/2026-10-12/aarch64.json) and
[x86_64](results/2026-10-12/x86_64.json). Their complete serial logs and images
were retained in the corresponding host state directories during qualification.

These are native package-mechanics checks. They do not qualify network traffic,
graphical display/audio brokers or Linux/Wine/Apple API coverage. The guest uses
an initramfs; [the separate ext2 recovery suite](persistence-check.md) checks
package checkpoints across abrupt termination/reboot. Wider filesystem/device
durability and the full roadmap release gate remain open.
