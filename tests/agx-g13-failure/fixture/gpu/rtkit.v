// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpu

import apple.mailbox
import apple.rtkit
import aarch64.cpu
import gpu.agx.alloc
import gpu.agx.hw
import gpu.agx.pgtable
import klock
import memory

__global rtkit_owner = unsafe { &GpuManager(nil) }
__global rtkit_alloc_attempts = 0
__global rtkit_fail_next_allocation = false
__global syslog_copy_attempts = 0
__global syslog_copy_refused = false
__global syslog_expected_iova = u64(0)
__global syslog_expected_size = u64(0)
__global syslog_expected_sent = 0

fn alloc_buffer_from_heap(mut _ ChannelTestHeap, size u64, protection u64,
	allocator u32) ?SharedBuffer {
	assert size in [u64(4096), 0x2345]! && allocator == buffer_allocator_g13_rtkit
	assert protection == pgtable.gpu_prot_fw_shared_rw && rtkit_owner.lock.is_held()
	rtkit_alloc_attempts++
	if rtkit_fail_next_allocation {
		rtkit_fail_next_allocation = false
		return none
	}
	span := (size + 0x3fff) & ~u64(0x3fff)
	physical := unsafe { C.calloc(1, span) }
	assert physical != unsafe { nil }
	return SharedBuffer{va: alloc.g13_rtkit_start, phys: u64(physical), size: span, allocator: allocator}
}

