# QCA9377 on the ThinkPad E470

The native V driver targets PCI **168c:0042**, Lenovo subsystem **17aa:0901**.
It boots Qualcomm firmware, uses PCI copy-engine DMA and HTC/WMI/HTT, performs
open-system authentication and association, and implements WPA2-PSK with CCMP.
The first release supports legacy 20 MHz operation on **2.4 GHz channels 1–11**,
bounded by the board's regulatory limits. It does not support 5 GHz, HT/VHT,
WPA3, enterprise authentication, WEP/TKIP, roaming or protected management frames.
Fragmented/aggregated MSDUs and rare firmware Native WiFi offload indications
are discarded; their buffers are recycled. Normal data uses full RX descriptors
with CCMP replay checks.
Physical hardware validation is still required; QEMU has no QCA9377 model.

The amd64 desktop image builder includes the pinned firmware, licences and
`wifi-ctl` automatically. For an existing installation, install a kernel
containing `dev.ath10k` and extract the supplied
`qca9377-firmware-and-tools.tar.gz` into the Vinix root filesystem. Keep the
included Qualcomm licence and notices with the firmware. The firmware files
must be present at:

```
/lib/firmware/ath10k/QCA9377/hw1.0/firmware-6.bin
/lib/firmware/ath10k/QCA9377/hw1.0/board-2.bin
```

Missing firmware leaves `/dev/wlan0` available for diagnostics. After installing
it, retry without rebooting:

```
wifi-ctl boot
wifi-ctl scan
wifi-ctl join "your SSID"
ip addr
cat /proc/bootlog
```

`join` reads a passphrase with terminal echo disabled, or from standard input;
never pass a password on the command line. `join-open SSID` joins an open AP.
Scanning and joining are separate steps. `status`, `networks`, `on` and `off`
are also available. Joining returns success after authorization, then DHCP
starts. A DHCP lease may take longer to appear.

Vinix currently has one physical IP stack, named `eth0`. A Wi-Fi join selects
it for Wi-Fi; disconnecting restores a connected Realtek wired adapter. Its
address is therefore still shown under `eth0`. Settings can control the radio
and display scans through the existing `/dev/wlan0` ABI; use the CLI to join.
Resume/reset erase credentials and return to an idle radio. Scan and join again.

Startup stages in `wifi-ctl status`: 1 firmware/board parsing, 2 reset/CE rings,
3 target PCI configuration, 4 BMI download, 5 HTC services, 6 WMI initialization,
7 HTT/vdev/channel setup, 8 ready. `/proc/bootlog` is readable independently of
Settings. Preserve it together with `wifi-ctl status` if a physical boot fails.
`cat /proc/net/dev` lists an attached interface even before a DHCP lease, with
software RX/TX counters; `ifconfig -a` can therefore enumerate it. Hardware-only
counter fields and loopback counters currently read zero. For Ethernet stuck
waiting for a lease, the `rtl8169: awaiting DHCP` boot-log lines also include
hardware descriptor ownership and completion counts.

Install the kernel and `wifi-ctl` from the same build. The public Wi-Fi state
and scan-record layout follow the desktop ABI. QCA connection phases and errors
are separate diagnostic fields at offsets 176 and 200; scan errors use 172.

Build firmware/tools with a musl x86_64 sysroot containing libc and libgcc:

```
V=/path/to/v v run tools/ath10k/build.v /path/to/sysroot build-thinkpad-e470-wifi
ATH10K_REFERENCE_DIR=/path/to/downloaded-images v run tests/ath10k/run.v
```

The bundle pins firmware `WLAN.TF.2.1-00021-QCARMSWP-1` and board data from
linux-firmware commit `711d3297bac870af42088a467459a0634c1970ca`, verifies SHA-256,
and preserves `LICENSE.QualcommAtheros_ath10k` and the firmware notice. The driver
selects the exact Lenovo board entry; it never substitutes generic calibration.

Protocol/register definitions follow the primary
[Linux v6.6 ath10k sources](https://github.com/torvalds/linux/tree/v6.6/drivers/net/wireless/ath/ath10k).
Firmware distribution follows the
[ath10k firmware documentation](https://wireless.docs.kernel.org/en/latest/en/users/drivers/ath10k/firmware.html).

The host suite contains 17 tests covering real firmware/board parsing, malformed
DMA and TLV input, ring wrap and timeouts, standard crypto vectors, WPA2 replay
and key reinstallation, key-install acknowledgements and disconnects, and the
desktop's decoding of driver states and scan records. On macOS
it measures live malloc bytes with GC disabled: 1,000 command/HMAC iterations
must keep memory flat. QEMU validates kernel boot logging and the production
carrier/DHCP state machine; it does not exercise a physical Wi-Fi radio.
