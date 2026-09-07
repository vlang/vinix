// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module typec

// Apple CD321x display hot-plug monitor for the base M1 (t8103).  The port
// controller uses the P.A. Semi I2C FIFO protocol and TPS6598x-style,
// length-prefixed registers.  We poll instead of claiming the shared GPIO 106
// interrupt: both CD321x controllers use that line, while Vinix does not yet
// have a threaded GPIO IRQ domain capable of doing the required I2C work.
import aarch64.kio
import aarch64.pmgr
import aarch64.timer
import devicetree
import errno
import event
import event.eventstruct
import file
import fs
import katomic
import klock
import memory
import resource
import sched
import stat
import time
import usercopy

#include "apple_display_hotplug.h"

fn C.vinix_display_hotplug_reset(state voidptr)
fn C.vinix_display_hotplug_state_size() u64
fn C.vinix_display_hotplug_sample(state voidptr, status u32, data_status u32,
	now_ms u64, debounce_ms u64) int
fn C.vinix_display_hotplug_connected(state voidptr) int

const fifo_tx = u32(0x00)
const tx_read = u32(1 << 10)
const tx_stop = u32(1 << 9)
const tx_start = u32(1 << 8)
const fifo_rx = u32(0x04)
const rx_empty = u32(1 << 8)
const status_reg = u32(0x14)
const status_ended = u32(1 << 27)
const control_reg = u32(0x1c)
const clear_rx = u32(1 << 10)
const clear_tx = u32(1 << 9)

const cd321x_status = u8(0x1a)
const cd321x_data_status = u8(0x5f)
const poll_interval_ns = i64(100_000_000)
const debounce_ms = u64(500)

struct Domain {
	phandle u32
	region  devicetree.DTReg
	offset  u32
}

struct Plan {
mut:
	i2c     devicetree.DTReg
	address u8
	power   []Domain
}

struct Controller {
mut:
	stat     stat.Stat
	refcount int
	event    eventstruct.Event
	status   int
	can_mmap bool
	base     u64
	address  u8
	state    voidptr
	io_lock  klock.Lock
	l        klock.Lock
	failed   bool
}

fn (mut controller Controller) read(_handle voidptr, buffer voidptr, offset u64,
	count u64) ?i64 {
	controller.l.acquire()
	word := if controller.failed {
		'unavailable\n'
	} else if C.vinix_display_hotplug_connected(controller.state) != 0 {
		'connected\n'
	} else {
		'disconnected\n'
	}
	controller.l.release()
	if offset >= u64(word.len) || count == 0 {
		return 0
	}
	amount := if count < u64(word.len) - offset { count } else { u64(word.len) - offset }
	if !usercopy.copy_to_user(u64(buffer), voidptr(u64(word.str) + offset), amount) {
		errno.set(errno.efault)
		return none
	}
	return i64(amount)
}

fn (mut controller Controller) write(_handle voidptr, _buffer voidptr, _offset u64,
	_count u64) ?i64 {
	errno.set(errno.erofs)
	return none
}

fn (mut controller Controller) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut controller Controller) unref(_handle voidptr) ? {
	katomic.dec(mut &controller.refcount)
}

fn (mut controller Controller) link(_handle voidptr) ? {
	katomic.inc(mut &controller.stat.nlink)
}

fn (mut controller Controller) unlink(_handle voidptr) ? {
	katomic.dec(mut &controller.stat.nlink)
}

fn (mut controller Controller) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.erofs)
	return none
}

fn (mut controller Controller) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

__global (
	monitor         = &Controller(unsafe { nil })
	hotplug_handler fn (bool)
)

fn enabled(node &devicetree.DTNode) bool {
	_ := devicetree.get_property(node, 'status') or { return true }
	values := devicetree.get_string_list(node, 'status') or { return false }
	defer { unsafe { values.free() } }
	return values.len == 1 && (values[0] == 'okay' || values[0] == 'ok')
}

fn compatible(node &devicetree.DTNode, wanted string) bool {
	values := devicetree.get_string_list(node, 'compatible') or { return false }
	defer { unsafe { values.free() } }
	return wanted in values
}

fn has_property(node &devicetree.DTNode, name string) bool {
	_ := devicetree.get_property(node, name) or { return false }
	return true
}

fn display_connector(node &devicetree.DTNode) bool {
	for child in node.children {
		if !compatible(child, 'usb-c-connector') || !has_property(child, 'displayport') {
			continue
		}
		handles := devicetree.get_u32_array(child, 'displayport') or { continue }
		defer { unsafe { handles.free() } }
		if handles.len != 1 {
			continue
		}
		display := devicetree.find_phandle(handles[0]) or { continue }
		if enabled(display) && compatible(display, 'apple,dcpext') {
			return true
		}
	}
	return false
}

fn find_display_hpm(node &devicetree.DTNode, depth int) ?&devicetree.DTNode {
	if depth > 64 || !enabled(node) {
		return none
	}
	if compatible(node, 'apple,cd321x') && display_connector(node) {
		return node
	}
	for child in node.children {
		found := find_display_hpm(child, depth + 1) or { continue }
		return found
	}
	return none
}

