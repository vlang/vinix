# M1 Air Wi-Fi

The experimental driver is integrated and clean debug/production ARM64 kernels
link successfully. Its control ABI supports firmware loading, reversible radio
on/off, asynchronous network scans, WPA2 association and raw Ethernet I/O.
Physical BCM4378 operation still needs validation on M1 Air hardware, and Vinix
does not yet have an IP stack behind this device.

See [build, validation and hardware bring-up instructions](../tests/m1-wifi/README.md).

Hardware probing remains opt-in with `vinix.apple_wifi=1`; firmware is not
included. The normal `desktop` and `desktop-drivers` deployments now supply
that argument, and `kek.sh desktop-wifi` names the Wi-Fi-only choice explicitly.
Direct deployments can pass `deploy-m1-efi.sh --apple-wifi`. A boot without one
of those choices intentionally has no `/dev/wlan0`.

The desktop initramfs includes the target `wifi-ctl` utility. To make a locally
packaged, matching bundle available at boot, build with
`VINIX_WIFI_BUNDLE=/path/to/wifi-bundle ./build-desktop-aarch64.sh` or pass
`--wifi-bundle=/path/to/wifi-bundle`. The build requires all five package files,
and init runs `wifi-ctl load /usr/share/vinix/wifi` before starting the desktop.
The loader rechecks the bundle manifest against the detected chip and refuses a
mismatch. Without a bundle, Settings reports that firmware still needs loading.

`/dev/wlan0` is a raw Ethernet/control interface, not AF_INET sockets. Once
matching firmware has loaded, the desktop's **Settings > Wi-Fi** pane can turn
the radio on or off, start a scan and list the networks it found.
