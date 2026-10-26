# Account store Linux regression build, 2026-10-26

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
Successful Linux guest execution and Google account login still require
separate evidence.

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

This report covers the cross-build and host checks. It does not claim that
the Linux guest ran, that GMS initialized, or that Google account login works.
The guest must emit `ACCOUNTSTORE-LINUX-PASS`; the runner must supply an
existing `/proc` mountpoint.
