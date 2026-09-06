module power

// Native Apple DeviceTree validation plus dormant wrapper and ApplePTD
// transports for the T6050 GPU power path. Actual PMP transitions remain
// disabled until PMP service integration and the firmware handoff are
// implemented.

import devicetree
import aarch64.kio
import aarch64.timer
import apple.dart
import klock
import memory

const pmgr_device_record_size = u32(48)
const pmgr_device_flags_offset = u32(0)
const pmgr_device_selector_offset = u32(3)
const pmgr_device_virtual_class_offset = u32(15)
const pmgr_device_handle_offset = u32(26)
const pmgr_device_name_offset = u32(32)
const pmgr_device_name_size = u32(16)
const pmp_ptd_record_size = u32(32)
const pmp_ptd_name_offset = u32(16)
const pmp_ptd_name_size = u32(16)
const t6050_ptd_reg_index = 7
const t6050_ptd_base = u64(0x84240000)
const t6050_ptd_size = u64(0x40000)
const t6050_die_stride = u64(0x4000000000)
const t6050_ptd_read_stride = u64(16)
const t6050_ptd_write_base = u64(0x10000)
const t6050_ptd_write_stride = u64(8)
const t6050_ptd_new_data = u64(1) << 54
const t6050_agx_record_index = u32(15)
const t6050_agx_request_entry = u32(0x1e0)
const t6050_agx_ack_entry = u32(0x1e8)
const t6050_pmp_status_entry = u32(1)
const t6050_agx_ack_timeout_us = u64(15_000_000)
const t6050_wrapper_cpu_control_offset = u64(0x44)
const t6050_wrapper_cpu_run = u32(1) << 4
const t6050_wrapper_cpu_stop_phase2 = u32(1) << 5
const t6050_wrapper_iorvbar_lock = u64(1)
const t6050_pmp_region_base = u64(0x284500000)
const t6050_pmp_region_size = u64(0x100000)
const t6050_pmp_segment_record_size = u32(32)
const t6050_pmp_text_iova = u64(0x1000000)
const t6050_pmp_text_size = u32(0x5e000)
const t6050_pmp_text_flags = u32(3)
const t6050_pmp_data_iova = u64(0x105e000)
const t6050_pmp_data_size = u32(0x9a000)
const t6050_pmp_data_flags = u32(6)

// ApplePTD returns one 16-byte pair. The second word is not the raw MMIO word:
// readPTD shifts its payload and retains the caller-provided byte at +0xf.
pub struct T6050PtdEntry {
pub:
	data     u64
	metadata u64
}

// This low-level transport intentionally has no internal spinlock. A complete
// owner must serialize the request read-modify-write and acknowledgement state
// machine without holding Vinix's interrupt-disabling spinlock while polling.
pub struct T6050PtdTransport {
pub:
	die_bases [2]u64
	die_count u32
}

// Device-memory resources owned by one AppleASCWrapV6 instance. reg[0] is
// the mailbox/control aperture and reg[1] is the IORVBAR aperture. reg[2]
// remains deliberately unmapped because its consumer has not been recovered.
pub struct T6050PmpWrapper {
pub:
	die          u32
	control_base u64
	iorvbar_base u64
mut:
	lock klock.Lock
}

pub struct T6050PmpWrapperState {
pub:
	iorvbar    u64
	cpu_control u32
}

pub fn (state &T6050PmpWrapperState) iorvbar_locked() bool {
	return state.iorvbar & t6050_wrapper_iorvbar_lock != 0
}

pub fn (state &T6050PmpWrapperState) cpu_running() bool {
	return state.cpu_control & t6050_wrapper_cpu_run != 0
}

pub struct T6050PmpSegment {
pub:
	physical u64
	iova     u64
	remap    u64
	size     u32
	flags    u32
}

// AppleA7IOP::_dartMapiBootFirmware skips records with flag bit 1. Such a
// record describes a translation already installed by iBoot; it must never be
// inserted again or treated as a page-table root owned by Vinix.
pub fn (segment &T6050PmpSegment) is_iboot_owned_mapping() bool {
	return segment.flags & u32(1 << 1) != 0
}

pub fn (segment &T6050PmpSegment) requires_mapper_insert() bool {
	return !segment.is_iboot_owned_mapping()
}

// iBoot supplies these two virtually contiguous firmware mappings on every
// active die. Keeping their address domains explicit prevents an IOP virtual
// address from being used as an AP physical address during later attachment.
pub struct T6050PmpPreload {
pub:
	die         u32
	region_base u64
	region_size u64
	segments    [2]T6050PmpSegment
}

enum T6050PowerPhase {
	idle
	waiting_for_ack
	faulted
}

pub enum T6050PowerResult {
	idle
	pending
	completed
	published_pre_ready
	busy
	transport_error
	timed_out
	faulted
}

// One controller owns both die apertures and admits only one outstanding
// read-modify-write transaction. Its lock is held for individual MMIO steps,
// never for the acknowledgement interval between poll() calls.
pub struct T6050PowerController {
mut:
	transport   T6050PtdTransport
	lock        klock.Lock
	phase       T6050PowerPhase
	pending_die u32
	request     u64
	started_us  u64
}

