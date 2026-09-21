// SPDX-License-Identifier: GPL-2.0-only OR MIT
// Copyright (c) 2026 Alexander Medvednikov
// Copyright The Asahi Linux Contributors
@[has_globals]
module dcp

// Minimal, real IOMFB client for the t8103 internal panel backlight.
//
// Vinix still scans out through the framebuffer inherited from m1n1.  This
// client deliberately does not modeset or replace that surface.  It boots the
// internal DCP, completes the firmware's normal IOMFB callback handshake and
// submits surface-less swaps containing only the versioned backlight fields.

import apple.rtkit
import apple.dart
import aarch64.cpu
import aarch64.kio
import aarch64.pmgr
import aarch64.timer
import devicetree
import event
import event.eventstruct
import gpu.dcp.backlight
import lib
import memory
import sched
import time

const real_iomfb_endpoint = u8(0x37)
const real_iomfb_shmem_size = u64(0x100000)
const real_iomfb_alignment = u64(0x40)
const real_dart_page_size = u64(0x4000)
const real_rpc_timeout_ns = u64(2_000_000_000)
const real_boot_timeout_ns = u64(12_000_000_000)
const real_max_call_depth = 8
const real_max_buffers = 128
const real_max_registers = 8
const real_max_brightness_failures = 3
const real_worker_period_ns = i64(20_000_000)
const real_asc_cpu_control = u64(0x44)
const real_asc_cpu_run = u32(1 << 4)

enum RealFirmware {
	v12_3
	v13_3
}

struct RealMapping {
	phys u64
	iova u64
	size u64
}

struct RealPlan {
mut:
	firmware                 RealFirmware
	dcp_node                 &devicetree.DTNode = unsafe { nil }
	coproc                   devicetree.DTReg
	mailbox                  devicetree.DTReg
	dcp_dart                 devicetree.DTReg
	dcp_sid                  u8
	disp_dart                devicetree.DTReg
	disp_sid                 u8
	dcp_iova_base            u64
	dcp_iova_size            u64
	maximum_nits             u32
	clock_hz                 u64
	registers                []devicetree.DTReg
	bandwidth_scratch        u32
	bandwidth_scratch_offset u32
	bandwidth_doorbell       u32
	bandwidth_bit            u32
	mappings                 []RealMapping
	display_mappings         []RealMapping
}

struct RealChannel {
mut:
	depth      u8
	end        [real_max_call_depth]u16
	offset     [real_max_call_depth]u16
	length     [real_max_call_depth]u32
	input_len  [real_max_call_depth]u32
	output_len [real_max_call_depth]u32
	tag        [real_max_call_depth]u32
	completed  [real_max_call_depth]bool
	response   [real_max_call_depth]u64
}

struct RealBuffer {
mut:
	used      bool
	physical  u64
	virtual   u64
	dcp_iova  u64
	disp_iova u64
	size      u64
	register  bool
}

@[heap]
struct RealTransport {
mut:
	firmware                 RealFirmware
	rtk                      rtkit.RTKit
	dcp_dart                 dart.DART
	disp_dart                dart.DART
	shmem_phys               u64
	shmem                    u64
	shmem_iova               u64
	next_dcp_iova            u64
	dcp_iova_end             u64
	registers                [real_max_registers]devicetree.DTReg
	register_count           u32
	bandwidth_scratch        u32
	bandwidth_scratch_offset u32
	bandwidth_doorbell       u32
	bandwidth_bit            u32
	command                  RealChannel
	callback                 RealChannel
	oob_command              RealChannel
	oob_callback             RealChannel
	async_channel            RealChannel
	oob_async                RealChannel
	buffers                  [real_max_buffers]RealBuffer
	maximum_nits             u32
	clock_hz                 u64
	brightness_scale         u32
	actual_raw_nits          u32
	have_actual              bool
	have_scale               bool
	service_matched          bool
	initialized              bool
	poisoned                 bool
	brightness_failures      u32
	device                   &backlight.Backlight = unsafe { nil }
	wake                     eventstruct.Event
}

__global (
	real_panel_transport &RealTransport
)

fn has_compatible(node &devicetree.DTNode, wanted string) bool {
	values := devicetree.get_string_list(node, 'compatible') or { return false }
	for value in values {
		if value == wanted {
			return true
		}
	}
	return false
}

fn node_enabled(node &devicetree.DTNode) bool {
	status := devicetree.get_string_prop(node, 'status') or { return true }
	return status == 'okay' || status == 'ok'
}

fn find_named_child(node &devicetree.DTNode, name string) ?&devicetree.DTNode {
	for child in node.children {
		base := if child.name.contains('@') { child.name.all_before('@') } else { child.name }
		if base == name {
			return child
		}
	}
	return none
}

fn discover_firmware(node &devicetree.DTNode) ?RealFirmware {
	compat := devicetree.get_u32_array(node, 'apple,firmware-compat') or {
		println('dcp-backlight: missing apple,firmware-compat')
		return none
	}
	if compat.len < 3 {
		println('dcp-backlight: short apple,firmware-compat')
		return none
	}
	if compat[0] == 12 && compat[1] == 3 {
		return .v12_3
	}
	// m1n1 describes 13.5 IOMFB as wire-compatible with 13.3.
	if compat[0] == 13 && (compat[1] == 3 || compat[1] == 5) {
		return .v13_3
	}
	C.printf(c'dcp-backlight: unsupported firmware compatibility %u.%u.%u\n', compat[0], compat[1], compat[2])
	return none
}

fn discover_panel(node &devicetree.DTNode) ?u32 {
	for child in node.children {
		if !node_enabled(child) {
			continue
		}
		if has_compatible(child, 'apple,panel') || has_compatible(child, 'apple,panel-mini-led') {
			maximum := devicetree.get_u32(child, 'apple,max-brightness') or {
				println('dcp-backlight: panel has no apple,max-brightness')
				return none
			}
			if maximum < 2 {
				println('dcp-backlight: panel maximum is invalid')
				return none
			}
			return maximum
		}
	}
	println('dcp-backlight: internal panel node not found')
	return none
}

