# Display-hotplug policy oracle

Run the independent V fixture against the actual kernel hotplug policy:

```sh
tests/apple_display_hotplug/run.sh
tests/apple_display_hotplug/run.sh --host-arch amd64
```

Host builds use ASan/UBSan with immediate failure. The generated production and
fixture objects have no allocator imports; the policy state stays on the stack.
Apple's sanitizer does not support LeakSanitizer. All 47 original checks and
line tags remain, including cold attach without HPD, short HPD pulses, unsigned
counter wrap, one-shot action selection, non-1 C truth values and zero debounce.

Build a static native fixture and boot an isolated guest:

```sh
tests/apple_display_hotplug/run.sh --arch aarch64 \
  --kernel-dir /path/to/isolated/kernel \
  --state-dir /path/to/new/hotplug-build \
  --guest-state-dir /path/to/new/hotplug-guest
```

Use `--arch x86_64` for musl GCC, or `--build-only` to emit the native executable.
`--original-reference /path/to/frozen/test_hotplug.c` compares the immutable
original with the same provider, compiler flags and guest entry. Normal builds
read maintained V only. The production provider is copied with a private module
name; its algorithms and public header remain unchanged. Native model tests do
not verify physical CD321x/DCP hardware operation.

The command now parses, builds and supervises guests in V. See
[host-controller.md](host-controller.md) and
[qualification](../apple-protocols/mailbox-hotplug.md) for current checks.
