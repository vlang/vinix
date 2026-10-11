// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn main() {
	root := os.real_path(os.dir(@FILE) + '/../..')
	scratch := os.getenv_opt('TMPDIR') or { os.temp_dir() }
	work := os.real_path(scratch) + '/vinix-mmap-budget-' + os.getpid().str()
	if os.exists(work) { panic('host state must be fresh') }
	os.mkdir_all(work + '/modules')!
	defer { os.rmdir_all(work) or {} }
	for name in ['kbudget', 'cgcontrol', 'vmstorage', 'klock', 'proc', 'errno', 'memory'] {
		os.mkdir_all(work + '/modules/' + name)!
	}
	for path in ['kbudget/budget.v', 'cgcontrol/control.v', 'vmstorage/storage.v'] {
		os.cp(root + '/kernel/' + path, work + '/modules/' + path)!
	}
	os.cp(root + '/tests/mmap-budget/storage_test.v', work + '/modules/vmstorage/storage_test.v')!
	os.write_file(work + '/v.mod', "Module { name: 'mmap_storage_budget_tests' }\n")!
	os.write_file(work + '/modules/memory/geometry.v', 'module memory\npub const page_size = u64(4096)\n')!
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
	mut child := os.new_process(os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!)
	child.set_args(['-nocache', '-cc', 'cc', '-enable-globals', '-gc', 'none', '-path',
		work + '/modules|@vlib', 'test', work + '/modules'])
	child.set_work_folder(work)
	child.wait()
	code := child.code
	child.close()
	if code != 0 { exit(code) }
	println('Mapping metadata storage admission: PASS')
}
