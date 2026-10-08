# Independent AGX trace workflow

`python3 run.py` compares the production V trace core with the immutable C core
at `823aeb116eb3b3ab20463ccb9b1c3fba6f0c41ae` and the original independent C
fixture at `8f7239d1fd4c593746279699f6ff25df5f4dd7bd`. `--baseline-rev` retains
its original override. The Python entry keeps the argument parser; the complete
build, execution, normalization and assertion policy lives in
`../agx-fake-g17/agxhost/trace*.v`.

The workflow retains all four complete ordered JSON comparisons, original
resource and method assertions, allocator import checks, exact interpose
section checks and compiler flags. It runs the real Mach/dyld ABI probe and
compiles the production bindings for both Darwin architectures. Generated
headers and preprocessor configuration surround the immutable C fixture;
its test bodies remain unchanged.

Qualification includes actual ARM and x86 V compilers, ASan/UBSan fixtures,
always enabled ASan fake-stack native tests, and both mixed caller/controller
architecture combinations. Per profile, 15,506 independent controls cover the
original numeric equality, arbitrary-width integers, Unicode line boundaries,
pointer text, complete ordered assertions and first-match section grammar.
Fourteen complete failure flows preserve exception arguments, `Path` command
values, raw Git output, inherited compiler output and strict UTF-8 errors.

Immutable original Python source, captured full fixture logs and source-bound
qualification receipts are retained in the machine-local
`~/.cache/vinix-python-to-v/agx-trace-runner-20261008/` directory. These are host
workflow and native ABI checks; physical GPU and guest execution have separate
tests.