fn discover_iommu(node &devicetree.DTNode) ?(&devicetree.DTNode, u8) {
	cells := devicetree.get_u32_array(node, 'iommus') or { return none }
	if cells.len != 2 || cells[1] > 15 {
		return none
	}
	provider := devicetree.find_phandle(cells[0]) or { return none }
	if !has_compatible(provider, 'apple,t8103-dart') {
		return none
	}
	return provider, u8(cells[1])
}

fn discover_dma_range(node &devicetree.DTNode) ?(u64, u64) {
	cells := devicetree.get_u32_array(node, 'apple,dma-range') or { return none }
	if cells.len != 4 {
		return none
	}
	base := (u64(cells[0]) << 32) | u64(cells[1])
	size := (u64(cells[2]) << 32) | u64(cells[3])
	if size < 0x20000000 || base >= (u64(1) << 36)
		|| size > (u64(1) << 36) - base {
		return none
	}
	return base, size
}

fn append_reserved_mappings(node &devicetree.DTNode, display bool, mut plan RealPlan) bool {
	handles := devicetree.get_u32_array(node, 'memory-region') or {
		println('dcp-backlight: DCP firmware memory regions are missing')
		return false
	}
	dcp_phandle := devicetree.get_u32(node, 'phandle') or {
		devicetree.get_u32(node, 'linux,phandle') or { u32(0) }
	}
	if dcp_phandle == 0 {
		println('dcp-backlight: DCP phandle is missing')
		return false
	}
	before := if display { plan.display_mappings.len } else { plan.mappings.len }
	for handle in handles {
		region_node := devicetree.find_phandle(handle) or { continue }
		regions := devicetree.get_translated_reg_ranges(region_node) or { continue }
		addresses := devicetree.get_u32_array(region_node, 'iommu-addresses') or { continue }
		if regions.len == 0 || addresses.len % 5 != 0 {
			continue
		}
		for index := 0; index < addresses.len; index += 5 {
			if addresses[index] != dcp_phandle {
				continue
			}
			iova := (u64(addresses[index + 1]) << 32) | u64(addresses[index + 2])
			size := (u64(addresses[index + 3]) << 32) | u64(addresses[index + 4])
			aligned_size := lib.align_up(size, real_dart_page_size)
			if size == 0 || aligned_size < size || aligned_size > regions[0].size
				|| iova & (real_dart_page_size - 1) != 0
				|| regions[0].base & (real_dart_page_size - 1) != 0 {
				println('dcp-backlight: invalid reserved DCP mapping')
				return false
			}
			mapping := RealMapping{
				phys: regions[0].base
				iova: iova
				size: aligned_size
			}
			if display {
				plan.display_mappings << mapping
			} else {
				plan.mappings << mapping
			}
		}
	}
	if (if display { plan.display_mappings.len } else { plan.mappings.len }) == before {
		println('dcp-backlight: no reserved DART mappings were described')
		return false
	}
	return true
}

fn append_bandwidth_register(node &devicetree.DTNode, property string, expected_args int,
	mut plan RealPlan) bool {
	cells := devicetree.get_u32_array(node, property) or { return false }
	if cells.len != expected_args + 1 {
		return false
	}
	provider := devicetree.find_phandle(cells[0]) or { return false }
	ranges := devicetree.get_translated_reg_ranges(provider) or { return false }
	address_index := cells[1]
	display_index := cells[2]
	if address_index >= u32(ranges.len) || display_index != u32(plan.registers.len)
		|| plan.registers.len >= real_max_registers {
		return false
	}
	plan.registers << ranges[address_index]
	if property == 'apple,bw-scratch' {
		if expected_args != 3 || ranges[address_index].size < 4
			|| u64(cells[3]) > ranges[address_index].size - 4 {
			return false
		}
		plan.bandwidth_scratch = display_index
		plan.bandwidth_scratch_offset = cells[3]
		plan.bandwidth_bit = 2
	} else {
		plan.bandwidth_doorbell = display_index
	}
	return true
}

fn discover_real_plan() ?RealPlan {
	root := devicetree.find_node('/') or { return none }
	if !has_compatible(root, 'apple,t8103') {
		println('dcp-backlight: only base M1/t8103 is supported')
		return none
	}
	mut node := devicetree.find_compatible('apple,dcp') or { return none }
	if !node_enabled(node) || !has_compatible(node, 'apple,t8103-dcp') {
		println('dcp-backlight: internal t8103 DCP is unavailable')
		return none
	}
	firmware := discover_firmware(node) or { return none }
	maximum := discover_panel(node) or { return none }
	clock_node := devicetree.get_phandle_node(node, 'clocks', 0) or { return none }
	clock_hz := devicetree.get_u32(clock_node, 'clock-frequency') or { return none }
	if clock_hz == 0 {
		println('dcp-backlight: display clock rate is unavailable')
		return none
	}
	coproc := devicetree.get_named_reg(node, 'coproc') or { return none }
	mailbox_node := devicetree.get_phandle_node(node, 'mboxes', 0) or { return none }
	mailbox_regs := devicetree.get_translated_reg_ranges(mailbox_node) or { return none }
	if mailbox_regs.len == 0 || !has_compatible(mailbox_node, 'apple,asc-mailbox-v4') {
		return none
	}
	dcp_dart_node, dcp_sid := discover_iommu(node) or { return none }
	dcp_dart_regs := devicetree.get_translated_reg_ranges(dcp_dart_node) or { return none }
	if dcp_dart_regs.len == 0 {
		return none
	}
	dcp_base, dcp_size := discover_dma_range(dcp_dart_node) or { return none }
	piodma := find_named_child(node, 'piodma') or { return none }
	disp_dart_node, disp_sid := discover_iommu(piodma) or { return none }
	disp_dart_regs := devicetree.get_translated_reg_ranges(disp_dart_node) or { return none }
	if disp_dart_regs.len == 0 || disp_sid != 4 {
		println('dcp-backlight: PIODMA stream is not display DART SID 4')
		return none
	}

	all_regs := devicetree.get_translated_reg_ranges(node) or { return none }
	reg_names := devicetree.get_string_list(node, 'reg-names') or { return none }
	if all_regs.len != reg_names.len {
		return none
	}
	mut plan := RealPlan{
		firmware: firmware
		dcp_node: node
		coproc: coproc
		mailbox: mailbox_regs[0]
		dcp_dart: dcp_dart_regs[0]
		dcp_sid: dcp_sid
		disp_dart: disp_dart_regs[0]
		disp_sid: disp_sid
		dcp_iova_base: dcp_base
		dcp_iova_size: dcp_size
		maximum_nits: maximum
		clock_hz: clock_hz
	}
	for index, name in reg_names {
		if name.starts_with('disp-') {
			plan.registers << all_regs[index]
		}
	}
	if plan.registers.len != 5
		|| !append_bandwidth_register(node, 'apple,bw-scratch', 3, mut plan)
		|| !append_bandwidth_register(node, 'apple,bw-doorbell', 2, mut plan)
		|| !append_reserved_mappings(node, false, mut plan)
		|| !append_reserved_mappings(piodma, true, mut plan) {
		println('dcp-backlight: incomplete display register or firmware topology')
		unsafe { plan.registers.free() }
		unsafe { plan.mappings.free() }
		unsafe { plan.display_mappings.free() }
		return none
	}
	return plan
}

