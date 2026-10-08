G17 recovery implementations already live in the native V decoder, expression
and report modules. This module maintains the import ABI for their 191 Python
forwarders: parameter names, defaults, string annotations, original docstrings,
generator kind, native call, transport conversions and returned container types.
The manifest contains declarations and stdlib serialization tags. It contains
no recovery bodies and earns no additional algorithm translation credit.

The Python binding adapts two fixed function templates with `types.FunctionType`
and `CodeType.replace`. Python itself binds positional and keyword arguments;
there is no source compilation or replacement argument parser. The generator
template defers dispatch until iteration. Each function retains its declaration,
module namespace and builtins; borrowed arguments and converted buffers survive
the synchronous native call. The existing native response release stays intact.

Qualification compares all public signatures, annotations, defaults, docstrings,
generator behavior and 1,542 argument/conversion cases with the frozen original
on ARM64 and actual x86-64 Python callers. The native manifest compiles and
validates on ARM64, x86-64 and ARM ASan/UBSan. One hundred namespace retirements
release all 19,100 bound functions after collection; independent lifetime review
passed. CLI behavior and first import from a foreign thread retain their original
behavior on both caller architectures.

Existing image fixtures retain all forty-seven typed results and borrowed input
immutability checks. All 264 public constants preserve their types and mutable
identity. The complete 935,250-byte report, fifty-two report errors and foreign
thread ownership checks pass on both ABIs. An older frozen suite's 181 test cases
also match exactly: 95 pass, 12 remain skipped and 74 retain their existing
failures where Python provider mocks cannot enter the already-native implementation. Those failures
are not counted as passing algorithm tests. No independent fixture assertion
was changed, and this binding change does not add kernel or physical GPU claims.
Evidence is under `~/.cache/vinix-python-to-v/g17-binding-20261008/`.
