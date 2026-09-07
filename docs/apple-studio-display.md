# Apple Studio Display on the M1 Air

Vinix can use one Apple Studio Display as its framebuffer output when the
Apple boot firmware and the m1n1/U-Boot chain have established the
Thunderbolt/USB-C scanout. The kernel deliberately preserves that scanout; it
does not attempt a display mode change after taking control.

The kernel monitors both CD321x Type-C controllers after boot. It polls cable
presence and the negotiated DP, Thunderbolt, or USB4 mode every 100 ms and
debounces transitions for 500 ms. First attach deliberately does not require
DisplayPort HPD, because HPD may remain low until firmware starts the external
DCP. The current aggregate state is also readable from
`/dev/display-hpd` as `connected`, `disconnected`, or `unavailable`.

Two attach cases are supported:

- When firmware handed Vinix the Studio Display framebuffer, unplugging and
  reconnecting it keeps the same single output and repaints an idle console
  without rebooting.
- When Vinix booted on the M1 Air's 2560x1600 internal panel, connecting the
  Studio Display triggers one warm reboot. Leave the cable attached: iBoot and
  m1n1 train the link on that boot, then Vinix selects the external framebuffer.

The second path is a boot-firmware recovery, not a native modeset. Vinix shuts
down ANS storage first and cancels the reboot if that shutdown fails. It is
restricted to the exact base-M1 Air panel mode; an unknown framebuffer is
never rebooted. On a MacBook Air, clamshell mode remains the most reliable way
to make firmware choose the Studio Display as the single boot output.

Save work before connecting the display to an internal-panel boot. Persistent
ANS writes are drained, but applications are not given a shutdown notification
and volatile desktop state is lost in the warm reboot.

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
- add `vinix.display_hotplug=1` to monitor both CD321x Type-C ports and publish
  their aggregate debounced display-attach state as `/dev/display-hpd`;
- add `vinix.display_coldplug=reboot` so a first connection after booting on
  the M1 Air panel restarts once with the cable present; use
  `vinix.display_coldplug=off` as a later command-line token to disable this;
- add `vinix.apple_dcp=0` and enforce that override in the kernel, because the
  current experimental DCP driver binds the built-in panel and can reset the
  display fabric underneath the inherited external scanout;
- register only the selected surface as `/dev/fb0`, so the desktop and kernel
  console render to the same output.

The expected kernel lines are:

```text
framebuffer: selected GOP 1/1, 5120x2880x32 (external handoff)
display: external GOP handoff active; native DCP probe disabled
apple-typec: port 0x38 status=0x........ data=0x........
apple-typec: port 0x3f status=0x........ data=0x........
apple-typec: polling 2 Type-C ports on I2C 0x235010000
```

The GOP number and mode depend on what firmware exposes. When both panel and
external GOP handles exist, the first number should identify the 5K surface.

If Vinix initially boots on the internal panel, the expected attach lines are:

```text
apple-typec: external display attached (debounced Type-C mode)
display: first post-boot Studio Display attach; rebooting once for firmware link training
```

The next boot should report a 5120x2880 external GOP. If it returns to the
internal panel, the boot firmware did not select the attached display; close
the lid or select the external display in the boot environment and try again.

If connecting after boot produces no attach line, compare the two raw `port`
lines before and after connecting. At least one must change. If neither changes,
or only one port was logged before the `polling 2` line, capture those exact
lines: they distinguish an I2C/controller failure from an unrecognized Type-C
negotiation.

## Current boundaries

- Unplug/replug of the firmware-established Studio Display output is
  supported. Vinix retains the framebuffer, observes HPD, and repaints its
  text console when the link returns.
- A first connection after Vinix booted on the internal panel is recovered by
  an automatic warm reboot. There is no external GOP surface before that
  reboot, so the screen does not switch in place.
- Switching between the internal panel and Studio Display therefore still
  crosses a reboot; Vinix intentionally exposes one framebuffer output.
- The display's speakers, camera, microphones, and downstream USB hub are not
  part of framebuffer handoff support.
- If the Studio Display never shows the firmware/U-Boot UI after recovery, no
  external GOP exists for Vinix to inherit. An in-place attach in that state
  needs the Apple HPM Type-C, ATC PHY/crossbar, external DCP, and DPTX protocol
  stack; the existing internal-panel DCP experiment is not a substitute.

For a failed hardware boot, first use the normal `diag`/`halt` modes described
by `kek.sh` to confirm the kernel is entered. If the internal panel shows the
`external handoff` line again after automatic recovery, firmware exposed only
that panel; make the Studio Display the active boot output before retrying.