pub fn decode_t6050_ptd_entry(data u64, raw_metadata u64, caller_tag u8) T6050PtdEntry {
	metadata := (raw_metadata >> 10) | (((raw_metadata >> 1) & 1) << 54)
		| ((raw_metadata & 1) << 55) | (u64(caller_tag) << 56)
	return T6050PtdEntry{
		data: data
		metadata: metadata
	}
}

pub fn (entry &T6050PtdEntry) has_new_data() bool {
	return entry.metadata & t6050_ptd_new_data != 0
}

pub fn (entry &T6050PtdEntry) matches_request(request u64, mask u64) bool {
	return entry.has_new_data() && (entry.data ^ request) & mask == 0
}

pub fn t6050_agx_request_value(current u64, enabled bool) u64 {
	mask := u64(1) << t6050_agx_record_index
	return if enabled { current | mask } else { current & ~mask }
}

pub fn t6050_agx_acknowledged(entry &T6050PtdEntry, request u64) bool {
	return entry.matches_request(request, u64(1) << t6050_agx_record_index)
}

pub fn t6050_iorvbar_value(firmware_address u64) u64 {
	return firmware_address | t6050_wrapper_iorvbar_lock
}

pub fn t6050_iorvbar_matches(value u64, firmware_address u64) bool {
	return firmware_address != 0
		&& firmware_address & t6050_wrapper_iorvbar_lock == 0
		&& value == t6050_iorvbar_value(firmware_address)
}

pub fn t6050_cpu_run_value(current u32) u32 {
	return current | t6050_wrapper_cpu_run
}

pub fn t6050_cpu_stop_request_value(current u32) u32 {
	return current & ~t6050_wrapper_cpu_run
}

pub fn t6050_cpu_stop_finalize_value(current u32) u32 {
	return current & ~t6050_wrapper_cpu_stop_phase2
}

fn decode_t6050_pmp_preload(node &devicetree.DTNode, die u32) ?T6050PmpPreload {
	if die >= 2 || !native_string_property_equals(node, 'segment-names',
		'__TEXT;__DATA') {
		return none
	}
	ranges := devicetree.get_property(node, 'segment-ranges') or { return none }
	if ranges.len != 2 * t6050_pmp_segment_record_size {
		return none
	}
	base := t6050_pmp_region_base + u64(die) * t6050_die_stride
	text := T6050PmpSegment{
		physical: read_native_u64(ranges.data, 0)
		iova: read_native_u64(ranges.data, 8)
		remap: read_native_u64(ranges.data, 16)
		size: read_native_u32(ranges.data, 24)
		flags: read_native_u32(ranges.data, 28)
	}
	data := T6050PmpSegment{
		physical: read_native_u64(ranges.data, t6050_pmp_segment_record_size)
		iova: read_native_u64(ranges.data, t6050_pmp_segment_record_size + 8)
		remap: read_native_u64(ranges.data, t6050_pmp_segment_record_size + 16)
		size: read_native_u32(ranges.data, t6050_pmp_segment_record_size + 24)
		flags: read_native_u32(ranges.data, t6050_pmp_segment_record_size + 28)
	}
	if text.physical != base || text.iova != t6050_pmp_text_iova
		|| text.remap != base || text.size != t6050_pmp_text_size
		|| text.flags != t6050_pmp_text_flags
		|| data.physical != base + u64(t6050_pmp_text_size)
		|| data.iova != t6050_pmp_data_iova
		|| data.remap != base + u64(t6050_pmp_text_size)
		|| data.size != t6050_pmp_data_size || data.flags != t6050_pmp_data_flags
		|| !text.is_iboot_owned_mapping() || !data.is_iboot_owned_mapping()
		|| text.requires_mapper_insert() || data.requires_mapper_insert()
		|| u64(text.size) + u64(data.size) != 0xf8000 {
		return none
	}
	return T6050PmpPreload{
		die: die
		region_base: base
		region_size: t6050_pmp_region_size
		segments: [text, data]!
	}
}

// Resolve the iBoot-owned firmware map from the RTBuddy nub without mapping or
// reading its physical pages. This is an attachment descriptor, not readiness.
pub fn get_t6050_pmp_preload(die u32) ?T6050PmpPreload {
	path := if die == 0 {
		'/arm-io/pmp0/iop-pmp0-nub'
	} else if die == 1 {
		'/arm-io/pmp1/iop-pmp1-nub'
	} else {
		return none
	}
	nub := devicetree.find_node(path) or { return none }
	preload := decode_t6050_pmp_preload(nub, die) or { return none }
	region_base := devicetree.get_le_u64(nub, 'region-base') or { return none }
	region_size := devicetree.get_le_u64(nub, 'region-size') or { return none }
	if region_base != preload.region_base || region_size != preload.region_size {
		return none
	}
	return preload
}

fn t6050_ptd_offset(entry u32, base u64, stride u64, width u64) ?u64 {
	offset := base + u64(entry) * stride
	if width > t6050_ptd_size || offset > t6050_ptd_size - width {
		return none
	}
	return offset
}

