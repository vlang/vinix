This is the amd64 Lavapipe Vulkan driver in Dota's private runtime.
`mesa-build.py` builds it from Debian's `mesa 22.3.6-1+deb12u2` source with all
of Debian's patches, the same release as the runtime's `mesa-vulkan-drivers`,
and adds `null-descriptor-sets.patch`. `vulkan-stage.py` replaces only Debian's
`libvulkan_lvp.so` with the result, and refuses a different Debian Mesa release.

`inputs.json` pins the source archive, Debian's diff and each of its patches,
the Lavapipe source file before and after the local patch, and the amd64
development packages used as the build's sysroot. The driver links against the
staged runtime's own `libLLVM-15.so.1`, also pinned, using only LLVM 15's
headers. Homebrew's LLVM (or `VINIX_DOTA2_LLVM_BIN`) cross-compiles it; a
private virtual environment supplies Meson and Mako.

`null-descriptor-sets.patch` covers descriptor sets that
`VK_EXT_graphics_pipeline_library` allows: a null set in
`vkCmdBindDescriptorSets` and a set layout omitted from an independent-set
pipeline layout. Debian's compute path read `set->layout` from the null set,
which crashed Dota while it loaded a local map. Both bind paths must also keep a
null set's descriptor slots: shaders count the slots of every set layout before
their own set, so skipping a null set, as Debian's graphics path did, moves
the sets bound after it.
`tests/dota2/lavapipe-run.py` checks all of these cases on Vinix.
