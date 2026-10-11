// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn main() {
	root := os.real_path(os.dir(@FILE) + '/../..')
	scratch := os.getenv_opt('TMPDIR') or { os.temp_dir() }
	work := os.real_path(scratch) + '/vinix-resource-host-' + os.getpid().str()
	if os.exists(work) { panic('host state must be fresh') }
	os.mkdir_all(work + '/modules')!
	defer { os.rmdir_all(work) or {} }
	for name in ['cgcontrol', 'kbudget', 'klock', 'memory', 'errno', 'proc', 'vmstorage'] {
		os.mkdir_all(work + '/modules/' + name)!
	}
	for path in ['cgcontrol/control.v', 'kbudget/budget.v', 'memory/table_budget.v'] {
		os.cp(root + '/kernel/' + path, work + '/modules/' + path)!
	}
	if os.is_file(root + '/kernel/vmstorage/storage.v') {
		os.cp(root + '/kernel/vmstorage/storage.v', work + '/modules/vmstorage/storage.v')!
	}
	for name, module_name in {'budget_test.v': 'kbudget', 'table_test.v': 'memory'} {
		os.cp(root + '/tests/kernel-resources/' + name, work + '/modules/' + module_name + '/' + name)!
	}
	os.write_file(work + '/v.mod', "Module { name: 'kernel_resource_budget_tests' }\n")!
	os.write_file(work + '/modules/klock/lock.v', 'module klock
import sync
pub struct Lock { mut: mutex sync.Mutex }
pub fn (mut l Lock) acquire() { l.mutex.lock() }
pub fn (mut l Lock) release() { l.mutex.unlock() }
')!
	os.write_file(work + '/modules/errno/errno.v', 'module errno
pub const enomem = 12
pub const einval = 22
pub fn set(_code u64) {}
')!
	os.write_file(work + '/modules/proc/budget.v', 'module proc
import kbudget
pub fn grow_kernel(mut charge kbudget.Charge, bytes u64) bool {
 return kbudget.grow(mut charge, bytes)
}
')!
	os.write_file(work + '/modules/memory/fixture.v', '@[has_globals]
module memory
import kbudget
pub const page_size = u64(4096)
pub const higher_half = u64(0)
pub const pte_flags_mask = ~u64(4095)
__global (la57 bool live_pages int)
pub struct Pagemap { pub mut: top_level &u64 = unsafe { nil } kernel_owner kbudget.Owner kernel_charge kbudget.Charge mmap_ranges []voidptr }
pub fn pmm_alloc_fallible(_count u64) voidptr { live_pages++; return unsafe { calloc(usize(page_size), 1) } }
pub fn pmm_free(ptr voidptr, _count u64) { live_pages--; unsafe { C.free(ptr) } }
pub fn user_room(_count u64) bool { return true }
')!
	mut child := os.new_process(os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!)
	child.set_args(['-nocache', '-cc', 'cc', '-enable-globals', '-gc', 'none', '-path',
		work + '/modules|@vlib', 'test', work + '/modules'])
	child.set_work_folder(work)
	child.wait()
	code := child.code
	child.close()
	if code != 0 { exit(code) }
	println('Kernel resource host tests: PASS')
}