fn is_pmgr_domain(node &devicetree.DTNode) bool {
	return has_compatible(node, 'apple,pmgr-pwrstate')
		|| has_compatible(node, 'apple,t8103-pmgr-pwrstate')
}

fn enable_power_domains(node &devicetree.DTNode, depth u32) bool {
	if depth > 8 {
		return false
	}
	handles := devicetree.get_u32_array(node, 'power-domains') or {
		return depth != 0
	}
	if depth == 0 && handles.len == 0 {
		return false
	}
	for handle in handles {
		domain := devicetree.find_phandle(handle) or { return false }
		if !is_pmgr_domain(domain)
			|| (devicetree.get_u32(domain, '#power-domain-cells') or { u32(0) }) != 0
			|| !enable_power_domains(domain, depth + 1) {
			return false
		}
		offset := devicetree.get_u32(domain, 'reg') or { return false }
		if domain.parent == unsafe { nil } {
			return false
		}
		apertures := devicetree.get_translated_reg_ranges(domain.parent) or { return false }
		if apertures.len == 0 || !pmgr.enable_region(apertures[0].base, apertures[0].size, offset) {
			return false
		}
	}
	return true
}

fn alloc_uncached(size u64) ?(u64, u64) {
	span := lib.align_up(size, real_dart_page_size)
	pages := lib.div_roundup(span, u64(4096))
	raw := u64(memory.pmm_alloc_aligned_fallible(pages, real_dart_page_size / 4096))
	if raw == 0 {
		return none
	}
	physical := raw
	virtual := memory.map_uncached(physical, span)
	if virtual == 0 {
		return none
	}
	unsafe { C.memset(voidptr(virtual), 0, span) }
	return physical, virtual
}

fn (mut transport RealTransport) allocate_dcp_iova(size u64) ?u64 {
	span := lib.align_up(size, real_dart_page_size)
	iova := lib.align_up(transport.next_dcp_iova, real_dart_page_size)
	if iova < transport.next_dcp_iova || iova > transport.dcp_iova_end
		|| span > transport.dcp_iova_end - iova {
		return none
	}
	transport.next_dcp_iova = iova + span
	return iova
}

fn (mut transport RealTransport) allocate_shared(size u64) ?(u64, u64, u64) {
	span := lib.align_up(size, real_dart_page_size)
	physical, virtual := alloc_uncached(span) or { return none }
	iova := transport.allocate_dcp_iova(span) or { return none }
	if !transport.dcp_dart.map(iova, physical, span) {
		return none
	}
	return physical, virtual, iova
}

fn real_rtkit_allocator(context voidptr, size u64) u64 {
	if context == unsafe { nil } {
		return 0
	}
	mut transport := unsafe { &RealTransport(context) }
	_, _, iova := transport.allocate_shared(size) or { return 0 }
	// RTKit owns these buffers for the firmware session. They are deliberately
	// lifetime allocations, not IOMFB memory descriptors that DCP may release.
	return iova
}

@[inline]
fn read_le32_at(address u64) u32 {
	p := unsafe { &u8(address) }
	return unsafe { u32(p[0]) | (u32(p[1]) << 8) | (u32(p[2]) << 16) | (u32(p[3]) << 24) }
}

@[inline]
fn read_le64_at(address u64) u64 {
	return u64(read_le32_at(address)) | (u64(read_le32_at(address + 4)) << 32)
}

@[inline]
fn write_le32_at(address u64, value u32) {
	p := unsafe { &u8(address) }
	unsafe {
		p[0] = u8(value)
		p[1] = u8(value >> 8)
		p[2] = u8(value >> 16)
		p[3] = u8(value >> 24)
	}
}

@[inline]
fn write_le64_at(address u64, value u64) {
	write_le32_at(address, u32(value))
	write_le32_at(address + 4, u32(value >> 32))
}

fn bytes_equal(address u64, text string, capacity u32) bool {
	if text.len >= int(capacity) {
		return false
	}
	p := unsafe { &u8(address) }
	for index in 0 .. text.len {
		if unsafe { p[index] } != text[index] {
			return false
		}
	}
	return unsafe { p[text.len] } == 0
}

fn fourcc_equal(address u64, text string) bool {
	if text.len != 4 {
		return false
	}
	p := unsafe { &u8(address) }
	for index in 0 .. 4 {
		if unsafe { p[index] } != text[index] {
			return false
		}
	}
	return true
}

fn channel_offset(context u8) ?u64 {
	return match context {
		0, 2 { u64(0x00000) }
		3 { u64(0x40000) }
		4, 6 { u64(0x08000) }
		7 { u64(0x48000) }
		else { none }
	}
}

fn receive_offset(context u8) ?u64 {
	return match context {
		0 { u64(0x60000) }
		3 { u64(0x40000) }
		4 { u64(0x68000) }
		7 { u64(0x48000) }
		2, 6 { channel_offset(context) }
		else { none }
	}
}

fn (mut transport RealTransport) channel_for(context u8) ?&RealChannel {
	match context {
		0 {
			return &transport.callback
		}
		2 {
			return &transport.command
		}
		4 {
			return &transport.oob_callback
		}
		6 {
			return &transport.oob_command
		}
		3 {
			return &transport.async_channel
		}
		7 {
			return &transport.oob_async
		}
		else {
			return none
		}
	}
}

