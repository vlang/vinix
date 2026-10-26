# Account store Linux regression, 2026-10-26

The r4 fixture ran successfully as PID 1 in the AArch64 Vinix guest. UART
contains each of the nine expected verdicts once, in order: existing procfs,
canonical persistence/reopen/visibility/userdata, SQLite rejection of the old
procfd path with code 14 and extended code 1550, all five hostile-link cases,
then `ACCOUNTSTORE-LINUX-PASS`. The runner exited 0 after terminating its
QEMU child. This verifies synthetic account storage in the Linux ABI guest;
Maps, GMS initialization and Google account sign-in require separate evidence.

The successful guest and runner log are retained at
`/Users/alex/.local/state/vinix/android/accountstore-linux-guest-2026-10-26-r2`
and its sibling `accountstore-linux-guest-2026-10-26-r2-run.log`. Their UART
and runner log SHA256 values are respectively
`330277a4204cbf2d38a987f33afaaa555c73a7d1a69a1ec73b425f037dd29e1c`
and `b04f3b8344d0bbd72a6f17b30d73e2d91cc210b5d849e649bc2a836d4912fda8`.

The complete execution seal is retained at
`/Users/alex/.local/state/vinix/android/accountstore-linux-guest-evidence-2026-10-26-r2`:

- `sha256.json`: `5e1c2f6a2af5069d660c4617eb3c7d122c146f505d524388f0523503c866cc92`.
- `receipt.json`: `17b9aae6625ee99f38b0b4a9101e0800435410a8becb592c85fba702660ee8d6`.
- `external-sha256.json`: `617ce5b01fb25291d0352deb53ec1ec1b9484e566276e9583a4d244a8cbc5c1a`.
- `external-symlinks.json`: `9822bf0bc61f3998b11ba5b6618366f7ac14d3e3ad0e47f32f7d64e199a00e3c`.

The maintained V sealer
[`seal-accountstore-linux-guest-r2.v`](seal-accountstore-linux-guest-r2.v)
verified the original complete producer manifests, then bound 8,521 regular
files and 707 kernel symlinks in place. It preserves both guest runs and the
r3/r4 fixture, kernel, runner and account producer bundles. It uses the kernel
builder's original separate file/link inventory semantics; the existing
regular-only bundle checker remains unchanged. Actual ISO boot configuration,
kernel bytes and init bytes match the selected producers. The original r1
failure below remains complete and unchanged.

Independent source review and a replay using the sealed executable passed.
The sibling receipt
`accountstore-linux-guest-evidence-2026-10-26-r2-peer-recheck.json`
has SHA256 `70453a5106279522c0fa0e31af13012b4cb5280bc353a4244ece35ad982d8156`;
its sibling `.log` has
`21bd0eebc5d09b62a04a65b86f0a33052c3ccd48c059efe508b285fd196a762a`.

The kernel producer's manifest is
`32a134cc1ee3d02bfb56d91ee429ac3f5fb9895ba525021eb7aa84a7ec64f6ee`,
with kernel ELF `a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`.
The runner producer's manifest is
`20719168a89db758e28b65078454da563def0222175293cd2fa7f31f8cb43475`.
Both complete paths and all file/link pins are in the execution seal.
The runner did not capture a per-run launch receipt: its argv and explicit
environment in `receipt.json` are reconstructed from the executing tool call.
Other inherited environment, the launched QEMU executable and firmware were
not pinned at launch. The host SDK and boot assembly environment are not
hermetic.

Replay the unchanged seal with its retained executable, supplying a fresh
receipt outside every evidence root:

```sh
/Users/alex/.local/state/vinix/android/accountstore-linux-guest-evidence-2026-10-26-r2/sealer \
  --check 5e1c2f6a2af5069d660c4617eb3c7d122c146f505d524388f0523503c866cc92 \
  /external/fresh-recheck.json
```

## r4 fixture and build

The r4 build includes `8fb04d7762946cb87073c626af5d21e9f88a4dcd`, which
first checks the root descriptor's `/proc/self/fd/N` link. It reuses an
existing usable procfs mount and mounts only when that descriptor lookup is
unavailable; mount failures include numeric errno. The strict SQLite
`CANTOPEN_SYMLINK` assertions remain unchanged. Independent source review
and fresh host persistence/link checks passed; a normal no-argument process
still exits 2.

