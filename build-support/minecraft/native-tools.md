# Native Minecraft tools

The fetcher, ARM LWJGL patcher, Microsoft sign-in command and their host tests
run V directly. Six former Python files are retired: 29,709 bytes / 824 lines.
The host shell entrypoints use the repository V bootstrap. Guest packaging
installs static Linux musl executables for fetching and sign-in; it never
installs the host bootstrap or a Python wrapper.

| Command | Implementation |
| --- | --- |
| `build-support/minecraft/fetch-minecraft` | `minecraftnative` |
| `build-support/minecraft/patch-lwjgl-aarch64` | `lwjglpatch` |
| `build-support/minecraft/minecraft-login` | `minecraftnative/login.v` |
| `build-support/minecraft/stage` | both static guest binaries |
| `tests/minecraft/test-fetcher` | version, policy, hash and staging contracts |
| `tests/minecraft/test-patch-lwjgl` | instruction golden values and independent ZIP producer/reader |
| `tests/minecraft/test-login` | ordered authentication model and real local HTTP observer |
| `tests/minecraft/test-native-cli` | real curl, CLI, process cleanup and optional cross-build checks |

The fetcher retains four download attempts, streamed SHA-1 verification,
Java-compatible version selection, last-matching Mojang rules, ordered library
selection, ARM native substitution, deduplicated assets and shell-quoted
`launch.env`. As before, rules target Linux ARM64, including when the tool itself
runs on x86. `--no-assets` still fetches the index. The original CLI options
remain; optional manifest/Maven/asset mirror URLs permit independent fixtures.
Worker counts are now bounded to 1–64. Unsafe or duplicate output paths are
rejected. A failed transfer or checksum leaves an existing destination intact.

V owns curl's private process group, log descriptor, wait status and temporary
directory. All download workers join before an error propagates. SIGINT and
SIGTERM return 130 and 143 after terminating and reaping active curl children.
Digest buffers are explicitly freed for the guest's `-gc none` build. The
spawn declarations use the platform SDK types through a declaration-only
header, with no implementation in C and no glibc-only spawn extensions.

Sign-in preserves device-code polling, pending/slowdown/default intervals,
Xbox/XSTS exchanges, the missing-profile and child-account errors, entitlement
checking before the profile request, and shell-sourceable session values.
It requires the launcher's configured Microsoft application ID. Tokens are
kept in private request/header files rather than curl arguments. Session
publication is atomic with mode 0600. Curl provides HTTP/TLS with the original
60-second request deadline; V constructs requests and decodes responses.

The patcher retains the exact five-instruction AArch64 transformation and
idempotence marker. It verifies ZIP payload sizes and CRCs before publishing,
preserves order, duplicate entry names, unrelated compressed payloads and ZIP
metadata, and uses a private file on the destination filesystem. It accepts
stored and deflated ordinary JARs plus small ZIP64 records. Encrypted or
multi-disk archives, unsupported compression, members above 128 MiB, expanded
archives above 256 MiB and more than 65,535 output entries are rejected.
Archive comments are preserved; rewritten deflate bytes can differ from the
former writer while decoded data agrees.

## Qualification

Final checks use pinned V 0.5.2 `4eb8f2b` and the matching source tree on
2026-10-11. Twenty-one cold builds and all three host suites pass on ARM,
Rosetta x86 and ARM ASan/UBSan. Three further cold builds cover the CLI suite.
The standalone login test also passes three fresh builds without a globals
command-line flag. All eight public shell entrypoints compile and pass their
help or complete host-suite checks through the normal repository bootstrap.
Actual curl checks cover full/cached/index-only downloads, independent hashes,
ARM natives, asset deduplication, shell quoting, checksum rollback, invalid
arguments and sign-in preflight. Six interrupt runs observe eight active
workers and eight descendants each; every recorded PID is gone and partial
download directories are absent afterward. Both static guest builds pass ELF
architecture/mode checks and preserve the previous executable after a rejected
compiler target. Existing launcher and package-manager regressions pass.

Real Maven LWJGL 3.3.3 and 3.4.1 ARM archives pass independent ZIP decompression:
every other member is identical, the native changes only at the five expected
instructions, and a repeated patch preserves the entire JAR byte-for-byte.
The sign-in fixture exercises all seven HTTP requests through real curl on
each profile. Its localhost proxy override is restored afterward.

Actual ARM and x86 QEMU guests boot frozen production kernels and run the
final static executables with native musl curl. Fresh downloads, cache reuse,
index-only staging, checksum failure preservation and sign-in help/missing-ID
preflight pass. Serial logs contain `MINECRAFT ACTUAL GUEST PASS`; QEMU logs
are separate, and private variable-store copies are removed after emulator
retirement. The bundles use unsigned developer firmware boot, not Secure Boot.

These checks use fixture game data and fake credentials. They do not establish
an actual account login, official game download or gameplay/rendering result.
No Python is run and no kernel is rebuilt. Frozen originals, compiler source,
build/test logs, real JARs and final guest evidence are retained on disk under
`/Users/alex/.cache/vinix-minecraft-native-20261011`.

Run the host suites with:

```sh
tests/minecraft/test-fetcher
tests/minecraft/test-patch-lwjgl
tests/minecraft/test-login
tests/minecraft/test-native-cli /path/to/fetch-minecraft /path/to/minecraft-login
# Include a separately built host stager for both static cross-build checks:
tests/minecraft/test-native-cli /path/to/fetch-minecraft /path/to/minecraft-login /path/to/stage
```