fn t6050_active_die_count() ?u32 {
	arm_io := devicetree.find_node('/arm-io') or { return none }
	die_count := devicetree.get_le_u32(arm_io, 'die-count') or { return none }
	if die_count == 0 || die_count > 2 {
		return none
	}
	return die_count
}

// Constructing this maps only active die apertures as Device-nGnRnE. The
// signed tree may contain an inactive die-1 template on a one-die M5 Max.
// Keep the call behind the G17 boot gate until the complete owner exists.
fn map_t6050_ptd_transport(die_count u32) ?T6050PtdTransport {
	if die_count == 0 || die_count > 2 {
		return none
	}
	die0 := memory.map_mmio(t6050_ptd_base, t6050_ptd_size)
	mut die1 := u64(0)
	if die_count == 2 {
		die1 = memory.map_mmio(t6050_ptd_base + t6050_die_stride, t6050_ptd_size)
	}
	if die0 == 0 || (die_count == 2 && die1 == 0) {
		return none
	}
	return T6050PtdTransport{
		die_bases: [u64(die0), die1]!
		die_count: die_count
	}
}

// Mapping is a separate, explicit construction step so read-only T6050 probe
// validation cannot accidentally access ApplePTD.
pub fn map_t6050_power_controller() ?T6050PowerController {
	die_count := t6050_active_die_count() or { return none }
	transport := map_t6050_ptd_transport(die_count) or { return none }
	return T6050PowerController{
		transport: transport
		phase: .idle
	}
}

// Map the two resources whose consumers and access widths are proven by the
// T6050 AppleASCWrapV6 binary. Construction performs no register access and is
// intentionally not part of the GPU probe until the PMP firmware image owner
// and RTBuddy state machine are implemented.
pub fn map_t6050_pmp_wrapper(die u32) ?T6050PmpWrapper {
	path := if die == 0 {
		'/arm-io/pmp0'
	} else if die == 1 {
		'/arm-io/pmp1'
	} else {
		return none
	}
	wrapper := devicetree.find_node(path) or { return none }
	if !validate_pmp_wrapper(wrapper, die) {
		return none
	}
	regions := devicetree.get_translated_reg_ranges(wrapper) or { return none }
	control_base := memory.map_mmio(regions[0].base, regions[0].size)
	iorvbar_base := memory.map_mmio(regions[1].base, regions[1].size)
	if control_base == 0 || iorvbar_base == 0 {
		return none
	}
	return T6050PmpWrapper{
		die: die
		control_base: control_base
		iorvbar_base: iorvbar_base
	}
}

// Program the firmware address and its hardware lock in one 64-bit access,
// then verify the lock bit exactly as AppleASCWrapV6::_isIORVBARLocked does.
// A physical firmware base must leave the hardware-owned lock bit clear.
pub fn (mut wrapper T6050PmpWrapper) set_iorvbar(firmware_address u64) bool {
	if wrapper.iorvbar_base == 0 || firmware_address == 0
		|| firmware_address & t6050_wrapper_iorvbar_lock != 0 {
		return false
	}
	wrapper.lock.acquire()
	defer {
		wrapper.lock.release()
	}
	address := unsafe { &u64(wrapper.iorvbar_base) }
	current := kio.mmin(address)
	if current & t6050_wrapper_iorvbar_lock != 0 {
		// Hardware makes this write-once. Accept only an exact idempotent
		// request and never attempt to replace an inherited iBoot value.
		return t6050_iorvbar_matches(current, firmware_address)
	}
	kio.mmout(address, t6050_iorvbar_value(firmware_address))
	return t6050_iorvbar_matches(kio.mmin(address), firmware_address)
}

// Read both inherited wrapper registers under one lock. Hardware bring-up can
// use this before any run-state transition; it performs no writes and assigns
// no ownership to an iBoot-preloaded firmware image.
pub fn (mut wrapper T6050PmpWrapper) snapshot() ?T6050PmpWrapperState {
	if wrapper.control_base == 0 || wrapper.iorvbar_base == 0 {
		return none
	}
	wrapper.lock.acquire()
	defer {
		wrapper.lock.release()
	}
	return T6050PmpWrapperState{
		iorvbar: kio.mmin(unsafe { &u64(wrapper.iorvbar_base) })
		cpu_control: kio.mmin32(unsafe { &u32(wrapper.control_base +
			t6050_wrapper_cpu_control_offset) })
	}
}

pub fn (mut wrapper T6050PmpWrapper) is_iorvbar_locked() bool {
	if wrapper.iorvbar_base == 0 {
		return false
	}
	wrapper.lock.acquire()
	defer {
		wrapper.lock.release()
	}
	value := kio.mmin(unsafe { &u64(wrapper.iorvbar_base) })
	return value & t6050_wrapper_iorvbar_lock != 0
}