fn check_rtkit_reply_owner() {
	assert rtkit_owner.lock.is_held() && rtkit_owner.rtkit_buffers.len == 1
	_, address, span := cpu.prepared_range()
	assert address == rtkit_owner.rtkit_buffers[0].phys && span == rtkit_owner.rtkit_buffers[0].size
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
			assert iova == alloc.g13_rtkit_start && transport.system_sizes[rtkit.ep_crashlog] == 4096
			if mode == 0 { check_rtkit_unknown_message(mut mgr, 1) }
			base := mgr.rtkit_buffers[0].phys
			span := mgr.rtkit_buffers[0].size
			crashlog_word(base, 0, 0x434c4845)
			crashlog_word(base, 4, 1)
			crashlog_word(base, 8, 0x60)
			crashlog_word(base, 0x20, 0x43737472)
			crashlog_word(base, 0x2c, 0x28)
			crashlog_word(base, 0x30, 7)
			crashlog_word(base, 0x48, 0x434c4845)
			unsafe { C.memcpy(voidptr(base + 0x34), c'private snapshot', 17) }

			mut probe := u64(0)
			assert !copy_rtkit_shmem(unsafe { &mgr }, iova + span - 4, unsafe { &probe }, 8)
			assert !copy_rtkit_shmem(unsafe { &mgr }, iova - 1, unsafe { &probe }, 1)
			assert !copy_rtkit_shmem(unsafe { &mgr }, ~u64(0), unsafe { &probe }, 1)
			assert !copy_rtkit_shmem(unsafe { &mgr }, iova, unsafe { nil }, 1)
			assert copy_rtkit_shmem(unsafe { &mgr }, iova + span - sizeof(probe), unsafe { &probe }, sizeof(probe))
			assert probe == 0
			match mode {
				1 { klock.on_next_release(unsafe { &mgr.rtkit_buffer_lock }, stop_rtkit_owner) }
				2 { klock.on_next_acquire(unsafe { &mgr.rtkit_buffer_lock }, stop_rtkit_owner) }
				3 { memory.refuse_snapshot(true) }
				4 { crashlog_word(base, 0, 0) }
				5 { crashlog_word(base, 8, 4097) }
				6 { crashlog_word(base, 0x2c, 8) }
				7 { transport.system_iovas[rtkit.ep_crashlog] = iova + span - 4096 + 1 }
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

fn check_rtkit_buffer_retries() {
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for ep in [rtkit.ep_syslog, rtkit.ep_ioreport, rtkit.ep_oslog]! {
			for timeout in [false, true]! {
				check_rtkit_buffer_retry(abi, ep, timeout)
			}
		}
	}
	println('G13 RTKit: 12 shared-buffer retry sequences across both ABIs')
}

fn check_rtkit_buffer_retry(abi hw.FirmwareAbi, ep u8, timeout bool) {
	mut transport := rtkit.RTKit{name: 'g13-retry', state: .running}
	mut mgr := GpuManager{
		hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}
		rtk: unsafe { &transport }
	}
	rtkit_owner = unsafe { &mgr }
	transport.set_shmem_allocator(unsafe { voidptr(&mgr) }, allocate_rtkit_shmem)

	// Wire fields are literal so the fixture can catch mask or shift errors.
	size := if ep == rtkit.ep_oslog { u64(0x2345) } else { u64(4096) }
	geometry := if ep == rtkit.ep_oslog { u64(0x0102345000000000) } else { u64(0x0010100000000000) }
	address := if ep == rtkit.ep_oslog { u64(0xffae00000) } else { u64(0xfae00000000) }
	size_bit := if ep == rtkit.ep_oslog { u64(1) << 36 } else { u64(1) << 44 }
	request_type := if ep == rtkit.ep_oslog { u64(1) << 56 } else { u64(1) << 52 }
	message := mailbox.MboxMsg{data0: geometry, data1: ep}
	before := rtkit_alloc_attempts
	cache_before, _, _ := cpu.prepared_range()
	// Initial validation/allocation failures still report failure to the caller.
	assert !mgr.handle_role_system_message(0, mailbox.MboxMsg{data0: geometry | address, data1: ep})
	assert rtkit_alloc_attempts == before
	rtkit_fail_next_allocation = true
	assert !mgr.handle_role_system_message(0, message)
	assert rtkit_alloc_attempts == before + 1 && mgr.rtkit_buffers.len == 0
	assert transport.system_iovas[ep] == 0 && transport.system_sizes[ep] == 0
	assert transport.mbox.attempts == 0

	transport.mbox.fail_next_send = timeout
	mailbox.watch_send(check_rtkit_reply_owner)
	assert mgr.handle_role_system_message(0, message)
	assert transport.mbox.attempts == 1 && transport.mbox.sent == if timeout { 0 } else { 1 }
	if !timeout {
		assert transport.mbox.last.data0 == (geometry | address) && transport.mbox.last.data1 == ep
	}
	assert mgr.rtkit_buffers.len == 1
	assert transport.system_iovas[ep] == alloc.g13_rtkit_start && transport.system_sizes[ep] == size
	backing := mgr.rtkit_buffers[0].phys
	crashlog_word(backing, 0, 0xfacecafe)

	// Conflicting size/IOVA and a zero-size request receive no reply.
	for data in [geometry + size_bit, geometry | (address ^ 1), request_type]! {
		assert mgr.handle_role_system_message(0, mailbox.MboxMsg{data0: data, data1: ep})
	}
	assert transport.mbox.attempts == 1

	// Both permitted forms of retry must publish the original wire reply.
	for data in [geometry, geometry | address]! {
		assert mgr.handle_role_system_message(0, mailbox.MboxMsg{data0: data, data1: ep})
		assert transport.mbox.last.data0 == (geometry | address) && transport.mbox.last.data1 == ep
	}
	assert transport.mbox.attempts == 3 && transport.mbox.sent == if timeout { 2 } else { 3 }
	assert rtkit_alloc_attempts == before + 2 && mgr.rtkit_buffers.len == 1
	cache_after, _, _ := cpu.prepared_range()
	assert cache_after == cache_before + 1
	assert mgr.rtkit_buffers[0].phys == backing && unsafe { *&u32(backing) } == 0xfacecafe
	assert mgr.state == .running && transport.state == .running
	mailbox.watch_send(unsafe { nil })

	mgr.shutdown()
	assert mgr.handle_role_system_message(0, message)
	assert mgr.rtkit_buffers.len == 0 && transport.mbox.attempts == 3
	assert rtkit_alloc_attempts == before + 2
	unsafe { mgr.rtkit_buffers.free() }
	rtkit_owner = unsafe { nil }
}