fn valid_region(region devicetree.DTReg, minimum u64) bool {
	return region.base != 0 && region.base & 3 == 0 && region.size >= minimum
		&& region.size <= 0x100000 && region.base <= ~u64(0) - region.size
}

fn single_region(node &devicetree.DTNode, minimum u64) ?devicetree.DTReg {
	regions := devicetree.get_translated_reg_ranges(node) or { return none }
	defer { unsafe { regions.free() } }
	if regions.len != 1 || !valid_region(regions[0], minimum) {
		return none
	}
	return regions[0]
}

fn domain(handle u32) ?Domain {
	node := devicetree.find_phandle(handle) or { return none }
	if !enabled(node) || !compatible(node, 'apple,pmgr-pwrstate') || devicetree.get_u32(node, '#power-domain-cells') or {
		u32(1)
	} != 0 {
		return none
	}
	parent := node.parent
	if parent == unsafe { nil } || !compatible(parent, 'apple,t8103-pmgr') {
		return none
	}
	region := single_region(parent, 4) or { return none }
	reg := devicetree.get_u32_array(node, 'reg') or { return none }
	defer { unsafe { reg.free() } }
	if reg.len != 2 || reg[0] & 3 != 0 || reg[1] < 4 || u64(reg[0]) > region.size - 4
		|| u64(reg[1]) > region.size - u64(reg[0]) {
		return none
	}
	return Domain{
		phandle: handle
		region:  region
		offset:  reg[0]
	}
}

fn plan_power(node &devicetree.DTNode, depth int, mut plan Plan) bool {
	if depth > 16 || plan.power.len > 32 {
		return false
	}
	_ := devicetree.get_property(node, 'power-domains') or { return true }
	handles := devicetree.get_u32_array(node, 'power-domains') or { return false }
	defer { unsafe { handles.free() } }
	if handles.len > 8 {
		return false
	}
	for handle in handles {
		mut seen := false
		for existing in plan.power {
			if existing.phandle == handle {
				seen = true
				break
			}
		}
		if seen {
			continue
		}
		d := domain(handle) or { return false }
		provider := devicetree.find_phandle(handle) or { return false }
		if !plan_power(provider, depth + 1, mut plan) || plan.power.len >= 32 {
			return false
		}
		plan.power << d
	}
	return true
}

fn discover(node &devicetree.DTNode, mut plan Plan) bool {
	i2c := node.parent
	if i2c == unsafe { nil } || !enabled(i2c) || !compatible(i2c, 'apple,t8103-i2c') {
		return false
	}
	plan.i2c = single_region(i2c, 0x20) or { return false }
	address := devicetree.get_u32_array(node, 'reg') or { return false }
	defer { unsafe { address.free() } }
	if address.len != 1 || address[0] > 0x7f {
		return false
	}
	plan.address = u8(address[0])
	return plan_power(i2c, 0, mut plan)
}

@[inline]
fn (controller &Controller) read_reg(offset u32) u32 {
	return kio.mmin32(unsafe { &u32(controller.base + offset) })
}

@[inline]
fn (controller &Controller) write_reg(offset u32, value u32) {
	kio.mmout32(unsafe { &u32(controller.base + offset) }, value)
}

fn (controller &Controller) wait_ended() bool {
	for _ in 0 .. 5000 {
		if controller.read_reg(status_reg) & status_ended != 0 {
			return true
		}
		timer.busywait_us(10)
	}
	return false
}

fn (controller &Controller) write_bytes(bytes &u8, length int, start bool, stop bool) bool {
	if start {
		controller.write_reg(fifo_tx, tx_start | (u32(controller.address) << 1))
	}
	for index in 0 .. length {
		mut value := u32(unsafe { bytes[index] })
		if stop && index == length - 1 {
			value |= tx_stop
		}
		controller.write_reg(fifo_tx, value)
	}
	return !stop || controller.wait_ended()
}

fn (controller &Controller) read_bytes(mut output &u8, length int) bool {
	for index in 0 .. length {
		mut value := u32(0)
		mut ready := false
		for _ in 0 .. 5000 {
			value = controller.read_reg(fifo_rx)
			if value & rx_empty == 0 {
				ready = true
				break
			}
			timer.busywait_us(10)
		}
		if !ready {
			return false
		}
		unsafe {
			output[index] = u8(value)
		}
	}
	return true
}

// CD321x SMBus registers put a byte count in front of their payload.  Reject
// both short and long replies: consuming only part of an unexpected response
// leaves the controller FIFO out of phase for the next status read.
fn (mut controller Controller) smbus_read(reg u8, mut output &u8, length int) bool {
	controller.io_lock.acquire()
	defer { controller.io_lock.release() }
	controller.write_reg(control_reg, clear_tx | clear_rx)
	controller.write_reg(status_reg, 0xffff_ffff)
	if !controller.write_bytes(&reg, 1, true, false) {
		return false
	}
	controller.write_reg(fifo_tx, tx_start | (u32(controller.address) << 1) | 1)
	controller.write_reg(fifo_tx, tx_read | tx_stop | u32(length + 1))
	mut reply_length := u8(0)
	if !controller.read_bytes(mut &reply_length, 1) || int(reply_length) != length {
		return false
	}
	if !controller.read_bytes(mut output, length) {
		return false
	}
	return controller.wait_ended()
}

