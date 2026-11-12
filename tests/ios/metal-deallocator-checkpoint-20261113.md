# Software Metal buffer deallocators — 2026-11-13

`61ed666bb` adds nonnil deallocator blocks to the no-copy buffer constructor.
Valid input copies the block and its captures before publishing the buffer;
the device stays retained while client copy helpers run. Invalid layouts,
wrong-type deallocators and blocks without an invoke function return nil
without copying or taking ownership. Nil deallocators retain their existing
caller-managed lifetime.

At final buffer destruction, cleanup detaches the block, invokes it once with
the original pointer and length, then releases it and its captures. Texture,
view and command references delay destruction normally. The callback owns
page cleanup. It runs on the releasing thread and can inherit a recursive
runtime lock from cleanup; same-thread runtime calls work, but waiting for a
thread needing that lock would deadlock. See
[METAL.md](../../compat/ios/runner/METAL.md).

All twenty software groups pass under ASan/UBSan on macOS ARM64 with normal
and deterministic Swift hashing. New checks exercise copied capture/invoke/
dispose ABIs, exact pointer/length, callback page unmapping, reentrant device
queries, invalid inputs preserving ownership, and exactly-once callbacks for
direct release, retained texture views, abandoned commands and committed
commands across two drained runtimes. Nil-deallocator regressions pass. The
ordinary runner/native device suite was rebuilt for the shared cleanup hook
and passes both hashing modes; it submits no GPU work.

Evidence bundle, including the ordinary qualification in `default-validation/`:

`/Users/alex/Library/Caches/vinix-ios/metal-deallocator-validation-20261113-r1/`

The sibling archive was decoded/extracted to a fresh `-restored` directory.
Saved source/compiler/header/both executable identities match. Both restored
executables pass, including all twenty software groups. The archive checksum
passes afterward; receipts remain beside the bundle. The maintained harness
retains its documented compiler-preamble corrections. Toolchain symlinks,
host SDKs and dylibs remain external prerequisites; dependency closures are
not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; object drainage is checked, retained heap is not measured. Shader
execution and presentation remain pending. No Fortnite frame or new launch
gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `bb0f1c6273096f20f55ec583e8a68992912328209f242ac56d893dcf417dbdd3` |
| `source.tar`, revision `61ed666bb` | `94b4da2eb1cb3895bf54644b94530e108991ab8f6566e806786ec2cac5ede8e4` |