// AppleASCWrapV6 performs a 32-bit read-modify-write at reg[0]+0x44. Preserve
// every unrelated bit rather than treating this as a command register.
pub fn (mut wrapper T6050PmpWrapper) start_cpu() bool {
	if wrapper.control_base == 0 {
		return false
	}
	wrapper.lock.acquire()
	defer {
		wrapper.lock.release()
	}
	address := unsafe { &u32(wrapper.control_base + t6050_wrapper_cpu_control_offset) }
	current := kio.mmin32(address)
	kio.mmout32(address, t6050_cpu_run_value(current))
	return true
}

// Stopping is two distinct hardware phases: clear bit 4, reread the register,
// then clear bit 5 in the new value. Do not combine the accesses.
pub fn (mut wrapper T6050PmpWrapper) stop_cpu() bool {
	if wrapper.control_base == 0 {
		return false
	}
	wrapper.lock.acquire()
	defer {
		wrapper.lock.release()
	}
	address := unsafe { &u32(wrapper.control_base + t6050_wrapper_cpu_control_offset) }
	current := kio.mmin32(address)
	kio.mmout32(address, t6050_cpu_stop_request_value(current))
	refreshed := kio.mmin32(address)
	kio.mmout32(address, t6050_cpu_stop_finalize_value(refreshed))
	return true
}

// Match ApplePTD::readPTD's single LDP from base + entry*16. Device memory
// supplies ordering; the memory clobber prevents compiler reordering.
pub fn (transport &T6050PtdTransport) read(die u32, entry u32,
	caller_tag u8) ?T6050PtdEntry {
	if die >= transport.die_count {
		return none
	}
	offset := t6050_ptd_offset(entry, 0, t6050_ptd_read_stride, 16) or { return none }
	address := unsafe { &u64(transport.die_bases[die] + offset) }
	mut data := u64(0)
	mut raw_metadata := u64(0)
	asm volatile aarch64 {
		ldp data, raw_metadata, [address]
		; =r (data)
		  =r (raw_metadata)
		; r (address)
		; memory
	}
	return decode_t6050_ptd_entry(data, raw_metadata, caller_tag)
}

// Match ApplePTD::writePTD's distinct base + 0x10000 + entry*8 portal.
pub fn (transport &T6050PtdTransport) write(die u32, entry u32, value u64) bool {
	if die >= transport.die_count {
		return false
	}
	offset := t6050_ptd_offset(entry, t6050_ptd_write_base, t6050_ptd_write_stride,
		8) or { return false }
	address := unsafe { &u64(transport.die_bases[die] + offset) }
	asm volatile aarch64 {
		str value, [address]
		; ; r (address)
		  r (value)
		; memory
	}
	return true
}

// Publish an AGX level request. A pre-ready PMP deliberately completes here
// without reading PS-ACK; otherwise poll() owns acknowledgement completion.
pub fn (mut controller T6050PowerController) begin(die u32,
	enabled bool) T6050PowerResult {
	if die >= controller.transport.die_count {
		return .transport_error
	}
	controller.lock.acquire()
	defer {
		controller.lock.release()
	}
	if controller.phase == .waiting_for_ack {
		return .busy
	}
	if controller.phase == .faulted {
		return .faulted
	}
	current := controller.transport.read(die, t6050_agx_request_entry, 0) or {
		return .transport_error
	}
	request := t6050_agx_request_value(current.data, enabled)
	if !controller.transport.write(die, t6050_agx_request_entry, request) {
		controller.phase = .faulted
		return .transport_error
	}
	controller.started_us = timer.get_us()
	status := controller.transport.read(die, t6050_pmp_status_entry, 0) or {
		controller.phase = .faulted
		return .transport_error
	}
	if status.data == 0 {
		return .published_pre_ready
	}
	controller.pending_die = die
	controller.request = request
	controller.phase = .waiting_for_ack
	return .pending
}

// Advance one nonblocking acknowledgement step. A timeout or transport error
// is sticky because the request may already have reached PMP; reconstruction
// of the controller is the only recovery until a reset protocol is recovered.
pub fn (mut controller T6050PowerController) poll() T6050PowerResult {
	controller.lock.acquire()
	defer {
		controller.lock.release()
	}
	if controller.phase == .idle {
		return .idle
	}
	if controller.phase == .faulted {
		return .faulted
	}
	ack := controller.transport.read(controller.pending_die, t6050_agx_ack_entry,
		0) or {
		controller.phase = .faulted
		return .transport_error
	}
	if t6050_agx_acknowledged(&ack, controller.request) {
		controller.phase = .idle
		return .completed
	}
	if timer.get_us() - controller.started_us >= t6050_agx_ack_timeout_us {
		controller.phase = .faulted
		return .timed_out
	}
	return .pending
}

