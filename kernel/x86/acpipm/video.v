// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A laptop panel's backlight where firmware drives it: ACPI's video
// extensions, the part of them that is brightness.
//
// A panel is a device in the namespace with _BCL, the levels it has, and
// _BCM, which sets one; most also have _BQC, which says which it is at. The
// first two numbers of _BCL are the levels firmware would choose on the
// charger and on the battery and the rest are the list, in no promised
// order; firmware that leaves the two out is common enough that Linux looks
// for them among the rest before believing they are there, and so does this
// (acpi_video_init_brightness(), drivers/acpi/acpi_video.c). The list is
// sorted, and a panel's brightness is a place in it: 0 the dimmest, which is
// what the panel is given for a sleep.
//
// The brightness keys are firmware's too. It does not change the level
// itself: it sends the panel a Notify -- brighter, dimmer, around again,
// darkest -- and the level is stepped here. The bus the panel hangs from is
// told through _DOS not to change brightness by itself when the charger
// comes or goes, as it is told by Linux.
//
// Each panel is on the device list under a driver of its own so that it is
// told of a sleep: put down before the embedded controller, which its
// methods often go through, and given its level back after it. At boot
// nothing is set: the panel stays as firmware left it until somebody asks,
// and one that cannot say what level that is stays so through a sleep too.
//
// Where this reaches nothing: a panel whose _BCM asks the graphics driver
// to do the work (Intel's, through the OpRegion) is listed and takes levels
// that change nothing, since there is no such driver. `vinix.acpi_backlight=off`
// leaves all of it alone.
@[has_globals]
module acpipm

import brightness
import devcore
import uacpi

const video_levels_max = 128

// What a panel is sent when a brightness key is pressed.
const notify_cycle_brightness = u64(0x85)
const notify_brighter = u64(0x86)
const notify_dimmer = u64(0x87)
const notify_darkest = u64(0x88)

// _DOS: the display is not switched by firmware, and brightness is not
// changed by it when the power source does.
const dos_brightness_is_ours = u64(4)

struct VideoPanel {
mut:
	node uacpi.Node
	// Distinct, lowest first.
	levels  [video_levels_max]u32
	count   int
	has_bqc bool
	// Owned: acpi_video0 and on.
	name  string
	panel &brightness.Panel = unsafe { nil }
}

__global (
	acpipm_video       [brightness.max_panels]VideoPanel
	acpipm_video_count int
	acpipm_video_driver &devcore.Driver
)

// Put `value` into the sorted list, unless it is there.
fn (mut p VideoPanel) add_level(value u32) {
	mut place := 0
	for place < p.count && p.levels[place] < value {
		place++
	}
	if (place < p.count && p.levels[place] == value) || p.count >= video_levels_max {
		return
	}
	for i := p.count; i > place; i-- {
		p.levels[i] = p.levels[i - 1]
	}
	p.levels[place] = value
	p.count++
}

// Read _BCL into the list. False where there is not a choice of at least two
// levels to be had from it.
fn (mut p VideoPanel) take_levels() bool {
	mut bcl := uacpi.evaluate_package(p.node, '_BCL') or { return false }
	total := bcl.len()
	first := bcl.integer(0) or { u64(0) }
	second := bcl.integer(1) or { u64(0) }
	mut first_listed := false
	mut second_listed := false
	for i := 2; i < total; i++ {
		value := bcl.integer(i) or { continue }
		if value == first {
			first_listed = true
		}
		if value == second {
			second_listed = true
		}
	}
	// Without both among the rest, the first two are levels like any other.
	start := if first_listed && second_listed { 2 } else { 0 }
	p.count = 0
	for i := start; i < total; i++ {
		value := bcl.integer(i) or { continue }
		if value <= 0xffffffff {
			p.add_level(u32(value))
		}
	}
	bcl.release()
	return p.count >= 2
}

// The place in the list of the level nearest `value`.
fn (p &VideoPanel) place_of(value u64) u32 {
	mut best := 0
	mut distance := ~u64(0)
	for i in 0 .. p.count {
		level := u64(p.levels[i])
		apart := if level > value { level - value } else { value - level }
		if apart < distance {
			distance = apart
			best = i
		}
	}
	return u32(best)
}

fn video_set(context voidptr, level u32) bool {
	p := unsafe { &VideoPanel(context) }
	if int(level) >= p.count {
		return false
	}
	return uacpi.execute_integer(p.node, '_BCM', u64(p.levels[level]))
}

