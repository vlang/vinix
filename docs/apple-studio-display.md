# Apple Studio Display on the M1 Air

Vinix can use one Apple Studio Display as its framebuffer output when the
Apple boot firmware and the m1n1/U-Boot chain have already established the
Thunderbolt/USB-C scanout. The kernel deliberately preserves that scanout; it
does not attempt a display mode change after taking control.

This first implementation is a boot-time handoff path, not a hot-plug driver.
The display must be connected and showing the Apple or U-Boot startup UI before
Limine enters Vinix. On a MacBook Air, clamshell mode is the most reliable way
to make firmware choose the Studio Display as the single boot output.

Use an m1n1 build with its external-display initialization enabled. Its boot
log should say `display: Display is external` before U-Boot starts; that is the
point where the Type-C link, external DCP and scanout are prepared for Vinix to
inherit.

## Build and deploy

Build the desktop image and the AArch64 kernel as usual:

```sh
./build-desktop-aarch64.sh
make -C kernel ARCH=aarch64 CC=clang
```

Deploy with the external-display handoff flag:

```sh
./deploy-m1-efi.sh --apple-studio-display --desktop-initramfs /Volumes/EFI
```

On the development M1 configured by `kek.sh`, the shorthand is:

```sh
sudo ~/code/kek.sh studio
```

`--external-display` is an equivalent generic spelling. Both spellings:

- remove Limine's `1024x768x32` mode request so the native firmware mode is
  not disturbed;
- add `vinix.display=external` to make Vinix choose the largest valid GOP
  framebuffer (the later GOP wins a resolution tie);
- add `vinix.apple_dcp=0` and enforce that override in the kernel, because the
  current experimental DCP driver binds the built-in panel and can reset the
  display fabric underneath the inherited external scanout;
- register only the selected surface as `/dev/fb0`, so the desktop and kernel
  console render to the same output.

The expected kernel lines are:

```text
framebuffer: selected GOP 1/1, 5120x2880x32 (external handoff)
display: external GOP handoff active; native DCP probe disabled
```

The GOP number and mode depend on what firmware exposes. When both panel and
external GOP handles exist, the first number should identify the 5K surface.

## Current boundaries

- Connecting or reconnecting the display after Vinix starts is not supported.
- Switching between the internal panel and Studio Display requires a reboot.
- The display's speakers, camera, microphones, and downstream USB hub are not
  part of framebuffer handoff support.
- If the Studio Display never shows the firmware/U-Boot UI, no external GOP
  exists for Vinix to inherit. Native hot-plug in that state needs the Apple
  HPM Type-C, ATC PHY/crossbar, external DCP, and DPTX protocol stack; the
  existing internal-panel DCP experiment is not a substitute for that stack.

For a failed hardware boot, first use the normal `diag`/`halt` modes described
by `kek.sh` to confirm the kernel is entered. If the internal panel shows the
`external handoff` line, firmware exposed only that panel; reboot after making
the Studio Display the active boot output.
