This is the x86-64 Mesa Venus driver in Dota's private runtime. It renders on
the host GPU when Vinix runs on KekVM's GPU-enabled QEMU (`--venus`); the
native ARM64 driver from `build-venus-aarch64.sh` cannot load into the
translated game. `venus-build.py` builds Mesa 25.0.5, the native driver's
release, with its `vinix.patch` (render-node discovery without sysfs and
X11 presentation through MIT-SHM). It uses the Debian sysroot that
`mesa-build.py` prepares for Lavapipe. `vulkan-stage.py` stages the result as
`virtio_icd.x86_64.json`, and `run-dota2` selects it when the native
`venus-available` probe finds a Venus GPU.

`x86-relax.patch` replaces the Vinix patch's AArch64 `yield` spin with
`pause`.

`promoted-dynamic-state.patch` makes Dota's Vulkan device creation succeed on
KekVM's KosmicKrisp renderer. Dota creates its instance below Vulkan 1.3, so
Venus capped the renderer at that version. It also chains
`VkPhysicalDeviceExtendedDynamicStateFeaturesEXT`, whose feature KosmicKrisp
reports as unsupported, so `vkCreateDevice` failed with
`VK_ERROR_FEATURE_NOT_PRESENT`. The patch creates the renderer instance at
Vulkan 1.3 when the renderer supports it, where the first two dynamic-state
extensions are core. It reports their features as supported and keeps their
feature structs from the renderer.

The translator's `drm-passthrough.patch` (`../qemu`) carries the driver's
virtio-gpu ioctls.
