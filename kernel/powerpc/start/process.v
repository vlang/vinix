// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.cpu
import powerpc.exception
import powerpc.hash32
import powerpc.mmu
import powerpc.runtime
import powerpc.serial

// Single CPU, IRQ-off kernel: no kernel stack survives a switch. Blocking
// calls retry their user instruction after another process makes progress.
const restart_call = -512

struct Process {
mut:
	pid u32
	parent u32
	state u32 // 0 free, 1 runnable, 2 zombie
	status u32
	frame exception.Frame
	fpu [33]u64
	space mmu.Space
	fds [64]&Descriptor
	cloexec [64]bool
	heap_min u32
	heap u32
	fb_length u32
	mask u32
	wait_pc u32
	deadline u64
	termination u32
	sandbox bool
}

__global processes [8]Process
__global current_process int
__global next_pid u32 = 2
__global process_ready bool
__global empty_descriptor Descriptor
__global open_files [256]Descriptor
__global close_on_exec [64]bool

fn C.vinix_save_fpu(address voidptr)
fn C.vinix_restore_fpu(address voidptr)

fn install_fd(fd int, value Descriptor) bool {
	for i in 0 .. 256 {
		if open_files[i].refs == 0 {
			open_files[i] = value
			open_files[i].refs = 1
			descriptors[fd] = unsafe { &open_files[i] }
			close_on_exec[fd] = value.flags & 0x80000 != 0
			return true
		}
	}
	return false
}

fn initialize_processes() {
	for i in 0 .. 64 { descriptors[i] = unsafe { &empty_descriptor } }
	for i in 0 .. 3 { install_fd(i, Descriptor{used: true, writable: i != 0, file: -8, flags: if i == 0 { u32(0) } else { u32(1) }}) }
	processes[0].pid = 1
	processes[0].state = 1
	processes[0].space = *user_space
	user_space = unsafe { &processes[0].space }
	process_ready = true
}

fn save_process() {
	mut p := unsafe { &processes[current_process] }
	p.fds = descriptors
	p.cloexec = close_on_exec
	p.heap_min = process_break_min
	p.heap = process_break
	p.fb_length = framebuffer_length
	p.mask = process_umask
}

fn switch_process(mut frame exception.Frame) {
	if !process_ready { return }
	mut next := current_process
	for distance in 1 .. 9 {
		index := (current_process + distance) % 8
		if processes[index].state == 1 { next = index; break }
	}
	if processes[next].state != 1 { halt(c'no runnable process') }
	if next == current_process { return }
	save_process()
	processes[current_process].frame = frame
	C.vinix_save_fpu(unsafe { &processes[current_process].fpu[0] })
	current_process = next
	mut p := unsafe { &processes[next] }
	descriptors = p.fds
	close_on_exec = p.cloexec
	process_break_min = p.heap_min
	process_break = p.heap
	framebuffer_length = p.fb_length
	process_umask = p.mask
	user_space = unsafe { &p.space }
	user_space.activate()
	C.vinix_restore_fpu(unsafe { &p.fpu[0] })
	frame = p.frame
	if p.termination != 0 {
		finish_process(p.termination)
		switch_process(mut frame)
	}
}

fn release_space(mut space mmu.Space) {
	for i := u32(0); i < space.count; i++ {
		m := space.mappings[i]
		if m.virtual < framebuffer_virtual || m.virtual >= framebuffer_virtual + 16 * 1024 * 1024 {
			if !physical_pages.give(m.physical, 1) { halt(c'process page ownership') }
		}
	}
	space.count = 0
	if space.table != 0 { physical_pages.give(space.table, hash32.bytes / 4096); space.table = 0 }
}

