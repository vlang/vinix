// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn exact_line(source string, line string, context string) ! {
	require(source.split_into_lines().filter(it.trim_space() == line).len == 1,
		'${context}: missing or duplicate ${line}')!
}

fn check_gpu_permission_contract(local string, file string, reference string, reference_file string) ! {
	for line in ['const UAT_AP_SHIFT: u32 = 6;', 'const UAT_HIGH_BITS_SHIFT: u32 = 52;',
		'const UAT_MEMATTR_SHIFT: u32 = 2;', 'const UAT_AF: u64 = 1 << 10;',
		'const MEMATTR_UNCACHED: u8 = 2;', 'const AP_GPU: u8 = 2;',
		'const HIGH_BITS_PXN: u16 = 1 << 1;', 'const HIGH_BITS_UXN: u16 = 1 << 2;',
		'const HIGH_BITS_GPU_ACCESS: u16 = 1 << 3;',
		'const PROT_GPU_RO: Prot = Prot::from_bits(AP_GPU, 0, 0);',
		'const PROT_GPU_WO: Prot = Prot::from_bits(AP_GPU, 0, 1);',
		'const PROT_GPU_RW: Prot = Prot::from_bits(AP_GPU, 1, 0);'] {
		exact_line(reference, line, 'Asahi GPU permission encoding')!
	}
	require(reference.contains('high_bits: HIGH_BITS_GPU_ACCESS | (pxn * HIGH_BITS_PXN) | (uxn * HIGH_BITS_UXN)'),
		'Asahi GPU permission bit composition changed')!
	require_order(reference, ['const fn as_pte(&self) -> u64 {',
		'(self.ap as u64) << UAT_AP_SHIFT', '| (self.high_bits as u64) << UAT_HIGH_BITS_SHIFT',
		'| (self.memattr as u64) << UAT_MEMATTR_SHIFT', '| UAT_AF'], 'Asahi GPU leaf composition')!
	for mode in ['RO', 'WO', 'RW'] {
		exact_line(reference, 'pub(crate) const PROT_GPU_SHARED_${mode}: Prot = PROT_GPU_${mode}.memattr(MEMATTR_UNCACHED);',
			'Asahi coherent GPU permission')!
	}
	for pair in [['ro', ''], ['wo', 'uat_pte_pxn | '], ['rw', 'uat_pte_uxn | ']] {
		exact_line(local, 'pub const gpu_prot_gpu_shared_${pair[0]} = uat_pte_os | ${pair[1]}uat_pte_ap_gpu_only | uat_memattr_normal_uncached | uat_pte_af',
			'Vinix coherent GPU permission')!
	}
	bind := section(file, 'pub fn (mut f GpuFile) ioctl_gem_bind(',
		'pub fn (f &GpuFile) ioctl_get_time(', 'Vinix GPU bind permissions')!
	selection := section(bind, 'protection :=', 'if !f.cleanup_closed_mappings_locked', 'Vinix GPU permission selection')!
	require_order(selection.fields().join(' '), ['if request.flags & ioctl.asahi_bind_read != 0 {',
		'if request.flags & ioctl.asahi_bind_write != 0 {', 'pgtable.gpu_prot_gpu_shared_rw',
		'} else { pgtable.gpu_prot_gpu_shared_ro }', '} else {', 'pgtable.gpu_prot_gpu_shared_wo'],
		'Vinix distinct RO/WO/RW bind permissions')!
	require(selection.count('pgtable.gpu_prot_gpu_shared_') == 3,
		'Vinix GPU permission selection must have exactly three modes')!
	ref_bind := section(reference_file, '    pub(crate) fn do_gem_bind(',
		'    pub(crate) fn do_gem_unbind(', 'Asahi GPU bind permissions')!
	require_order(ref_bind, ['let prot = if data.flags & uapi::drm_asahi_bind_flags_DRM_ASAHI_BIND_READ != 0',
		'if data.flags & uapi::drm_asahi_bind_flags_DRM_ASAHI_BIND_WRITE != 0',
		'mmu::PROT_GPU_SHARED_RW', 'mmu::PROT_GPU_SHARED_RO',
		'else if data.flags & uapi::drm_asahi_bind_flags_DRM_ASAHI_BIND_WRITE != 0',
		'mmu::PROT_GPU_SHARED_WO'], 'Asahi distinct RO/WO/RW bind permissions')!
}
