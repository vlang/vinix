# Apple display hotplug policy

`./run.sh` generates C from the production V policy and links it to the
independent C caller with ASan/UBSan. It preserves the state layout and tests
DP, Thunderbolt and USB4 detection, cold attach without HPD, transient pulses,
connect/disconnect debounce, unsigned timer wrap and one-shot reboot selection.
Boundary cases include null reset, initial attachment without an event, zero
debounce, raw status preservation and non-`1` C truth values. The extended
fixture also passes against the original C implementation.
The policy object must have no allocator imports.

Kernel builds and guest boots cover integration on both architectures. QEMU
does not emulate Apple's CD321x/DCP hardware; physical cable attachment and
firmware display training require a base M1 machine.
