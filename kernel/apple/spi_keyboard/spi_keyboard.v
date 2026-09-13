// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module spi_keyboard

import aarch64.kio
import aarch64.pmgr
import devicetree
import klock
import memory

#include "apple_spi_keyboard.h"

fn C.vinix_apple_spi_keyboard_init(spi u64, enable u64, enable_low int, ready u64, ready_low int, input_hz u32, maximum_hz u32) int
fn C.vinix_apple_spi_keyboard_poll(output &u8, capacity u64, application_cursor int) int
fn C.vinix_apple_spi_keyboard_reports() u64
fn C.vinix_apple_spi_touchpad_reports() u64
fn C.vinix_call_void_fn(callback voidptr)

__global (
	apple_spi_keyboard_lock klock.Lock
	apple_spi_keyboard_enabled = false
	apple_spi_keyboard_probed = false
	apple_spi_keyboard_reported = false
	apple_spi_pointer_callback = voidptr(0)
)

// /dev/pointer registers this after it has published its event resource. The
// callback boundary avoids making the shared SPI transport depend on a device
// that already imports it for snapshots.
pub fn set_pointer_event_callback(callback voidptr) {
	apple_spi_pointer_callback = callback
}

struct Gpio {
	region     devicetree.DTReg
	pin        u32
	active_low bool
	provider   &devicetree.DTNode = unsafe { nil }
}

struct PinMux {
	region   devicetree.DTReg
	pin      u32
	function u32
}

struct PowerDomain {
	phandle u32
	region  devicetree.DTReg
	offset  u32
}

struct Plan {
mut:
	spi        devicetree.DTReg
	enable     Gpio
	ready      Gpio
	has_ready  bool
	input_hz   u32
	maximum_hz u32
	pins       []PinMux
	power      []PowerDomain
}

fn compatible(node &devicetree.DTNode, name string) bool {
	values := devicetree.get_string_list(node, 'compatible') or { return false }
	defer { unsafe { values.free() } }
	for value in values {
		if value == name {
			return true
		}
	}
	return false
}

fn enabled(node &devicetree.DTNode) bool {
	mut current := node
	// Do not probe a child of a disabled bus. Bound even malformed ancestry.
	for _ in 0 .. 64 {
		if current == unsafe { nil } {
			return true
		}
		status := devicetree.get_string_prop(current, 'status') or { 'okay' }
		if status != 'okay' && status != 'ok' {
			return false
		}
		current = current.parent
	}
	return false
}

fn find_keyboard(node &devicetree.DTNode, depth int) ?&devicetree.DTNode {
	if depth > 64 || !enabled(node) {
		return none
	}
	if compatible(node, 'apple,spi-hid-transport') {
		return node
	}
	for child in node.children {
		found := find_keyboard(child, depth + 1) or { continue }
		return found
	}
	return none
}

fn has_property(node &devicetree.DTNode, name string) bool {
	_ := devicetree.get_property(node, name) or { return false }
	return true
}

fn first_region(node &devicetree.DTNode, minimum u64) ?devicetree.DTReg {
	regions := devicetree.get_translated_reg_ranges(node) or { return none }
	defer { unsafe { regions.free() } }
	if regions.len != 1 {
		return none
	}
	r := regions[0]
	if r.base == 0 || r.base & 3 != 0 || r.size < minimum || r.size > 0x100000
		|| r.base > ~u64(0) - r.size {
		return none
	}
	return r
}