fn validate_t6050_ptd_codec() bool {
	decoded := decode_t6050_ptd_entry(0x1234, (u64(0x155) << 10) | 3, 0xa5)
	expected_metadata := (u64(0xa5) << 56) | (u64(3) << 54) | 0x155
	request_on := t6050_agx_request_value(0, true)
	request_off := t6050_agx_request_value(request_on, false)
	status_offset := t6050_ptd_offset(t6050_pmp_status_entry, 0,
		t6050_ptd_read_stride, 16) or { return false }
	request_write_offset := t6050_ptd_offset(t6050_agx_request_entry,
		t6050_ptd_write_base, t6050_ptd_write_stride, 8) or { return false }
	ack_read_offset := t6050_ptd_offset(t6050_agx_ack_entry, 0,
		t6050_ptd_read_stride, 16) or { return false }
	ack := T6050PtdEntry{
		data: request_on
		metadata: t6050_ptd_new_data
	}
	// Exercise the bounds-failure path so the dormant MMIO methods remain in
	// the generated C/assembly without touching an aperture during validation.
	unmapped := T6050PtdTransport{
		die_bases: [u64(0), 0]!
	}
	if unmapped.write(2, 0, 0) {
		return false
	}
	if _ := unmapped.read(2, 0, 0) {
		return false
	}
	one_die := T6050PtdTransport{
		die_bases: [u64(0), 0]!
		die_count: 1
	}
	if one_die.write(1, 0, 0) {
		return false
	}
	if _ := one_die.read(1, 0, 0) {
		return false
	}
	mut controller := T6050PowerController{
		transport: unmapped
		phase: .idle
	}
	if controller.begin(2, true) != .transport_error || controller.poll() != .idle {
		return false
	}
	return sizeof(T6050PtdEntry) == 16 && decoded.data == 0x1234
		&& decoded.metadata == expected_metadata
		&& request_on == u64(1) << t6050_agx_record_index && request_off == 0
		&& t6050_agx_acknowledged(&ack, request_on)
		&& !t6050_agx_acknowledged(&ack, request_off)
		&& status_offset == 16 && request_write_offset == 0x10f00
		&& ack_read_offset == 0x1e80
}

fn validate_t6050_wrapper_codec() bool {
	firmware_address := u64(0x284500000)
	control := u32(0xa5a55a65)
	running := t6050_cpu_run_value(control)
	stop_requested := t6050_cpu_stop_request_value(running)
	stop_finalized := t6050_cpu_stop_finalize_value(stop_requested)
	// Exercise the rejected-input path without accessing the zero MMIO bases.
	// This keeps the concrete IORVBAR writer reachable in generated code while
	// read-only admission validation remains side-effect free.
	mut unmapped := T6050PmpWrapper{}
	if _ := map_t6050_pmp_wrapper(2) {
		return false
	}
	if unmapped.set_iorvbar(0) || unmapped.is_iorvbar_locked()
		|| unmapped.start_cpu() || unmapped.stop_cpu() {
		return false
	}
	if _ := unmapped.snapshot() {
		return false
	}
	state := T6050PmpWrapperState{
		iorvbar: t6050_iorvbar_value(firmware_address)
		cpu_control: running
	}
	return t6050_iorvbar_value(firmware_address) == 0x284500001
		&& t6050_iorvbar_matches(state.iorvbar, firmware_address)
		&& !t6050_iorvbar_matches(state.iorvbar, firmware_address + 0x4000)
		&& state.iorvbar_locked() && state.cpu_running()
		&& running == 0xa5a55a75 && stop_requested == 0xa5a55a65
		&& stop_finalized == 0xa5a55a45
}

fn read_native_u8(data voidptr, offset u32) u8 {
	value := unsafe { &u8(u64(data) + offset) }
	return unsafe { value[0] }
}

fn read_native_u16(data voidptr, offset u32) u16 {
	value := unsafe { &u8(u64(data) + offset) }
	return unsafe { u16(value[0]) | (u16(value[1]) << 8) }
}

fn read_native_u32(data voidptr, offset u32) u32 {
	value := unsafe { &u8(u64(data) + offset) }
	return unsafe {
		u32(value[0]) | (u32(value[1]) << 8) | (u32(value[2]) << 16) |
			(u32(value[3]) << 24)
	}
}

fn read_native_u64(data voidptr, offset u32) u64 {
	return u64(read_native_u32(data, offset))
		| (u64(read_native_u32(data, offset + 4)) << 32)
}

fn native_string_property_equals(node &devicetree.DTNode, property string,
	expected string) bool {
	value := devicetree.get_property(node, property) or { return false }
	if value.len != u32(expected.len + 1) {
		return false
	}
	bytes := unsafe { &u8(value.data) }
	for index := 0; index < expected.len; index++ {
		if unsafe { bytes[index] } != expected[index] {
			return false
		}
	}
	return unsafe { bytes[expected.len] } == 0
}

fn fixed_native_name_matches(data voidptr, size u32, expected string) bool {
	if expected.len >= int(size) {
		return false
	}
	value := unsafe { &u8(data) }
	for index := 0; index < expected.len; index++ {
		if unsafe { value[index] } != expected[index] {
			return false
		}
	}
	return unsafe { value[expected.len] } == 0
}

fn node_string_contains(node &devicetree.DTNode, property string, expected string) bool {
	values := devicetree.get_string_list(node, property) or { return false }
	for value in values {
		if value == expected {
			return true
		}
	}
	return false
}

