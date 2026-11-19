// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_single_page_guards_reject_wrong_backing_stride_ownership_and_software_acceptance() {
	repo := g13layout.repo_root()
	header := read(repo + '/kernel/drm/ioctl/ioctl.v')!
	pure := read(repo + '/kernel/gpu/agx/vm/vm.v')!
	file := read(repo + '/kernel/gpu/agx/file/file.v')!
	page_table := read(repo + '/kernel/gpu/agx/pgtable/pgtable.v')!
	fake := read(repo + '/kernel/gpu/agx/fake/driver.v')!
	check_single_page_local(header, pure, file, page_table, fake)!
	if _ := check_single_page_local(header.replace('asahi_bind_single_page = u32(1) << 3', 'asahi_bind_single_page = u32(1) << 2'), pure, file, page_table, fake) { assert false }
	if _ := check_single_page_local(header, pure.replace('{ page_size } else { request.range }', '{ request.range } else { request.range }'), file, page_table, fake) { assert false }
	if _ := check_single_page_local(header, pure, file.replace('pt.map_repeated_page(', 'pt.map('), page_table, fake) { assert false }
	if _ := check_single_page_local(header, pure, file.replace('if done != 0 { pt.unmap(addr, done) }', ''), page_table, fake) {
		assert false, 'a failed run must unmap the runs already installed'
	}
	for token in ['pt.map_page_locked(iova + i * uat_pgsz, phys, prot)', 'pt.unmap_page_locked(iova + j * uat_pgsz)', 'pt.invalidate_range_locked(iova, size)'] {
		if _ := check_single_page_local(header, pure, file, page_table.replace(token, ''), fake) { assert false, token }
	}
	if _ := check_single_page_local(header, pure, file, page_table, fake.replace('return -95', 'return 0')) { assert false }
}

fn test_single_page_reference_requires_repeat_flag_and_one_uat_page() {
	header := 'DRM_ASAHI_BIND_SINGLE_PAGE = (1L << 3),'
	mmu := 'pub(crate) fn bind_object< single_page: bool; let (flags, gem_range) = if single_page { GpuVaFlag::REPEAT; UAT_PGSZ as u32 };\n' +
		'let req = OpMapRequest { range: size, gem_offset: offset, gem_range, flags }; .sm_map(req);\n/// Spend the binding generation'
	check_single_page_reference(header, mmu)!
	for token in ['GpuVaFlag::REPEAT', 'UAT_PGSZ as u32', 'range: size'] {
		if _ := check_single_page_reference(header, mmu.replace(token, '')) { assert false, token }
	}
}
