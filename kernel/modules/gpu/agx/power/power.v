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
const t6050_pmp_ready_slot_absent = u32(0xff)
const t6050_pmp_die_slots = u32(2)
const t6050_interrupt_config_record_size = u32(20)
const t6050_interrupt_config_kind_offset = u32(3)
const t6050_interrupt_config_name_offset = u32(4)
const t6050_interrupt_config_name_size = u32(16)
const t6050_interrupt_config_max_bytes = u32(0x13f)
const t6050_interrupt_config_kind_limit = u8(0x10)
const t6050_pmp_ready_interrupt_name = 'PMP_STATUS'
const t6050_nub_preloaded_property = 'pre-loaded'
const t6050_nub_running_property = 'running'
const t6050_nub_no_firmware_service_property = 'no-firmware-service'
const t6050_nub_segment_ranges_property = 'segment-ranges'
const rtk_id_block_magic = u32(0x64697575) // 'uuid' in stored byte order
const rtk_id_block_size = u32(0x40)
const rtk_id_block_version_offset = u32(4)
const rtk_id_block_v4_offset = u32(0x20)
const rtk_id_block_v5_offset = u32(0x28)
const rtk_patchbay_header_size = u32(8)
const t6050_chosen_path = '/chosen'
// RTBuddyFirmware::copyIdBlock tries exactly these IOP-virtual offsets from
// the image base, in order, and takes the first that carries the magic and a
// supported version.
const t6050_rtk_id_candidates = [u32(0x20), 0xc0, 0x204, 0xc00, 0x1020, 0x1204,
	0x4020, 0x4204]
const t6050_pmgr_path = '/arm-io/pmgr'

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