fn native_properties_equal(left &devicetree.DTNode, right &devicetree.DTNode,
	property string) bool {
	left_value := devicetree.get_property(left, property) or { return false }
	right_value := devicetree.get_property(right, property) or { return false }
	if left_value.len != right_value.len {
		return false
	}
	left_bytes := unsafe { &u8(left_value.data) }
	right_bytes := unsafe { &u8(right_value.data) }
	for index := u32(0); index < left_value.len; index++ {
		if unsafe { left_bytes[index] } != unsafe { right_bytes[index] } {
			return false
		}
	}
	return true
}

fn find_native_asc_node(role u32) ?&devicetree.DTNode {
	name := if role == 0 { 'gfx-asc' } else { 'gfx1-asc' }
	if node := devicetree.find_node('/arm-io/${name}') {
		return node
	}
	if node := devicetree.find_node('/soc/${name}') {
		return node
	}
	return none
}

fn validate_gate_array(node &devicetree.DTNode, property string, expected []u32) bool {
	values := devicetree.get_le_u32_array(node, property) or {
		C.printf(c'agx: native node %s has malformed %s\n', node.name.str, property.str)
		return false
	}
	if values.len != expected.len {
		C.printf(c'agx: native node %s has unexpected %s count\n', node.name.str, property.str)
		return false
	}
	for index := 0; index < expected.len; index++ {
		if values[index] != expected[index] {
			C.printf(c'agx: native node %s has unexpected %s[%u]=0x%x\n', node.name.str,
				property.str, u32(index), values[index])
			return false
		}
	}
	return true
}

fn validate_u32_array(node &devicetree.DTNode, property string, expected []u32) bool {
	values := devicetree.get_le_u32_array(node, property) or {
		C.printf(c'agx: native node %s has malformed %s\n', node.name.str, property.str)
		return false
	}
	if values.len != expected.len {
		C.printf(c'agx: native node %s has unexpected %s count\n', node.name.str, property.str)
		return false
	}
	for index := 0; index < expected.len; index++ {
		if values[index] != expected[index] {
			C.printf(c'agx: native node %s has unexpected %s[%u]=0x%x\n', node.name.str,
				property.str, u32(index), values[index])
			return false
		}
	}
	return true
}

// Apple DeviceTree gate values are public u16 handles at +0x1a in PMGR's
// 48-byte device records. They are not MMIO offsets. Require one exact name
// match so an OS/device-tree change cannot turn a handle into a raw write.
fn validate_pmgr_device(pmgr_node &devicetree.DTNode, handle u16,
	expected_name string, expected_index u32, expected_flags u8, expected_selector u8,
	expected_virtual_class u8) bool {
	devices := devicetree.get_property(pmgr_node, 'devices') or {
		println('agx: t6050 PMGR has no device table')
		return false
	}
	if devices.len == 0 || devices.len % pmgr_device_record_size != 0 {
		println('agx: t6050 PMGR device table is malformed')
		return false
	}
	mut matches := u32(0)
	for record := u32(0); record < devices.len; record += pmgr_device_record_size {
		if read_native_u16(devices.data, record + pmgr_device_handle_offset) != handle {
			continue
		}
		name := unsafe { voidptr(u64(devices.data) + record + pmgr_device_name_offset) }
		if !fixed_native_name_matches(name, pmgr_device_name_size, expected_name) {
			C.printf(c'agx: t6050 PMGR handle 0x%x has an unexpected device name\n', u32(handle))
			return false
		}
		index := record / pmgr_device_record_size
		if index != expected_index
			|| read_native_u8(devices.data, record + pmgr_device_flags_offset) != expected_flags
			|| read_native_u8(devices.data, record + pmgr_device_selector_offset) != expected_selector
			|| read_native_u8(devices.data, record + pmgr_device_virtual_class_offset) != expected_virtual_class {
			C.printf(c'agx: t6050 PMGR device %s changed dispatch fields\n', expected_name.str)
			return false
		}
		matches++
	}
	if matches != 1 {
		C.printf(c'agx: t6050 PMGR handle 0x%x resolved %u times\n', u32(handle), matches)
		return false
	}
	return true
}

fn validate_ptd_range(nub &devicetree.DTNode, expected_name string,
	expected_id u32, expected_offset u32, expected_count u32, expected_doorbell u32) bool {
	ranges := devicetree.get_property(nub, 'ptd-range') or {
		println('agx: t6050 PMP has no PTD range table')
		return false
	}
	if ranges.len == 0 || ranges.len % pmp_ptd_record_size != 0 {
		println('agx: t6050 PMP PTD range table is malformed')
		return false
	}
	mut matches := u32(0)
	for record := u32(0); record < ranges.len; record += pmp_ptd_record_size {
		name := unsafe { voidptr(u64(ranges.data) + record + pmp_ptd_name_offset) }
		if !fixed_native_name_matches(name, pmp_ptd_name_size, expected_name) {
			continue
		}
		if read_native_u32(ranges.data, record) != expected_id
			|| read_native_u32(ranges.data, record + 4) != expected_offset
			|| read_native_u32(ranges.data, record + 8) != expected_count
			|| read_native_u32(ranges.data, record + 12) != expected_doorbell {
			C.printf(c'agx: t6050 PMP range %s changed layout\n', expected_name.str)
			return false
		}
		matches++
	}
	if matches != 1 {
		C.printf(c'agx: t6050 PMP range %s resolved %u times\n', expected_name.str, matches)
		return false
	}
	return true
}