fn read_syslog_fixture(context voidptr, iova u64, destination voidptr, size u64) bool {
	assert rtkit_owner.lock.is_held()
	assert rtkit_owner.rtk.mbox.sent == syslog_expected_sent, 'the slot must be copied before its ACK'
	assert iova == syslog_expected_iova && size == syslog_expected_size
	syslog_copy_attempts++
	return !syslog_copy_refused && copy_rtkit_shmem(context, iova, destination, size)
}

fn init_syslog_fixture(mut mgr GpuManager, entries u8, size u8) {
	data := (u64(8) << 52) | (u64(size) << 24) | u64(entries)
	sent := mgr.rtk.mbox.sent
	assert mgr.handle_role_system_message(0, mailbox.MboxMsg{data0: data, data1: rtkit.ep_syslog})
	assert mgr.rtk.mbox.sent == sent
}

fn notify_syslog_fixture(mut mgr GpuManager, index u8, offset u64, length u64) {
	data := (u64(5) << 52) | 0xabc000 | u64(index)
	copies := syslog_copy_attempts
	barriers := cpu.barriers()
	cache_before, _, _ := cpu.prepared_range()
	syslog_expected_sent = mgr.rtk.mbox.sent
	syslog_expected_iova = alloc.g13_rtkit_start + offset
	syslog_expected_size = length
	assert mgr.handle_role_system_message(0, mailbox.MboxMsg{data0: data, data1: rtkit.ep_syslog})
	assert mgr.rtk.mbox.sent == syslog_expected_sent + 1
	assert mgr.rtk.mbox.last.data0 == data && mgr.rtk.mbox.last.data1 == rtkit.ep_syslog
	expected_reads := if length == 0 { 0 } else { 1 }
	assert syslog_copy_attempts == copies + expected_reads && cpu.barriers() == barriers + u32(expected_reads)
	cache_after, _, _ := cpu.prepared_range()
	assert cache_after == cache_before
}

fn check_rtkit_syslog() {
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		mut transport := rtkit.RTKit{name: 'g13-syslog', state: .running}
		mut mgr := GpuManager{
			hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}
			rtk: unsafe { &transport }
		}
		rtkit_owner = unsafe { &mgr }
		transport.set_shmem_allocator(unsafe { voidptr(&mgr) }, allocate_rtkit_shmem)
		transport.set_shmem_reader(read_syslog_fixture)
		init_syslog_fixture(mut mgr, 100, 32)
		notify_syslog_fixture(mut mgr, 1, 0, 0) // INIT without backing
		assert mgr.handle_role_system_message(0, mailbox.MboxMsg{data0: 0x0010100000000000, data1: rtkit.ep_syslog})
		base := mgr.rtkit_buffers[0].phys
		unsafe {
			C.memcpy(voidptr(base + 72), c'abcdefghijklmnopqrstuvwx', 24)
			C.memcpy(voidptr(base + 96), c'  trim \r\n ', 11)
		}
		notify_syslog_fixture(mut mgr, 1, 72, 56)
		notify_syslog_fixture(mut mgr, 64, 0, 0) // INIT count exceeds backing
		transport.set_shmem_reader(unsafe { nil })
		notify_syslog_fixture(mut mgr, 1, 0, 0) // Client only acknowledges
		transport.set_shmem_reader(read_syslog_fixture)
		syslog_copy_refused = true
		notify_syslog_fixture(mut mgr, 1, 72, 56)
		syslog_copy_refused = false

		init_syslog_fixture(mut mgr, 1, 255)
		unsafe {
			C.memcpy(voidptr(base + 8), c'wide', 5)
			C.memset(voidptr(base + 32), `M`, 254)
			*&u8(base + 32 + 254) = `X`
		}
		notify_syslog_fixture(mut mgr, 0, 8, 279)
		notify_syslog_fixture(mut mgr, 1, 0, 0) // Index outside replacement INIT

		init_syslog_fixture(mut mgr, 1, 1)
		unsafe { C.memcpy(voidptr(base + 8), c'one', 4) }
		notify_syslog_fixture(mut mgr, 0, 8, 25)
		init_syslog_fixture(mut mgr, 0, 32)
		notify_syslog_fixture(mut mgr, 0, 0, 0)
		init_syslog_fixture(mut mgr, 1, 0)
		notify_syslog_fixture(mut mgr, 0, 0, 0)
		mgr.shutdown()
		assert mgr.rtkit_buffers.len == 0
		unsafe { mgr.rtkit_buffers.free() }
		rtkit_owner = unsafe { nil }
	}
	println('G13 RTKit: 20 Syslog notifications across both ABIs check slot bounds, text and ACK order')
}