fn make_message(context u8, length u32, offset u16, ack bool) u64 {
	mut value := (u64(length) << 32) | (u64(offset) << 16) | (u64(context) << 8) | 2
	if ack {
		value |= u64(1) << 6
	}
	return value
}

fn (mut transport RealTransport) send_ack(context u8) bool {
	cpu.dmb_sy()
	return transport.rtk.send_message(real_iomfb_endpoint, make_message(context, 0, 0, true))
}

fn (mut transport RealTransport) rpc(tag string, input voidptr, input_len u32,
	output_len u32, timeout_ns u64) ?u64 {
	if transport.poisoned || tag.len != 4
		|| u64(input_len) + u64(output_len) + 12 > 0x8000 {
		return none
	}
	context := if transport.command.depth > 0 { u8(0) } else { u8(2) }
	mut channel := transport.channel_for(context) or { return none }
	if channel.depth >= real_max_call_depth {
		return none
	}
	level := channel.depth
	offset := if level == 0 { u16(0) } else { channel.end[level - 1] }
	length := u32(12) + input_len + output_len
	end := lib.align_up(u64(offset) + u64(length), real_iomfb_alignment)
	if end > 0x8000 {
		return none
	}
	base := channel_offset(context) or { return none }
	packet := transport.shmem + base + u64(offset)
	unsafe {
		mut bytes := &u8(packet)
		bytes[0] = tag[3]
		bytes[1] = tag[2]
		bytes[2] = tag[1]
		bytes[3] = tag[0]
	}
	write_le32_at(packet + 4, input_len)
	write_le32_at(packet + 8, output_len)
	if input_len > 0 {
		unsafe { C.memcpy(voidptr(packet + 12), input, input_len) }
	}
	if output_len > 0 {
		unsafe { C.memset(voidptr(packet + 12 + input_len), 0, output_len) }
	}
	channel.end[level] = u16(end)
	channel.offset[level] = offset
	channel.length[level] = length
	channel.input_len[level] = input_len
	channel.output_len[level] = output_len
	channel.tag[level] = read_le32_at(packet)
	channel.completed[level] = false
	channel.response[level] = 0
	channel.depth++
	cpu.dmb_sy()
	if !transport.rtk.send_message(real_iomfb_endpoint, make_message(context, length, offset, false)) {
		transport.poisoned = true
		return none
	}
	deadline := timer.get_ns() + timeout_ns
	for timer.get_ns() < deadline {
		if channel.completed[level] {
			return channel.response[level]
		}
		if !transport.receive_one() {
			asm volatile aarch64 { yield ; ; ; memory }
		}
		if transport.poisoned {
			return none
		}
	}
	C.printf(c'dcp-backlight: RPC %.4s timed out\n', tag.str)
	transport.poisoned = true
	return none
}

fn callback_id(packet u64) ?u32 {
	p := unsafe { &u8(packet) }
	if unsafe { p[3] } != `D` {
		return none
	}
	mut digits := [3]u32{}
	for index in 0 .. 3 {
		value := unsafe { p[index] }
		if value < `0` || value > `9` {
			return none
		}
		digits[index] = u32(value - `0`)
	}
	return digits[0] + digits[1] * 10 + digits[2] * 100
}

fn set_bool_output(output u64, output_len u32, value bool) bool {
	if output_len < 1 {
		return false
	}
	unsafe { (&u8(output))[0] = if value { u8(1) } else { u8(0) } }
	return true
}

fn (mut transport RealTransport) boot_callback(output u64, output_len u32) bool {
	create_tag := if transport.firmware == .v12_3 { 'A357' } else { 'A373' }
	default_tag := if transport.firmware == .v12_3 { 'A443' } else { 'A445' }
	flush_tag := if transport.firmware == .v12_3 { 'A463' } else { 'A466' }
	refresh_tag := if transport.firmware == .v12_3 { 'A460' } else { 'A463' }
	if transport.rpc(create_tag, unsafe { nil }, 0, 0, real_rpc_timeout_ns) == none
		|| transport.rpc(default_tag, unsafe { nil }, 0, 4, real_rpc_timeout_ns) == none
		|| transport.rpc('A029', unsafe { nil }, 0, 0, real_rpc_timeout_ns) == none {
		return false
	}
	mut one := u32(1)
	if transport.rpc(flush_tag, voidptr(&one), 4, 0, real_rpc_timeout_ns) == none {
		return false
	}
	if transport.firmware == .v12_3 {
		if transport.rpc('A000', unsafe { nil }, 0, 4, real_rpc_timeout_ns) == none {
			return false
		}
	} else if transport.rpc('A000', voidptr(&one), 4, 4, real_rpc_timeout_ns) == none {
		return false
	}
	if transport.rpc(refresh_tag, unsafe { nil }, 0, 4, real_rpc_timeout_ns) == none {
		return false
	}
	return set_bool_output(output, output_len, true)
}

fn (mut transport RealTransport) allocate_firmware_buffer(input u64, input_len u32,
	output u64, output_len u32) bool {
	if input_len < 20 || output_len < 28 {
		return false
	}
	size := read_le64_at(input + 4)
	if size == 0 || size > 16 * 1024 * 1024 {
		return false
	}
	mut id := -1
	for index := 0; index < real_max_buffers; index++ {
		if !transport.buffers[index].used {
			id = index
			break
		}
	}
	if id < 0 {
		return false
	}
	physical, virtual, iova := transport.allocate_shared(size) or { return false }
	span := lib.align_up(size, real_dart_page_size)
	transport.buffers[id] = RealBuffer{
		used: true
		physical: physical
		virtual: virtual
		dcp_iova: iova
		size: span
	}
	// Linux intentionally returns a null AP physical address.  DCP consumes
	// the DVA and refers to this allocation later by descriptor ID.
	write_le64_at(output, 0)
	write_le64_at(output + 8, iova)
	write_le64_at(output + 16, lib.align_up(size, u64(4096)))
	write_le32_at(output + 24, u32(id))
	return true
}