fn validate_ptd_apertures(pmgr_node &devicetree.DTNode) bool {
	regions := devicetree.get_translated_reg_ranges(pmgr_node) or {
		println('agx: t6050 PMGR register table is malformed')
		return false
	}
	if regions.len != 60 {
		C.printf(c'agx: t6050 PMGR has %u register regions, expected 60\n', u32(regions.len))
		return false
	}
	ptd := regions[t6050_ptd_reg_index]
	if ptd.base != t6050_ptd_base || ptd.size != t6050_ptd_size {
		C.printf(c'agx: t6050 PTD reg[7] changed to 0x%llx+0x%llx\n', ptd.base,
			ptd.size)
		return false
	}
	die_stride := devicetree.get_le_u64(pmgr_node, 'die-stride') or {
		println('agx: t6050 PMGR has no die stride')
		return false
	}
	if die_stride != t6050_die_stride {
		C.printf(c'agx: t6050 PMGR die stride changed to 0x%llx\n', die_stride)
		return false
	}
	// AppleT6050PMGR maps this same RegMap entry once per die. Keep both
	// physical results explicit even though this validator performs no mapping.
	if ptd.base + die_stride != 0x4084240000 {
		println('agx: t6050 die-1 PTD aperture changed')
		return false
	}
	return true
}

fn validate_pmp_wrapper(wrapper &devicetree.DTNode, die u32) bool {
	if die >= 2 {
		return false
	}
	regions := devicetree.get_translated_reg_ranges(wrapper) or {
		println('agx: t6050 PMP wrapper register table is malformed')
		return false
	}
	if regions.len != 4 {
		C.printf(c'agx: t6050 PMP%u has %u wrapper registers, expected 4\n', die,
			u32(regions.len))
		return false
	}
	// AppleWrapperMailbox maps reg[0] as its mailbox/control Device-MMIO
	// aperture. AppleASCWrapV6 maps reg[1] as its 64-bit IORVBAR aperture,
	// while ApplePMPv2 independently resolves reg[3] as PTD-update memory.
	// Keep reg[2] unlabeled until its consumer is proven.
	bases := [u64(0x84e00000), 0x84850000, 0x84500000, 0x84250000]!
	sizes := [u64(0x88000), 0x4000, 0x100000, 0x4000]!
	die_offset := u64(die) * t6050_die_stride
	for index := 0; index < regions.len; index++ {
		if regions[index].base != bases[index] + die_offset
			|| regions[index].size != sizes[index] {
			C.printf(c'agx: t6050 PMP%u wrapper reg[%u] changed\n', die, u32(index))
			return false
		}
	}
	iop_version := devicetree.get_le_u32(wrapper, 'iop-version') or { return false }
	// ApplePMPv2 reads this property from the wrapper service and uses its
	// value in getDeviceMemoryWithIndex(), proving that reg[3] is the
	// PTD-update resource. This still says nothing about firmware readiness.
	ptd_update_reg_index := devicetree.get_le_u32(wrapper, 'ptd-update-reg-index') or {
		return false
	}
	// Despite its name, AppleA7IOP passes sram-index as the provider power
	// transition's domain selector; it is not a DeviceTree reg[] index.
	sram_power_domain := devicetree.get_le_u32(wrapper, 'sram-index') or { return false }
	if iop_version != 1 || ptd_update_reg_index != 3 || sram_power_domain != 1 {
		C.printf(c'agx: t6050 PMP%u wrapper control properties changed\n', die)
		return false
	}
	if die == 0 {
		return validate_u32_array(wrapper, 'interrupts', [u32(0x18d), 0x18c, 0x18f,
			0x18e])
			&& validate_gate_array(wrapper, 'power-gates', [u32(0x1b), 0x1c])
			&& validate_gate_array(wrapper, 'clock-gates', [u32(0x1b), 0x1c])
	}
	return validate_u32_array(wrapper, 'interrupts', [u32(0xdad), 0xdac, 0xdaf,
		0xdae])
		&& validate_gate_array(wrapper, 'power-gates', [u32(0x1000001b), 0x1000001c])
		&& validate_gate_array(wrapper, 'clock-gates', [u32(0x1000001b), 0x1000001c])
}

