# PowerPC desktop display stability

The console flashes were false display-disconnect events. The compositor
checks output geometry and `/dev/fb0` existence every two seconds. PPC32
`open` and `statx` recognized that device, but `access(F_OK)` returned ENOENT.
The compositor consequently unmapped and reopened its framebuffer on every
check. Unmapping correctly restored the kernel console; display recovery
also cancelled held drags and rebuilt click targets. The console's larger
font made this look like a resolution change, although scanout stayed 800x600.

Commit `f8935e63c` shares device lookup and presence checks between `open`,
`access` and `statx`, including consistent path/fd inode identity. Missing
framebuffers remain absent. Console restoration and diagnostic output remain
enabled. No desktop executable change is needed.

The unchanged desktop and the same disposable saved-account fixture were
booted before and after the fix. The baseline mapped its framebuffer 22
times and the new checker rejected it. The fixed kernel mapped it once.
All 56 subsequent captures retained the desktop. A held USB mouse drag crossed
multiple discovery intervals and moved the System window by the expected
(-220,+78) pixels; USB clicks opened and closed the Start menu. The resulting
drag and open-menu screenshots were also inspected visually.

`tests/powerpc/persistence.v desktop` now runs this check on its second boot,
after creating and validating a disposable account on its first boot. This
checks continued interaction as well as initial presentation. Run it using
the traced native desktop executable:

```sh
VINIX_PPC_INIT=/path/to/traced/vinix-desktop v run tests/powerpc/persistence.v desktop /external/fresh-display-test
```

The native musl fixture also passes with and without a firmware framebuffer,
checking `access`, path/fd `stat`, character-device type, permissions and
missing fb1/fb7. The 128 MiB shell regression passes nested USB hubs,
keyboard/mouse, framebuffer ownership and console restoration, GEM Ethernet
DHCP/ARP/ICMP and independently checked USB audio output.

Complete local evidence is retained under
`/Users/pancake/.local/share/vinix-powerpc/audits/display-20261108`:

- `vinix-ppc-display-baseline`: rejected capture bundle and original boot image.
- `vinix-ppc-display-fixed` and `vinix-ppc-display-fixed-image`: passing capture
  bundle and the corresponding image, generated code and exact sources.
- `vinix-ppc-display-account-qualified`: fresh two-boot account/interaction
  qualification, disk snapshots and filesystem checks.
- `vinix-ppc-display-runtime-{graphics,headless}` and `vinix-ppc-display-shell`:
  native device, libc and driver regression bundles.

The initial fixed builds used source base `5bbad6689` plus the exact source
copies in each bundle; the fresh account build used `f8935e63c`. The baseline
was built on `1dc267a58` with source snapshots containing the pre-fix device
implementation from `5bbad6689`. Capture manifests retain their original
temporary paths; the external inventory binds every file in the retained
copies, including the original baseline rejection and checker source.

Inventory receipt: `display-20261108.inventory.json` beside the evidence
directory. SHA-256:
`9ef42d295e86c580b4d416ddb658a854eaadd30d5eb3546587608c2dcbdd5857`.
The recorded inventory was checked against the retained copy successfully.

These checks cover a fixed 800x600 QEMU display and sustained USB interaction.
They do not qualify physical iMac graphics hardware, real display hotplug,
or the separate application processes missing at that revision. See
[app validation](powerpc-app-validation.md) for the later process work.
