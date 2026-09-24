// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A polled xHCI driver for USB keyboards and pointers.
//
// VirtualBox's arm64 machine has neither PS/2 nor virtio input: its keyboard
// and tablet are USB devices behind an xHCI controller on PCIe. This is as much
// of xHCI as driving them takes -- one interrupter, polled from the idle loop
// the way virtio-input is, no hubs, no hotplug -- and it hands what they report
// to virtio_input, whose state the console and /dev/pointer already read. QEMU's
// qemu-xhci with usb-kbd and usb-tablet is the same arrangement, and is how
// this is tested.
//
// Every register is accessed 32 bits at a time through the out-of-line helpers
// below. A 64-bit register is two such writes, low half first, which the
// specification allows; a paired or post-indexed access is one a hypervisor
// cannot decode (see aarch64/gic).
@[has_globals]
module xhci

import pci
import memory
import aarch64.cpu
import aarch64.timer
import aarch64.virtio_input

// TRB types.
const trb_normal = u32(1)
const trb_setup = u32(2)
const trb_data = u32(3)
const trb_status = u32(4)
const trb_link = u32(6)
const trb_enable_slot = u32(9)
const trb_address_device = u32(11)
const trb_configure_endpoint = u32(12)
const trb_evaluate_context = u32(13)
const trb_transfer_event = u32(32)
const trb_command_completion = u32(33)

// TRB control bits.
const trb_cycle = u32(1)
const trb_toggle_cycle = u32(1) << 1
const trb_isp = u32(1) << 2
const trb_ioc = u32(1) << 5
const trb_idt = u32(1) << 6

// Completion codes.
const cc_success = u32(1)
const cc_short_packet = u32(13)

// Operational registers.
const op_usbcmd = u64(0x00)
const op_usbsts = u64(0x04)
const op_crcr = u64(0x18)
const op_dcbaap = u64(0x30)
const op_config = u64(0x38)
const op_ports = u64(0x400)

const usbcmd_run = u32(1)
const usbcmd_reset = u32(1) << 1
const usbsts_halted = u32(1)
const usbsts_not_ready = u32(1) << 11

// PORTSC bits. The change bits and PED are write-1-to-clear, and writing PR or
// WPR starts a reset, so a write that means to change none of them must have
// them all clear.
const portsc_connected = u32(1)
const portsc_enabled = u32(1) << 1
const portsc_reset = u32(1) << 4
const portsc_reset_change = u32(1) << 21
const portsc_write_mask = ~(u32(0x80FE0012) | (u32(1) << 16))

// One page of 16-byte TRBs per ring. A transfer or command ring gives its last
// slot to a link back to the start.
const ring_trbs = u32(256)

const max_slots = u32(16)
const max_functions = 8

pub struct Ring {
mut:
	phys  u64
	virt  u64
	index u32
	cycle u32
}

pub struct Event {
pub:
	param   u64
	status  u32
	control u32
}

// A USB device as it is enumerated: its slot, the port it hangs off, and the
// scratch memory its control transfers use.
struct Device {
mut:
	slot        u32
	port        u32
	speed       u32
	ep0         Ring
	input_phys  u64
	input_virt  u64
	output_phys u64
	buf_phys    u64
	buf_virt    u64
}

__global (
	xhci_ready        bool
	xhci_cap          u64
	xhci_op           u64
	xhci_db           u64
	xhci_ir0          u64
	xhci_ctx_size     u64
	xhci_ports        u32
	xhci_slots        u32
	xhci_dcbaa_virt   u64
	xhci_cmd          Ring
	xhci_event_phys   u64
	xhci_event_virt   u64
	xhci_event_index  u32
	xhci_event_cycle  u32
	xhci_functions    [8]HidFunction
	xhci_function_cnt int
)

fn hhdm() u64 {
	return memory.get_hhdm_offset()
}

@[noinline]
fn rd(addr u64) u32 {
	value := unsafe { *&u32(addr) }
	cpu.dmb_ish()
	return value
}

@[noinline]
fn wr(addr u64, value u32) {
	cpu.dmb_ish()
	unsafe {
		*&u32(addr) = value
	}
}

fn wr64(addr u64, value u64) {
	wr(addr, u32(value))
	wr(addr + 4, u32(value >> 32))
}