fn validate_t6050_pmp_instance(die u32) ?&devicetree.DTNode {
	wrapper_path := if die == 0 {
		'/arm-io/pmp0'
	} else if die == 1 {
		'/arm-io/pmp1'
	} else {
		return none
	}
	nub_path := if die == 0 {
		'/arm-io/pmp0/iop-pmp0-nub'
	} else {
		'/arm-io/pmp1/iop-pmp1-nub'
	}
	role := if die == 0 { 'PMP0' } else { 'PMP1' }
	wrapper := devicetree.find_node(wrapper_path) or { return none }
	nub := devicetree.find_node(nub_path) or { return none }
	if !node_string_contains(wrapper, 'compatible', 'iop,ascwrap-v6')
		|| !node_string_contains(wrapper, 'role', role)
		|| !node_string_contains(nub, 'compatible', 'iop-nub,rtbuddy-v2')
		|| !node_string_contains(nub, 'firmware-name', 't6050pmp')
		|| !validate_pmp_wrapper(wrapper, die) {
		return none
	}
	if _ := dart.get_t6050_pmp_dart_contract(die, wrapper) {
	} else {
		return none
	}
	preload := decode_t6050_pmp_preload(nub, die) or { return none }
	region_base := devicetree.get_le_u64(nub, 'region-base') or { return none }
	region_size := devicetree.get_le_u64(nub, 'region-size') or { return none }
	if region_base != preload.region_base || region_size != preload.region_size {
		return none
	}
	return nub
}

// Validate only the read-only ownership and transport contract here. Apple's
// initial synchronization can publish a persistent request before readiness,
// and Vinix has a serialized nonblocking controller for that transaction. The
// controller remains dormant until the firmware-side handoff owns its startup
// order. This function therefore performs no mapping or MMIO access.
pub fn validate_t6050_contract(gpu_node &devicetree.DTNode) bool {
	if !validate_t6050_ptd_codec() || !validate_t6050_wrapper_codec()
		|| !dart.validate_t8110_codec() {
		println('agx: internal t6050 PMP transport validation failed')
		return false
	}
	die_count := t6050_active_die_count() or {
		println('agx: native t6050 active die count is unavailable')
		return false
	}
	pmgr_node := devicetree.find_compatible('pmgr1,t6050') or {
		println('agx: native t6050 PMGR node not found')
		return false
	}
	gfx_asc := find_native_asc_node(0) or { return false }
	gfx1_asc := find_native_asc_node(1) or { return false }
	pmp0_nub := validate_t6050_pmp_instance(0) or {
		println('agx: native t6050 active PMP0 contract changed')
		return false
	}
	if die_count == 2 {
		pmp1_nub := validate_t6050_pmp_instance(1) or {
			println('agx: native t6050 active PMP1 contract changed')
			return false
		}
		if !native_properties_equal(pmp0_nub, pmp1_nub, 'soc-device')
			|| !native_properties_equal(pmp0_nub, pmp1_nub, 'ptd-range')
			|| !native_properties_equal(pmp0_nub, pmp1_nub, 'pm-ptd-ranges') {
			println('agx: native t6050 active PMP die contracts differ')
			return false
		}
	}
	pmp_version := devicetree.get_le_u32(pmgr_node, 'pmp') or {
		println('agx: t6050 PMGR has no PMP version')
		return false
	}
	if pmp_version != 2
		|| !validate_u32_array(pmgr_node, 'ptd-ranges', [u32(10), 11, 12, 13, 2, 4])
		|| !validate_ptd_apertures(pmgr_node) {
		println('agx: native t6050 ApplePTD ownership changed')
		return false
	}
	if !validate_gate_array(gpu_node, 'power-gates', [u32(0x268), 0x267])
		|| !validate_gate_array(gpu_node, 'clock-gates', [u32(0x268), 0x267])
		|| !validate_gate_array(gfx_asc, 'power-gates', [u32(0x266)])
		|| !validate_gate_array(gfx_asc, 'clock-gates', [u32(0x266)])
		|| !validate_gate_array(gfx1_asc, 'power-gates', [u32(0x291)])
		|| !validate_gate_array(gfx1_asc, 'clock-gates', [u32(0x291)]) {
		return false
	}
	if !validate_pmgr_device(pmgr_node, 0x268, 'GFX_SGX', 572, 0x10, 0, 0)
		|| !validate_pmgr_device(pmgr_node, 0x267, 'GFX_BUSY', 575, 0x10, 0, 0)
		|| !validate_pmgr_device(pmgr_node, 0x266, 'GFX_ASC', 573, 0x10, 0, 0)
		|| !validate_pmgr_device(pmgr_node, 0x291, 'GFX_ASC1', 574, 0x10, 0, 0)
		|| !validate_pmgr_device(pmgr_node, 0x16a, 'GFX', 357, 0x02, 0x10, 0) {
		return false
	}
	if !validate_ptd_range(pmp0_nub, 'PMP-STATUS', 2, 1, 1, 16)
		|| !validate_ptd_range(pmp0_nub, 'SOC-DEV-PKT', 9, 0x90, 0x150, 0)
		|| !validate_ptd_range(pmp0_nub, 'SOC-DEV-PS-REQ', 10, 0x1e0, 8, 0)
		|| !validate_ptd_range(pmp0_nub, 'SOC-DEV-PS-ACK', 11, 0x1e8, 8, 0)
		|| !validate_u32_array(pmp0_nub, 'pm-ptd-ranges', [u32(1), 2, 3, 4, 5, 6,
			7, 8, 40, 9, 10, 11, 12, 13, 14]) {
		return false
	}
	C.printf(c'agx: validated native t6050 PMP power ownership (%u active die(s), read-only)\n', die_count)
	return true
}
