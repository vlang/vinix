# AF_INET smoke test

`init.c` is a freestanding aarch64 guest test for the IPv4 socket path. It
checks TCP and UDP over `127.0.0.1`, Linux-compatible socket options, then
waits for QEMU's DHCP lease and sends a DNS query to the resolver advertised
by QEMU user networking.

Build it and place it at `/sbin/init` in a ustar initramfs:

```sh
clang -target aarch64-linux-none -nostdlib -ffreestanding -O2 \
  -Wl,-e,_start -Wl,-static -o /tmp/vinix-net-init tests/network/init.c
```

Boot through `run-aarch64.sh` with that archive selected through
`VINIX_INITRAMFS`. A successful serial log ends with `NET TEST PASSED`.

`guest-tools-boot.sh` is the integration test used by the network developer
tool image. It checks curl over local HTTP and public HTTPS, Git smart HTTPS,
an OpenSSH TCP handshake, and live APK/XBPS repository synchronization.
