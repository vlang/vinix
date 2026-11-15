Compile `run.v` with V to an external executable and run it. Set
`GEM_PRIVATE_TEST_BINARY` to retain the ASan/UBSan executable outside Git.
Set `GEM_PRIVATE_TEST_C` to an external `.c` path to retain generated host C.

The fixture executes the complete production GEM module with host PMM,
atomic and lock services. Two hundred private objects must expose their
assigned identity at the first global handle lookup, preserve alignment and
references, and return backing after final unref. Empty/overflowing sizes,
zero identity and allocation failure must publish nothing. Ordinary and
external constructors keep their shareable defaults.

Normal GEM metadata currently has a separate retention policy in the kernel.
After final unref and removal from the global handle table, this isolated
fixture explicitly frees that metadata, with no borrowed pointers remaining.
It measures physical backing ownership here; it neither changes nor qualifies
the kernel's metadata retention or whole-kernel heap behavior.
