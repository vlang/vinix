# VORE (vOS Runtime Environment)

A fork of [vlib](https://github.com/vlang/v/tree/master/vlib) optimized for bare-metal/embedded environments.

Usage:

```
$ v -freestanding -vlib_path /path/to/v_runtime/vlib -o /path/to/output.c build /path/to/source_directory
$ gcc -ffreestanding -std=gnu-99 -nostdlib -lgcc -I/path/to/v_runtime -o output.elf output.c vrt_main.c /path/to/v_runtime/vrt_impl.c
```