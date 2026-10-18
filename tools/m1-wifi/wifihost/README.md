The Wi-Fi firmware packager, control/provider C producers and linked-kernel
verifier now use native V entrypoints. The driver, firmware format and original
nineteen-symbol kernel policy remain unchanged.

`tools/m1-wifi/package` checks the saved 256-byte status, revision/board and all
five identity fields before creating an exclusive output directory. It preserves
the 128-byte manifest, payload limits, minimum vector-table size, ASCII NVRAM
and SHA256 provenance. The RAMS override is optional; the driver validates RAM
bounds using the chip's SYSMEM banks. Firmware is selected locally; packaging
does not access hardware.

`tools/m1-wifi/capture.v` is a read-only SSH alternative for a running macOS
J313. It binds the bundle to the live module and antenna identity, copying only
the four files explicitly selected by AppleBCMWLANCore. macOS evidence is kept
separate from a successful Vinix chip probe; the runtime manifest check is
unchanged. See [capture instructions and evidence](../../../docs/apple-wifi.md).
`v test tools/m1-wifi/wifihost` checks this parser and manifest path, including
ambiguous identities and mismatched or unsafe filenames.

`tools/m1-wifi/compile-v` and `tests/m1-wifi/compile-provider` select the repository
compiler, stage the unchanged source, retain the original freestanding/manualfree
flags and clean their private trees on success and returned failures. Provider
symbol replacement preserves Unicode word boundaries. Maintained build callers
and desktop cache inputs name the native entrypoints and implementation.

`tests/m1-wifi/verify-build KERNEL GENERATED_C` rejects wrong architectures,
dynamic loaders, out-of-range ELF tables, unresolved or missing Wi-Fi symbols,
duplicate Limine requests and missing/reordered console hooks.
`tests/m1-wifi/verify-test` retains all eleven bad-copy regression groups.

`tests/m1-wifi/run-tools.sh` builds its five native tools in private scratch and
checks exact manifest bytes, binary payloads, JSON ordering/escaping/digests,
input limits and refusal to overwrite output. A real Clang/LLD AArch64 fixture
exercises the verifier and malformed ELF bounds. A V compiler double checks all
six producer profiles, unchanged staged sources, exact flags, token replacement
and success/failure cleanup. `--real-generators` additionally emits all six real
profiles, compiles strict ARM/x86 musl objects, audits allocator imports and
links both control utilities statically using this checkout's cross toolchains.
`VINIX_WIFI_TOOLS` can select a precompiled tool directory for instrumentation.

ARM, x86 and ASan/UBSan qualification passed, as did a cold launch outside the
checkout. Python was not run. The cached current kernel fails the retained
legacy symbol policy (it exposes V module-prefixed symbols and inlines some
providers); the older Wi-Fi artifact lacks the maintained `wifi` symbols.
Neither artifact is accepted as a complete passing build. Positive coverage
comes from the independently linked fixture. This port establishes no fresh
full kernel build, guest boot or Wi-Fi hardware result. The existing build.sh
also references retired C providers and needs a separate driver-build update.
