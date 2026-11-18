@[has_globals]
module gpu

import gpu.agx.mmu
import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import gpu.agx.pgtable
import klock
import aarch64.timer

const ep_doorbell = u32(0x21)
const msg_fwctl = u64(0x84) << 48

pub enum GpuState { idle starting running error stopped }
pub struct GpuManager {
mut:
	state GpuState
	hw_config hw.HwConfig
	channels GpuChannels
	lock klock.Lock
	fwctl_lock klock.Lock
	mode int
	sends int
	acknowledged bool
	slot u32
	kernel_pte &u64 = unsafe { nil }
}
struct GpuChannels { mut: fw_ctrl channel.TxChannel }

__global uat_mgr = unsafe { &mmu.UatManager(nil) }
__global active = unsafe { &GpuManager(nil) }

fn consume(mut manager GpuManager) {
	assert manager.fwctl_lock.is_held()
	assert uat_mgr.handoff.flush[manager.slot].state == 1
	manager.acknowledged = true
	if manager.mode != 6 { uat_mgr.handoff.flush[manager.slot].state = 2 }
	unsafe { *&u32(manager.channels.fw_ctrl.state_phys) = *&u32(manager.channels.fw_ctrl.state_phys + 0x10) }
}
fn poll_callback() {
	mut manager := unsafe { active }
	assert manager != unsafe { nil } && manager.fwctl_lock.is_held()
	if manager.mode == 1 && !manager.acknowledged { consume(mut manager) }
	if manager.mode == 4 { manager.state = .error }
	if manager.mode == 5 { manager.state = .stopped }
}
fn (mut manager GpuManager) send_role_message(role u32, endpoint u8, message u64) bool {
	assert manager.fwctl_lock.is_held()
	assert role == 0 && endpoint == 0x21 && message == u64(0x84) << 48
	assert uat_mgr.handoff.flush[manager.slot].state == 1
	if manager.kernel_pte != unsafe { nil } {
		pte := unsafe { *manager.kernel_pte }
		assert manager.lock.is_held() && manager.slot == mmu.uat_kernel_flush_slot
		assert pte & pgtable.uat_pte_valid != 0 && !pgtable.is_cached_noncoherent(pte),
			'kernel FwCtl must see a valid uncached PTE before unmap'
	}
	manager.sends++
	if manager.mode in [0, 6]! || manager.mode >= 13 { consume(mut manager) }
	if manager.mode >= 13 {
		mut header := unsafe { &channel.FwCtlRingHeader(manager.channels.fw_ctrl.state_phys) }
		match manager.mode {
			13 { header.write_ptr = 256 }
			14 { header.read_ptr = 256 }
			15 { manager.channels.fw_ctrl.faulted = 1 }
			16 { manager.state = .stopped }
			17 { header.write_ptr = (header.write_ptr + 1) % 256 }
			else { panic('invalid completion fixture') }
		}
	}
	return manager.mode != 2
}