fn (mut transport RealTransport) map_piodma(input u64, input_len u32, output u64,
	output_len u32) bool {
	if input_len < 12 || output_len < 20 {
		return false
	}
	id64 := read_le64_at(input)
	if id64 >= real_max_buffers {
		write_le32_at(output + 16, 22)
		return true
	}
	mut buffer := &transport.buffers[int(id64)]
	if !buffer.used || buffer.register {
		write_le32_at(output + 16, 22)
		return true
	}
	if buffer.disp_iova == 0 {
		// PIODMA uses the same DVA chosen for this DCP allocation.
		iova := buffer.dcp_iova
		if !transport.disp_dart.map(iova, buffer.physical, buffer.size) {
			write_le32_at(output + 16, 5)
			return true
		}
		buffer.disp_iova = iova
	}
	write_le64_at(output, 0)
	write_le64_at(output + 8, buffer.disp_iova)
	write_le32_at(output + 16, 0)
	return true
}

fn (mut transport RealTransport) release_descriptor(input u64, input_len u32,
	output u64, output_len u32) bool {
	if input_len < 4 || output_len < 1 {
		return false
	}
	id := read_le32_at(input)
	if id >= real_max_buffers || !transport.buffers[id].used {
		return set_bool_output(output, output_len, false)
	}
	// Firmware has stopped using the mapping.  Vinix's PMM does not yet have a
	// matching contiguous-free primitive, so retain the pages and make the ID
	// reusable only after clearing its DART translations.
	buffer := transport.buffers[id]
	transport.dcp_dart.unmap(buffer.dcp_iova, buffer.size)
	if buffer.disp_iova != 0 {
		transport.disp_dart.unmap(buffer.disp_iova, buffer.size)
	}
	transport.buffers[id] = RealBuffer{}
	return set_bool_output(output, output_len, true)
}

fn (transport &RealTransport) physical_register_allowed(physical u64, size u64) bool {
	if size == 0 || physical + size < physical {
		return false
	}
	for index := 0; index < int(transport.register_count); index++ {
		region := transport.registers[index]
		if region.base + region.size >= region.base && physical >= region.base
			&& physical + size <= region.base + region.size {
			return true
		}
	}
	return false
}

fn (mut transport RealTransport) map_physical(input u64, input_len u32,
	output u64, output_len u32) bool {
	if input_len < 24 || output_len < 20 {
		return false
	}
	physical := read_le64_at(input)
	requested_size := read_le64_at(input + 8)
	dva_size := lib.align_up(requested_size, u64(4096))
	size := lib.align_up(dva_size, real_dart_page_size)
	if dva_size < requested_size || size < dva_size {
		return true
	}
	if physical & (real_dart_page_size - 1) != 0
		|| !transport.physical_register_allowed(physical, dva_size) {
		return true
	}
	mut id := -1
	for index := 0; index < real_max_buffers; index++ {
		if !transport.buffers[index].used {
			id = index
			break
		}
	}
	if id < 0 {
		return true
	}
	iova := transport.allocate_dcp_iova(size) or { return true }
	if !transport.dcp_dart.map(iova, physical, size) {
		return true
	}
	transport.buffers[id] = RealBuffer{
		used: true
		physical: physical
		dcp_iova: iova
		size: size
		register: true
	}
	write_le64_at(output, iova)
	write_le64_at(output + 8, dva_size)
	write_le32_at(output + 16, u32(id))
	return true
}

fn (mut transport RealTransport) map_register(input u64, input_len u32,
	output u64, output_len u32) bool {
	if input_len < 16 {
		return false
	}
	index := read_le32_at(input + 4)
	if index >= transport.register_count {
		if transport.firmware == .v12_3 {
			if output_len < 20 {
				return false
			}
			write_le32_at(output + 16, 1)
		} else {
			if output_len < 28 {
				return false
			}
			write_le32_at(output + 24, 1)
		}
		return true
	}
	region := transport.registers[index]
	if transport.firmware == .v12_3 {
		if output_len < 20 {
			return false
		}
		write_le64_at(output, region.base)
		write_le64_at(output + 8, region.size)
		write_le32_at(output + 16, 0)
		return true
	}
	if output_len < 28 || region.base & (real_dart_page_size - 1) != 0 {
		return false
	}
	size := lib.align_up(region.size, real_dart_page_size)
	iova := transport.allocate_dcp_iova(size) or { return false }
	if !transport.dcp_dart.map(iova, region.base, size) {
		return false
	}
	write_le64_at(output, iova)
	write_le64_at(output + 8, region.base)
	write_le64_at(output + 16, region.size)
	write_le32_at(output + 24, 0)
	return true
}

fn (mut transport RealTransport) handle_service_match(tag string, output u64,
	output_len u32, is_backlight bool) bool {
	if transport.rpc(tag, unsafe { nil }, 0, 4, real_rpc_timeout_ns) == none {
		return false
	}
	if is_backlight {
		transport.service_matched = true
	}
	return set_bool_output(output, output_len, true)
}

