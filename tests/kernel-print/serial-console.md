Run the focused host fixture (no kernel build or QEMU):

```
sh build-support/run-v-tool.sh tests/native-policy-tools/serial-console-main.v
```

It stages the production COM1 console/resume, PL011 polling, ACPI discovery,
and amd64 `kwrite` bodies with fake I/O boundaries, in debug and production
modes. ASan/UBSan, a ten-second process deadline, and an undefined allocator
symbol check cover CRLF, absent/floating/stuck UARTs, timeout suppression,
pre/post `_vinit` state, delayed readiness, RX IRQ setup/resume, framebuffer
delivery after serial failure, and SPCR/DSDT/QEMU qualification. Source guards
check early entry-point ordering and the UART mapping before the TTBR switch.

Hardware MMIO validity under Limine's page tables and actual baud timing still
require the parent's two-architecture builds and boot checks. DT-only UART
discovery is deferred: the current DT parser allocates nodes and arrays.
