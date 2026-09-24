# M1 AGX reference audit

Hardware boots are an acceptance test, not the first place to discover a
firmware contract. Before deploying a G13 image, compare the driver with the
reverse-engineered sources already on the development machine:

```sh
make -C tools/agx-re check-g13-reference
```

The default m1n1 checkout is `~/code/3rd/m1n1`; override it with
`VINIX_M1N1`. If an Asahi Linux checkout is available, include its independent
MMU and channel implementation too:

```sh
make -C tools/agx-re check-g13-reference \
    ASAHI_LINUX=/path/to/asahi-linux
```

The gate currently verifies the contracts that have already caused, or would
cause, hardware-only failures:

- the generated 12.3 and 13.5 InitData layouts;
- normal and firmware-control channel geometry;
- the fixed G13 firmware-control invalidate opcode and handoff slot;
- writable/shared InitData RegionA memory;
- the timestamp aperture address and its HwDataB publication;
- cached mapping teardown order: reprotect uncached, invalidate while mapped,
  remember that the cache flush completed, unmap, then invalidate the
  translation (including safe retry after an unpublished request);
- a full system barrier between writing a TX ring entry and publishing its
  write pointer.

The layout generator and reference checker resolve repository files relative
to their scripts, so running them from the repository root, an editor, or the
`tools/agx-re` makefile checks the same file. A new m1n1 or Asahi revision that
changes one of these facts should fail here with the specific contract name.
Update the Vinix implementation and the gate together only after understanding
the reference change.

The Apple artifacts extracted from the local restore image remain under
`tools/agx-re/build/kext/g13g`, and `make -C tools/agx-re recover-t8103-adt`
mechanically recovers the native t8103 DeviceTree contract. Those inputs cover
platform data; m1n1 and Asahi remain the executable references for the G13
queue, UAT, and firmware handoff protocols.