fn notify_oslog_fixture(mut mgr GpuManager, data u64, acknowledge bool) {
	attempts := mgr.rtk.mbox.attempts
	sent := mgr.rtk.mbox.sent
	assert mgr.handle_role_system_message(0, mailbox.MboxMsg{data0: data, data1: rtkit.ep_oslog})
	if acknowledge {
		assert mgr.rtk.mbox.attempts == attempts + 1 && mgr.rtk.mbox.sent == sent + 1
		assert mgr.rtk.mbox.last.data0 == data && mgr.rtk.mbox.last.data1 == rtkit.ep_oslog
	} else {
		assert mgr.rtk.mbox.attempts == attempts && mgr.rtk.mbox.sent == sent
	}
}

fn check_rtkit_oslog() {
	notification := u64(0x02) << 56
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		mut transport := rtkit.RTKit{name: 'g13-oslog', state: .running}
		mut mgr := GpuManager{
			hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}
			rtk: unsafe { &transport }
		}
		rtkit_owner = unsafe { &mgr }
		transport.set_shmem_allocator(unsafe { voidptr(&mgr) }, allocate_rtkit_shmem)
		assert !transport.oslog_ack_enabled
		transport.oslog_ack_enabled = true
		notify_oslog_fixture(mut mgr, notification, false) // No negotiated buffer

		allocations := rtkit_alloc_attempts
		request := mailbox.MboxMsg{data0: 0x0102345000000000, data1: rtkit.ep_oslog}
		assert mgr.handle_role_system_message(0, request)
		assert mgr.rtkit_buffers.len == 1 && transport.mbox.sent == 1
		transport.oslog_ack_enabled = false
		notify_oslog_fixture(mut mgr, notification, false) // Default policy for other clients
		transport.oslog_ack_enabled = true

		mailbox.watch_send(check_rtkit_reply_owner)
		for counter in [u64(0xffff_fffe), 0xffff_ffff, 0, 0, 0x8000_0000, 1]! {
			notify_oslog_fixture(mut mgr, notification | counter, true)
		}
		for bit := u32(32); bit < 56; bit++ {
			notify_oslog_fixture(mut mgr, notification | (u64(1) << bit) | 4, false)
		}
		for kind in [u64(3), 4, 5, 6]! {
			notify_oslog_fixture(mut mgr, (kind << 56) | 4, false)
		}

		transport.mbox.fail_next_send = true
		attempts := transport.mbox.attempts
		sent := transport.mbox.sent
		assert mgr.handle_role_system_message(0, mailbox.MboxMsg{data0: notification | 5, data1: rtkit.ep_oslog})
		assert transport.mbox.attempts == attempts + 1 && transport.mbox.sent == sent
		assert mgr.state == .running && transport.state == .running
		notify_oslog_fixture(mut mgr, notification | 5, true)
		mailbox.watch_send(unsafe { nil })

		mgr.shutdown()
		assert transport.system_iovas[rtkit.ep_oslog] != 0 && mgr.rtkit_buffers.len == 0
		notify_oslog_fixture(mut mgr, notification | 6, false) // Stale allocation metadata
		assert rtkit_alloc_attempts == allocations + 1
		unsafe { mgr.rtkit_buffers.free() }
		rtkit_owner = unsafe { nil }
	}
	println('G13 RTKit: 78 OSLog notifications across both ABIs check full-width ACKs, reserved bits and shutdown')
}
