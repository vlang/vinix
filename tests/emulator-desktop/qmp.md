# Native emulator desktop QMP

`emulatorhost/qmp.v` owns one nonblocking Unix socket, the buffered reply
stream and the desktop pointer sequence. Setup, send and read operations use
ten-second socket deadlines. Short polling checkpoints allow SIGINT to
interrupt a pending reply; setup, error and ordinary close paths retire the
socket, including failed connects. A second close is harmless.

The client parses the greeting and negotiates capabilities, skips asynchronous
events, raises on error replies and returns the first `return` value. JSON
number tokens keep their complete spelling, including integers beyond 64 bits.
Malformed JSON, EOF and invalid UTF-8 remain errors. Native error text can
differ from the earlier Python transport's exception formatting.

Pointer events retain x/y ordering, ties-to-even coordinate rounding, button
press/release order, 150 ms click holds, 500 ms post-click waits and all three
250 ms analog-drag pauses. Long waits retain their deadlines and use short
interrupt checkpoints. Production screenshot crop rectangles, startup and
close deadlines, animation/movement thresholds and pause checks retain their
original values.

The previous borrowed Package Session query and its Python classes are
retired. [Controller qualification](controllers.md) records actual socket
exchanges, measured timing, resource and signal checks and guest limits.