fn (mut transport RealTransport) dispatch_callback(id u32, input u64, input_len u32,
	output u64, output_len u32) bool {
	// Output slots are shared with firmware and may contain bytes from an older
	// nested call.  Every callback starts from a deterministic zero response.
	if output_len > 0 {
		unsafe { C.memset(voidptr(output), 0, output_len) }
	}
	match id {
		0, 1 {
			return set_bool_output(output, output_len, true)
		}
		2, 102, 103, 104, 106, 211, 404, 406, 577, 584, 588, 592, 594, 598 {
			return true
		}
		6 {
			// 13.3 frame-sync properties: return an all-zero 28-byte value.
			return transport.firmware == .v13_3 && output_len >= 28
		}
		3 {
			if output_len < 60 {
				return false
			}
			if transport.bandwidth_scratch < transport.register_count {
				reg := transport.registers[transport.bandwidth_scratch]
				write_le64_at(output + 8, reg.base + transport.bandwidth_scratch_offset)
			}
			if transport.bandwidth_doorbell < transport.register_count {
				write_le64_at(output + 16, transport.registers[transport.bandwidth_doorbell].base)
				write_le32_at(output + 28, transport.bandwidth_bit)
				write_le32_at(output + 44, 4)
			}
			return true
		}
		100 {
			tag := if transport.firmware == .v12_3 { 'A358' } else { 'A374' }
			return transport.rpc(tag, unsafe { nil }, 0, 4, real_rpc_timeout_ns) != none
		}
		101 {
			return output_len >= 4
		}
		107 {
			if transport.firmware == .v12_3 {
				return set_bool_output(output, output_len, true)
			}
			return true
		}
		108, 109, 110, 111, 112, 113, 413, 415, 552, 561, 563, 565, 567, 582 {
			return set_bool_output(output, output_len, true)
		}
		114 {
			if transport.firmware == .v13_3 {
				if output_len < 8 {
					return false
				}
				write_le32_at(output + 4, 1)
				return true
			}
			return true
		}
		115 {
			return transport.firmware == .v13_3
				&& set_bool_output(output, output_len, false)
		}
		116, 120 {
			boot_id := if transport.firmware == .v12_3 { u32(116) } else { u32(120) }
			if id == boot_id {
				return transport.boot_callback(output, output_len)
			}
			// The other overlapping ID is read_edt_data on 12.3.
			if transport.firmware == .v12_3 && id == 120 {
				if input_len < 100 || output_len < 36 {
					return false
				}
				write_le32_at(output, read_le32_at(input + 68))
				return true
			}
			return false
		}
		117, 118, 121, 122 {
			dark_id := if transport.firmware == .v12_3 { u32(117) } else { u32(121) }
			wake_id := if transport.firmware == .v12_3 { u32(118) } else { u32(122) }
			if id == dark_id || id == wake_id {
				return set_bool_output(output, output_len, false)
			}
			// D122 is the 12.3 property transfer start.
			if transport.firmware == .v12_3 && id == 122 {
				return set_bool_output(output, output_len, true)
			}
			return false
		}
		123, 124, 126, 127, 128 {
			read_edt_id := if transport.firmware == .v13_3 { u32(124) } else { u32(120) }
			if id == read_edt_id {
				if input_len < 100 || output_len < 36 {
					return false
				}
				write_le32_at(output, read_le32_at(input + 68))
				return true
			}
			return set_bool_output(output, output_len, true)
		}
		129 {
			if input_len < 34 || output_len < 20 {
				return false
			}
			write_le64_at(output, read_le64_at(input))
			write_le64_at(output + 8, read_le64_at(input + 8))
			write_le32_at(output + 16, 1)
			return true
		}
		201 {
			return transport.map_piodma(input, input_len, output, output_len)
		}
		202 {
			if input_len >= 26 {
				descriptor_id := read_le64_at(input)
				if descriptor_id < real_max_buffers {
					mut buffer := &transport.buffers[int(descriptor_id)]
					if buffer.used && buffer.disp_iova != 0
						&& read_le64_at(input + 16) == buffer.disp_iova {
						transport.disp_dart.unmap(buffer.disp_iova, buffer.size)
						buffer.disp_iova = 0
					}
				}
			}
			return true
		}
		206 {
			return transport.handle_service_match('A131', output, output_len, false)
		}
		207 {
			return transport.handle_service_match('A132', output, output_len, true)
		}
		208 {
			if transport.firmware == .v13_3 {
				return true
			}
			if output_len < 8 {
				return false
			}
			now := time.clock_now(time.clock_type_realtime) or { time.TimeSpec{} }
			write_le64_at(output, u64(now.tv_sec) * 1000 + u64(now.tv_nsec / 1_000_000))
			return true
		}
		209 {
			if transport.firmware != .v13_3 || output_len < 8 {
				return false
			}
			now := time.clock_now(time.clock_type_realtime) or { time.TimeSpec{} }
			write_le64_at(output, u64(now.tv_sec) * 1000 + u64(now.tv_nsec / 1_000_000))
			return true
		}
		300 {
			if input_len < 8 {
				return false
			}
			if read_le32_at(input) == 15 {
				transport.actual_raw_nits = read_le32_at(input + 4)
				transport.have_actual = true
				if transport.device != unsafe { nil } {
					transport.device.publish_nits(transport.actual_raw_nits)
				}
			}
			return true
		}
		401 {
			if output_len < 12 {
				return false
			}
			return true
		}
		408 {
			if output_len < 8 {
				return false
			}
			write_le64_at(output, transport.clock_hz)
			return true
		}
		411 {
			return transport.map_register(input, input_len, output, output_len)
		}
		414 {
			if input_len < 77 || output_len < 1 {
				return false
			}
			if fourcc_equal(input, 'FMOI')
				&& bytes_equal(input + 4, 'Brightness_Scale', 64)
				&& unsafe { (&u8(input))[76] } == 0 {
				scale64 := read_le64_at(input + 68)
				if scale64 > 0 && scale64 <= 0xffff_ffff {
					transport.brightness_scale = u32(scale64)
					transport.have_scale = true
				}
			}
			return set_bool_output(output, output_len, true)
		}
		451 {
			return transport.allocate_firmware_buffer(input, input_len, output, output_len)
		}
		452 {
			return transport.map_physical(input, input_len, output, output_len)
		}
		454, 456 {
			release_id := if transport.firmware == .v12_3 { u32(456) } else { u32(454) }
			if id == release_id {
				return transport.release_descriptor(input, input_len, output, output_len)
			}
			return true
		}
		574 {
			if output_len < 4 {
				return false
			}
			return true
		}
		576 {
			return true
		}
		589 {
			return true
		}
		591 {
			return true
		}
		593 {
			if transport.device != unsafe { nil } {
				event.trigger(mut transport.wake, false)
			}
			return true
		}
		596, 597 {
			return set_bool_output(output, output_len, false)
		}
		else {
			C.printf(c'dcp-backlight: unsupported callback D%03u\n', id)
			return false
		}
	}
}

fn (mut transport RealTransport) handle_callback(context u8, message u64) bool {
	offset := u16((message >> 16) & 0xffff)
	length := u32(message >> 32)
	base := receive_offset(context) or { return false }
	if offset & u16(real_iomfb_alignment - 1) != 0
		|| u64(offset) + u64(length) > 0x8000 || length < 12 {
		return false
	}
	packet := transport.shmem + base + u64(offset)
	input_len := read_le32_at(packet + 4)
	output_len := read_le32_at(packet + 8)
	if u64(12) + u64(input_len) + u64(output_len) > u64(length) {
		return false
	}
	id := callback_id(packet) or { return false }
	mut channel := transport.channel_for(context) or { return false }
	if channel.depth >= real_max_call_depth {
		return false
	}
	level := channel.depth
	channel.end[level] = u16(lib.align_up(u64(offset) + u64(length), real_iomfb_alignment))
	channel.depth++
	ok := transport.dispatch_callback(id, packet + 12, input_len, packet + 12 + input_len, output_len)
	if channel.depth == 0 {
		return false
	}
	channel.depth--
	if !ok {
		return false
	}
	cpu.dmb_sy()
	return transport.send_ack(context)
}