// RTBuddy::getSegmentMap inverts DeviceTree flag bit 0 into RTBuddySegment's
// writable bit, so bit 0 set means read-only. This is a different bit from the
// iBoot-owned bit above and the two move independently: on T6050 __TEXT is
// `0x3` (iBoot-owned, read-only) and __DATA is `0x6` (iBoot-owned, writable).
pub fn (segment &T6050PmpSegment) is_writable() bool {
	return segment.flags & 1 == 0
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

// Where an address inside the preloaded image actually lives in memory.
pub struct T6050PmpImageAddress {
pub:
	physical u64
	writable bool
}

// Map an IOP virtual address inside the preloaded image to the physical
// address iBoot placed it at. Each segment carries its own physical base, so
// this never assumes the image is laid out contiguously, and the result is
// rejected unless the whole span stays inside both the segment and the
// declared region. This is the bridge from a located patchbay -- whose offsets
// are IOP virtual -- to memory Vinix could actually map.
pub fn (preload &T6050PmpPreload) resolve_iop_virtual(iop_virtual u64,
	size u32) ?T6050PmpImageAddress {
	if size == 0 {
		return none
	}
	for segment in preload.segments {
		if segment.size == 0 || iop_virtual < segment.iova {
			continue
		}
		offset := iop_virtual - segment.iova
		if offset >= u64(segment.size) || offset + u64(size) > u64(segment.size) {
			continue
		}
		physical := segment.physical + offset
		if physical < preload.region_base
			|| physical + u64(size) > preload.region_base + preload.region_size {
			return none
		}
		return T6050PmpImageAddress{
			physical: physical
			writable: segment.is_writable()
		}
	}
	return none
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
	not_ready
	busy
	transport_error
	timed_out
	faulted
}

// Where one mandatory patchbay input comes from. ApplePMPFirmware reads two
// nodes by path and takes the remaining four from the RTBuddy provider nub.
pub enum T6050PatchBayInputNode {
	chosen
	pmgr
	provider
}

// How the raw property becomes the published value.
pub enum T6050PatchBayInputDerivation {
	value
	pmc_pmgr_bit0
	pmc_pmgr_bit3
}

pub struct T6050PatchBayInput {
pub:
	tag        string
	property   string
	node       T6050PatchBayInputNode
	derivation T6050PatchBayInputDerivation
	// Only the two path-resolved nodes reject a property that is not exactly
	// four bytes; the provider reads take the first four bytes regardless.
	width_checked bool
}

pub struct T6050PatchBayValue {
pub:
	tag     u32
	value   u32
	present bool
}

// ApplePMPFirmware::patchFirmware writes all nine unconditionally, so an
// absent property publishes zero rather than leaving the firmware's own
// default in place. Keeping `present` separate lets a caller report that.
pub const t6050_patchbay_inputs = [
	T6050PatchBayInput{'BDID', 'board-id', .chosen, .value, true},
	T6050PatchBayInput{'DVID', 'dram-vendor-id', .chosen, .value, true},
	T6050PatchBayInput{'DCAP', 'dram-capacity', .provider, .value, false},
	T6050PatchBayInput{'DCHD', 'dram-channel-disable', .provider, .value, false},
	T6050PatchBayInput{'PMC_', 'pmc', .pmgr, .value, true},
	T6050PatchBayInput{'PMCV', 'pmc-pmgr', .pmgr, .pmc_pmgr_bit0, true},
	T6050PatchBayInput{'PMCB', 'pmc-pmgr', .pmgr, .pmc_pmgr_bit3, true},
	T6050PatchBayInput{'PMCX', 'pmc-msg-disabled', .provider, .value, false},
	T6050PatchBayInput{'CVAR', 'soc-chip-variant', .provider, .value, false},
]

// One located patchbay region inside an RTKit image. RTBuddy searches a fixed
// list of candidate IOP-virtual offsets for a `uuid` identity block and reads
// the region's offset and size out of it; the region is then aligned down to
// four bytes and the leftover becomes the first record's offset.
pub struct T6050PatchBayRegion {
pub:
	iop_virtual u64
	align_pad   u32
	size        u32
	padded_size u32
	// Set when the containing segment is writable, or when no segment claims
	// the address at all. writeBackPatchBay refuses to push a region without
	// it, so an edit to a non-writable region is silently lost.
	writable bool
}

// Rebuild a region with its writability decided. The region's own address is
// what determines which segment it lands in, so the flag can only be settled
// after the region has been decoded.
pub fn (region &T6050PatchBayRegion) with_writable(writable bool) T6050PatchBayRegion {
	return T6050PatchBayRegion{
		iop_virtual: region.iop_virtual
		align_pad: region.align_pad
		size: region.size
		padded_size: region.padded_size
		writable: writable
	}
}

// A host-side copy of one patchbay region. Apple never edits the target
// directly: the padded region is copied out once, edited in place, and pushed
// back only if it was writable and something actually changed.
pub struct T6050PatchBayCopy {
pub:
	region T6050PatchBayRegion
pub mut:
	data  []u8
	dirty bool
}

// One `{u32 tag, u32 length, u8 value[length]}` record. There is no padding
// between records, so a bad length silently reinterprets the whole tail; the
// walker therefore refuses any record that leaves the declared region.
pub struct T6050PatchBayRecord {
pub:
	tag    u32
	offset u32
	length u32
}

// Apple's fourcc constants spell the tag most-significant byte first, so a
// little-endian load of a record header compares equal to the constant
// directly and needs no swapping.
pub fn t6050_patchbay_tag(name string) ?u32 {
	if name.len != 4 {
		return none
	}
	return (u32(name[0]) << 24) | (u32(name[1]) << 16) | (u32(name[2]) << 8)
		| u32(name[3])
}

// The bytes a tag actually occupies in the image, which read as the printed
// spelling reversed. Searching an image for the literal characters of a tag
// name finds nothing; this is the spelling to look for.
pub fn t6050_patchbay_stored_bytes(tag u32) [4]u8 {
	return [u8(tag), u8(tag >> 8), u8(tag >> 16), u8(tag >> 24)]!
}

// Decode the patchbay region from a 0x40-byte RTKit identity block. Only
// versions 4 and 5 are accepted, matching `version & ~1 == 4`.
pub fn decode_t6050_patchbay_region(block voidptr, iop_virtual_base u64,
	writable bool) ?T6050PatchBayRegion {
	if read_native_u32(block, 0) != rtk_id_block_magic {
		return none
	}
	version := read_native_u32(block, rtk_id_block_version_offset)
	if version & ~u32(1) != 4 {
		return none
	}
	field := if version == 4 { rtk_id_block_v4_offset } else { rtk_id_block_v5_offset }
	offset := read_native_u32(block, field)
	size := read_native_u32(block, field + 4)
	if size == 0 {
		return none
	}
	unaligned := iop_virtual_base + u64(offset)
	pad := u32(unaligned & 3)
	return T6050PatchBayRegion{
		iop_virtual: unaligned & ~u64(3)
		align_pad: pad
		size: size
		padded_size: (pad + size + 3) & ~u32(3)
		writable: writable
	}
}

// Walk one record. `cursor` is relative to the aligned region base, so it
// starts at the region's alignment pad exactly as RTBuddyPatchBay does.
pub fn next_t6050_patchbay_record(data voidptr, region &T6050PatchBayRegion,
	cursor u32) ?T6050PatchBayRecord {
	end := region.align_pad + region.size
	if cursor < region.align_pad || cursor + rtk_patchbay_header_size > end {
		return none
	}
	length := read_native_u32(data, cursor + 4)
	if cursor + rtk_patchbay_header_size + length > end {
		return none
	}
	return T6050PatchBayRecord{
		tag: read_native_u32(data, cursor)
		offset: cursor
		length: length
	}
}

pub fn (record &T6050PatchBayRecord) next_cursor() u32 {
	return record.offset + rtk_patchbay_header_size + record.length
}

// Locate one tag. Returns none when the tag is absent or any record on the way
// is malformed, so a partially readable patchbay is never half-applied.
pub fn find_t6050_patchbay_tag(data voidptr, region &T6050PatchBayRegion,
	tag u32) ?T6050PatchBayRecord {
	mut cursor := region.align_pad
	end := region.align_pad + region.size
	for cursor + rtk_patchbay_header_size <= end {
		record := next_t6050_patchbay_record(data, region, cursor) or { return none }
		if record.tag == tag {
			return record
		}
		cursor = record.next_cursor()
	}
	return none
}

// Take the host-side copy of a located region. The copy spans the whole
// padded region because the write-back pushes all of it, not just the edited
// record.
pub fn copy_t6050_patchbay(data voidptr, region &T6050PatchBayRegion) ?T6050PatchBayCopy {
	if region.padded_size == 0 || region.align_pad + region.size > region.padded_size {
		return none
	}
	mut bytes := []u8{len: int(region.padded_size)}
	for index := u32(0); index < region.padded_size; index++ {
		bytes[index] = read_native_u8(data, index)
	}
	return T6050PatchBayCopy{
		region: *region
		data: bytes
		dirty: false
	}
}

// Edit one record in place. Apple treats a record whose length is not four as
// fatal rather than skipping it, so refuse instead of writing a partial value.
// The writable flag is deliberately not consulted here: Apple's writer does
// not check it either, and the region-level write-back is what enforces it.
pub fn (mut bay T6050PatchBayCopy) set_value(tag u32, value u32) bool {
	record := find_t6050_patchbay_tag(bay.data.data, &bay.region, tag) or {
		return false
	}
	if record.length != 4 {
		return false
	}
	offset := record.offset + rtk_patchbay_header_size
	bay.data[offset] = u8(value)
	bay.data[offset + 1] = u8(value >> 8)
	bay.data[offset + 2] = u8(value >> 16)
	bay.data[offset + 3] = u8(value >> 24)
	bay.dirty = true
	return true
}

// Apply the resolved DeviceTree inputs. Every tag must already exist as a
// 32-bit record; an image missing one is a different image, not a partially
// patchable one, so nothing is written unless all of them resolve first.
pub fn (mut bay T6050PatchBayCopy) apply_values(values []T6050PatchBayValue) bool {
	for value in values {
		record := find_t6050_patchbay_tag(bay.data.data, &bay.region, value.tag) or {
			return false
		}
		if record.length != 4 {
			return false
		}
	}
	for value in values {
		if !bay.set_value(value.tag, value.value) {
			return false
		}
	}
	return true
}

// Push the edited region back. Apple copies the whole region with 32-bit
// stores, which is why the located region is aligned down and padded up, and
// it writes nothing unless the region is writable and something changed.
// `destination` is the mapped read-write target of region.iop_virtual.
pub fn (bay &T6050PatchBayCopy) write_back(destination voidptr) bool {
	if !bay.region.writable || !bay.dirty {
		return false
	}
	if bay.region.padded_size & 3 != 0 || u64(destination) & 3 != 0 {
		return false
	}
	if bay.data.len != int(bay.region.padded_size) {
		return false
	}
	for offset := u32(0); offset < bay.region.padded_size; offset += 4 {
		word := read_native_u32(bay.data.data, offset)
		target := unsafe { &u32(u64(destination) + offset) }
		unsafe {
			*target = word
		}
	}
	return true
}

// Which firmware image an RTBuddy target adopts. RTBuddy::_attemptFirmwareLoad
// only bypasses its firmware service when the nub declares itself already
// `running` or opts out with `no-firmware-service`; `pre-loaded` alone is the
// second gate and never reaches that test on its own.
pub enum T6050PmpFirmwareSource {
	await_firmware_service
	service_firmware
	preload
}

// The two iBoot ownership questions are distinct and must not be conflated.
// `segment-ranges` makes AppleA7IOP::_hasiBootFirmware true, which only marks
// the DART records as iBoot-installed; it says nothing about whether the image
// itself is inherited.
pub struct T6050PmpFirmwareOwnership {
pub:
	source                T6050PmpFirmwareSource
	iboot_mapped_segments bool
	preloaded             bool
	running               bool
	no_firmware_service   bool
}

// True when RTBuddy would skip waiting for an RTBuddyFirmwareService.
pub fn (ownership &T6050PmpFirmwareOwnership) skips_firmware_service() bool {
	return ownership.running || ownership.no_firmware_service
}

// True when the host must supply and patch a firmware image itself, which is
// the case for every source other than the DeviceTree segment-map preload.
pub fn (ownership &T6050PmpFirmwareOwnership) needs_host_image() bool {
	return ownership.source != .preload
}

// Where the PMP readiness interrupt lives, resolved from PMGR's runtime
// interrupt-config table rather than assumed. The record count is the per-die
// interrupt stride that ApplePMGR::_handleInterruptAll divides by, and iBoot
// merges the selected chip-variant overlay into that property before the OS
// sees it, so neither value may be hardcoded.
pub struct T6050PmpReadyInterrupt {
pub:
	interrupts_per_die u32
	slot               u32
}

pub fn (config &T6050PmpReadyInterrupt) matches(interrupt_index u32) bool {
	return t6050_pmp_ready_interrupt(interrupt_index, config.interrupts_per_die,
		config.slot)
}

pub fn (config &T6050PmpReadyInterrupt) die(interrupt_index u32) ?u32 {
	return t6050_pmp_ready_die(interrupt_index, config.interrupts_per_die)
}

// One latched readiness byte per die, mirroring ApplePMGR's per-die ready-byte
// array. Two independent producers set it and none ever clears it:
// _pmpReadyActionGated latches from the per-die PMP interrupt and then wakes
// every command-gate waiter, and _waitForPMPReadyActionGatedv2 latches the same
// byte itself once the PTD PMP-STATUS entry reads back nonzero. Treating the
// interrupt as the only source would deadlock a die whose interrupt is absent.
pub struct T6050PmpReadiness {
mut:
	lock  klock.Lock
	ready [2]bool
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

// ApplePMGR::_handleInterruptAll decodes the PMP ready interrupt out of a flat
// interrupt index: the die is index / interrupts-per-die and the position
// inside that die is the remainder. Only the remainder that equals the
// configured ready slot closes the handshake.
pub fn t6050_pmp_ready_die(interrupt_index u32, interrupts_per_die u32) ?u32 {
	if interrupts_per_die == 0 {
		return none
	}
	return interrupt_index / interrupts_per_die
}

// A ready slot of 0xff means the die publishes no ready interrupt at all, so
// no interrupt may ever be treated as its readiness event.
pub fn t6050_pmp_ready_interrupt(interrupt_index u32, interrupts_per_die u32,
	ready_slot u32) bool {
	if interrupts_per_die == 0 || ready_slot == t6050_pmp_ready_slot_absent {
		return false
	}
	return interrupt_index % interrupts_per_die == ready_slot
}

// Latch one die from its PMP ready interrupt. A die outside the recovered
// two-die topology is rejected so a decoded interrupt index can never widen
// the array.
pub fn (mut readiness T6050PmpReadiness) notify_ready(die u32) bool {
	if die >= t6050_pmp_die_slots {
		return false
	}
	readiness.lock.acquire()
	defer {
		readiness.lock.release()
	}
	readiness.ready[die] = true
	return true
}

// Latch one die from an observed PMP-STATUS value. A zero status proves
// nothing, so it neither latches nor clears.
pub fn (mut readiness T6050PmpReadiness) observe_status(die u32, status u64) bool {
	if status == 0 {
		return false
	}
	return readiness.notify_ready(die)
}

pub fn (mut readiness T6050PmpReadiness) is_ready(die u32) bool {
	if die >= t6050_pmp_die_slots {
		return false
	}
	readiness.lock.acquire()
	defer {
		readiness.lock.release()
	}
	return readiness.ready[die]
}

// Apple splits the two publications deliberately. The initial one runs from
// ApplePMGR::start, inside _initPMPv2, with no readiness observation in the
// path at all, which is why begin() may legitimately report
// published_pre_ready. Every later transition instead goes through
// _enableDeviceGated, which calls _waitForPMPReadyAction before it mutates
// device state. Keep that precondition explicit rather than letting a dynamic
// request race a PMP that has not reported in.
pub fn (mut controller T6050PowerController) begin_dynamic(die u32, enabled bool,
	mut readiness T6050PmpReadiness) T6050PowerResult {
	if !readiness.is_ready(die) {
		return .not_ready
	}
	return controller.begin(die, enabled)
}

fn derive_t6050_patchbay_value(raw u32,
	derivation T6050PatchBayInputDerivation) u32 {
	return match derivation {
		.value { raw }
		.pmc_pmgr_bit0 { raw & 1 }
		.pmc_pmgr_bit3 { (raw >> 3) & 1 }
	}
}

fn read_t6050_patchbay_property(node &devicetree.DTNode, input &T6050PatchBayInput) ?u32 {
	value := devicetree.get_property(node, input.property) or { return none }
	if value.len < 4 || (input.width_checked && value.len != 4) {
		return none
	}
	return derive_t6050_patchbay_value(read_native_u32(value.data, 0),
		input.derivation)
}

// Resolve the nine mandatory patchbay inputs from the native DeviceTree.
// A missing node is fatal because it would silently zero several inputs at
// once, while a missing individual property is Apple's own behaviour and is
// reported as an absent zero.
pub fn get_t6050_patchbay_values(provider &devicetree.DTNode) ?[]T6050PatchBayValue {
	chosen := devicetree.find_node(t6050_chosen_path) or { return none }
	pmgr := devicetree.find_node(t6050_pmgr_path) or { return none }
	mut values := []T6050PatchBayValue{cap: t6050_patchbay_inputs.len}
	for input in t6050_patchbay_inputs {
		node := match input.node {
			.chosen { chosen }
			.pmgr { pmgr }
			.provider { provider }
		}
		tag := t6050_patchbay_tag(input.tag) or { return none }
		if raw := read_t6050_patchbay_property(node, &input) {
			values << T6050PatchBayValue{
				tag: tag
				value: raw
				present: true
			}
		} else {
			values << T6050PatchBayValue{
				tag: tag
				value: 0
				present: false
			}
		}
	}
	return values
}

// Classify one PMP nub exactly as RTBuddy::_initConfigEDT plus// Classify one PMP nub exactly as RTBuddy::_initConfigEDT plus
// _attemptFirmwareLoad would. This is read-only classification: it tells a
// future owner whether it must provide a firmware image, and it never implies
// that an iBoot-mapped segment list is an inherited image.
fn get_t6050_pmp_firmware_ownership(nub &devicetree.DTNode) T6050PmpFirmwareOwnership {
	preloaded := native_flag_property_set(nub, t6050_nub_preloaded_property)
	running := native_flag_property_set(nub, t6050_nub_running_property)
	no_firmware_service := native_flag_property_set(nub,
		t6050_nub_no_firmware_service_property)
	mut iboot_mapped_segments := false
	if _ := devicetree.get_property(nub, t6050_nub_segment_ranges_property) {
		iboot_mapped_segments = true
	}
	mut source := T6050PmpFirmwareSource.await_firmware_service
	if running || no_firmware_service {
		source = if preloaded {
			T6050PmpFirmwareSource.preload
		} else {
			T6050PmpFirmwareSource.service_firmware
		}
	}
	return T6050PmpFirmwareOwnership{
		source: source
		iboot_mapped_segments: iboot_mapped_segments
		preloaded: preloaded
		running: running
		no_firmware_service: no_firmware_service
	}
}

fn validate_t6050_patchbay_codec() bool {
	mandatory := ['BDID', 'DVID', 'DCAP', 'DCHD', 'PMC_', 'PMCV', 'PMCB',
		'PMCX', 'CVAR']
	// Build a version-5 identity block and a patchbay holding the nine
	// mandatory 32-bit tags, then walk it exactly as RTBuddyPatchBay does.
	mut records := []u8{}
	for index, name in mandatory {
		tag := t6050_patchbay_tag(name) or { return false }
		stored := t6050_patchbay_stored_bytes(tag)
		for byte_index in 0 .. 4 {
			records << stored[byte_index]
		}
		records << [u8(4), 0, 0, 0]
		records << [u8(index), 0, 0, 0]
	}
	// The image spells every tag backwards; BDID is stored as the bytes DIDB.
	bdid := t6050_patchbay_tag('BDID') or { return false }
	if bdid != 0x42444944 || t6050_patchbay_stored_bytes(bdid) != [u8(`D`), `I`, `D`, `B`]! {
		return false
	}
	mut block := []u8{len: int(rtk_id_block_size)}
	block[0] = u8(rtk_id_block_magic)
	block[1] = u8(rtk_id_block_magic >> 8)
	block[2] = u8(rtk_id_block_magic >> 16)
	block[3] = u8(rtk_id_block_magic >> 24)
	block[rtk_id_block_version_offset] = 5
	block[rtk_id_block_v5_offset] = 0
	block[rtk_id_block_v5_offset + 4] = u8(records.len)
	region := decode_t6050_patchbay_region(block.data, 0, true) or { return false }
	if region.align_pad != 0 || region.size != u32(records.len)
		|| region.padded_size != (u32(records.len) + 3) & ~u32(3) {
		return false
	}
	// An unsupported identity-block version must not yield a region at all.
	block[rtk_id_block_version_offset] = 6
	if _ := decode_t6050_patchbay_region(block.data, 0, true) {
		return false
	}
	block[rtk_id_block_version_offset] = 5
	mut seen := 0
	for index, name in mandatory {
		tag := t6050_patchbay_tag(name) or { return false }
		record := find_t6050_patchbay_tag(records.data, &region, tag) or { return false }
		if record.length != 4
			|| read_native_u32(records.data, record.offset + rtk_patchbay_header_size) != u32(index) {
			return false
		}
		seen++
	}
	if seen != mandatory.len {
		return false
	}
	if _ := find_t6050_patchbay_tag(records.data, &region, t6050_patchbay_tag('ZZZZ') or {
		return false
	}) {
		return false
	}
	if _ := t6050_patchbay_tag('BDI') {
		return false
	}
	// The host copy spans the whole padded region, and an edit is refused
	// unless every requested tag already exists as a 32-bit record.
	mut bay := copy_t6050_patchbay(records.data, &region) or { return false }
	if bay.data.len != int(region.padded_size) || bay.dirty {
		return false
	}
	mut target := []u8{len: int(region.padded_size)}
	// Nothing is pushed before an edit, and nothing is pushed for a region
	// whose segment is not writable.
	if bay.write_back(target.data) {
		return false
	}
	if !bay.set_value(bdid, 0x1234abcd) || !bay.dirty {
		return false
	}
	if bay.set_value(t6050_patchbay_tag('ZZZZ') or { return false }, 1) {
		return false
	}
	mut values := []T6050PatchBayValue{}
	for index, name in mandatory {
		values << T6050PatchBayValue{
			tag: t6050_patchbay_tag(name) or { return false }
			value: u32(0x100 + index)
			present: true
		}
	}
	if !bay.apply_values(values) {
		return false
	}
	values << T6050PatchBayValue{
		tag: t6050_patchbay_tag('ZZZZ') or { return false }
		value: 0
		present: false
	}
	if bay.apply_values(values) {
		return false
	}
	if !bay.write_back(target.data) {
		return false
	}
	// The pushed copy must read back through the same walker.
	for index, name in mandatory {
		tag := t6050_patchbay_tag(name) or { return false }
		record := find_t6050_patchbay_tag(target.data, &region, tag) or { return false }
		if read_native_u32(target.data, record.offset + rtk_patchbay_header_size) != u32(0x100 + index) {
			return false
		}
	}
	unwritable := T6050PatchBayRegion{
		iop_virtual: region.iop_virtual
		align_pad: region.align_pad
		size: region.size
		padded_size: region.padded_size
		writable: false
	}
	mut locked := copy_t6050_patchbay(records.data, &unwritable) or { return false }
	if !locked.set_value(bdid, 1) || locked.write_back(target.data) {
		return false
	}
	// A length that leaves the declared region must abort the whole walk
	// rather than reinterpret neighbouring bytes.
	records[4] = 0xff
	if _ := find_t6050_patchbay_tag(records.data, &region, t6050_patchbay_tag('CVAR') or {
		return false
	}) {
		return false
	}
	return true
}

fn validate_t6050_patchbay_input_codec() bool {
	if t6050_patchbay_inputs.len != 9 {
		return false
	}
	mut checked := 0
	for input in t6050_patchbay_inputs {
		if t6050_patchbay_tag(input.tag) == none {
			return false
		}
		if input.width_checked {
			checked++
		}
	}
	// Only /chosen and /arm-io/pmgr reject a wrong width, and pmc-pmgr
	// contributes two of those four reads.
	if checked != 4 {
		return false
	}
	return derive_t6050_patchbay_value(0x3f, .value) == 0x3f
		&& derive_t6050_patchbay_value(0x3f, .pmc_pmgr_bit0) == 1
		&& derive_t6050_patchbay_value(0x3f, .pmc_pmgr_bit3) == 1
		&& derive_t6050_patchbay_value(0x37, .pmc_pmgr_bit0) == 1
		&& derive_t6050_patchbay_value(0x37, .pmc_pmgr_bit3) == 0
		&& derive_t6050_patchbay_value(0x3e, .pmc_pmgr_bit0) == 0
}

// One identity block found inside a preloaded image.
pub struct T6050RtkIdentity {
pub:
	iop_virtual u64
	physical    u64
	version     u32
}

// The lowest segment IOVA is the image base that copyIdBlock adds its
// candidate offsets to.
pub fn (preload &T6050PmpPreload) image_base() u64 {
	mut base := u64(0)
	mut seen := false
	for segment in preload.segments {
		if segment.size == 0 {
			continue
		}
		if !seen || segment.iova < base {
			base = segment.iova
			seen = true
		}
	}
	return base
}

// Search the recovered candidate offsets for the image's identity block.
// `region` addresses the whole reserved region at preload.region_base. Two
// matching candidates are ambiguous rather than first-wins, matching the
// recovery, because a stale block would silently redirect every later offset.
pub fn locate_t6050_rtk_identity(region voidptr,
	preload &T6050PmpPreload) ?T6050RtkIdentity {
	base := preload.image_base()
	mut found := T6050RtkIdentity{}
	mut matches := 0
	for candidate in t6050_rtk_id_candidates {
		iop := base + u64(candidate)
		resolved := preload.resolve_iop_virtual(iop, rtk_id_block_size) or { continue }
		block := unsafe {
			voidptr(u64(region) + (resolved.physical - preload.region_base))
		}
		if read_native_u32(block, 0) != rtk_id_block_magic {
			continue
		}
		version := read_native_u32(block, rtk_id_block_version_offset)
		if version & ~u32(1) != 4 {
			continue
		}
		found = T6050RtkIdentity{
			iop_virtual: iop
			physical: resolved.physical
			version: version
		}
		matches++
	}
	if matches != 1 {
		return none
	}
	return found
}

// What a read-only pass over the preloaded image found.
pub struct T6050PmpImageProbe {
pub:
	die               u32
	identity          T6050RtkIdentity
	region            T6050PatchBayRegion
	patchbay_physical u64
	record_count      u32
	mandatory_present u32
}

// Read the iBoot-preloaded image in place and report what is actually there.
// This maps the reserved region, so it is deliberately not part of the
// read-only DeviceTree admission check; it writes nothing and leaves the
// firmware untouched.
pub fn probe_t6050_pmp_image(die u32) ?T6050PmpImageProbe {
	preload := get_t6050_pmp_preload(die) or { return none }
	if preload.region_size == 0 {
		return none
	}
	// Reserved coprocessor memory: the cacheable alias could hand back stale
	// bytes once the IOP is running, so read it Normal Non-Cacheable.
	mapped := memory.map_uncached(preload.region_base, preload.region_size)
	if mapped == 0 {
		return none
	}
	region_ptr := voidptr(mapped)
	identity := locate_t6050_rtk_identity(region_ptr, preload) or { return none }
	block := unsafe {
		voidptr(u64(region_ptr) + (identity.physical - preload.region_base))
	}
	decoded := decode_t6050_patchbay_region(block, preload.image_base(), false) or {
		return none
	}
	placed := preload.resolve_iop_virtual(decoded.iop_virtual, decoded.padded_size) or {
		return none
	}
	patchbay := decoded.with_writable(placed.writable)
	data := unsafe {
		voidptr(u64(region_ptr) + (placed.physical - preload.region_base))
	}
	mut records := u32(0)
	mut cursor := patchbay.align_pad
	for cursor + rtk_patchbay_header_size <= patchbay.align_pad + patchbay.size {
		record := next_t6050_patchbay_record(data, &patchbay, cursor) or { return none }
		records++
		cursor = record.next_cursor()
	}
	if cursor != patchbay.align_pad + patchbay.size {
		return none
	}
	mut present := u32(0)
	for input in t6050_patchbay_inputs {
		tag := t6050_patchbay_tag(input.tag) or { return none }
		record := find_t6050_patchbay_tag(data, &patchbay, tag) or { continue }
		if record.length == 4 {
			present++
		}
	}
	return T6050PmpImageProbe{
		die: die
		identity: identity
		region: patchbay
		patchbay_physical: placed.physical
		record_count: records
		mandatory_present: present
	}
}

// A plain function rather than a closure: V lowers closures onto mmap'd
// trampolines, which a freestanding kernel cannot link.
fn write_t6050_test_identity(mut image []u8, offset u32) {
	image[offset] = u8(rtk_id_block_magic)
	image[offset + 1] = u8(rtk_id_block_magic >> 8)
	image[offset + 2] = u8(rtk_id_block_magic >> 16)
	image[offset + 3] = u8(rtk_id_block_magic >> 24)
	image[offset + rtk_id_block_version_offset] = 5
}

fn validate_t6050_preload_address_codec() bool {
	// The recovered Mac17,6 layout: one region holding a read-only __TEXT and
	// a writable __DATA, each with its own physical base.
	preload := T6050PmpPreload{
		die: 0
		region_base: t6050_pmp_region_base
		region_size: t6050_pmp_region_size
		segments: [
			T6050PmpSegment{
				physical: t6050_pmp_region_base
				iova: t6050_pmp_text_iova
				remap: t6050_pmp_region_base
				size: t6050_pmp_text_size
				flags: t6050_pmp_text_flags
			},
			T6050PmpSegment{
				physical: t6050_pmp_region_base + u64(t6050_pmp_text_size)
				iova: t6050_pmp_data_iova
				remap: t6050_pmp_region_base + u64(t6050_pmp_text_size)
				size: t6050_pmp_data_size
				flags: t6050_pmp_data_flags
			},
		]!
	}
	if preload.segments[0].is_writable() || !preload.segments[1].is_writable() {
		return false
	}
	if !preload.segments[0].is_iboot_owned_mapping()
		|| !preload.segments[1].is_iboot_owned_mapping() {
		return false
	}
	// The identity block sits in read-only __TEXT; the patchbay it points at
	// sits in writable __DATA, which is what makes a write-back legal at all.
	identity := preload.resolve_iop_virtual(t6050_pmp_text_iova + 0x204,
		rtk_id_block_size) or { return false }
	if identity.physical != t6050_pmp_region_base + 0x204 || identity.writable {
		return false
	}
	patchbay := preload.resolve_iop_virtual(0x107e570, 0x2f8) or { return false }
	if patchbay.physical != t6050_pmp_region_base + 0x7e570 || !patchbay.writable {
		return false
	}
	// A span that leaves its segment, an address in neither segment, and a
	// zero length must all be refused rather than clamped.
	if _ := preload.resolve_iop_virtual(t6050_pmp_text_iova + u64(t6050_pmp_text_size) - 4,
		8) {
		return false
	}
	if _ := preload.resolve_iop_virtual(t6050_pmp_text_iova - 4, 4) {
		return false
	}
	if _ := preload.resolve_iop_virtual(t6050_pmp_data_iova + u64(t6050_pmp_data_size), 4) {
		return false
	}
	if _ := preload.resolve_iop_virtual(t6050_pmp_text_iova, 0) {
		return false
	}
	if preload.image_base() != t6050_pmp_text_iova {
		return false
	}
	// Exercise the identity-block search over a small synthetic region sized so
	// only the first three candidate offsets resolve, so the walk never reads
	// past the buffer it is given.
	small_size := u32(0x300)
	small := T6050PmpPreload{
		die: 0
		region_base: t6050_pmp_region_base
		region_size: u64(small_size)
		segments: [
			T6050PmpSegment{
				physical: t6050_pmp_region_base
				iova: t6050_pmp_text_iova
				remap: t6050_pmp_region_base
				size: small_size
				flags: t6050_pmp_text_flags
			},
			T6050PmpSegment{},
		]!
	}
	mut image := []u8{len: int(small_size)}
	if _ := locate_t6050_rtk_identity(image.data, &small) {
		return false
	}
	write_t6050_test_identity(mut image, 0x204)
	located := locate_t6050_rtk_identity(image.data, &small) or { return false }
	if located.iop_virtual != t6050_pmp_text_iova + 0x204
		|| located.physical != t6050_pmp_region_base + 0x204 || located.version != 5 {
		return false
	}
	// A second block is ambiguous, not first-wins: a stale one would redirect
	// every later offset without any other symptom.
	write_t6050_test_identity(mut image, 0xc0)
	if _ := locate_t6050_rtk_identity(image.data, &small) {
		return false
	}
	// An unsupported version is not an identity block at all.
	image[0xc0 + rtk_id_block_version_offset] = 6
	image[0x204 + rtk_id_block_version_offset] = 6
	if _ := locate_t6050_rtk_identity(image.data, &small) {
		return false
	}
	// Keep the dormant hardware probe reachable without mapping anything: an
	// out-of-range die is rejected before the region is touched.
	if _ := probe_t6050_pmp_image(t6050_pmp_die_slots) {
		return false
	}
	return true
}

fn validate_t6050_firmware_ownership_codec() bool {
	// Mac17,6 publishes segment-ranges and pre-loaded but neither running nor
	// no-firmware-service, so RTBuddy waits for ApplePMPFirmware and the image
	// is host-supplied despite the iBoot-installed DART records.
	observed := T6050PmpFirmwareOwnership{
		source: .await_firmware_service
		iboot_mapped_segments: true
		preloaded: true
	}
	if observed.skips_firmware_service() || !observed.needs_host_image() {
		return false
	}
	inherited := T6050PmpFirmwareOwnership{
		source: .preload
		iboot_mapped_segments: true
		preloaded: true
		running: true
	}
	if !inherited.skips_firmware_service() || inherited.needs_host_image() {
		return false
	}
	opted_out := T6050PmpFirmwareOwnership{
		source: .service_firmware
		no_firmware_service: true
	}
	return opted_out.skips_firmware_service() && opted_out.needs_host_image()
}

// ApplePMGR::initDriver decodes this property as 20-byte records whose byte 0
// is a per-die slot, byte 3 an interrupt kind below 16, and bytes 4..19 a
// fixed-size name. It rejects a property above 0x13f bytes and a slot at or
// above the record count, and it selects the readiness interrupt purely by the
// `PMP_STATUS` name.
fn get_t6050_pmp_ready_interrupt(pmgr_node &devicetree.DTNode) ?T6050PmpReadyInterrupt {
	records := devicetree.get_property(pmgr_node, 'interrupt-config') or { return none }
	if records.len == 0 || records.len > t6050_interrupt_config_max_bytes
		|| records.len % t6050_interrupt_config_record_size != 0 {
		return none
	}
	count := records.len / t6050_interrupt_config_record_size
	mut matches := u32(0)
	mut slot := u32(0)
	for offset := u32(0); offset < records.len; offset += t6050_interrupt_config_record_size {
		if read_native_u8(records.data, offset + t6050_interrupt_config_kind_offset)
			>= t6050_interrupt_config_kind_limit {
			return none
		}
		record_slot := u32(read_native_u8(records.data, offset))
		if record_slot >= count {
			return none
		}
		name := unsafe {
			voidptr(u64(records.data) + offset + t6050_interrupt_config_name_offset)
		}
		if !fixed_native_name_matches(name, t6050_interrupt_config_name_size,
			t6050_pmp_ready_interrupt_name) {
			continue
		}
		matches++
		slot = record_slot
	}
	if matches != 1 || slot >= t6050_pmp_ready_slot_absent {
		return none
	}
	return T6050PmpReadyInterrupt{
		interrupts_per_die: count
		slot: slot
	}
}

fn validate_t6050_readiness_codec() bool {
	mut readiness := T6050PmpReadiness{}
	if readiness.is_ready(0) || readiness.notify_ready(t6050_pmp_die_slots)
		|| readiness.is_ready(t6050_pmp_die_slots) {
		return false
	}
	if readiness.observe_status(0, 0) || readiness.is_ready(0) {
		return false
	}
	if !readiness.observe_status(0, 1) || !readiness.is_ready(0) {
		return false
	}
	if readiness.is_ready(1) || !readiness.notify_ready(1) || !readiness.is_ready(1) {
		return false
	}
	if _ := t6050_pmp_ready_die(4, 0) {
		return false
	}
	die := t6050_pmp_ready_die(9, 4) or { return false }
	if die != 2 || !t6050_pmp_ready_interrupt(9, 4, 1)
		|| t6050_pmp_ready_interrupt(9, 4, 2)
		|| t6050_pmp_ready_interrupt(9, 4, t6050_pmp_ready_slot_absent)
		|| t6050_pmp_ready_interrupt(9, 0, 1) {
		return false
	}
	// Mac17,6 merges two base records with four chip-variant records, so the
	// readiness interrupt is index 1 on die 0 and index 7 on die 1.
	config := T6050PmpReadyInterrupt{
		interrupts_per_die: 6
		slot: 1
	}
	config_die := config.die(7) or { return false }
	if config_die != 1 || !config.matches(1) || !config.matches(7)
		|| config.matches(6) || config.matches(2) {
		return false
	}
	// Exercise both dynamic admission outcomes against an unmapped transport so
	// the dormant path stays in the generated code without touching an
	// aperture: an unlatched die is refused before any access, and a latched
	// one still fails the transport bounds check.
	mut controller := T6050PowerController{
		transport: T6050PtdTransport{
			die_bases: [u64(0), 0]!
		}
		phase: .idle
	}
	mut unlatched := T6050PmpReadiness{}
	if controller.begin_dynamic(0, true, mut unlatched) != .not_ready {
		return false
	}
	return controller.begin_dynamic(0, true, mut readiness) == .transport_error
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

// Apple's EDT flags are presence-tested first and only then read, so an
// unreadable or non-unit value is not a set flag.
fn native_flag_property_set(node &devicetree.DTNode, property string) bool {
	value := devicetree.get_le_u32(node, property) or { return false }
	return value == 1
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
// initial synchronization publishes a persistent request before readiness --
// ApplePMGR::start runs the whole walk inside _initPMPv2 -- and Vinix has a
// serialized nonblocking controller plus a per-die readiness latch for that
// split. The controller remains dormant until the firmware-side handoff owns
// its startup order. This function therefore performs no mapping or MMIO
// access.
pub fn validate_t6050_contract(gpu_node &devicetree.DTNode) bool {
	if !validate_t6050_ptd_codec() || !validate_t6050_wrapper_codec()
		|| !validate_t6050_readiness_codec()
		|| !validate_t6050_firmware_ownership_codec()
		|| !validate_t6050_patchbay_codec()
		|| !validate_t6050_patchbay_input_codec()
		|| !validate_t6050_preload_address_codec()
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
	ready_interrupt := get_t6050_pmp_ready_interrupt(pmgr_node) or {
		println('agx: native t6050 PMGR PMP readiness interrupt is unavailable')
		return false
	}
	patchbay_values := get_t6050_patchbay_values(pmp0_nub) or {
		println('agx: native t6050 PMP patchbay inputs are unavailable')
		return false
	}
	mut resolved_inputs := u32(0)
	for value in patchbay_values {
		if value.present {
			resolved_inputs++
		}
	}
	firmware := get_t6050_pmp_firmware_ownership(pmp0_nub)
	if firmware.needs_host_image() {
		// Expected on Mac17,6: iBoot maps the segments but does not hand off a
		// started image, so bring-up still owes a firmware image and its
		// patchbay before any PMP transition is legal.
		println('agx: native t6050 PMP firmware image is host-owned; RTKit handoff still required')
	}
	if !validate_ptd_range(pmp0_nub, 'PMP-STATUS', 2, 1, 1, 16)
		|| !validate_ptd_range(pmp0_nub, 'SOC-DEV-PKT', 9, 0x90, 0x150, 0)
		|| !validate_ptd_range(pmp0_nub, 'SOC-DEV-PS-REQ', 10, 0x1e0, 8, 0)
		|| !validate_ptd_range(pmp0_nub, 'SOC-DEV-PS-ACK', 11, 0x1e8, 8, 0)
		|| !validate_u32_array(pmp0_nub, 'pm-ptd-ranges', [u32(1), 2, 3, 4, 5, 6,
			7, 8, 40, 9, 10, 11, 12, 13, 14]) {
		return false
	}
	C.printf(c'agx: validated native t6050 PMP power ownership (%u active die(s), PMP_STATUS interrupt slot %u of %u per die, iboot-mapped segments %u, %u/%u patchbay inputs resolved, read-only)\n',
		die_count, ready_interrupt.slot, ready_interrupt.interrupts_per_die,
		u32(firmware.iboot_mapped_segments), resolved_inputs,
		u32(t6050_patchbay_inputs.len))
	return true
}