// Memory the controller reads or writes. It is ordinary cacheable RAM: every
// hypervisor this runs under sees the guest's memory coherently.
@[noinline]
fn mem_rd(addr u64) u32 {
	return unsafe { *&u32(addr) }
}

@[noinline]
fn mem_wr(addr u64, value u32) {
	unsafe {
		*&u32(addr) = value
	}
}

fn mem_wr64(addr u64, value u64) {
	mem_wr(addr, u32(value))
	mem_wr(addr + 4, u32(value >> 32))
}

fn alloc_page() (u64, u64) {
	phys := u64(memory.pmm_alloc(1))
	return phys, phys + hhdm()
}

fn halted() bool {
	return rd(xhci_op + op_usbsts) & usbsts_halted != 0
}

fn running() bool {
	return rd(xhci_op + op_usbsts) & usbsts_halted == 0
}

fn reset_done() bool {
	return rd(xhci_op + op_usbcmd) & usbcmd_reset == 0
		&& rd(xhci_op + op_usbsts) & usbsts_not_ready == 0
}

// Spin until `cond` holds or `timeout_ms` passes.
fn wait_for(timeout_ms u64, cond fn () bool) bool {
	deadline := timer.get_ns() + timeout_ms * 1000000
	for !cond() {
		if timer.get_ns() > deadline {
			return false
		}
	}
	return true
}

fn new_ring() Ring {
	phys, virt := alloc_page()
	link := virt + u64(ring_trbs - 1) * 16
	mem_wr64(link, phys)
	mem_wr(link + 8, 0)
	mem_wr(link + 12, (trb_link << 10) | trb_toggle_cycle)
	return Ring{
		phys:  phys
		virt:  virt
		index: 0
		cycle: 1
	}
}

// Queue one TRB and return its physical address. The cycle bit is written
// last, which is what hands the TRB to the controller.
fn (mut r Ring) push(d0 u32, d1 u32, d2 u32, d3 u32) u64 {
	addr := r.virt + u64(r.index) * 16
	phys := r.phys + u64(r.index) * 16
	mem_wr(addr, d0)
	mem_wr(addr + 4, d1)
	mem_wr(addr + 8, d2)
	cpu.dmb_ish()
	mem_wr(addr + 12, (d3 & ~trb_cycle) | r.cycle)
	r.index++
	if r.index == ring_trbs - 1 {
		link := r.virt + u64(ring_trbs - 1) * 16
		control := mem_rd(link + 12)
		cpu.dmb_ish()
		mem_wr(link + 12, (control & ~trb_cycle) | r.cycle)
		r.index = 0
		r.cycle ^= 1
	}
	return phys
}

fn ring_doorbell(slot u32, target u32) {
	cpu.dsb_sy()
	wr(xhci_db + u64(slot) * 4, target)
}

fn event_type(ev Event) u32 {
	return (ev.control >> 10) & 0x3f
}

fn event_code(ev Event) u32 {
	return ev.status >> 24
}

fn event_slot(ev Event) u32 {
	return ev.control >> 24
}

fn event_endpoint(ev Event) u32 {
	return (ev.control >> 16) & 0x1f
}

// The next event the controller has written, if there is one.
fn next_event() ?Event {
	addr := xhci_event_virt + u64(xhci_event_index) * 16
	control := mem_rd(addr + 12)
	if control & trb_cycle != xhci_event_cycle {
		return none
	}
	cpu.dmb_ish()
	ev := Event{
		param:   u64(mem_rd(addr)) | (u64(mem_rd(addr + 4)) << 32)
		status:  mem_rd(addr + 8)
		control: control
	}
	xhci_event_index++
	if xhci_event_index == ring_trbs {
		xhci_event_index = 0
		xhci_event_cycle ^= 1
	}
	// Tell the controller how far the ring has been read; EHB is write-1-to-clear.
	wr64(xhci_ir0 + 0x18, (xhci_event_phys + u64(xhci_event_index) * 16) | 8)
	return ev
}

// Issue a command and wait for its completion. Events for anything else that
// arrive meanwhile are dealt with as the poller would.
fn command(d0 u32, d1 u32, d2 u32, d3 u32) ?Event {
	trb := xhci_cmd.push(d0, d1, d2, d3)
	ring_doorbell(0, 0)
	deadline := timer.get_ns() + 1000000000
	for timer.get_ns() < deadline {
		ev := next_event() or { continue }
		if event_type(ev) == trb_command_completion && ev.param == trb {
			if event_code(ev) != cc_success {
				println('xhci: command ${(d3 >> 10) & 0x3f} failed with code ${event_code(ev)}')
				return none
			}
			return ev
		}
		handle_event(ev)
	}
	println('xhci: command ${(d3 >> 10) & 0x3f} timed out')
	return none
}