fn run_case(initial u32, slot u32, mode int, outer_lock bool, pages u64) {
	mut handoff := mmu.UatHandoff{}
	mut table := mmu.UatManager{handoff: &handoff, handoff_initialized: true}
	uat_mgr = unsafe { &table }
	mut header := channel.FwCtlRingHeader{read_ptr: initial, write_ptr: initial}
	mut ring := [256]fw.FwFwCtlMsg{}
	mut manager := GpuManager{
		state: .running
		hw_config: hw.HwConfig{gpu_gen: if mode == 12 { .g17 } else { .g13 }}
		channels: GpuChannels{fw_ctrl: channel.new_fwctl_tx_channel('fwctl', 1, u64(&header), 1, u64(&ring), 256, 20)}
		mode: mode
		slot: slot
	}
	active = unsafe { &manager }; timer.reset(); timer.on_tick(poll_callback)
	address := u64(0xffffffa000004000)
	size := pages * 0x4000
	if mode == 7 { handoff.flush[slot].state = 1 }
	if mode == 8 { header.read_ptr = (initial + 1) % 256 }
	if mode == 9 { header.write_ptr = 256 }
	if mode == 10 { table.handoff_initialized = false }
	if mode == 11 { manager.state = .starting }
	if outer_lock { manager.lock.acquire() }
	result := manager.flush_g13_uat_range(slot, address, size)
	assert !manager.fwctl_lock.is_held(), 'every UAT return must release the firmware-control lock'
	assert manager.lock.is_held() == outer_lock, 'polling must preserve its caller lock state'
	if outer_lock { manager.lock.release() }
	success := mode in [0, 1]!
	if mode >= 13 { assert !result, 'a faulted or stopped FwCtl transaction must retain its handoff' }
	assert result == success, 'UAT success requires both its ring token and completed handoff'
	published := mode < 7 || mode >= 13
	assert manager.sends == if published { 1 } else { 0 }
	if published {
		expected_write := match mode {
			13 { u32(256) }
			17 { (initial + 2) % 256 }
			else { (initial + 1) % 256 }
		}
		assert header.write_ptr == expected_write
		assert ring[initial] == fw.FwFwCtlMsg{
			addr: address
			slot: slot
			page_count: u16(pages)
			unk_12: 2
		}, 'FwCtl must publish the 16-bit page count alongside the full handoff range'
		assert handoff.flush[slot].addr == address && handoff.flush[slot].size == size,
			'published failures must retain their handoff slot and unpublished failures must roll back'
	}
	expected_state := if mode >= 13 { u64(2) } else if success { u64(0) } else if mode < 8 { u64(1) } else { u64(0) }
	assert handoff.flush[slot].state == expected_state,
		'published failures must retain their handoff slot and unpublished failures must roll back'
	if mode in [2, 3, 4, 6, 9, 13, 14, 15, 17]! { assert manager.state == .error }
	if mode in [5, 16]! { assert manager.state == .stopped }
	if mode in [13, 14, 15, 17]! {
		timer.on_tick(fn () {})
		assert manager.channels.fw_ctrl.has_fault() && timer.get_ns() < u64(1_000_000_000)
	}
	if !published && mode != 7 { assert handoff.flush[slot].addr == 0 && handoff.flush[slot].size == 0 }
	for index, entry in handoff.flush {
		if u32(index) != slot { assert entry == mmu.UatFlushInfo{}, 'unrelated handoff owners must stay untouched' }
	}
	if published && !success {
		manager.state = .running
		before := manager.sends
		assert !manager.flush_g13_uat_range(slot, address, size)
		assert manager.sends == before && handoff.flush[slot].state == expected_state,
			'a published failure must block reuse until firmware or shutdown resolves it'
	}
	// Reset the fixture's simulated firmware before testing a fresh request.
	// Production deliberately cannot recycle a timed-out published slot.
	handoff.flush[slot] = mmu.UatFlushInfo{}
	header = channel.FwCtlRingHeader{}
	manager.channels.fw_ctrl = channel.new_fwctl_tx_channel('fwctl', 1, u64(&header), 1, u64(&ring), 256, 20)
	manager.state = .running; manager.mode = 1; manager.acknowledged = false
	table.handoff_initialized = true
	if mode != 12 {
		timer.reset()
		timer.on_tick(poll_callback)
		assert manager.flush_g13_uat_range(slot, address, size),
			'UAT success requires both its ring token and completed handoff'
		assert !manager.fwctl_lock.is_held()
	}
	active = unsafe { nil }; uat_mgr = unsafe { nil }; timer.on_tick(fn () {})
}

fn validation_case(invalid int, outer_lock bool) {
	mut handoff := mmu.UatHandoff{}
	mut table := mmu.UatManager{handoff: &handoff, handoff_initialized: true}
	uat_mgr = unsafe { &table }
	mut header := channel.FwCtlRingHeader{}
	mut ring := [256]fw.FwFwCtlMsg{}
	mut manager := GpuManager{
		state: match invalid { 0 { .idle } 1 { .starting } 2 { .error } 3 { .stopped } else { .running } }
		hw_config: hw.HwConfig{gpu_gen: if invalid == 4 { .g17 } else { .g13 }}
		channels: GpuChannels{fw_ctrl: channel.new_fwctl_tx_channel('validation', 1, u64(&header), 1, u64(&ring), 256, 20)}
		slot: 3
		mode: 3
	}
	active = unsafe { &manager }; timer.reset(); timer.on_tick(poll_callback)
	if invalid == 5 { uat_mgr = unsafe { nil } }
	slot := if invalid == 6 { u32(65) } else if invalid == 7 { ~u32(0) } else { u32(3) }
	address := if invalid == 8 { u64(0x10001) } else { u64(0x10000) }
	size := match invalid { 9 { u64(0) } 10 { u64(1) } 11 { u64(0x4001) } else { u64(0x4000) } }
	state := manager.state
	if outer_lock { manager.lock.acquire() }
	assert !manager.flush_g13_uat_range(slot, address, size)
	assert !manager.fwctl_lock.is_held() && manager.lock.is_held() == outer_lock
	assert manager.state == state && manager.sends == 0 && header.write_ptr == 0,
		'invalid UAT requests must not reserve, publish or mutate device state'
	for entry in handoff.flush { assert entry == mmu.UatFlushInfo{} }
	if outer_lock { manager.lock.release() }
	active = unsafe { nil }; uat_mgr = unsafe { nil }; timer.on_tick(fn () {})
}

pub fn check_uat_flush() {
	mut cases := 0
	for initial in [u32(0), 254, 255]! {
		for slot in [u32(0), 1, 63, 64]! {
			for mode in 0 .. 18 {
				for outer_lock in [false, true]! { run_case(initial, slot, mode, outer_lock, 2); cases++ }
			}
		}
	}
	assert cases == 432
	for invalid in 0 .. 12 { for outer_lock in [false, true]! { validation_case(invalid, outer_lock) } }
	println('AGX UAT flush: 432 transport and handoff cases cover wrap, completion faults, ownership retention and lock release')
	println('AGX UAT flush: 24 invalid requests preserve ring, handoff, device state and caller locks')
	for pages in [u64(1), 3, 0xffff, 0x10000, 0x10001]! {
		run_case(255, mmu.uat_kernel_flush_slot, 0, true, pages)
	}
	println('AGX UAT flush: 5 page-count boundaries preserve the full handoff range')
	check_kernel_teardown()
}
