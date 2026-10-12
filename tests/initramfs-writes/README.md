# Complete archive writes

```sh
v run tests/initramfs-writes/run.v
```

Runs the production initramfs write helper against a resource that accepts at
most 1 MiB per call, as VJFS does, and one with irregular short writes. A binary
payload larger than 3 MiB must be reproduced byte for byte with advancing file
offsets. Backend errors, zero progress, negative or oversized counts must fail
the entry; an empty file must not issue a write.

The launcher's temporary module supplies only the resource callback needed by
the helper. Release ISO boot checks additionally verify the real resource
interface and VJFS installation by starting the desktop from an installed disk.