// Wait for the transfer event that finishes a TD whose last TRB is `trb`. An
// error is reported against whichever TRB hit it, so any failure on the
// endpoint ends the wait too.
fn await_transfer(slot u32, dci u32, trb u64) ?Event {
	deadline := timer.get_ns() + 1000000000
	for timer.get_ns() < deadline {
		ev := next_event() or { continue }
		if event_type(ev) == trb_transfer_event && event_slot(ev) == slot
			&& event_endpoint(ev) == dci {
			code := event_code(ev)
			if ev.param == trb || (code != cc_success && code != cc_short_packet) {
				if code != cc_success && code != cc_short_packet {
					return none
				}
				return ev
			}
			continue
		}
		handle_event(ev)
	}
	return none
}

// A control transfer on endpoint 0. With `length` > 0 the data stage reads
// that many bytes into the device's buffer when `request_type` is IN, and
// writes them from it when it is OUT.
fn control(mut dev Device, request_type u8, request u8, value u16, index u16, length u16) bool {
	data_in := request_type & 0x80 != 0
	mut transfer_type := u32(0)
	if length > 0 {
		transfer_type = if data_in { u32(3) } else { u32(2) }
	}
	dev.ep0.push(u32(request_type) | (u32(request) << 8) | (u32(value) << 16),
		u32(index) | (u32(length) << 16), 8, (trb_setup << 10) | trb_idt | (transfer_type << 16))
	if length > 0 {
		dev.ep0.push(u32(dev.buf_phys), u32(dev.buf_phys >> 32), u32(length),
			(trb_data << 10) | (if data_in { u32(1) << 16 } else { u32(0) }))
	}
	// The status stage runs the other way from the data, or IN without data.
	status_in := length == 0 || !data_in
	last := dev.ep0.push(0, 0, 0, (trb_status << 10) | trb_ioc | (if status_in {
		u32(1) << 16
	} else {
		u32(0)
	}))
	ring_doorbell(dev.slot, 1)
	await_transfer(dev.slot, 1, last) or { return false }
	return true
}

fn ctx(base u64, index u64) u64 {
	return base + index * xhci_ctx_size
}

fn clear_input(dev &Device) {
	for off := u64(0); off < 33 * xhci_ctx_size; off += 4 {
		mem_wr(dev.input_virt + off, 0)
	}
}

// Endpoint 0's context, into the input context.
fn write_ep0(dev &Device, max_packet u32) {
	ep0 := ctx(dev.input_virt, 2)
	// Error count 3, type 4 (control), and the packet size.
	mem_wr(ep0 + 4, (3 << 1) | (4 << 3) | (max_packet << 16))
	mem_wr64(ep0 + 8, dev.ep0.phys | 1)
	mem_wr(ep0 + 16, 8)
}

fn write_slot(dev &Device, context_entries u32) {
	slot := ctx(dev.input_virt, 1)
	mem_wr(slot, (context_entries << 27) | (dev.speed << 20))
	mem_wr(slot + 4, dev.port << 16)
}

fn address_device(mut dev Device, max_packet u32) bool {
	clear_input(dev)
	mem_wr(ctx(dev.input_virt, 0) + 4, 0b11)
	write_slot(dev, 1)
	write_ep0(dev, max_packet)
	mem_wr64(xhci_dcbaa_virt + u64(dev.slot) * 8, dev.output_phys)
	command(u32(dev.input_phys), u32(dev.input_phys >> 32), 0, (trb_address_device << 10) | (dev.slot << 24)) or {
		return false
	}
	return true
}

// A full-speed device's first descriptor read says how big its control
// packets really are; tell the controller if that is not the 8 it started with.
fn set_ep0_packet(mut dev Device, max_packet u32) bool {
	clear_input(dev)
	mem_wr(ctx(dev.input_virt, 0) + 4, 0b10)
	write_ep0(dev, max_packet)
	command(u32(dev.input_phys), u32(dev.input_phys >> 32), 0, (trb_evaluate_context << 10) | (dev.slot << 24)) or {
		return false
	}
	return true
}

