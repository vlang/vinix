This module declares the Python import ABI for fifty-four already-native
DeviceTree and T6050 proof functions. It reuses the G17 stdlib binder with named
native modules and live class arguments. Dataclasses, arbitrary predicate
traversal, DeviceTree discovery and argparse remain in the frontend. This is
binding consolidation with zero additional algorithm translation credit.

Bound functions retain their actual module globals, one private dispatch,
declarations and borrowed argument owners until synchronous native calls finish.
Class replacement by an importing caller remains visible. Fixed templates
retain ordinary interpreter argument binding and future annotation flags;
generator dispatch stays lazy. These owners form collectable Python cycles,
and the existing native result release is unchanged. Independent lifetime
review passed.

Both ARM64 and actual x86-64 callers pass 445 frozen-original signature,
defaults, annotations, type-hint, docstring, code-flag, module-global, late-class
and call controls. Native ABI data compiles and validates on ARM64, x86-64 and
ARM ASan/UBSan. All 199 public constants retain their types, lazy access,
mutable identity, directory/from-import behavior and caller overrides. The
three retained independent public fixture tests pass. An older twenty-case
suite matches exactly, including three existing native-provider errors.

Actual frozen and native CLIs emit identical 49,676-byte manifests on both
ABIs, also matching the retained original image report. CLI argument/error
controls remain identical. One hundred namespace retirements release all
5,400 bound functions and their one hundred dispatch owners after collection.
The shared G17 binder retains all 1,542 call controls per ABI, its 191 actual
module globals and code flags, the complete older fixture baseline and lazy
generator behavior; its one hundred namespace cycles retire 19,200 owners.
No independent assertion was changed. This adds no kernel, guest or physical
hardware claim. Evidence is under
`~/.cache/vinix-python-to-v/t6050-binding-20261008/`.
