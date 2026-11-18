// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import apple.mailbox
import apple.rtkit
import aarch64.cpu
import gpu.agx.hw
import gpu.agx.pgtable
import klock
import memory

__global rtkit_owner = unsafe { &GpuManager(nil) }

fn alloc_buffer_from_heap(mut _ ChannelTestHeap, size u64, protection u64,
	allocator u32) ?SharedBuffer {
	assert size == 4096 && allocator == buffer_allocator_g13_rtkit
	assert protection == pgtable.gpu_prot_fw_shared_rw && rtkit_owner.lock.is_held()
	physical := unsafe { C.calloc(1, size) }
	assert physical != unsafe { nil }
	return SharedBuffer{va: 0x400000, phys: u64(physical), size: size, allocator: allocator}
}

fn check_rtkit_reply_owner() {
	assert rtkit_owner.lock.is_held() && rtkit_owner.rtkit_buffers.len == 1
}

fn stop_rtkit_owner() {
	assert !rtkit_owner.lock.is_held() && !rtkit_owner.rtkit_buffer_lock.is_held()
	assert memory.snapshots() == 1, 'the private copy must survive transport teardown'
	rtkit_owner.shutdown()
	assert rtkit_owner.rtkit_buffers.len == 0
}

fn crashlog_word(base u64, offset u64, value u32) {
	unsafe { C.memcpy(voidptr(base + offset), &value, sizeof(value)) }
}

fn crashlog_quad(base u64, offset u64, value u64) {
	crashlog_word(base, offset, u32(value))
	crashlog_word(base, offset + 4, u32(value >> 32))
}

struct CrashLogFixture {
	base u64
mut:
	offset u64 = 0x20
}

fn (mut log CrashLogFixture) record(kind u32, size u32) u64 {
	crashlog_word(log.base, log.offset, kind)
	crashlog_word(log.base, log.offset + 12, size + 16)
	payload := log.offset + 16
	log.offset = payload + size
	return payload
}

fn build_crashlog_sections(base u64, malformed bool) {
	unsafe { C.memset(voidptr(base + 0x20), 0, 4096 - 0x20) }
	mut log := CrashLogFixture{base: base}
	if malformed {
		log.record(0x43737472, 4) // Cstr
		log.record(0x43766572, 16) // Cver
		log.record(0x4374696d, 7) // Ctim
		log.record(0x436d6278, 27) // Cmbx
		log.record(0x43726738, 0x34f) // Crg8
	} else {
		text := log.record(0x43737472, 16)
		crashlog_word(base, text, 0xcafe)
		unsafe { C.memcpy(voidptr(base + text + 4), c'one\ntwo\nlast', 12) }
		version := log.record(0x43766572, 20)
		unsafe { C.memcpy(voidptr(base + version + 16), c'vM1!', 4) }
		time := log.record(0x4374696d, 8)
		crashlog_quad(base, time, 0xfedcba9876543210)
		mail := log.record(0x436d6278, 28 + 2 * 24 + 8)
		crashlog_word(base, mail + 16, 17)
		crashlog_word(base, mail + 24, 5)
		crashlog_quad(base, mail + 28, 0x0123456789abcdef)
		crashlog_quad(base, mail + 36, 0xfedcba9876543210)
		crashlog_word(base, mail + 44, 0x88888888)
		crashlog_quad(base, mail + 52, 1)
		crashlog_quad(base, mail + 60, 2)
		crashlog_word(base, mail + 68, 3)
		crashlog_quad(base, mail + 76, 0xffffffffffffffff)
		regs := log.record(0x43726738, 0x350)
		for i := u64(0); i < 31; i++ {
			crashlog_quad(base, regs + 8 + i * 8, 0x1111000000000000 + i)
		}
		crashlog_quad(base, regs + 0x100, 0x111111111)
		crashlog_quad(base, regs + 0x108, 0x222222222)
		crashlog_quad(base, regs + 0x110, 0x209)
		crashlog_quad(base, regs + 0x330, 0x333333333)
		crashlog_quad(base, regs + 0x340, 0x444444444)
	}
	task := log.record(0x43637374, 8)
	crashlog_word(base, task, 47)
	log.record(0x434c4845, 0)
	crashlog_word(base, 8, u32(log.offset))
}

fn check_rtkit_unknown_message(mut mgr GpuManager, sent int) {
	requests := memory.requests()
	barriers := cpu.barriers()
	unsupported := mailbox.MboxMsg{data0: (u64(2) << 52) | (u64(1) << 44), data1: rtkit.ep_crashlog}
	assert mgr.handle_role_system_message(0, unsupported)
	assert mgr.rtk.state == .running && mgr.rtk.mbox.sent == sent
	assert cpu.barriers() == barriers && memory.requests() == requests
	assert mgr.rtkit_buffers.len == sent
}