// Apple PMGR providers have zero argument cells and a reg offset into their
// enclosing syscon. That offset is NOT a physical address or a generic ID.
// Build the entire dependency plan before performing any MMIO writes.
fn plan_power(node &devicetree.DTNode, depth int, mut plan Plan) bool {
	if depth > 16 || plan.power.len > 64 {
		return false
	}
	if !has_property(node, 'power-domains') {
		return true
	}
	handles := devicetree.get_u32_array(node, 'power-domains') or { return false }
	defer { unsafe { handles.free() } }
	if handles.len > 8 {
		return false
	}
	for handle in handles {
		mut seen := false
		for domain in plan.power {
			if domain.phandle == handle {
				seen = true
				break
			}
		}
		if seen {
			continue
		}
		domain := devicetree.find_phandle(handle) or { return false }
		if !enabled(domain) || !compatible(domain, 'apple,pmgr-pwrstate')
			|| devicetree.get_u32(domain, '#power-domain-cells') or { u32(1) } != 0 {
			return false
		}
		parent := domain.parent
		if parent == unsafe { nil } || !compatible(parent, 'apple,t8103-pmgr')
			|| devicetree.get_u32(parent, '#address-cells') or { u32(0) } != 1
			|| devicetree.get_u32(parent, '#size-cells') or { u32(0) } != 1 {
			return false
		}
		region := first_region(parent, 4) or { return false }
		reg := devicetree.get_u32_array(domain, 'reg') or { return false }
		defer { unsafe { reg.free() } }
		if reg.len != 2 || reg[0] & 3 != 0 || reg[1] < 4
			|| u64(reg[0]) > region.size - 4 || u64(reg[1]) > region.size - u64(reg[0]) {
			return false
		}
		if !plan_power(domain, depth + 1, mut plan) || plan.power.len >= 64 {
			return false
		}
		plan.power << PowerDomain{phandle: handle, region: region, offset: reg[0]}
	}
	return true
}

fn gpio_region(provider &devicetree.DTNode, pin u32) ?devicetree.DTReg {
	if !enabled(provider) || !compatible(provider, 'apple,t8103-pinctrl')
		|| !has_property(provider, 'gpio-controller')
		|| devicetree.get_u32(provider, '#gpio-cells') or { u32(0) } != 2 {
		return none
	}
	region := first_region(provider, 4) or { return none }
	// Check the actual GPIO count, not just the much larger register aperture.
	ranges := devicetree.get_u32_array(provider, 'gpio-ranges') or { return none }
	defer { unsafe { ranges.free() } }
	if ranges.len != 4 || ranges[1] != 0 || ranges[2] != 0 || pin >= ranges[3]
		|| u64(ranges[3]) > region.size / 4 {
		return none
	}
	range_provider := devicetree.find_phandle(ranges[0]) or { return none }
	if range_provider != provider {
		return none
	}
	return region
}

fn enable_gpio(node &devicetree.DTNode) ?Gpio {
	cells := devicetree.get_u32_array(node, 'spien-gpios') or { return none }
	defer { unsafe { cells.free() } }
	if cells.len != 3 || cells[2] & ~u32(1) != 0 {
		return none // Only push-pull GPIO_ACTIVE_HIGH/LOW is supported.
	}
	provider := devicetree.find_phandle(cells[0]) or { return none }
	region := gpio_region(provider, cells[1]) or { return none }
	return Gpio{region: region, pin: cells[1], active_low: cells[2] == 1, provider: provider}
}

fn ready_gpio(node &devicetree.DTNode) ?Gpio {
	cells := devicetree.get_u32_array(node, 'interrupts-extended') or { return none }
	defer { unsafe { cells.free() } }
	if cells.len != 3 || (cells[2] != 1 && cells[2] != 2 && cells[2] != 4 && cells[2] != 8) {
		return none
	}
	provider := devicetree.find_phandle(cells[0]) or { return none }
	if devicetree.get_u32(provider, '#interrupt-cells') or { u32(0) } != 2 {
		return none
	}
	region := gpio_region(provider, cells[1]) or { return none }
	return Gpio{region: region, pin: cells[1], active_low: cells[2] == 2 || cells[2] == 8,
		provider: provider}
}

