module g13contract

import g13layout
import os

fn test_distinct_gpu_permission_selectors_and_reference_drift() {
	local := os.read_file(g13layout.repo_root() + '/kernel/gpu/agx/pgtable/pgtable.v')!
	file := os.read_file(g13layout.repo_root() + '/kernel/gpu/agx/file/file.v')!
	// Minimal source oracle for the selected Asahi facts, independent of a
	// local reference checkout. The CLI also checks the real packaged files.
	reference := 'const UAT_AP_SHIFT: u32 = 6;\n' +
		'const UAT_HIGH_BITS_SHIFT: u32 = 52;\nconst UAT_MEMATTR_SHIFT: u32 = 2;\n' +
		'const UAT_AF: u64 = 1 << 10;\nconst MEMATTR_UNCACHED: u8 = 2;\n' +
		'const AP_GPU: u8 = 2;\nconst HIGH_BITS_PXN: u16 = 1 << 1;\n' +
		'const HIGH_BITS_UXN: u16 = 1 << 2;\nconst HIGH_BITS_GPU_ACCESS: u16 = 1 << 3;\n' +
		'const PROT_GPU_RO: Prot = Prot::from_bits(AP_GPU, 0, 0);\n' +
		'const PROT_GPU_WO: Prot = Prot::from_bits(AP_GPU, 0, 1);\n' +
		'const PROT_GPU_RW: Prot = Prot::from_bits(AP_GPU, 1, 0);\n' +
		'high_bits: HIGH_BITS_GPU_ACCESS | (pxn * HIGH_BITS_PXN) | (uxn * HIGH_BITS_UXN)\n' +
		'pub(crate) const PROT_GPU_SHARED_RO: Prot = PROT_GPU_RO.memattr(MEMATTR_UNCACHED);\n' +
		'pub(crate) const PROT_GPU_SHARED_WO: Prot = PROT_GPU_WO.memattr(MEMATTR_UNCACHED);\n' +
		'pub(crate) const PROT_GPU_SHARED_RW: Prot = PROT_GPU_RW.memattr(MEMATTR_UNCACHED);\n' +
		'const fn as_pte(&self) -> u64 { (self.ap as u64) << UAT_AP_SHIFT\n' +
		'| (self.high_bits as u64) << UAT_HIGH_BITS_SHIFT\n' +
		'| (self.memattr as u64) << UAT_MEMATTR_SHIFT | UAT_AF }\n'
	reference_file := '    pub(crate) fn do_gem_bind(\n' +
		'let prot = if data.flags & uapi::drm_asahi_bind_flags_DRM_ASAHI_BIND_READ != 0 {\n' +
		'if data.flags & uapi::drm_asahi_bind_flags_DRM_ASAHI_BIND_WRITE != 0 {\n' +
		'mmu::PROT_GPU_SHARED_RW } else { mmu::PROT_GPU_SHARED_RO }\n' +
		'} else if data.flags & uapi::drm_asahi_bind_flags_DRM_ASAHI_BIND_WRITE != 0 {\n' +
		'mmu::PROT_GPU_SHARED_WO }\n    pub(crate) fn do_gem_unbind('
	check_gpu_permission_contract(local, file, reference, reference_file)!
	for broken in [file.replace('pgtable.gpu_prot_gpu_shared_wo', 'pgtable.gpu_prot_gpu_shared_rw'),
		file.replace('if request.flags & ioctl.asahi_bind_read != 0', 'if request.flags & ioctl.asahi_bind_write != 0'),
		file.replace('pgtable.gpu_prot_gpu_shared_ro', 'pgtable.gpu_prot_gpu_shared_wo')] {
		if _ := check_gpu_permission_contract(local, broken, reference, reference_file) { assert false }
	}
	for broken in [local.replace('gpu_prot_gpu_shared_wo = uat_pte_os | uat_pte_pxn',
		'gpu_prot_gpu_shared_wo = uat_pte_os | uat_pte_uxn'),
		local.replace('gpu_prot_gpu_shared_ro = uat_pte_os |', 'gpu_prot_gpu_shared_ro = uat_pte_os | uat_pte_pxn |'),
		local + '\n' + local] {
		if _ := check_gpu_permission_contract(broken, file, reference, reference_file) { assert false }
	}
	for broken in [reference.replace('AP_GPU, 0, 1', 'AP_GPU, 1, 0'),
		reference.replace('UAT_HIGH_BITS_SHIFT: u32 = 52', 'UAT_HIGH_BITS_SHIFT: u32 = 53'),
		reference.replace('AP_GPU: u8 = 2', 'AP_GPU: u8 = 0'),
		reference.replace('(pxn * HIGH_BITS_PXN)', '(uxn * HIGH_BITS_PXN)'),
		reference.replace('(self.ap as u64) << UAT_AP_SHIFT', '(self.ap as u64) << 7'),
		reference + '\n' + reference] {
		if _ := check_gpu_permission_contract(local, file, broken, reference_file) { assert false }
	}
	if _ := check_gpu_permission_contract(local, file, reference,
		reference_file.replace('mmu::PROT_GPU_SHARED_WO', 'mmu::PROT_GPU_SHARED_RW')) { assert false }
}
