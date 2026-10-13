# Signed native counter

This static V application uses native window protocol 1 for a label and button.
Software renders its display list, delivers frame-bound button events and asks
it to close. The ordinary account retains the count in private application data.
It needs no display device, X11 server or host runtime.

Build a dual-architecture publisher workspace with the V/musl toolchain:

```sh
V=/path/to/v VINIX_MUSL_COPYRIGHT=/path/to/musl/COPYRIGHT \
  /path/to/v -no-skip-unused run examples/package-counter/build.v /build/new-counter-workspace
vinix-package publish-release /build/new-counter-workspace company /secure/publisher.seed 1 EXPIRES_UNIX /srv/new-counter-release
```

The builder retains SDK, V and musl notices. It does not create trust or a signing
seed. Enroll the actual publisher, refresh its catalog, and install
`org.vinix.counter`. Start/Quick Launch and Software select the broker from the
installed signed `window_protocol:1` manifest. `run-window org.vinix.counter` is
the equivalent stream boundary for custom broker clients; its output is a display
list rather than terminal text. See [the SDK](../../tools/packages/SDK.md).
