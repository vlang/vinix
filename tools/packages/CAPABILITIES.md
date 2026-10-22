# Package-tool interface discovery

Run `vinix-package capabilities` before choosing a package SDK or native window
protocol. The command always writes one JSON object to standard output and exits
zero on success. It reads no repository configuration or installation state and
does not contact a repository, request approval, or create an installation.

```console
$ vinix-package capabilities
{"format":1,"package_formats":[1],"application_sdks":[1],"native_window_protocols":[1,2],"deployment_formats":[1,2]}
```

`vinix-package --json capabilities` produces the same response. Global options
precede the command: `vinix-package capabilities --json` is refused, as are
operands, `--root`, `--offline`, and `--progress`. An older package tool that does
not implement the command will exit nonzero; callers must treat that as unknown
capabilities and require a compatible package tool rather than assume a version.

The lists report interfaces accepted by this executable:

| Field | Meaning |
| --- | --- |
| `format` | Version of this capabilities response schema. |
| `package_formats` | Signed package/index metadata format versions. |
| `application_sdks` | Application context SDK versions. |
| `native_window_protocols` | Native window broker protocol versions, including text input protocol 2. |
| `deployment_formats` | Application deployment declaration/lock schema versions. |

Select versions by exact membership. A response containing `[1,3]` does not
advertise version 2. A package without a native window interface does not need a
window protocol entry. A matching version still requires normal metadata,
architecture, dependency, permission, policy, and signature validation.

This response does not report installed packages, available foreign runtimes,
publisher enrollment, license approval, or native qualification of a runtime or
application. A Linux, Wine, or Apple publisher profile is not a promise that its
payload runs on every target.

## Format 1 reader contract

Format 1 contains exactly the five required fields above. Each version list is
nonempty, has at most 32 entries, and contains distinct, ascending integers from
1 through 65535. The response is at most 4096 bytes. Numbers use canonical
unsigned decimal JSON notation. Field ordering and JSON whitespace are
insignificant; escaped field names have the same identity as their decoded form.
Duplicate or unknown fields, missing fields, trailing input, and an unknown
`format` are refused.

New interface version numbers may be added to these lists within format 1.
Callers retain unfamiliar numbers and use only exact versions they understand.
Adding a response field requires a new response schema format; unknown fields
are not silently ignored by the format 1 decoder.

V callers can use `tools.packages.pkgprotocol.decode_capabilities(text)!` and
`value.supports_package(package_format, sdk, window_protocol)`. Decode or validate
the response before calling the membership helper. Pass window protocol zero
when no native window interface is requested. A successfully decoded value owns
its four arrays, independently of the borrowed input string; call `value.close()`
when finished. Closing the value twice is safe.

## Focused validation

The V driver retains sources, literal build arguments, logs, generated C, and
executable hashes. It runs non-production assertion tests against the actual
package/deployment admission gates, decoder allocation tracking and
ASan/UBSan, and real CLI checks in a new private directory. Both ordinary and
production CLI builds must return the same capabilities with no configuration,
refuse eight invalid argument forms, and preserve the private directory and
home. It also cross-compiles the package CLI for aarch64 and x86_64 using the
repository's locally prepared musl sysroots; it does not boot a guest.

```console
$ V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1 \
    "$V" -backend c -gc none -manualfree -prod \
    -o build/capabilities-build tests/packages/capabilities-build.v
$ build/capabilities-build "$PWD" "$PWD" "$PWD/build/capabilities-result"
```

Use a new output directory. The source worktree and the repository containing
the prepared sysroots may be different directories. Set `V` to the compiler
being qualified. `artifacts.json` records the V executable, runtime helper
headers, cross compiler, source inventory, outputs, and commands. Imported
compiler libraries, transitive host tools, and sysroot contents are not a fully
hermetic toolchain inventory; this is focused interface validation and target
compilation evidence.