fn check_rtkit_crash_snapshot() {
	const_request := mailbox.MboxMsg{data0: (u64(1) << 52) | (u64(1) << 44), data1: rtkit.ep_crashlog}
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for mode in 0 .. 11 {
			mut transport := rtkit.RTKit{name: 'g13-test', state: .running}
			mut mgr := GpuManager{
				hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}
				rtk: unsafe { &transport }
			}
			rtkit_owner = unsafe { &mgr }
			transport.set_shmem_allocator(unsafe { voidptr(&mgr) }, allocate_rtkit_shmem)
			transport.set_shmem_reader(copy_rtkit_shmem)
			if mode == 0 { check_rtkit_unknown_message(mut mgr, 0) }
			mailbox.watch_send(check_rtkit_reply_owner)
			assert mgr.handle_role_system_message(0, const_request)
			mailbox.watch_send(unsafe { nil })
			assert transport.mbox.sent == 1 && mgr.rtkit_buffers.len == 1
			iova := transport.system_iovas[rtkit.ep_crashlog]
			assert iova == 0x400000 && transport.system_sizes[rtkit.ep_crashlog] == 4096
			if mode == 0 { check_rtkit_unknown_message(mut mgr, 1) }
			base := mgr.rtkit_buffers[0].phys
			crashlog_word(base, 0, 0x434c4845)
			crashlog_word(base, 4, 1)
			crashlog_word(base, 8, 0x60)
			crashlog_word(base, 0x20, 0x43737472)
			crashlog_word(base, 0x2c, 0x28)
			crashlog_word(base, 0x30, 7)
			crashlog_word(base, 0x48, 0x434c4845)
			unsafe { C.memcpy(voidptr(base + 0x34), c'private snapshot', 17) }

			mut probe := u64(0)
			assert !copy_rtkit_shmem(unsafe { &mgr }, iova + 4092, unsafe { &probe }, 8)
			assert !copy_rtkit_shmem(unsafe { &mgr }, iova - 1, unsafe { &probe }, 1)
			assert !copy_rtkit_shmem(unsafe { &mgr }, ~u64(0), unsafe { &probe }, 1)
			assert !copy_rtkit_shmem(unsafe { &mgr }, iova, unsafe { nil }, 1)
			assert copy_rtkit_shmem(unsafe { &mgr }, iova + 4096 - sizeof(probe), unsafe { &probe }, sizeof(probe))
			assert probe == 0
			match mode {
				1 { klock.on_next_release(unsafe { &mgr.rtkit_buffer_lock }, stop_rtkit_owner) }
				2 { klock.on_next_acquire(unsafe { &mgr.rtkit_buffer_lock }, stop_rtkit_owner) }
				3 { memory.refuse_snapshot(true) }
				4 { crashlog_word(base, 0, 0) }
				5 { crashlog_word(base, 8, 4097) }
				6 { crashlog_word(base, 0x2c, 8) }
				7 { transport.system_iovas[rtkit.ep_crashlog] = iova + 1 }
				8, 9 { build_crashlog_sections(base, mode == 9) }
				10 { crashlog_word(base, 8, 0x2f) }
				else {}
			}
			requests := memory.requests()
			barriers := cpu.barriers()
			assert !mgr.handle_role_system_message(0, const_request)
			assert transport.state == .error && memory.snapshots() == 0
			assert memory.requests() == requests + 1
			assert cpu.barriers() == barriers + if mode == 3 { u32(0) } else { u32(1) }
			if mode in [1, 2]! { assert mgr.state == .stopped && mgr.rtkit_buffers.len == 0 }
			memory.refuse_snapshot(false)
			mgr.shutdown()
			assert mgr.rtkit_buffers.len == 0 && transport.mbox.sent == 1
			unsafe { mgr.rtkit_buffers.free() }
			rtkit_owner = unsafe { nil }
		}
	}
	mut late := rtkit.RTKit{name: 'g13-stopped', state: .running}
	mut stopped := GpuManager{state: .stopped, hw_config: hw.HwConfig{gpu_gen: .g13}, rtk: unsafe { &late }}
	rtkit_owner = unsafe { &stopped }
	late.set_shmem_allocator(unsafe { voidptr(&stopped) }, allocate_rtkit_shmem)
	assert stopped.handle_role_system_message(0, const_request)
	assert late.mbox.sent == 0 && stopped.rtkit_buffers.len == 0
	rtkit_owner = unsafe { nil }
	println('G13 RTKit: 22 crash paths and four unknown notifications across both ABIs')
}