fn sys_fork(frame &exception.Frame) int {
	mut slot := -1
	for i in 1 .. 8 { if processes[i].state == 0 { slot = i; break } }
	if slot < 0 { return -11 }
	mut child := unsafe { &processes[slot] }
	table := physical_pages.take(hash32.bytes / 4096, hash32.bytes / 4096)
	if table == 0 || !child.space.init(table) { return -12 }
	for i := u32(0); i < user_space.count; i++ {
		m := user_space.mappings[i]
		// Shared device mappings survive fork. Exec drops the child's mapping
		// without exposing the console while the compositor still owns one.
		if m.virtual >= framebuffer_virtual && m.virtual < framebuffer_virtual + 16 * 1024 * 1024 {
			if !child.space.map_device(m.virtual, m.physical, m.writable) { release_space(mut child.space); return -12 }
			continue
		}
		physical := physical_pages.take(1, 1)
		if physical == 0 { release_space(mut child.space); return -12 }
		runtime.copy(voidptr(physical), voidptr(m.physical), 4096)
		if !child.space.map(m.virtual, physical, m.writable) {
			physical_pages.give(physical, 1); release_space(mut child.space); return -12
		}
		if m.virtual < 0x50000000 { cpu.publish_code(physical, 4096) }
	}
	child.pid = next_pid; next_pid++
	child.parent = processes[current_process].pid
	child.frame = *frame
	child.frame.gpr[3] = 0
	child.frame.cr &= ~u32(0x10000000)
	child.fds = descriptors
	child.cloexec = close_on_exec
	for fd in 0 .. 64 { if child.fds[fd].used { child.fds[fd].refs++ } }
	child.heap_min = process_break_min; child.heap = process_break
	child.fb_length = framebuffer_length; child.mask = process_umask
	if framebuffer_length != 0 { framebuffer_users++ }
	child.wait_pc = 0; child.deadline = 0
	child.termination = 0
	child.sandbox = false
	C.vinix_save_fpu(unsafe { &child.fpu[0] })
	child.state = 1
	return int(child.pid)
}

fn sys_kill(pid i32, signal u32) int {
	if pid <= 0 || signal > 64 { return -22 }
	for i in 0 .. 8 {
		if processes[i].state == 0 || processes[i].pid != u32(pid) { continue }
		if signal == 0 { return 0 }
		if signal != 9 && signal != 15 { return -95 }
		if i == 0 { return -1 }
		processes[i].termination = signal
		return 0
	}
	return -3
}

fn finish_process(status u32) {
	if framebuffer_length != 0 { framebuffer_unmap(framebuffer_virtual, framebuffer_length) }
	for fd in 0 .. 64 { if descriptors[fd].used { sys_close(u32(fd)) } }
	release_space(mut processes[current_process].space)
	processes[current_process].status = status
	processes[current_process].state = 2
	if processes[current_process].pid == 1 {
		serial.text(c'\nVinix: init exited, status '); serial.hex(status >> 8); serial.text(c'\n')
		for {}
	}
	for i in 1 .. 8 {
		if processes[i].parent == processes[current_process].pid { processes[i].parent = 1 }
	}
}

fn sys_waitpid(pid i32, address u32, options u32) int {
	if pid == 0 || pid < -1 { return -95 } // process groups are not implemented
	if options & ~u32(1) != 0 { return -22 }
	if address != 0 && !user_space.accessible(address, 4, true) { return -14 }
	mut found := false
	for i in 1 .. 8 {
		mut p := unsafe { &processes[i] }
		if p.state == 0 || p.parent != processes[current_process].pid || (pid > 0 && p.pid != u32(pid)) { continue }
		found = true
		if p.state == 2 {
			if address != 0 && !copy_to_user(address, unsafe { &u8(&p.status) }, 4) { return -14 }
			p.state = 0
			return int(p.pid)
		}
	}
	if !found { return -10 }
	return if options & 1 != 0 { 0 } else { restart_call }
}

fn sys_dup(fd u32, target u32, flags u32) int {
	if fd >= 64 || target >= 64 || !descriptors[fd].used { return -9 }
	if flags & ~u32(0x80000) != 0 { return -22 }
	if fd == target { return int(fd) }
	if descriptors[target].used { sys_close(target) }
	descriptors[target] = descriptors[fd]
	descriptors[target].refs++
	close_on_exec[target] = flags != 0
	return int(target)
}

fn sys_dup_min(fd u32, minimum u32, flags u32) int {
	if fd >= 64 || !descriptors[fd].used { return -9 }
	if minimum >= 64 { return -22 }
	for at := minimum; at < 64; at++ { if !descriptors[at].used { return sys_dup(fd, at, flags) } }
	return -24
}
