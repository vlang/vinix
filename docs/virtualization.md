# Virtualization and KVM support

Vinix supports running as a guest under Linux KVM. It also has an experimental
native Intel VT-x hypervisor. These use different userspace APIs:

| Use case | Current support |
| --- | --- |
| Run amd64 Vinix under QEMU/KVM on an x86_64 Linux host | Supported by the desktop launcher and ISO boot checks. |
| Run arm64 Vinix under QEMU/KVM on an AArch64 Linux host | Supported by the ISO boot checks. |
| Create small hardware-accelerated VMs inside amd64 Vinix | Intel VT-x through `/dev/hypervisor`; one vCPU and at most 2 MiB per VM. |
| Use Linux's `/dev/kvm` API inside Vinix | Not implemented on either architecture. |
| Run another arm64 Vinix instance through QEMU inside Vinix | TCG software emulation through `vinix-qemu`. |

## Run Vinix as a KVM guest

KVM runs on the Linux host, which needs a working KVM kernel backend,
hardware virtualization enabled in firmware, a QEMU build with KVM support,
and read/write access to the host's `/dev/kvm`. On x86_64 the host can use
Intel VT-x or AMD SVM; the Intel-only limit of Vinix's own hypervisor does not
restrict running Vinix as a guest. Use an image matching the host architecture.
QEMU documents its supported host accelerators in its
[system emulator introduction](https://www.qemu.org/docs/master/system/introduction.html).

Check the host before launching an amd64 guest:

```sh
qemu-system-x86_64 -accel help
ls -l /dev/kvm
test -r /dev/kvm && test -w /dev/kvm
```

The accelerator list should include `kvm`, and the access check should exit
successfully. Listing an accelerator alone does not prove it can initialize.
If `/dev/kvm` is missing, check the Linux host's KVM setup and firmware; if
access is denied, use the host distribution's KVM device permissions.

With the released `vinix-amd64.iso`, create a new disk once and boot:

```sh
qemu-img create -f qcow2 vinix-amd64.qcow2 16G
qemu-system-x86_64 -machine q35 -accel kvm -cpu host -m 4096 -smp 2 \
    -cdrom vinix-amd64.iso \
    -drive file=vinix-amd64.qcow2,format=qcow2 \
    -nic user,model=e1000
```

Keep the disk for later launches. The first boot installs onto the empty disk;
subsequent boots preserve users, files, and installed apps. Keep the ISO
attached as described in the [image instructions](../README.md#download-an-image).

For an amd64 desktop built from this checkout:

```sh
./scripts/run-desktop-amd64.sh
```

The launcher selects KVM with `-cpu host` when `/dev/kvm` is readable and
writable. Otherwise it selects HVF on an Intel Mac or TCG software emulation.
An explicit `VINIX_QEMU_ACCEL` overrides this selection; specify the CPU too:

```sh
VINIX_QEMU_ACCEL=kvm ./scripts/run-desktop-amd64.sh --no-build -cpu host
VINIX_QEMU_ACCEL=tcg ./scripts/run-desktop-amd64.sh --no-build -cpu max
```

The selection checks device permissions; it does not retry with TCG if KVM
initialization fails. Use the explicit TCG command in that case. `--no-build`
requires an existing `vinix-desktop-amd64.iso`. The desktop launcher also needs
x86_64 UEFI firmware; set `VINIX_OVMF_CODE` if it is not found automatically.

For release-image boot checks on a matching Linux host, run either:

```sh
./scripts/test-iso.sh --no-virtualbox vinix-amd64.iso
./scripts/test-iso.sh --no-virtualbox vinix-arm64.iso
```

The ISO runner selects KVM when the host device is writable (and, for arm64,
the host is AArch64). The AArch64 development runner
`scripts/run-desktop-aarch64.sh` uses HVF by default, or TCG with `USE_TCG=1`;
it does not automatically select Linux KVM.

## Host VMs inside Vinix

The native backend requires Intel VMX, EPT, and unrestricted-guest support
available to the amd64 Vinix kernel. When Vinix itself runs in a VM, the outer
hypervisor must expose nested VT-x for `/dev/hypervisor` to become available.
Running Vinix as an ordinary KVM guest does not require nested VT-x.

At boot, Vinix checks VMX and runs a real-mode guest self-test before publishing
the root-only `/dev/hypervisor` device. A successful boot logs
`hypervisor: /dev/hypervisor ready`. If VMX is unavailable or the self-test
fails, Vinix continues booting without the device.

This backend targets small firmware and device-model experiments. AMD SVM,
an ARM hardware virtualization backend, multiple vCPUs, interrupt injection,
and a complete device model are not implemented. See the
[native hypervisor API](hypervisor.md) for its ioctl sequence and C example,
and the [hypervisor checks](../tests/hypervisor/README.md) for validation and
the distinction between host model checks and actual VM-entry coverage.

Linux KVM applications expect `/dev/kvm` and `KVM_*` ioctls, as specified in the
[Linux KVM API](https://docs.kernel.org/virt/kvm/api.html). Vinix's
`VINIX_HV_*` ioctls are a separate interface, so QEMU `-accel kvm` cannot use
the native backend. For QEMU running inside arm64 Vinix, follow the
[nested QEMU instructions](qemu-nested.md), which use `-accel tcg`.
