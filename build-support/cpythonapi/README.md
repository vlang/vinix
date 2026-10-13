# CPython C API from V

This module resolves the pinned SDK's C API directly. `Api` must remain alive
until all arenas, callbacks and interpreter threads retire. Close arenas before
finalization and close the library afterwards. Caller code owns initialization
and finalization. An arena tracks new references and separately increments any
borrowed reference it retains; consumers cannot use it after `close()`.

`Method` supplies CPython's 32-byte method definition on supported 64-bit hosts.
Its C flags and all C integer slots are explicitly `i32`. Keep the definition
and its literal name alive with the callable. Native callbacks enter with the
SDK's GIL and transfer their return reference independently of their local arena.
Use `-gc none` when SDK threads call V, and retain context with an SDK capsule
whose destructor releases every strong SDK reference before freeing the context.

The native [CPython smoke controller](../../tests/native-python-smoke/README.md)
is the initial consumer. Its ownership/callback tests use V models rather than
executing Python. No interpreter or first-party Python source is bundled here.

The [macOS installer policy](../../installer/macos/asahipolicy/README.md) also
uses native method descriptors with keyword arguments. A descriptor borrows its
`Method` definition, so keep the definition array and callback context alive
through interpreter finalization. `set_attr` retains no caller reference;
`dictionary_value` increments a found borrowed dictionary value in its arena.
An optional `error_factory` receives borrowed exception type/value/traceback
references; retain each reference needed after it returns. Restore transfers
those references to the SDK, while retirement decrements them exactly once.
The default error handler remains unchanged for the smoke controller.