fn (mut transport RealTransport) handle_rpc_ack(context u8, message u64) bool {
	offset := u16((message >> 16) & 0xffff)
	length := u32(message >> 32)
	base := receive_offset(context) or { return false }
	if offset & u16(real_iomfb_alignment - 1) != 0
		|| u64(offset) + u64(length) > 0x8000 || length < 12 {
		return false
	}
	packet := transport.shmem + base + u64(offset)
	input_len := read_le32_at(packet + 4)
	output_len := read_le32_at(packet + 8)
	if u64(12) + u64(input_len) + u64(output_len) > u64(length) {
		return false
	}
	mut channel := transport.channel_for(context) or { return false }
	if channel.depth == 0 {
		return false
	}
	level := channel.depth - 1
	if offset != channel.offset[level] || length != channel.length[level]
		|| input_len != channel.input_len[level] || output_len != channel.output_len[level]
		|| read_le32_at(packet) != channel.tag[level] {
		return false
	}
	channel.depth = level
	channel.response[level] = packet + 12 + input_len
	channel.completed[level] = true
	return true
}

fn (mut transport RealTransport) receive_one() bool {
	msg := transport.rtk.recv_msg() or { return false }
	ep := u8(msg.data1 & 0xff)
	if ep != real_iomfb_endpoint {
		if !transport.rtk.handle_system_message(msg) {
			transport.poisoned = true
		}
		return true
	}
	kind := u8(msg.data0 & 0xf)
	if kind == 1 {
		transport.initialized = true
		return true
	}
	if kind != 2 {
		C.printf(c'dcp-backlight: unknown endpoint message 0x%llx\n', msg.data0)
		transport.poisoned = true
		return true
	}
	context := u8((msg.data0 >> 8) & 0xf)
	ok := if msg.data0 & (u64(1) << 6) != 0 {
		transport.handle_rpc_ack(context, msg.data0)
	} else {
		transport.handle_callback(context, msg.data0)
	}
	if !ok {
		C.printf(c'dcp-backlight: malformed IOMFB message 0x%llx\n', msg.data0)
		transport.poisoned = true
	}
	return true
}

fn (mut transport RealTransport) wait_initialized() bool {
	deadline := timer.get_ns() + real_boot_timeout_ns
	for timer.get_ns() < deadline {
		transport.receive_one()
		if transport.initialized {
			return true
		}
		if transport.poisoned {
			return false
		}
		asm volatile aarch64 { yield ; ; ; memory }
	}
	println('dcp-backlight: IOMFB shared-memory handshake timed out')
	return false
}

fn (mut transport RealTransport) start_iomfb() bool {
	if !transport.rtk.start_endpoint(real_iomfb_endpoint) {
		return false
	}
	message := (transport.shmem_iova << 16) | (u64(4) << 4)
	if !transport.rtk.send_message(real_iomfb_endpoint, message)
		|| !transport.wait_initialized() {
		return false
	}
	if transport.rpc('A401', unsafe { nil }, 0, 4, real_boot_timeout_ns) == none {
		return false
	}
	mut remap := [8]u8{}
	write_le32_at(u64(&remap[0]), 6)
	if transport.rpc('A426', voidptr(&remap[0]), 8, 8, real_rpc_timeout_ns) == none {
		return false
	}
	mut zero := u32(0)
	savings_tag := if transport.firmware == .v12_3 { 'A447' } else { 'A449' }
	first_tag := if transport.firmware == .v12_3 { 'A454' } else { 'A456' }
	if transport.rpc(savings_tag, voidptr(&zero), 4, 4, real_rpc_timeout_ns) == none
		|| transport.rpc(first_tag, unsafe { nil }, 0, 0, real_rpc_timeout_ns) == none {
		return false
	}
	main_display := transport.rpc('A411', unsafe { nil }, 0, 4, real_rpc_timeout_ns) or { return false }
	if read_le32_at(main_display) == 0 {
		println('dcp-backlight: DCP did not identify itself as the internal display')
		return false
	}
	// Resume the quiesced internal DCP without changing its inherited timing.
	mut handle := u32(0)
	if transport.rpc('A410', voidptr(&handle), 4, 4, real_rpc_timeout_ns) == none {
		return false
	}
	mut power := [12]u8{}
	write_le64_at(u64(&power[0]), 1)
	power_tag := if transport.firmware == .v12_3 { 'A468' } else { 'A472' }
	power_result := transport.rpc(power_tag, voidptr(&power[0]), 12, 8, real_boot_timeout_ns) or { return false }
	if read_le32_at(power_result + 4) != 0 {
		println('dcp-backlight: firmware rejected panel power-on')
		return false
	}
	return true
}

fn (mut transport RealTransport) submit_brightness() bool {
	if transport.device == unsafe { nil } || transport.poisoned {
		return false
	}
	request_size := if transport.firmware == .v12_3 { 0xb64 } else { 0x1884 }
	swap_size := if transport.firmware == .v12_3 { 0x320 } else { 0x468 }
	mut request := [0x1884]u8{}
	if transport.firmware == .v12_3 {
		// Four IOSurface pointers are null in a brightness-only transaction.
		for index in 0 .. 4 {
			request[0xb5e + index] = 1
		}
	} else {
		for index in 0 .. 4 {
			request[0x1877 + index] = 1
		}
		for index in 0 .. 5 {
			request[0x187b + index] = 1
		}
		request[0x1881] = 1
		request[0x1882] = 1
	}
	token := transport.device.prepare_swap(voidptr(&request[0]), u64(swap_size)) or {
		return false
	}
	if token == 0 {
		return true
	}
	mut start := [24]u8{}
	start_result := transport.rpc('A407', voidptr(&start[0]), 24, 24, real_rpc_timeout_ns) or {
		transport.device.complete_swap(token, false)
		return false
	}
	if read_le32_at(start_result + 20) != 0 {
		transport.device.complete_swap(token, false)
		return false
	}
	write_le32_at(u64(&request[0]) + 0x50, read_le32_at(start_result))
	result_len := if transport.firmware == .v12_3 { u32(8) } else { u32(12) }
	result := transport.rpc('A408', voidptr(&request[0]), u32(request_size), result_len, real_rpc_timeout_ns) or {
		transport.device.complete_swap(token, false)
		return false
	}
	status_offset := if transport.firmware == .v12_3 { u64(1) } else { u64(5) }
	accepted := read_le32_at(result + status_offset) == 0
	transport.device.complete_swap(token, accepted)
	return accepted
}

