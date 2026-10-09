# Browser boot controller

V owns the browser supervisor: environment and command construction, socket
selection, wait-status decoding, serial capture, marker decisions, shutdown
windows, process cleanup and reporting. Python keeps the public signatures,
seven fixed profile dictionaries, parser and early CLI guards. The retained
`_checks` generator is a counted syntax binding so a caller's `any` receives the
original lazy expression; its use and decision belong to V.

Library objects stay in the invoking interpreter under monotonic borrowed IDs.
Calls use the exact namespace factories and receivers. Loop checkpoints retire
replaced temporary objects while keeping named locals, including the last raw
block through stop, close and report. Completed calls return ordinary process
responsibility to the original caller; broken transport retains the shared
bounded guardian. The original 5/2-second escalation, 10-second post-marker
window, 65,536-byte reads and 131,072-byte recent search remain intact.

Host fixtures compare the original policy with native ARM, Rosetta x86 and
sanitizer builds. Real PTY subprocess tests establish host supervision behavior,
without claiming a new kernel or hosted browser guest run. Actual library
tracebacks and aliases are retained; exact private adapter-frame layouts and
post-return cyclic garbage-collection ordering are not claimed.
