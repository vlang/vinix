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
	unsafe { *&u32(base + offset) = value }
}

fn check_rtkit_crash_snapshot() {
	const_request := mailbox.MboxMsg{data0: (u64(1) << 52) | (u64(1) << 44), data1: rtkit.ep_crashlog}
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for mode in 0 .. 8 {
			mut transport := rtkit.RTKit{name: 'g13-test', state: .running}
			mut mgr := GpuManager{
				hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}
				rtk: unsafe { &transport }
			}
			rtkit_owner = unsafe { &mgr }
			transport.set_shmem_allocator(unsafe { voidptr(&mgr) }, allocate_rtkit_shmem)
			transport.set_shmem_reader(copy_rtkit_shmem)
			mailbox.watch_send(check_rtkit_reply_owner)
			assert mgr.handle_role_system_message(0, const_request)
			mailbox.watch_send(unsafe { nil })
			assert transport.mbox.sent == 1 && mgr.rtkit_buffers.len == 1
			iova := transport.system_iovas[rtkit.ep_crashlog]
			assert iova == 0x400000 && transport.system_sizes[rtkit.ep_crashlog] == 4096
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
	println('G13 RTKit snapshot: 16 crash paths on both ABIs cover teardown before and after copy, allocation failure, malformed records and bounded IOVA lookup')
}
