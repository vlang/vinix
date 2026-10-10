# Verified-boot policy fixture controller

`test.py` retains its Python import interface, `unittest.TestCase` discovery,
argument parser and optional real PE-signature integration. The ELF/PE fixture
construction and the two unsigned-bundle/block-root regression bodies live in
this V module. The PE fixture remains a mapped parser input; it is never signed
or booted.

The controller calls the real policy implementation, `struct`, `Path`, temporary
directories and the supplied test case's `assertRaises`, `assertIn` and `subTest`
methods through the existing package SDK. The original artifact, symlink,
truncation, geometry, digest and command-line assertions remain in force. There
is no stand-in signing result or policy verifier.

Fixed attribute keys borrow the adapter's literal name objects. Function and
method targets are captured before their arguments are evaluated. Named local
values survive to their original overwrite or method-return boundary. On an
escaping error, the adapter traceback pins those values until its traceback
is cleared; temporary
references retire at statement boundaries. Entered managers retain their cached
exit method, and caught exception slots retire after the real assertion context
has handled them. Counted Python leaves retain FORMAT_VALUE and dictionary
unpacking syntax; formatting, option selection and iteration policy remain in V.

The finite scalar and byte literals retain their actual CPython objects in a
module-owned dictionary. Identifier and keyword names retain their interned
identity. The PE zero field is a folded byte constant, as in the original
Python implementation. Caller-provided values stay outside this literal pool.

`VINIX_BOOT_TEST_QUERY` selects an already built controller. Normal discovery
uses `build-support/run-v-tool.sh`, with a private executable cleaned at process
exit. Query children use the existing bundle controller's process factory and
run in their own process groups. The package and boot SDK libraries must match the invoking interpreter.
Host fixture validation alone does not establish a fresh kernel build, boot,
firmware trust enrollment or real signed-loader result.