The first minimal guest run of r3 failed before any store checks because
the kernel already mounts procfs before starting init and the fixture tried
to mount it again. The original failure remains under
`/Users/alex/.local/state/vinix/android/accountstore-linux-guest-2026-10-26-r1`,
with the sibling `accountstore-linux-guest-2026-10-26-r1-run.log`.
Their UART and runner log hashes are respectively
`8bfe16e7b713e9d04a372151511bde7165fc8e8def76c9fbba44eadf1a76c5e2`
and `f4ea4b287a8beee24f984668251943359f5fbbfd919643a1e16db5f8b0ed50f3`.

The complete r4 cross-build bundle is
`/Users/alex/.local/state/vinix/android/accountstore-linux-regression-build-2026-10-26-r4`:

- Complete `sha256.json`: `efa7bd437e33ec2abd7a0202e4ff58ba4a6860cd0283032e6a393d17a5829d5d`.
- `build.json`: `167bfb7449b160537099ec157bf87457d8d752beeb11b4d635adf1053746b802`.
- `bin/accountstore-linux-regression`: `9c989f21bef68a689be5e61a11d756a4cdd9e5f5075b51f1e0609e0fbfc822d9`.
- Fixture source: `82df8620e93e18d8334a46013ef44287ee87aacc3a8fa584836c348ee17cd922`.

The production store and account producer pins are unchanged from r3 below.
All maintained build checks passed. An independent check verified exact
membership and all 2,405 hashes; its sibling receipt
`accountstore-linux-regression-build-2026-10-26-r4-peer-inventory.json`
has SHA256 `d49aba0e3b425e569b624c1e92a7e0584bccac6d81449c1dff00108681176aa2`.
The successful Linux execution above uses this exact retained build.

## Earlier r3 cross-build

Source revision `d08088163eb8e690d8f72999bddc7a21b22922f8` adds a minimal
guest entry path to the synthetic SQLite regression. Linux PID 1 with no
arguments mounts procfs and selects a fixed, fresh synthetic directory.
Ordinary invocations still require an explicit fresh absolute directory.
The same persistence, visibility, user-data and hostile-link checks run in
both modes; the Linux branch additionally reproduces SQLite's rejection of
the old `/proc/self/fd` path with `SQLITE_OPEN_NOFOLLOW`.

The retained static AArch64 build passed. Its complete bundle is outside Git:

`/Users/alex/.local/state/vinix/android/accountstore-linux-regression-build-2026-10-26-r3`

- Complete `sha256.json`: `e1bcff85fd35e78c5c5e6cd069696cfe82db08f08089907d04b350acd671efbb`.
- `build.json`: `5632830f14a4dcd6de96cc21a6ac413190b4ca39edfc02e0f460e8e12f5bc72f`.
- `bin/accountstore-linux-regression`: `386821aecbbbdfdb5c7607e0d247236dcf51f67013df4d5e80784207b4b7d9a9`.
- Fixture source: `78eacda7efd09e070b37ba45eb753920eabdab523af4519b07c962d0ad7ae086`.
- Production store source: `b174fd25e52bcd5f8f29c068a426979a76de3ff6eef05e8550b136530756d6d3`.

The maintained V builder retains its executable, source, compiler, selected V
closure, SQLite source, cross tools, consumed headers and linker inputs. Its
before/after input checks, strict compilation/link, static ELF inspection and
complete output inventory passed. It uses the same account r7 producer and
canonical store implementation as the Maps r4 stage. Host SDK dependencies
remain environmental.

An independent full-bundle check passed all 2,405 file hashes and exact file
membership. Its retained receipt, beside the bundle at
`accountstore-linux-regression-build-2026-10-26-r3-peer-inventory.json`, has
SHA256 `fd8189c392bcf9687fca89c53338635e0b148b38d409a93f9a5c3aba8581ad88`.

Independent source review passed. A freshly compiled host fixture passed the
existing persistence and unsafe-link checks; no-argument non-init invocation
returned usage with exit 2. Host logs are beside the bundle under
`accountstore-linux-regression-host-init-2026-10-26-r1.run.log` (SHA256
`fa850abf541eeca468ce718c1200853b7d8d0cdd78072a46fb376b6c6f860f58`)
and `.noargs.log` (`6f1a3260bf76d62af61d915424f22673c22e8e8f88f9088a92ae09450fd83640`).

The earlier r3 result covered cross-build and host checks. Its first guest
execution failed as described above; the r4 guest subsequently passed. None
of these synthetic store results establish GMS initialization or Google
account login.
