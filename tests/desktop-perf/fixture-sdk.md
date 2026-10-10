# Desktop measurement fixture controller

`fixture_library.v` exports the V fixture policies through the calling CPython's
object API. `test_runner.py` preserves its public helper and unittest method
signatures, the actual caller objects, and the original measurement assertions.
The adapter builds a private library with the repository compiler selector on
first use. `VINIX_PERF_FIXTURE_LIBRARY` can select an already qualified library.
The loaded implementation keeps only a finite pool of its own byte, integer and
text literals. Callback results and caller objects retain explicit references
only while their original operation or saved exception needs them.

V owns the prepared portable dictionary, measurement-line policies, complete
line iteration, five main-verdict assertion methods, four dictionary-asset
methods and both temporary-VM cleanup methods. The main-verdict setup and its
nested mocked guest callback, the missing-dictionary test and unittest CLI stay
Python. The existing `path.name` generator remains a counted Python syntax leaf;
it is lazy and is consumed by the actual supplied tuple factory. Original
scenario/program constants stay Python and receive no translation credit.

Supplied factories, comparison/format callbacks, context managers and assertions
are real Python objects. Special context methods are looked up on the actual
type before entry. Temporary arguments and formatted values retire in original
order; named locals are retained when the actual saved traceback needs them.
Clearing a traceback also requires leaving its currently handled exception
scope before CPython releases that scope's saved traceback. Actual callback
exceptions, prior handled state and explicit cleanup remain observable.

The native boundary does not reproduce private helper frames or their precise
contribution to CPython's global recursion budget inside arbitrary callbacks.
It does preserve the maintained helper results, iteration, context order and
allocation ownership. The library has no independent interpreter or copied
object model. Cold compiler setup privately captures its own standard-library
operands before fixture callbacks can replace policy globals.

Qualification compares the frozen original with production V on ARM, x86 and
ASan/UBSan, using the same original test assertions. Host fixture checks add no
new kernel, QEMU desktop, performance or physical device evidence.