fn discover(node &devicetree.DTNode, mut plan Plan) bool {
	spi := node.parent
	if spi == unsafe { nil } || !compatible(spi, 'apple,t8103-spi') || !enabled(spi) {
		return false
	}
	// This driver owns one native, active-low chip select, in SPI mode 0.
	cs := devicetree.get_u32_array(node, 'reg') or { return false }
	defer { unsafe { cs.free() } }
	if cs.len != 1 || cs[0] != 0 || has_property(spi, 'cs-gpios')
		|| has_property(node, 'spi-cpha') || has_property(node, 'spi-cpol')
		|| has_property(node, 'spi-cs-high') || has_property(node, 'spi-lsb-first')
		|| has_property(node, 'spi-3wire') {
		return false
	}
	plan.spi = first_region(spi, 0x158) or { return false }
	plan.maximum_hz = devicetree.get_u32(node, 'spi-max-frequency') or { return false }
	if plan.maximum_hz == 0 || plan.maximum_hz > 8000000 {
		return false
	}
	clocks := devicetree.get_u32_array(spi, 'clocks') or { return false }
	defer { unsafe { clocks.free() } }
	if clocks.len != 1 {
		return false
	}
	clock := devicetree.find_phandle(clocks[0]) or { return false }
	if !enabled(clock) || !compatible(clock, 'fixed-clock')
		|| devicetree.get_u32(clock, '#clock-cells') or { u32(1) } != 0 {
		return false
	}
	plan.input_hz = devicetree.get_u32(clock, 'clock-frequency') or { return false }
	if plan.input_hz == 0 || (u64(plan.input_hz) + plan.maximum_hz - 1) / plan.maximum_hz > 0x7ff {
		return false
	}
	plan.enable = enable_gpio(node) or { return false }
	if ready := ready_gpio(node) {
		if ready.region.base != plan.enable.region.base || ready.pin != plan.enable.pin {
			plan.ready = ready
			plan.has_ready = true
		}
	}
	// SPI power is mandatory; GPIO providers may be always-on with no domains.
	if !has_property(spi, 'power-domains') || !plan_power(spi, 0, mut plan)
		|| !plan_power(plan.enable.provider, 0, mut plan) {
		return false
	}
	if plan.has_ready && !plan_power(plan.ready.provider, 0, mut plan) {
		return false
	}
	groups := devicetree.get_u32_array(spi, 'pinctrl-0') or { return false }
	defer { unsafe { groups.free() } }
	if groups.len > 8 {
		return false
	}
	for handle in groups {
		group := devicetree.find_phandle(handle) or { return false }
		provider := group.parent
		if provider == unsafe { nil } || !enabled(group) {
			return false
		}
		pins := devicetree.get_u32_array(group, 'pinmux') or { return false }
		defer { unsafe { pins.free() } }
		if pins.len > 16 || !plan_power(provider, 0, mut plan) {
			return false
		}
		for encoded in pins {
			// APPLE_PINMUX(pin, function) = pin | (function << 16).
			pin := encoded & 0xffff
			function := encoded >> 16
			region := gpio_region(provider, pin) or { return false }
			if function > 3 || plan.pins.len >= 16
				|| (region.base == plan.enable.region.base && pin == plan.enable.pin)
				|| (plan.has_ready && region.base == plan.ready.region.base && pin == plan.ready.pin) {
				return false
			}
			plan.pins << PinMux{region: region, pin: pin, function: function}
		}
	}
	return plan.pins.len > 0
}

pub fn initialise() {
	$if no_apple_spi_keyboard ? {
		println('apple-spi-kbd: disabled at build time')
	} $else {
		initialise_hardware()
	}
}

