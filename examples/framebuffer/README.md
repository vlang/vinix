# Framebuffer demo

A standalone Vinix GUI application using only `desktop.windowfb`, mmap, and a
waitable Unix socket. It does not import ui2. Move the pointer to move the white
square; press `q` or Escape to exit, or close its normal desktop window.

Build with the repository on V's module path:

```sh
v -new-compiler -path '@vlib|@vmodules|.' -o framebuffer-demo examples/framebuffer
```

For Vinix, compile for the guest architecture and link against its musl SDK,
as with other standalone executables. Run `./framebuffer-demo` from a Terminal
inside the desktop; it connects to `/run/vinix-session.<uid>/windows`.

The [wire-format documentation](../../desktop/FRAMEBUFFER.md) explains how to
implement the same interface in another language without using the V module.
