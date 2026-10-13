// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import encoding.binary
import encoding.hex
import os
import sourcefixture
import utilitysource

fn check(work string, root string) ! {
	if os.exists(work) { return error('expected new source-tool fixture directory') }
	os.mkdir_all(work + '/desktop/tools/tests')!
	os.mkdir(work + '/tests')!
	path := work + '/unicode.v'
	os.write_file(path, 'module x\r\n// café\rpub struct TimeSpec {}\r\nfn add() {}\n__global (\nignored')!
	assert sourcefixture.clock(sourcefixture.read(path)!)! == 'module time\npub struct TimeSpec {}\nfn add() {}\n'
	os.write_file_array(path, [u8(255)])!
	mut failed := false
	sourcefixture.read(path) or { failed = true }
	assert failed
	failed = false
	sourcefixture.clock('missing marker') or { failed = true }
	assert failed
	assert sourcefixture.ext2_mmap('before\nfn (mut this EXT2Resource) mmap(a int) ? {\n}\nfn (mut this EXT2Resource) read(a int) {}\n')! ==
		'module ext2\nimport errno\nimport memory\nimport memory.mmap as mmap_mod\nimport stat\nfn (mut this EXT2Resource) mmap(a int) ? {\n}\n'
	fixture, tests := sourcefixture.private_fixture('@[has_globals]\nmodule mmap\nimport memory\nconst page_size = 4096\nfn helper() {}\nfn test_one() {}\n')!
	assert fixture == '@[has_globals]\nmodule mmap\nimport memory\nconst page_size = 4096\nfn helper() {}\n'
	assert tests == '@[has_globals]\nmodule mmap\nimport memory\nfn test_one() {}\n'
	mut source := ''
	for name in ['page_table_flags', 'range_page_has_file_data', 'install_range_page',
		'resolve_cow_fault', 'unshare_private_page_unlocked', 'range_priority'] {
		source += 'pub fn ' + name + '() {\n    // ' + name + '\n}\n'
	}
	paging_text := 'struct PagedPage { value int }\nfn page_extra() {}\nfn reclaim_uncovered_paged_locked() {}\n__global (anything int)\npub fn reclaim_anonymous() {\n}\npub fn max_u64() u64 { return 17 }\n'
	for file_pages in [false, true] {
		for paging in [false, true] {
			result := sourcefixture.private_install(source, paging_text, file_pages, paging)!
			assert result.contains('resolve_shared_file_write') == !file_pages
			assert result.contains('pageout_file_span') == !file_pages
			assert result.contains('import sched\nimport kbudget\n') == paging
			assert result.contains('pub fn reclaim_anonymous()') == paging
			assert result.contains('pub fn max_u64() u64 { return 17 }\n\n') == paging
			assert result.contains('pub fn range_priority()') == paging
			for name in ['page_table_flags', 'range_page_has_file_data', 'install_range_page',
				'resolve_cow_fault', 'unshare_private_page_unlocked'] { assert result.count('pub fn ' + name + '(') == 1 }
		}
	}
	for name in ['activity_kill', 'activity_controls'] {
		os.write_file(work + '/desktop/tools/tests/' + name + '_test.v', 'module main\nimport z\nfn test_' + name + '() {}\n')!
	}
	for name in ['activity_b_test.v', 'activity_a_test.v', 'activity_memory_test.v', 'activity_lifetime_test.v', 'unrelated_test.v'] {
		os.write_file(work + '/tests/' + name, 'module main\r\nimport a\r\n// ' + name + '\u2028fn fixture_' + name.all_before('.') + '() {}\r\n')!
	}
	paths := utilitysource.activity_paths(work)!
	assert paths.map(os.file_name(it)) == ['activity_kill_test.v', 'activity_controls_test.v', 'activity_a_test.v', 'activity_b_test.v']
	utilitysource.merge_paths(paths, work + '/merged.v')!
	assert os.read_file(work + '/merged.v')! == 'module main\nimport a\nimport z\n\nfn test_activity_kill() {}\n\nfn test_activity_controls() {}\n\n// activity_a_test.v\nfn fixture_activity_a_test() {}\n\n// activity_b_test.v\nfn fixture_activity_b_test() {}'
	os.write_file_array(work + '/raw', [u8(0), 255, 13, 10])!
	os.symlink('raw', work + '/frozen')!
	os.symlink('missing', work + '/dangling')!
	os.symlink('tests', work + '/directory-link')!
	utilitysource.materialize(work)!
	os.write_file(work + '/raw', 'changed')!
	assert os.read_bytes(work + '/frozen')! == [u8(0), 255, 13, 10]
	assert !os.is_link(work + '/frozen') && os.is_link(work + '/dangling') && os.is_link(work + '/directory-link')
	bytes := sourcefixture.m1_kernel()
	assert bytes.len == 96 && bytes[..7] == [u8(127), `E`, `L`, `F`, 2, 1, 1]
	assert bytes[7..16].all(it == 0) && bytes[24..64].all(it == 0)
	assert binary.little_endian_u16_at(bytes, 16) == 2 && binary.little_endian_u16_at(bytes, 18) == 183
	assert binary.little_endian_u32_at(bytes, 20) == 1
	assert bytes[64..] == hex.decode('888b4cdf30ddb1c77bf094a183e8820a7e851b9a817ba695e0736a3b721bb6a0')!
	// Actual source selection retains original function bodies, ordering and bytes.
	clock_source := sourcefixture.read(root + '/kernel/time/time.v')!
	clock_selected := sourcefixture.clock(clock_source)!
	assert clock_selected.contains('pub struct TimeSpec') && !clock_selected.contains('__global (')
	mmap_source := sourcefixture.read(root + '/kernel/memory/mmap/mmap.v')!
	paging_source := sourcefixture.read(root + '/kernel/memory/mmap/paging.v')!
	for file_pages in [false, true] {
		for paging in [false, true] {
			selected := sourcefixture.private_install(mmap_source, paging_source, file_pages, paging)!
			os.write_file(work + '/install-' + file_pages.str() + '-' + paging.str() + '.v', selected)!
			assert selected.contains('fn install_range_page(') && selected.contains('fn resolve_cow_fault(')
		}
	}
	for profile in ['activity', 'parity'] {
		output := work + '/actual-' + profile + '.v'
		if profile == 'activity' { utilitysource.merge_paths(utilitysource.activity_paths(root)!, output)! }
		else { utilitysource.merge(root, output, utilitysource.parity_tests)! }
		assert os.read_file(output)!.starts_with('module main\n')
		assert os.file_size(output) > 10000
		println(profile + ' source sha256 ' + sha256.hexhash(os.read_file(output)!))
	}
	println('PASS source extraction variants, strict text, exact merged fixture, link freezing and M1 ELF')
}

fn main() {
	if os.args.len != 3 { exit(2) }
	check(os.args[1], os.args[2]) or { eprintln(err); exit(1) }
}