fn buf_u8(dev &Device, offset u64) u8 {
	return unsafe { *&u8(dev.buf_virt + offset) }
}

fn buf_u16(dev &Device, offset u64) u16 {
	return u16(buf_u8(dev, offset)) | (u16(buf_u8(dev, offset + 1)) << 8)
}

fn port_register(port u32) u64 {
	return xhci_op + op_ports + u64(port - 1) * 0x10
}

// Reset a USB 2 port so it is enabled; a USB 3 port enables itself.
fn reset_port(port u32) bool {
	reg := port_register(port)
	mut sc := rd(reg)
	if sc & portsc_enabled != 0 {
		return true
	}
	wr(reg, (sc & portsc_write_mask) | portsc_reset)
	deadline := timer.get_ns() + 500000000
	for timer.get_ns() < deadline {
		sc = rd(reg)
		if sc & portsc_reset_change != 0 {
			break
		}
	}
	wr(reg, (rd(reg) & portsc_write_mask) | portsc_reset_change)
	timer.busywait_us(20000)
	return rd(reg) & portsc_enabled != 0
}

// Enumerate the device on `port` and take it into use if it is a keyboard or
// a pointer.
fn attach(port u32) {
	if !reset_port(port) {
		println('xhci: port ${port} did not enable')
		return
	}
	speed := (rd(port_register(port)) >> 10) & 0xf
	ev := command(0, 0, 0, trb_enable_slot << 10) or { return }

	mut dev := Device{
		slot:  event_slot(ev)
		port:  port
		speed: speed
		ep0:   new_ring()
	}
	dev.input_phys, dev.input_virt = alloc_page()
	dev.output_phys, _ = alloc_page()
	dev.buf_phys, dev.buf_virt = alloc_page()

	// Low and full speed start at 8 bytes, high speed is 64, SuperSpeed 512.
	mut max_packet := match speed {
		3 { u32(64) }
		4, 5 { u32(512) }
		else { u32(8) }
	}
	if !address_device(mut dev, max_packet) {
		return
	}
	if !control(mut dev, 0x80, 6, 0x0100, 0, 8) {
		println('xhci: port ${port}: no device descriptor')
		return
	}
	if speed < 3 && u32(buf_u8(&dev, 7)) != max_packet && buf_u8(&dev, 7) >= 8 {
		max_packet = u32(buf_u8(&dev, 7))
		if !set_ep0_packet(mut dev, max_packet) {
			return
		}
	}
	if !control(mut dev, 0x80, 6, 0x0200, 0, 9) {
		return
	}
	mut total := buf_u16(&dev, 2)
	if total > 1024 {
		total = 1024
	}
	if !control(mut dev, 0x80, 6, 0x0200, 0, total) {
		return
	}
	take_hid_functions(mut dev, u64(total))
}

