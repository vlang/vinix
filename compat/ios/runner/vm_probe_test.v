// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn C.dup(i32) i32
fn C.dup2(i32, i32) i32

fn test_vm_probe_results_and_errno() {
	previous := module_runtime
	mut runtime := ModuleRuntime{}
	defer { module_runtime = previous }
	objc_start()
	defer { objc_stop() }
	system_data_start()!
	defer { system_data_stop() }
	path := os.temp_dir() + '/vinix-vm-probe-' + C.getpid().str() + '.log'
	defer { os.rm(path) or {} }
	fd := C.open(path.str, C.O_CREAT | C.O_TRUNC | C.O_RDWR, 384)
	assert fd >= 0
	saved := C.dup(2)
	assert saved >= 0 && C.dup2(fd, 2) == 2
	defer { C.dup2(saved, 2); C.close(saved); C.close(fd) }
	for initialized in [false, true] {
		module_runtime = if initialized { unsafe { &runtime } } else { unsafe { nil } }
		darwin_set_errno(37)
		vm_probe_record(c'disabled', 0, 0, [10]u64{}, -1)
		assert unsafe { *C.ios_errno_address() } == 37
	}
	assert C.lseek(fd, 0, 1) == 0
	runtime.probe_no_ads = true
	page := mach_page_size()
	flags := i32(C.MAP_PRIVATE | C.MAP_ANONYMOUS)
	mapped := darwin_mmap(unsafe { nil }, usize(page), 0, flags, -1, 0)
	assert mapped != unsafe { voidptr(-1) }
	assert unsafe { *C.ios_errno_address() } == 37
	assert darwin_mprotect(mapped, usize(page), 3) == 0
	unsafe { *(&u8(mapped)) = 123 }
	assert darwin_munmap(mapped, usize(page)) == 0
	assert darwin_mmap(unsafe { nil }, 0, 0, flags, -1, 0) == unsafe { voidptr(-1) }
	assert unsafe { *C.ios_errno_address() } == C.EINVAL
	darwin_set_errno(37)
	mut address := u64(0)
	assert darwin_vm_allocate(system_data.task_self, unsafe { &address }, page, 1) == 0
	assert unsafe { *C.ios_errno_address() } == 37
	assert darwin_vm_deallocate(system_data.task_self, address, page) == 0
	assert darwin_vm_allocate(system_data.task_self, unsafe { nil }, page, 1) == 4
	assert darwin_vm_map(system_data.task_self, unsafe { &address }, page, 0, 1, 0, 0, 0, 3, 3, 1) == 0
	assert darwin_vm_deallocate(system_data.task_self, address, page) == 0
	assert darwin_vm_map(system_data.task_self, unsafe { &address }, page, 1, 1, 0, 0, 0, 3, 3, 1) == 46
	assert unsafe { *C.ios_errno_address() } == 37
	// A failed diagnostic write must not replace the caller's errno either.
	assert C.close(2) == 0
	vm_probe_record(c'closed', 0, 0, [10]u64{}, -1)
	assert unsafe { *C.ios_errno_address() } == 37
	assert C.dup2(saved, 2) == 2
	text := os.read_file(path)!
	lines := text.trim_space().split_into_lines()
	assert lines.len == 10
	for line in lines { assert line.starts_with('IOS-PROBE-VM: op=') }
	assert !text.contains('disabled') && !text.contains('closed')
	assert lines[0].contains('op=mmap address=0x0 size=0x' + page.hex())
	assert lines[0].ends_with('result=0x' + u64(mapped).hex() + ' errno=37')
	assert lines[3].ends_with('result=0xffffffffffffffff errno=' + C.EINVAL.str())
	assert lines[6].contains('op=vm_allocate address=0x0') && lines[6].ends_with('result=0x4 errno=37')
	assert lines[9].contains('op=vm_map') && lines[9].ends_with('result=0x2e errno=37')
	println('IOS-VM-PROBE: disabled mode, reserve/commit/release, Mach results, errno and failed diagnostic write PASS')
}