fn video_get(context voidptr) ?u32 {
	p := unsafe { &VideoPanel(context) }
	value := uacpi.evaluate_integer(p.node, '_BQC')?
	return p.place_of(value)
}

fn video_notify(context voidptr, _node voidptr, value u64) uacpi.UACPIStatus {
	p := unsafe { &VideoPanel(context) }
	if p.panel == unsafe { nil } {
		return .ok
	}
	mut panel := p.panel
	if value == notify_brighter {
		panel.step(1)
	} else if value == notify_dimmer {
		panel.step(-1)
	} else if value == notify_darkest {
		panel.ask(0)
	} else if value == notify_cycle_brightness {
		if panel.asked() >= panel.max {
			panel.ask(0)
		} else {
			panel.step(1)
		}
	}
	return .ok
}

fn video_tell_bus(node uacpi.Node) {
	bus := uacpi.parent_of(node)
	if bus != unsafe { nil } && uacpi.has_method(bus, '_DOS') {
		uacpi.execute_integer(bus, '_DOS', dos_brightness_is_ours)
	}
}

fn video_panel_of(dev &devcore.Device) &VideoPanel {
	for i in 0 .. acpipm_video_count {
		if voidptr(acpipm_video[i].node) == dev.bus_data {
			return &acpipm_video[i]
		}
	}
	return unsafe { nil }
}

// A sleep is not refused for a backlight that would not go down.
fn video_suspend(mut dev devcore.Device) bool {
	p := video_panel_of(dev)
	if p != unsafe { nil } && p.panel != unsafe { nil } {
		mut panel := p.panel
		panel.put_down()
	}
	return true
}

// Firmware may have put the panel anywhere, and forgotten what it was told
// about who changes its brightness.
fn video_resume(mut dev devcore.Device) bool {
	p := video_panel_of(dev)
	if p != unsafe { nil } && p.panel != unsafe { nil } {
		video_tell_bus(p.node)
		mut panel := p.panel
		panel.bring_back()
	}
	return true
}

fn video_found(_context voidptr, node uacpi.Node) {
	if acpipm_video_count >= brightness.max_panels || !uacpi.has_method(node, '_BCL')
		|| !uacpi.has_method(node, '_BCM') {
		return
	}
	mut p := &acpipm_video[acpipm_video_count]
	p.node = node
	if !p.take_levels() {
		return
	}
	p.has_bqc = uacpi.has_method(node, '_BQC')
	mut name := [16]u8{}
	prefix := 'acpi_video'
	for i in 0 .. prefix.len {
		name[i] = prefix[i]
	}
	name[prefix.len] = u8(`0` + acpipm_video_count)
	p.name = unsafe { tos(&name[0], prefix.len + 1) }.clone()
	// Where it is now, if it can say and names a level it has. One that
	// cannot, or answers with something not on its list -- firmware does
	// -- is counted from its brightest when a key is first pressed, and is
	// not touched for a sleep until it has been set once.
	mut level := u32(p.count - 1)
	mut known := false
	if p.has_bqc {
		if now := uacpi.evaluate_integer(node, '_BQC') {
			place := p.place_of(now)
			if u64(p.levels[place]) == now {
				level = place
				known = true
			}
		}
	}
	p.panel = brightness.register(brightness.Panel{
		name:    p.name
		kind:    'firmware'
		max:     u32(p.count - 1)
		context: voidptr(p)
		set:     video_set
		get:     if p.has_bqc { video_get } else { unsafe { nil } }
	}, level, known) or {
		unsafe { p.name.free() }
		return
	}
	acpipm_video_count++
	video_tell_bus(node)
	uacpi.on_notify(node, video_notify, voidptr(p))
	mut driver := acpipm_video_driver
	add_device(node, 'LNXVIDEO', mut driver)
}

// Find the panels firmware can dim. After the embedded controller and the
// other power devices are on the list, so that a sleep reaches these first.
pub fn initialise_backlight() {
	if !devcore.boot_flag('vinix.acpi_backlight=', true) {
		return
	}
	acpipm_video_driver = devcore.register_driver(devcore.Driver{
		name:    'video'
		bus:     .acpi
		suspend: video_suspend
		resume:  video_resume
	}) or { return }
	uacpi.for_each_device_node(video_found, unsafe { nil })
	if acpipm_video_count != 0 {
		C.kprintf(c'acpipm: %lld panels with a backlight firmware sets\n', i64(acpipm_video_count))
	}
}