// Bring the controller up. Returns false if there is none.
pub fn initialise() bool {
	dev := pci.get_device_by_class(0x0c, 0x03, 0x30, 0) or { return false }
	bar := dev.get_bar(0)
	if !bar.is_mmio || bar.base == 0 {
		println('xhci: controller has no memory BAR')
		return false
	}
	// Memory decoding and bus mastering on; the legacy interrupt off, since
	// this driver polls.
	command_reg := dev.read[u32](0x4)
	dev.write[u32](0x4, (command_reg | 0x6) | (u32(1) << 10))

	size := if bar.size >= 0x10000 { bar.size } else { u64(0x10000) }
	xhci_cap = memory.map_mmio(bar.base, size)
	cap_length := u64(rd(xhci_cap) & 0xff)
	hcs1 := rd(xhci_cap + 4)
	hcs2 := rd(xhci_cap + 8)
	hcc1 := rd(xhci_cap + 0x10)
	xhci_op = xhci_cap + cap_length
	xhci_db = xhci_cap + u64(rd(xhci_cap + 0x14) & ~u32(3))
	xhci_ir0 = xhci_cap + u64(rd(xhci_cap + 0x18) & ~u32(0x1f)) + 0x20
	xhci_ctx_size = if hcc1 & (1 << 2) != 0 { u64(64) } else { u64(32) }
	xhci_ports = hcs1 >> 24
	xhci_slots = hcs1 & 0xff
	if xhci_slots > max_slots {
		xhci_slots = max_slots
	}
	println('xhci: controller at 0x${bar.base:x}, ${xhci_ports} ports, ${xhci_slots} slots')

	take_ownership((hcc1 >> 16) << 2)

	// Stop it, then reset it.
	wr(xhci_op + op_usbcmd, rd(xhci_op + op_usbcmd) & ~usbcmd_run)
	if !wait_for(100, halted) {
		println('xhci: controller did not halt')
		return false
	}
	wr(xhci_op + op_usbcmd, usbcmd_reset)
	if !wait_for(1000, reset_done) {
		println('xhci: controller did not come out of reset')
		return false
	}

	wr(xhci_op + op_config, xhci_slots)

	// The device context array, with entry 0 pointing at the scratchpad the
	// controller asked for, if any.
	dcbaa_phys, dcbaa_virt := alloc_page()
	xhci_dcbaa_virt = dcbaa_virt
	scratchpads := (((hcs2 >> 21) & 0x1f) << 5) | ((hcs2 >> 27) & 0x1f)
	if scratchpads > 0 {
		array_phys, array_virt := alloc_page()
		for i := u64(0); i < u64(scratchpads) && i < 512; i++ {
			page_phys, _ := alloc_page()
			mem_wr64(array_virt + i * 8, page_phys)
		}
		mem_wr64(dcbaa_virt, array_phys)
	}
	wr64(xhci_op + op_dcbaap, dcbaa_phys)

	xhci_cmd = new_ring()
	wr64(xhci_op + op_crcr, xhci_cmd.phys | 1)

	// One event ring segment, a page long, for interrupter 0.
	xhci_event_phys, xhci_event_virt = alloc_page()
	xhci_event_index = 0
	xhci_event_cycle = 1
	erst_phys, erst_virt := alloc_page()
	mem_wr64(erst_virt, xhci_event_phys)
	mem_wr(erst_virt + 8, ring_trbs)
	wr(xhci_ir0 + 0x8, 1)
	wr64(xhci_ir0 + 0x18, xhci_event_phys)
	wr64(xhci_ir0 + 0x10, erst_phys)

	wr(xhci_op + op_usbcmd, usbcmd_run)
	if !wait_for(100, running) {
		println('xhci: controller did not start')
		return false
	}

	// Give the ports a moment to report what is plugged into them.
	timer.busywait_us(100000)
	for port := u32(1); port <= xhci_ports; port++ {
		if rd(port_register(port)) & portsc_connected != 0 {
			attach(port)
		}
	}
	for i := 0; i < xhci_function_cnt; i++ {
		queue_report(mut xhci_functions[i])
	}
	cpu.dmb_ish()
	xhci_ready = true
	virtio_input.set_extra_poller(voidptr(poll))
	println('xhci: ${xhci_function_cnt} input device(s)')
	return true
}

// Firmware that used the controller itself hands it over through the USB
// Legacy Support capability.
fn take_ownership(first u64) {
	mut offset := first
	for steps := 0; offset != 0 && steps < 64; steps++ {
		reg := xhci_cap + offset
		value := rd(reg)
		if value & 0xff == 1 {
			wr(reg, value | (u32(1) << 24))
			deadline := timer.get_ns() + 1000000000
			for rd(reg) & (u32(1) << 16) != 0 && timer.get_ns() < deadline {
			}
			// SMI enables off; their status bits are write-1-to-clear.
			wr(reg + 4, (rd(reg + 4) & 0xffff1fee) | 0xe0000000)
			return
		}
		next := u64((value >> 8) & 0xff)
		if next == 0 {
			return
		}
		offset += next << 2
	}
}

fn handle_event(ev Event) {
	if event_type(ev) != trb_transfer_event {
		return
	}
	slot := event_slot(ev)
	dci := event_endpoint(ev)
	for i := 0; i < xhci_function_cnt; i++ {
		mut f := &xhci_functions[i]
		if f.slot != slot || f.dci != dci {
			continue
		}
		code := event_code(ev)
		if code == cc_success || code == cc_short_packet {
			residual := ev.status & 0xffffff
			length := if residual < f.packet { f.packet - residual } else { u32(0) }
			f.report(length)
		}
		queue_report(mut f)
		return
	}
}

// Called from virtio_input.poll(), under its lock.
fn poll() {
	if !xhci_ready {
		return
	}
	for {
		ev := next_event() or { break }
		handle_event(ev)
	}
	repeat_keys()
}
