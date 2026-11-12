// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

// One locally tested QEMU 9.1.2 build. These pins admit bytes, not a complete
// corresponding-source closure, publisher authority or arbitrary QEMU builds.
pub const qemu_forksafe_input = '21bbd59fb9be632214a1c0fcc73624bf568ea525dd11762513a1faa0334eca83'
pub const qemu_forksafe_manifest = '2d9e7a3ea55ddebcd935df49bc3e2c71dfbf224581efd1e18e4ba3e39fbde53d'
pub const qemu_forksafe_patch = 'd7b9bddebbabc1e10c5472ae8626e1add97e0bddbe3ac0400c46cb6f38d578f7'
pub const qemu_forksafe_scope = 'local-qualification-only: source-built QEMU 9.1.2 with splitwx-fork.patch; split RW/RX chosen when W+X is refused; private JIT across fork'

fn forksafe_file(path string, expected string) ! {
	bytes := layout_bytes(path)!
	defer { unsafe { bytes.free() } }
	hash := patch_digest(bytes)
	defer { unsafe { hash.free() } }
	if hash != expected { return error('Wine fork-safe translator input differs: ' + path) }
}

// All three inputs are required ordinary, non-linked, bounded files. The
// exact manifest pins the static AArch64 target and its declared build inputs;
// checking the actual binary separately never trusts a manifest's own digest.
pub fn admit_forksafe_translator(binary string, manifest string, patch string) ! {
	forksafe_file(binary, qemu_forksafe_input)!
	forksafe_file(manifest, qemu_forksafe_manifest)!
	forksafe_file(patch, qemu_forksafe_patch)!
}
