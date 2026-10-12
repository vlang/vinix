The Mesa guest controller owns PTY launch, byte transcripts, prompt and exact
marker validation, QMP shutdown, deadlines, process-group escalation and child
retirement in V. The header exposes SDK declarations and constants only. The
native frontend retains the original CLI, byte markers and regex boundaries.
V performs `chdir` and `execve` directly, with no interpreter child adapter.

The historical borrowed-child protocol remains available to legacy native
requests. The maintained VM command calls its process primitives directly from V.
All argv strings, environment entries, transcripts and scratch paths remain
owned until their last use. Socket descriptors close on every return, and PTY
retirement preserves stop/close error precedence.

A first SIGINT or SIGTERM ends the test and retires its child. Further signals are ignored
only during that retirement, with the previous handlers restored afterward.
An integer timeout outside floating-point range raises the original OverflowError
and also retires the native child. These two bounded cleanup improvements prevent
abandoned children; the original overflow deadline preceded its try/finally.

Qualification on ARM, Rosetta x86 and ARM ASan compares 9,105 frozen-original
marker/prompt/resource/status cases per profile, eleven actual PTY/QMP flows,
seven QMP helper cases, four parent-owned stop/reap cases, three interruption
flows, seven CLI cases, nine typed timeout API pairs and timeout/second-interrupt edges. Native units measure
100 socket lifetimes and 100 child reaps against exact descriptor baselines,
and check FD_SETSIZE before touching a select fd_set. Cold installation and
failure retire their private directories on both caller architectures.

Two actual AArch64 QEMU runs use an explicitly hashed existing kernel and image.
Both the frozen original and native controller reach the shell, submit the
unchanged guest command and report the same FAIL:127 and missing-marker
list because the existing image's Mesa/Wayland/libc dependencies disagree.
This is a matched guest failure, not rendering or fresh kernel-build evidence.
The independent renderer assertions and timeouts are unchanged.