fn initialise_hardware() {
	apple_spi_keyboard_lock.acquire()
	defer { apple_spi_keyboard_lock.release() }
	if apple_spi_keyboard_enabled {
		return
	}
	root := devicetree.find_node('/') or {
		println('apple-spi-kbd: no device tree; not probing')
		return
	}
	// Deliberately do not guess addresses or bind newer DockChannel/MTP Macs.
	if !compatible(root, 'apple,t8103') {
		return
	}
	node := find_keyboard(root, 0) or {
		println('apple-spi-kbd: no enabled apple,spi-hid-transport node')
		return
	}
	mut plan := Plan{}
	defer {
		unsafe {
			plan.pins.free()
			plan.power.free()
		}
	}
	if !discover(node, mut plan) {
		println('apple-spi-kbd: unsupported or incomplete DT resources; not probing')
		return
	}
	spi := memory.map_mmio(plan.spi.base, plan.spi.size)
	enable_base := memory.map_mmio(plan.enable.region.base, plan.enable.region.size)
	if spi == 0 || enable_base == 0 {
		println('apple-spi-kbd: MMIO mapping failed')
		return
	}
	mut ready_reg := u64(0)
	if plan.has_ready {
		base := memory.map_mmio(plan.ready.region.base, plan.ready.region.size)
		if base == 0 {
			println('apple-spi-kbd: ready GPIO mapping failed')
			return
		}
		ready_reg = base + u64(plan.ready.pin) * 4
	}
	mut pin_registers := []u64{cap: plan.pins.len}
	defer { unsafe { pin_registers.free() } }
	for pin in plan.pins {
		base := memory.map_mmio(pin.region.base, pin.region.size)
		if base == 0 {
			println('apple-spi-kbd: pinmux mapping failed')
			return
		}
		pin_registers << base + u64(pin.pin) * 4
	}
	for domain in plan.power {
		if !pmgr.enable_region(domain.region.base, domain.region.size, domain.offset) {
			println('apple-spi-kbd: power-domain enable failed')
			return
		}
	}
	for index, pin in plan.pins {
		reg := unsafe { &u32(pin_registers[index]) }
		value := kio.mmin32(reg)
		// Preserve pulls/drive configuration, select the peripheral, enable input.
		kio.mmout32(reg, (value & ~u32(0x6f)) | (pin.function << 5) | (u32(1) << 9))
	}
	if ready_reg != 0 {
		reg := unsafe { &u32(ready_reg) }
		value := kio.mmin32(reg)
		kio.mmout32(reg, (value & ~u32(0x6e)) | (u32(1) << 9))
	}
	if C.vinix_apple_spi_keyboard_init(spi, enable_base + u64(plan.enable.pin) * 4,
		int(plan.enable.active_low), ready_reg, int(plan.ready.active_low),
		plan.input_hz, plan.maximum_hz) == 0 {
		println('apple-spi-kbd: controller initialization failed')
		return
	}
	// `probed` says the hardware was found and is ours to poll; `enabled` says
	// the transport is currently up. They part company while it is recovering.
	apple_spi_keyboard_probed = true
	apple_spi_keyboard_enabled = true
	C.printf(c'apple-spi-kbd: SPI at 0x%llx, input %u Hz, limit %u Hz; awaiting reports\n',
		plan.spi.base, plan.input_hz, plan.maximum_hz)
}

// Called by the existing ARM64 console idle-poll path, never from an IRQ.
// Try-lock also prevents re-entry if a diagnostic or scheduler path polls.
// The caller owns output and feeds it to the console AFTER this lock is freed.
pub fn poll(output &u8, capacity u64, application_cursor bool) int {
	if !apple_spi_keyboard_lock.test_and_acquire() {
		return 0
	}
	defer { apple_spi_keyboard_lock.release() }
	if !apple_spi_keyboard_probed {
		return 0
	}
	// Polling continues even while the transport is down: the driver holds the
	// cool-off itself and answers immediately until it has passed, and if it
	// never gets called again it can never come back. Not calling it is what
	// used to make three bad reads permanent.
	pointer_reports := C.vinix_apple_spi_touchpad_reports()
	count := C.vinix_apple_spi_keyboard_poll(output, capacity, int(application_cursor))
	if C.vinix_apple_spi_touchpad_reports() != pointer_reports
		&& apple_spi_pointer_callback != voidptr(0) {
		C.vinix_call_void_fn(apple_spi_pointer_callback)
	}
	if count < 0 {
		match count {
			-2 {
				if apple_spi_keyboard_enabled {
					apple_spi_keyboard_enabled = false
					println('apple-spi-kbd: repeated SPI packet errors; resetting the transport')
				}
			}
			-3 {
				apple_spi_keyboard_enabled = true
				println('apple-spi-kbd: transport recovered')
			}
			else {
				println('apple-spi-kbd: SPI packet error; retrying after backoff')
			}
		}
		return 0
	}
	if !apple_spi_keyboard_enabled {
		apple_spi_keyboard_enabled = true
	}
	if !apple_spi_keyboard_reported && C.vinix_apple_spi_keyboard_reports() != 0 {
		apple_spi_keyboard_reported = true
		println('apple-spi-kbd: first valid keyboard report received')
	}
	return count
}
