# Protected Google Maps browser deployment

`build.v` reconstructs a protected AArch64 musl/WebKit/Xvfb runtime from pinned
APK archives and a sealed `webview-engine` build. It prepares deployment inputs;
it does not boot a guest or establish that Google authentication works.

Build with V's normal garbage collector. Include these module paths:

```sh
v -prod -path '@vlib|tests/android-browser-deployment|tests/native-android-ws|build-support|build-support/android' \
  -o /external/state/browser-deployment-builder tests/android-browser-deployment/build.v
```

Run with the repository, base runtime, its `runtime-manifest.json` SHA256, base
APK cache, addon build, its `build.json` SHA256, addon APK cache, engine build,
its `build-sha256.json` SHA256, the compiler sysroot's `libc.so` and its SHA256,
and a fresh output directory outside the repo:

```sh
/external/state/browser-deployment-builder REPO BASE_RUNTIME BASE_MANIFEST_SHA \
  BASE_APK_CACHE ADDON_BUILD ADDON_BUILD_SHA ADDON_APK_CACHE \
  ENGINE_BUILD ENGINE_INVENTORY_SHA TOOLCHAIN_LIBC TOOLCHAIN_LIBC_SHA FRESH_OUTPUT
```

The builder verifies the inputs before and after extraction. Offline APK
dependency resolution requires every declared package or command provider to
exist in the pinned locks. It rejects ambiguous providers, conflicting package
payloads, unsafe archive paths, escaped or cyclic links, unsupported ELF files,
and missing ELF dependencies. Package links become independent regular files;
the deployed tree has no symlinks or hardlink aliases.

ELF search-path overrides are rejected except exact, SHA-pinned fallback paths
in seven aliases of SQLite, LLVM and libproxy. The launcher supplies a protected
`LD_LIBRARY_PATH` first, and every ELF dependency must exist there. Legacy
`DT_RPATH` is rejected for every file. The protected library search list includes
`usr/lib/libproxy` so its backend resolves inside the pinned closure.

The engine's musl cross compiler requests `libc.so`; Alpine uses
`libc.musl-aarch64.so.1`. The builder requires identical pinned runtime loader
and libc bytes, then checks the engine's unversioned dynamic imports against
both the retained, pinned compiler libc and deployed musl. Required symbols,
types and data sizes must agree, including executable COPY data symbols.
Only then does it create an independent
`lib/libc.so` copy and retain the comparison in `musl-abi.json`.

The output contains:

- `payload/opt/vinix-google-browser/`: runtime files, relocated fontconfig,
  generated X bitmap-font index, injected WebKit bundle, and cookie-capable engine.
- `payload/lib/ld-musl-aarch64.so.1`, fixed WebKit subprocesses, `xkbcomp`,
  `bwrap`, and the exact TLS trust data at
  `payload/etc/ssl/certs/ca-certificates.crt`.
- `manifests/maps.manifest` and `manifests/gms.manifest`: exclusive principals
  10012 and 10013, respectively, with distinct private app data directories.
- `payload-files.json`: expected root ownership and exact file modes/hashes.
- `build.json`, complete `sha256.json`, retained builder/source files, package
  receipts, and source/input inventories for audit.

Payload leaves are 0444 or 0555. Deployment must retain root ownership and
protected ancestors, preflight collisions against the original guest modules,
and enforce those leaf modes before launch. The Maps account stager installs
the manifests under `/opt/vinix-maps-account/browser/`. Existing kernel overlay
inodes may retain their original modes and require controlled hardening before
strict browser admission.

The launcher requires the injected bundle and seven exact external pins,
including the non-executable CA file. Production keeps WebKit's sandbox enabled.
CPU rendering and other diagnostic environment changes require separate guest
qualification; this bundle does not enable them.

Host tests:

```sh
v -path '@vlib|tests/android-browser-deployment|tests/native-android-ws|build-support|build-support/android' \
  test tests/android-browser-deployment
```
