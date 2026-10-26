# Native Android host tools

The extensionless Android entries call this V dispatcher through the maintained
compiler bootstrap. Probe compilation, pinned downloads, ZIP/DEX processing,
bootclasspath preparation and staging, overlay verification, private runtime
staging, generated runtime/configuration sources and host/VM fixtures use SDK
files, processes and sockets. These entries do not launch a Python interpreter.

`build-support/android/build` stages the private ARM64 runtime.
`art-bootclasspath` prepares desugared boot libraries and its optional probe.
`compile-v-runtime`, `compile-v-atl-configuration` and `atl-dex` keep their
existing compiler arguments. The eight extensionless probe builders and three
fixture suites live in `tests/android`; suite class/method names, `-k` selection
and verbose/quiet options remain available. `run-runtime-vm`, `atl-configuration`
and `test-runtime-v` retain their fresh-state, baseline and architecture options.

The ART, Bionic and ATL shell builders use `native-tool` for their former inline
Python path resolution, hashes, compiler arguments, copy operations and
manifests. Native producer source closures participate in build and provenance
keys, so previous overlays and caches must be rebuilt. Compiler children keep
their own process groups; preferred host architecture and inherited stderr use
the shared `sourcecommand` owner. APK extraction reads concatenated compressed
streams and checks payload parents and links against the private runtime.

Runtime fixtures call the native public API and use typed `StageHooks` for the
original compiler effects. The complete 26 ART/Bionic/ATL, nine bootclasspath
and ten musl cases preserve their builders, mutation vectors and assertions.
Qualification ran 36 fresh builds on ARM, x86 and ASan/UBSan, all 45 fixture
cases on each profile, the seven existing Androidhost regressions, archive and
metadata cases, and compressed APK link/path checks. Public checks exercised
20 entry paths, eight argument guards, all three suites and three actual cold
compiler bootstraps. The Darwin runtime test compared generated V with frozen
original C using real ASan/UBSan atfork, fortify and allocator ABI fixtures.
GNU cross-compiler qualification records both runtime ELF targets and allocation
imports. This qualification does not claim a fresh Android application or VM
boot, or a full native Alpine ART/ATL source build.

The application supervisor and interactive fixtures now live in
`tests/native-android-run`. The unused Android `_native.py` and application
`_run_native.py` adapters are retired after fresh native dispatcher and suite
qualification. The generic `_boot_native.py` bridge remains for unported
consumers; its file receives no retirement credit here.

Protected storage extends `ApplicationInfo` with both Android directory fields,
preserves them in copies, and initializes them together with `dataDir` for primary
and companion packages. Ordinary contexts retain the existing private app root;
device-protected contexts use its private `device_protected` child, including
after configuration cloning. This provides separate storage namespaces. Vinix
does not implement Android's separate encryption keys or unlock lifecycle.
The checker exercises the actual sealed baseline and rejects incompatible or
repeated extensions before writing any class:

```sh
v -path tests/native-android-tools:@vlib -o /tmp/check-protected-storage tests/native-android-tools/check-protected-storage.v
/tmp/check-protected-storage BASELINE_SMALI SMALI_TOOLS JAVA
```

The native bootstrap and extended framework must be deployed together: the
bootstrap uses `ApplicationInfo.vinixSetDataDirectory(String)` to keep the
primary package's shared metadata object consistent before app startup.