fn real_backlight_notify(context voidptr) {
	if context == unsafe { nil } {
		return
	}
	mut transport := unsafe { &RealTransport(context) }
	event.trigger(mut transport.wake, false)
}

fn real_backlight_worker() {
	mut transport := real_panel_transport
	mut poll_timer := time.new_timer(time.TimeSpec{ tv_nsec: real_worker_period_ns })
	mut events := [&transport.wake, &poll_timer.event]
	for !transport.poisoned {
		event.await(mut events, true) or {}
		poll_timer.disarm()
		for transport.receive_one() {
		}
		if !transport.poisoned {
			if transport.submit_brightness() {
				transport.brightness_failures = 0
			} else {
				transport.brightness_failures++
				if transport.brightness_failures >= real_max_brightness_failures {
					println('dcp-backlight: repeated brightness transaction failure')
					transport.poisoned = true
				}
			}
		}
		poll_timer.when = time.TimeSpec{ tv_nsec: real_worker_period_ns }
		poll_timer.arm()
	}
	if transport.device != unsafe { nil } {
		transport.device.set_online(false)
	}
	println('dcp-backlight: transport stopped after firmware/protocol failure')
	unsafe { events.free() }
	unsafe { free(poll_timer) }
	sched.dequeue_and_die()
}

fn start_real_backlight(mut transport RealTransport) bool {
	if !transport.service_matched || !transport.have_scale {
		println('dcp-backlight: firmware did not publish a usable backlight service/scale')
		return false
	}
	layout := if transport.firmware == .v12_3 {
		backlight.Layout.v12_3
	} else {
		backlight.Layout.v13_3
	}
	device := backlight.register_panel(layout, transport.maximum_nits, transport.brightness_scale, transport.actual_raw_nits, transport.have_actual, voidptr(transport), real_backlight_notify) or {
		println('dcp-backlight: failed to register /dev/apple-panel-bl')
		return false
	}
	transport.device = device
	real_panel_transport = transport
	spawn real_backlight_worker()
	C.printf(c'dcp-backlight: /dev/apple-panel-bl online (max %u nits, scale %u)\n', transport.maximum_nits, transport.brightness_scale)
	return true
}

// Called by the opt-in DCP probe after devtmpfs and the scheduler are live.
fn initialise_real_backlight() bool {
	mut plan := discover_real_plan() or {
		println('dcp-backlight: supported internal-panel topology not found')
		return false
	}
	defer {
		unsafe { plan.registers.free() }
		unsafe { plan.mappings.free() }
		unsafe { plan.display_mappings.free() }
	}
	if !enable_power_domains(plan.dcp_node, 0) {
		println('dcp-backlight: failed to enable DCP power-domain hierarchy')
		return false
	}
	mut transport := &RealTransport{
		firmware: plan.firmware
		rtk: rtkit.new_rtkit(plan.mailbox.base, 'dcp-backlight')
		dcp_dart: dart.new_dart(plan.dcp_dart.base, plan.dcp_sid)
		disp_dart: dart.new_dart(plan.disp_dart.base, plan.disp_sid)
		next_dcp_iova: plan.dcp_iova_base + 0x10000000
		dcp_iova_end: plan.dcp_iova_base + plan.dcp_iova_size
		maximum_nits: plan.maximum_nits
		clock_hz: plan.clock_hz
		bandwidth_scratch: plan.bandwidth_scratch
		bandwidth_scratch_offset: plan.bandwidth_scratch_offset
		bandwidth_doorbell: plan.bandwidth_doorbell
		bandwidth_bit: plan.bandwidth_bit
	}
	transport.register_count = u32(plan.registers.len)
	for index, register in plan.registers {
		transport.registers[index] = register
	}
	if !transport.dcp_dart.init_preserving() {
		println('dcp-backlight: failed to initialize the DCP DART')
		return false
	}
	if !transport.disp_dart.init_preserving() {
		println('dcp-backlight: failed to adopt the locked display DART')
		return false
	}
	for mapping in plan.mappings {
		if !transport.dcp_dart.map(mapping.iova, mapping.phys, mapping.size) {
			println('dcp-backlight: failed to install a firmware DART mapping')
			return false
		}
	}
	for mapping in plan.display_mappings {
		if !transport.disp_dart.map(mapping.iova, mapping.phys, mapping.size) {
			println('dcp-backlight: failed to preserve a PIODMA DART mapping')
			return false
		}
	}
	physical, virtual, iova := transport.allocate_shared(real_iomfb_shmem_size) or {
		println('dcp-backlight: failed to allocate IOMFB shared memory')
		return false
	}
	transport.shmem_phys = physical
	transport.shmem = virtual
	transport.shmem_iova = iova
	transport.rtk.set_shmem_allocator(voidptr(transport), real_rtkit_allocator)

	coproc := memory.map_mmio(plan.coproc.base, plan.coproc.size)
	if coproc == 0 || plan.coproc.size < real_asc_cpu_control + 4 {
		return false
	}
	control := unsafe { &u32(coproc + real_asc_cpu_control) }
	value := kio.mmin32(control)
	kio.mmout32(control, value | real_asc_cpu_run)
	cpu.dsb_sy()
	cpu.isb()
	if !transport.rtk.boot() {
		println('dcp-backlight: RTKit boot failed')
		return false
	}
	if !transport.start_iomfb() || transport.poisoned {
		println('dcp-backlight: IOMFB initialization failed')
		return false
	}
	return start_real_backlight(mut transport)
}
