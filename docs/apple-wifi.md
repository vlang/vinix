# M1 Air Wi-Fi: build milestone

The experimental driver is integrated and clean debug/production ARM64 kernels
link successfully. This does **not** establish a working radio or IP stack.

See [build, validation and hardware bring-up instructions](../tests/m1-wifi/README.md).

Hardware probing remains opt-in with `vinix.apple_wifi=1`; firmware is not
included. `/dev/wlan0` is a raw Ethernet/control interface, not AF_INET sockets.
