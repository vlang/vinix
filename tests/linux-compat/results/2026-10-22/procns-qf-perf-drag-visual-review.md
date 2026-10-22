# ARM Q2 fresh-drag visual review

Reviewer: /root/lifetime_review, 2026-10-22. I viewed both complete PNG screenshots after the strict raw/JSON/input-marker/full-PPM audit passed with status 0.

The System window moves from the upper center to the lower left. Its visible frame counter advances from 6 to 245. The window remains rendered, with the same System content and one open window. This confirms actual window movement for the fresh drag scenario; changed pixels alone were not used as the motion oracle.

This is a five-second functional check with the cached desktop and exact Q2 allocation-tracking kernel, not a release-performance comparison or a long soak.

07267c19f0b06c62e6d761088cca98f017897378acb012dfaee4a48b88e26c33  /Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/qf-perf-drag-shots/before-drag.ppm
947810d2b8ce908c1cb6a36cffe2082d44836288ba44a2dea74dd1c65c60ad00  /Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/qf-perf-drag-shots/new-drag-1.ppm
5c7cc0ff79f9aec5391c2a639b544110d4b633e3fa5b7ca2a273e0ab3bdb4c69  /Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/qf-perf-drag-shots/before-drag.png
de84c2fa35804f376a35a3681c2e848cc7b5dec547c8ebd6b049d68223000ff8  /Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/qf-perf-drag-shots/new-drag-1.png
