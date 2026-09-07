# M1 Air Wi-Fi

The experimental driver is integrated and clean debug/production ARM64 kernels
link successfully. Its control ABI supports firmware loading, reversible radio
on/off, asynchronous network scans, WPA2 association and raw Ethernet I/O.
Physical BCM4378 operation still needs validation on M1 Air hardware, and Vinix
does not yet have an IP stack behind this device.

See [build, validation and hardware bring-up instructions](../tests/m1-wifi/README.md).

Hardware probing remains opt-in with `vinix.apple_wifi=1`; firmware is not
included. `/dev/wlan0` is a raw Ethernet/control interface, not AF_INET sockets.
Once matching firmware has been loaded, the desktop's **Settings > Wi-Fi** pane
can turn the radio on or off, start a scan and list the networks it found.
