# PCI configuration transactions

`./run.sh` compiles the production V transaction core and links independent C
callers against its preserved ABI. Both GNU C dialects run with AddressSanitizer
and UndefinedBehaviorSanitizer. The transport model checks register widths and
bounds, unchanged outputs on error, serialized CF8 access, atomic COMMAND
updates, preserved interrupt state, and the adjacent write-one-to-clear STATUS
register. Allocator calls are replaced with traps.

The host transport model cannot validate real interrupt masking or ECAM access.
Build an ARM kernel with `PCI_CONFIG_TEST=1` and run `arm_vm.py --kernel <image>`
to exercise the actual platform transport and every DAIF mask combination.
