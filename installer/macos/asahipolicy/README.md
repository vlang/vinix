# Native Asahi installer policy

`native-auto/main.v` replaces the first-party `vinix_auto.py` adapter. The app
bundle carries `Resources/vinix-auto`; source-checkout installations build the
same V program before downloading installer components. The prepared support
command invokes that executable with the GUI's selected disk and allocation.

All twelve overrides are implemented in V. They preserve disk/action selection,
the normal 38 GB macOS margin, unique booted-container selection, aligned resize
accounting, the sole Vinix profile, stub subtraction, compatible firmware choice
and the shutdown/recovery instructions. Other choices and Apple authentication
stay in the pinned upstream SDK. No disk or authentication operation is replaced
by a host-side guess. Invalid configuration fails before SDK initialization.

The verified Asahi v0.9.1 archive still supplies its third-party CPython 3.13
framework, modules and installation machinery. V resolves the framework's C API
and attaches native method descriptors to a subclass of `InstallerMain`; it
does not evaluate first-party Python source or generated evaluation strings.
The original support script retains archive checksums, M1 checks, the explicit
GUI confirmation, root preparation and upstream disk mutation/authentication.

Callback keyword binding accepts the original positional and named parameters,
including defaults, and rejects duplicate, missing and unknown arguments. Each
callback arena owns its temporary SDK references and transfers its return
reference. Saved SDK exceptions retain type, value and traceback until they are
restored to the SDK or retired exactly once. Definitions, callback context and
the API remain allocated through finalization; callbacks retire before their
SDK references close, and the dynamic library closes last.
The executable uses `-gc none` for callbacks into V.

Pure V tests cover 256 action combinations, every unique-container selection
through nine candidates, alignment/minimum/stub bounds and profile guards.
The native SDK model covers keyword binding, base-method fallback, external
selection, resize arguments, original SDK calls, completion recording and saved
exception/interrupt/exit ownership. Shutdown and sleep are replaced by V test
recorders. Existing ui2 and smoke ownership tests also run under ARM, Rosetta
x86 and ARM ASan/UBSan. Both slices of the actual pinned framework are checked
for all 40 required exports as data. The shared API smoke controller is rebuilt
and requalified separately, including both real guest ELF builds per profile.

```sh
build-support/run-v-tool.sh tests/native-installer-policy/qualify.v \
  /path/to/qualified/v /fresh/evidence arm /path/to/sdk-framework-data
# Also x86 or san. Framework data is the verified archive's 3.13/Python member.
```

These checks execute no SDK initialization, Python, authentication, installation,
APFS mutation, shutdown or Vinix guest. The signed thin app is built and verified
without launching it. The current qualification compiler reports pre-existing
format differences in `main.v` and `installer_test.v`, so the aggregate
`installer/macos/test.sh` stops at its existing formatter guard; its UI test
binary and policy suites are built and run directly by the qualifier. The
payload/argument checks are exercised separately. No formatter guard is removed.

CPython documents [method calling conventions](https://docs.python.org/3.13/c-api/structures.html)
and [exception reference transfer](https://docs.python.org/3.13/c-api/exceptions.html).
The foreign SDK remains pinned by `install-vinix.sh`.
