# Apple provider host controllers

`applehost/providers.v` owns the source-copy and hardware-omission policies used
by the ANS, SPI and speaker fixtures. The existing provider Python modules keep
their import APIs, hardware-name constants and standard-library digest binding.
Their copy operations call this native controller through a byte-safe adapter.

The controller preserves whole-definition removal, original line ranges,
reference classification, retained-chunk hashes, receipt key order and copied
source bytes. UTF-8 text reads retain the original newline conversion; ext2
source remains raw bytes. Parser errors and partial filesystem states remain
visible to callers. Private compiler/result directories and file descriptors
have explicit owners.

Qualification compares frozen original providers against the installed adapter
on ARM64, x86-64 and with ARM ASan/UBSan. It covers production source variants,
malformed definitions, Unicode13 boundaries, overlapping ranges, read failures,
literal Unix backslashes and raw-byte filename errors. Native tests exercise
retained source bytes, omission ranges, parser errors and repeated descriptor
retirement. Cold concurrent imports share one private installer and retire it
when the process exits.

This is host-controller qualification. It adds no physical Apple hardware or
kernel/QEMU validation result. Independent fixture inputs and assertions stay
unchanged.

The broader ANS, SPI and speaker consumers currently fail under V 0.5.2
`6d549c2f`: generated freestanding C uses undeclared `memdup`; x86 ANS also
rejects the existing ARM inline assembly. Frozen original providers produce
the same diagnostics and identical provider inputs on both host architectures.
These comparisons establish baseline parity, not passing consumer fixtures.