fn read_le32(bytes &u8) u32 {
	return unsafe {
		u32(bytes[0]) | (u32(bytes[1]) << 8) | (u32(bytes[2]) << 16) | (u32(bytes[3]) << 24)
	}
}

fn (mut controller Controller) sample() int {
	mut status := [4]u8{}
	mut data := [4]u8{}
	if !controller.smbus_read(cd321x_status, mut &status[0], 4)
		|| !controller.smbus_read(cd321x_data_status, mut &data[0], 4) {
		return -1
	}
	now_ms := timer.get_ns() / 1_000_000
	controller.l.acquire()
	result := C.vinix_display_hotplug_sample(controller.state, read_le32(&status[0]),
		read_le32(&data[0]), now_ms, debounce_ms)
	controller.l.release()
	return result
}

fn service() {
	mut controller := monitor
	mut poll_timer := time.new_timer(time.TimeSpec{ tv_nsec: poll_interval_ns })
	mut events := [&poll_timer.event]
	mut failures := 0
	for {
		event.await(mut events, true) or {}
		poll_timer.disarm()
		result := controller.sample()
		if result < 0 {
			failures++
			if failures == 5 {
				println('apple-typec: CD321x status reads failed; hot-plug monitor stopped')
				controller.l.acquire()
				controller.failed = true
				controller.l.release()
				event.trigger(mut controller.event, false)
				break
			}
		} else {
			failures = 0
			if result == 1 {
				println('apple-typec: external display connected (debounced HPD)')
				event.trigger(mut controller.event, false)
				if hotplug_handler != unsafe { nil } {
					hotplug_handler(true)
				}
			} else if result == 2 {
				println('apple-typec: external display disconnected (debounced HPD)')
				event.trigger(mut controller.event, false)
				if hotplug_handler != unsafe { nil } {
					hotplug_handler(false)
				}
			}
		}
		poll_timer.when = time.TimeSpec{
			tv_nsec: poll_interval_ns
		}
		poll_timer.arm()
	}
	unsafe {
		events.free()
		free(poll_timer)
	}
	sched.dequeue_and_die()
}

pub fn register_hotplug_handler(handler fn (bool)) {
	hotplug_handler = handler
}

pub fn connected() bool {
	if monitor == unsafe { nil } {
		return false
	}
	mut controller := monitor
	controller.l.acquire()
	value := !controller.failed && C.vinix_display_hotplug_connected(controller.state) != 0
	controller.l.release()
	return value
}

// Must be called from a scheduled kernel thread after the device tree, PMGR
// and timers exist.  Every hardware write follows complete, t8103-specific DT
// discovery; there are no fixed-address fallbacks.
pub fn initialise() bool {
	if monitor != unsafe { nil } {
		return !monitor.failed
	}
	root := devicetree.find_node('/') or {
		println('apple-typec: no device tree; hot-plug unavailable')
		return false
	}
	if !compatible(root, 'apple,t8103') {
		println('apple-typec: hot-plug is currently limited to base M1/t8103')
		return false
	}
	node := find_display_hpm(root, 0) or {
		println('apple-typec: no display-linked CD321x port in the device tree')
		return false
	}
	mut plan := Plan{}
	defer { unsafe { plan.power.free() } }
	if !discover(node, mut plan) {
		println('apple-typec: incomplete CD321x/I2C resources; not probing')
		return false
	}
	base := memory.map_mmio(plan.i2c.base, plan.i2c.size)
	if base == 0 {
		println('apple-typec: I2C MMIO mapping failed')
		return false
	}
	for d in plan.power {
		if !pmgr.enable_region(d.region.base, d.region.size, d.offset) {
			println('apple-typec: I2C power-domain enable failed')
			return false
		}
	}
	mut controller := &Controller{
		base:    base
		address: plan.address
		state:   memory.malloc(C.vinix_display_hotplug_state_size())
		status:  file.pollin
	}
	if controller.state == unsafe { nil } {
		println('apple-typec: state allocation failed')
		unsafe { free(controller) }
		return false
	}
	C.vinix_display_hotplug_reset(controller.state)
	if controller.sample() < 0 {
		println('apple-typec: initial CD321x status read failed')
		unsafe {
			free(controller.state)
			free(controller)
		}
		return false
	}
	monitor = controller
	controller.stat.size = 0
	controller.stat.blksize = 16
	controller.stat.rdev = resource.create_dev_id()
	controller.stat.mode = 0o444 | stat.ifchr
	fs.devtmpfs_add_device(controller, 'display-hpd')
	C.printf(c'apple-typec: polling display port 0x%x on I2C 0x%llx\n', controller.address,
		plan.i2c.base)
	spawn service()
	return true
}
