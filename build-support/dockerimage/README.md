# Native offline Docker image fixture

`build-support/make-docker-image --busybox PATH --output PATH [--tag TAG]`
writes the deterministic busybox filesystem used by the Docker image builder.
The compatibility tag remains accepted and unused. The command compiles and
invokes V directly; archive headers, data and padding are written in V.

The filesystem retains ten directories (including mode 1777 `/tmp`), the
supplied busybox binary, 50 applet symlinks, passwd/group/os-release contents,
root ownership, fixed epoch 1735689600 and USTAR's 10 KiB record padding.

```sh
v -cc cc test build-support/tarcore
v -cc cc test build-support/dockerimage
v -cc cc -o /tmp/make-docker-image build-support/make-docker-image.v
VINIX_DOCKERIMAGE_TOOL=/tmp/make-docker-image v -cc cc test build-support/dockerimage
```

Native checks inspect every header and payload independently of the archive
reader, including checksums, permissions, member order and end padding, for
six binary sizes around block boundaries. System `tar` independently lists
all 64 members and extracts the supplied bytes. Repeat builds are identical.
Optional command checks exercise separately built host executables, CLI
options and failure status. No Docker daemon or guest boot is required.
