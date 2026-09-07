// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module wifi

import aarch64.pmgr
import crypto.sha256
import devicetree
import errno
import event
import event.eventstruct
import file
import fs
import katomic
import klock
import limine
import memory
import resource
import stat
import usercopy

#include "brcm_m1.h"

struct C.bw_m1_plan {
mut:
	config          u64
	config_size     u64
	rc              u64
	port            u64
	phy             u64
	gpio            u64
	dart            u64
	window          u64
	window_bus      u64
	window_size     u64
	pool_cpu        u64
	pool_physical   u64
	tables_cpu      u64
	tables_physical u64
	sid             u32
	gpio_active_low u32
	calibration     &u8 = unsafe { nil }
	seed            &u8 = unsafe { nil }
	calibration_len usize
	seed_len        usize
	mac             [6]u8
	antenna         [16]u8
}

fn C.brcm_m1_prepare(plan &C.bw_m1_plan) int

fn C.brcm_m1_status(output &u8) int

fn C.brcm_m1_upload(input &u8) int

fn C.brcm_m1_boot(input &u8) int

fn C.brcm_m1_join(input &u8) int

fn C.brcm_m1_radio(input &u8) int

fn C.brcm_m1_scan() int

fn C.brcm_m1_networks(output &u8) int

fn C.brcm_m1_poll() int

fn C.brcm_m1_read(output &u8, capacity usize) int

fn C.brcm_m1_write(input &u8, count usize) int

fn C.brcm_m1_stop()

__global (
	wifi_lock klock.Lock
	wifi_res  = &WifiDevice(unsafe { nil })
	wifi_seed [256]u8
)

struct PowerDomain {
	handle u32
	region devicetree.DTReg
	offset u32
}

struct Plan {
mut:
	power    []PowerDomain
	config   devicetree.DTReg
	rc       devicetree.DTReg
	port     devicetree.DTReg
	phy      devicetree.DTReg
	dart     devicetree.DTReg
	gpio     devicetree.DTReg
	gpio_pin u32
	gpio_low u32
	window   devicetree.DTReg
	bus_base u64
	sid      u32
	cal      devicetree.DTProperty
	mac      [6]u8
	antenna  [16]u8
}

fn compatible(node &devicetree.DTNode, name string) bool {
	values := devicetree.get_string_list(node, 'compatible') or { return false }
	defer { unsafe { values.free() }
	 }
	return name in values
}

fn enabled(node &devicetree.DTNode) bool {
	mut cur := node
	for _ in 0 .. 64 {
		if cur == unsafe { nil } {
			return true
		}
		status := devicetree.get_string_prop(cur, 'status') or { 'okay' }
		if status != 'okay' && status != 'ok' {
			return false
		}
		cur = cur.parent
	}
	return false
}

fn has_prop(node &devicetree.DTNode, name string) bool {
	_ := devicetree.get_property(node, name) or { return false }
	return true
}

fn valid_region(r devicetree.DTReg, minimum u64) bool {
	return r.base != 0 && r.base & 3 == 0 && r.size >= minimum && r.base <= ~u64(0) - r.size
}

fn first_region(node &devicetree.DTNode, minimum u64) ?devicetree.DTReg {
	ranges := devicetree.get_translated_reg_ranges(node) or { return none }
	defer { unsafe { ranges.free() }
	 }
	if ranges.len != 1 || !valid_region(ranges[0], minimum) {
		return none
	}
	return ranges[0]
}

fn plan_power(node &devicetree.DTNode, depth int, mut p Plan) bool {
	if depth > 16 || p.power.len > 64 {
		return false
	}
	if !has_prop(node, 'power-domains') {
		return true
	}
	handles := devicetree.get_u32_array(node, 'power-domains') or { return false }
	defer { unsafe { handles.free() }
	 }
	if handles.len > 8 {
		return false
	}
	for handle in handles {
		mut seen := false
		for power in p.power {
			if power.handle == handle {
				seen = true
			}
		}
		if seen {
			continue
		}
		domain := devicetree.find_phandle(handle) or { return false }
		if !enabled(domain) || !compatible(domain, 'apple,pmgr-pwrstate')
			|| (devicetree.get_u32(domain, '#power-domain-cells') or { u32(1) }) != 0 {
			return false
		}
		parent := domain.parent
		if parent == unsafe { nil } || !compatible(parent, 'apple,t8103-pmgr') {
			return false
		}
		region := first_region(parent, 4) or { return false }
		cells := devicetree.get_u32_array(domain, 'reg') or { return false }
		defer { unsafe { cells.free() }
		 }
		if cells.len != 2 || cells[0] & 3 != 0 || cells[1] < 4 || u64(cells[0]) > region.size - 4
			|| u64(cells[1]) > region.size - u64(cells[0]) {
			return false
		}
		if !plan_power(domain, depth + 1, mut p) {
			return false
		}
		p.power << PowerDomain{ handle: handle, region: region, offset: cells[0] }
	}
	return true
}

fn named_or_index(node &devicetree.DTNode, name string, index int, minimum u64) ?devicetree.DTReg {
	if has_prop(node, 'reg-names') {
		r := devicetree.get_named_reg(node, name) or { return none }
		if !valid_region(r, minimum) {
			return none
		}
		return r
	}
	ranges := devicetree.get_translated_reg_ranges(node) or { return none }
	defer { unsafe { ranges.free() }
	 }
	if index >= ranges.len || !valid_region(ranges[index], minimum) {
		return none
	}
	return ranges[index]
}

fn exact_cells(node &devicetree.DTNode, name string, expected []u32) bool {
	cells := devicetree.get_u32_array(node, name) or { return false }
	defer { unsafe { cells.free() }
	 }
	return cells == expected
}

fn discover(mut p Plan) bool {
	root := devicetree.find_node('/') or { return false }
	if !compatible(root, 'apple,j313') || !compatible(root, 'apple,t8103') {
		return false
	}
	wifi := devicetree.find_compatible('pci14e4,4425') or { return false }
	if !enabled(wifi) || !exact_cells(wifi, 'reg', [u32(0x10000), 0, 0, 0, 0])
		|| (devicetree.get_string_prop(wifi, 'brcm,board-type') or { '' }) != 'apple,shikoku' {
		return false
	}
	port := wifi.parent
	if port == unsafe { nil } || !exact_cells(port, 'reg', [u32(0), 0, 0, 0, 0])
		|| !exact_cells(port, 'bus-range', [u32(1), 1]) {
		return false
	}
	host := port.parent
	if host == unsafe { nil } || !compatible(host, 'apple,t8103-pcie') || !enabled(host) {
		return false
	}
	p.config = named_or_index(host, 'config', 0, 0x200000) or { return false }
	p.rc = named_or_index(host, 'rc', 1, 0x100000) or { return false }
	p.port = named_or_index(host, 'port0', 2, 0x1000) or { return false }
	p.phy = devicetree.get_named_reg(host, 'phy0') or {
		devicetree.DTReg{ base: p.rc.base + 0x84000, size: 0x4000 }
	}
	if !valid_region(p.phy, 0x4000) {
		return false
	}
	if (devicetree.get_u32(host, '#address-cells') or { u32(0) }) != 3
		|| (devicetree.get_u32(host, '#size-cells') or { u32(0) }) != 2 {
		return false
	}
	// Parse PCI ranges explicitly; generic DT reg parsing does not support
	// three-cell PCI addresses. Parent is the CPU-addressed /soc bus on J313.
	if host.parent == unsafe { nil } || (devicetree.get_u32(host.parent, '#address-cells') or { u32(2) }) != 2 {
		return false
	}
	ranges := devicetree.get_u32_array(host, 'ranges') or { return false }
	defer { unsafe { ranges.free() }
	 }
	if ranges.len == 0 || ranges.len % 7 != 0 {
		return false
	}
	for i := 0; i < ranges.len; i += 7 {
		if ranges[i] != 0x02000000 || ranges[i + 1] != 0 {
			continue
		}
		cpu_base := (u64(ranges[i + 3]) << 32) | ranges[i + 4]
		size := (u64(ranges[i + 5]) << 32) | ranges[i + 6]
		bus_base := u64(ranges[i + 2])
		if size < 0x4000000 || cpu_base > ~u64(0) - size || size > u64(0x100000000) - bus_base {
			return false
		}
		// Map only the last 64 MiB, not the entire multi-GiB PCI window.
		p.window = devicetree.DTReg{ base: cpu_base + size - 0x4000000, size: 0x4000000 }
		p.bus_base = bus_base + size - 0x4000000
		break
	}
	if p.window.base == 0 {
		return false
	}
	mask := devicetree.get_u32(host, 'iommu-map-mask') or { u32(0xffffffff) }
	mapping := devicetree.get_u32_array(host, 'iommu-map') or { return false }
	defer { unsafe { mapping.free() }
	 }
	if mapping.len == 0 || mapping.len % 4 != 0 {
		return false
	}
	rid := u32(0x100) & mask
	mut dart_node := &devicetree.DTNode(unsafe { nil })
	for i := 0; i < mapping.len; i += 4 {
		if rid >= mapping[i] && rid - mapping[i] < mapping[i + 3] {
			if dart_node != unsafe { nil } {
				return false
			}
			dart_node = devicetree.find_phandle(mapping[i + 1]) or { return false }
			if mapping[i + 2] > 15 || rid - mapping[i] > 15 - mapping[i + 2] {
				return false
			}
			p.sid = mapping[i + 2] + rid - mapping[i]
		}
	}
	if dart_node == unsafe { nil } || !enabled(dart_node) || !compatible(dart_node, 'apple,t8103-dart')
		|| (devicetree.get_u32(dart_node, '#iommu-cells') or { u32(0) }) != 1 || p.sid != 1 {
		return false
	}
	p.dart = first_region(dart_node, 0x4000) or { return false }
	gpio := devicetree.get_u32_array(port, 'reset-gpios') or { return false }
	defer { unsafe { gpio.free() }
	 }
	if gpio.len != 3 || gpio[2] > 1 {
		return false
	}
	gpio_node := devicetree.find_phandle(gpio[0]) or { return false }
	if !enabled(gpio_node) || !compatible(gpio_node, 'apple,t8103-pinctrl')
		|| (devicetree.get_u32(gpio_node, '#gpio-cells') or { u32(0) }) != 2 {
		return false
	}
	p.gpio = first_region(gpio_node, 4) or { return false }
	gpio_ranges := devicetree.get_u32_array(gpio_node, 'gpio-ranges') or { return false }
	defer { unsafe { gpio_ranges.free() }
	 }
	if gpio_ranges.len != 4 || gpio_ranges[0] != gpio[0] || gpio_ranges[1] != 0 || gpio_ranges[2] != 0
		|| gpio[1] >= gpio_ranges[3] || u64(gpio_ranges[3]) > p.gpio.size / 4 {
		return false
	}
	p.gpio_pin = gpio[1]
	p.gpio_low = gpio[2]
	p.cal = devicetree.get_property(wifi, 'brcm,cal-blob') or { return false }
	if p.cal.len == 0 || p.cal.len > 0x100000 {
		return false
	}
	mac := devicetree.get_property(wifi, 'local-mac-address') or { return false }
	if mac.len != 6 {
		return false
	}
	unsafe { C.memcpy(&p.mac[0], mac.data, 6) }
	if p.mac[0] & 1 != 0 || p.mac == [6]u8{} {
		return false
	}
	antenna := devicetree.get_string_prop(wifi, 'apple,antenna-sku') or { return false }
	if antenna.len == 0 || antenna.len >= 16 || antenna == 'XX' {
		return false
	}
	for i, c in antenna {
		if !((c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c == `_` || c == `-`) {
			return false
		}
		p.antenna[i] = c
	}
	return plan_power(host, 0, mut p) && plan_power(dart_node, 0, mut p) && plan_power(gpio_node, 0, mut p)
}

fn prepare_seed() bool {
	chosen := devicetree.find_node('/chosen') or { return false }
	seed := devicetree.get_property(chosen, 'rng-seed') or { return false }
	if seed.len < 32 || seed.len > 4096 {
		return false
	}
	// Domain-separated SHA-256 expansion of bootloader entropy. M1n1's SEP
	// path supplies 128 bytes. No timer-based or deterministic fallback.
	domain := 'Vinix BCM4378 firmware seed v1'
	mut input := []u8{len: domain.len + int(seed.len) + 1}
	defer {
		unsafe {
			C.memset(input.data, 0, input.len)
			input.free()
		}
	}
	unsafe {
		C.memcpy(input.data, domain.str, domain.len)
		C.memcpy(&input[domain.len], seed.data, seed.len)
	}
	for i in 0 .. 8 {
		input[input.len - 1] = u8(i)
		digest := sha256.sum(input)
		unsafe {
			C.memcpy(&wifi_seed[i * 32], digest.data, 32)
			C.memset(digest.data, 0, digest.len)
			digest.free()
		}
	}
	return true
}

fn alloc_aligned(bytes u64) u64 {
	raw := memory.pmm_alloc(bytes / 4096 + 3)
	if raw == unsafe { nil } {
		return 0
	}
	// This reservation, including alignment slack, is never reused while the
	// endpoint can DMA. Failed bring-up deliberately quarantines it as well.
	return (u64(raw) + 0x3fff) & ~u64(0x3fff)
}

fn setup(mut p Plan) bool {
	pool := alloc_aligned(0x400000)
	tables := alloc_aligned(0x8000)
	if pool == 0 || tables == 0 {
		return false
	}
	for power in p.power {
		if !pmgr.enable_region(power.region.base, power.region.size, power.offset) {
			return false
		}
	}
	mut c := C.bw_m1_plan{
		config: memory.map_mmio(p.config.base, 0x200000)
		config_size: 0x200000
		rc: memory.map_mmio(p.rc.base, 0x100000)
		port: memory.map_mmio(p.port.base, 0x1000)
		phy: memory.map_mmio(p.phy.base, 0x4000)
		dart: memory.map_mmio(p.dart.base, 0x4000)
		gpio: memory.map_mmio(p.gpio.base, p.gpio.size) + u64(p.gpio_pin) * 4
		window: memory.map_mmio(p.window.base, p.window.size)
		window_bus: p.bus_base
		window_size: p.window.size
		pool_cpu: pool + higher_half
		pool_physical: pool
		tables_cpu: tables + higher_half
		tables_physical: tables
		sid: p.sid
		gpio_active_low: p.gpio_low
		calibration: &u8(p.cal.data)
		calibration_len: usize(p.cal.len)
		seed: &wifi_seed[0]
		seed_len: 256
		mac: p.mac
		antenna: p.antenna
	}
	return C.brcm_m1_prepare(&c) == 0
}

fn requested() bool {
	f := limine.kernel_file()
	if f == unsafe { nil } || f.cmdline == unsafe { nil } {
		return false
	}
	line := unsafe { cstring_to_vstring(f.cmdline) }
	args := line.split(' ')
	defer { unsafe { args.free() }
	 }
	return 'vinix.apple_wifi=1' in args
}

pub fn initialise() {
	if !requested() {
		return
	}
	mut p := Plan{}
	defer { unsafe { p.power.free() }
	 }
	if !devicetree.is_available() || !discover(mut p) || !prepare_seed() {
		println('wifi: missing/unsupported J313 device tree, calibration, or boot entropy; not probing')
		return
	}
	ok := setup(mut p)
	wifi_res = &WifiDevice{}
	wifi_res.stat.mode = 0o600 | stat.ifchr
	wifi_res.stat.blksize = 1514
	wifi_res.stat.rdev = resource.create_dev_id()
	wifi_res.status = file.pollout
	fs.devtmpfs_add_device(wifi_res, 'wlan0')
	if ok {
		println('wifi: BCM4378 detected; upload matching firmware with wifi-ctl')
	} else {
		println('wifi: PCIe/DART/chip probe failed; /dev/wlan0 exposes diagnostics only')
	}
}

pub fn poll() {
	if wifi_res == unsafe { nil } || !wifi_lock.test_and_acquire() {
		return
	}
	defer { wifi_lock.release() }
	result := C.brcm_m1_poll()
	if result != 0 {
		wifi_res.status |= file.pollin
		event.trigger(mut wifi_res.event, false)
	}
}

fn error_code(value int) {
	match value {
		-1 { errno.set(errno.einval) }
		-2 { errno.set(errno.ewouldblock) }
		-4 { errno.set(errno.etimedout) }
		else { errno.set(errno.eio) }
	}
}

struct WifiDevice {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut d WifiDevice) mmap(_ voidptr, _ u64, _ int) voidptr {
	return unsafe { nil }
}

fn (mut d WifiDevice) grow(_ voidptr, _ u64) ? {
	return none
}

fn (mut d WifiDevice) read(_ voidptr, output voidptr, _ u64, count u64) ?i64 {
	if count == 0 {
		return i64(0)
	}
	mut data := [1514]u8{}
	capacity := if count < 1514 { count } else { u64(1514) }
	wifi_lock.acquire()
	defer { wifi_lock.release() }
	got := C.brcm_m1_read(&data[0], usize(capacity))
	if got == 0 {
		d.status &= ~file.pollin
		errno.set(errno.ewouldblock)
		return none
	}
	if got < 0 {
		error_code(got)
		return none
	}
	if !usercopy.copy_to_user(u64(output), &data[0], u64(got)) {
		errno.set(errno.efault)
		return none
	}
	return i64(got)
}

fn (mut d WifiDevice) write(_ voidptr, input voidptr, _ u64, count u64) ?i64 {
	if count < 14 || count > 1514 {
		errno.set(errno.einval)
		return none
	}
	mut data := [1514]u8{}
	if !usercopy.copy_from_user(&data[0], u64(input), count) {
		errno.set(errno.efault)
		return none
	}
	wifi_lock.acquire()
	defer { wifi_lock.release() }
	result := C.brcm_m1_write(&data[0], usize(count))
	if result != 0 {
		error_code(result)
		return none
	}
	return i64(count)
}

fn (mut d WifiDevice) ioctl(_ voidptr, request u64, arg voidptr) ?int {
	wifi_lock.acquire()
	defer { wifi_lock.release() }
	mut result := 0
	match request {
		0x5700 {
			mut data := [256]u8{}
			result = C.brcm_m1_status(&data[0])
			if !usercopy.copy_to_user(u64(arg), &data[0], 256) {
				errno.set(errno.efault)
				return none
			}
		}
		0x5701 {
			mut data := [4112]u8{}
			if !usercopy.copy_from_user(&data[0], u64(arg), 4112) {
				errno.set(errno.efault)
				return none
			}
			result = C.brcm_m1_upload(&data[0])
		}
		0x5702 {
			mut data := [128]u8{}
			if !usercopy.copy_from_user(&data[0], u64(arg), 128) {
				errno.set(errno.efault)
				return none
			}
			result = C.brcm_m1_boot(&data[0])
			if result != -1 {
				unsafe { C.memset(&wifi_seed[0], 0, 256) }
			}
		}
		0x5703 {
			mut data := [104]u8{}
			defer { unsafe { C.memset(&data[0], 0, 104) }
			 }
			if !usercopy.copy_from_user(&data[0], u64(arg), 104) {
				errno.set(errno.efault)
				return none
			}
			result = C.brcm_m1_join(&data[0])
		}
		0x5704 { C.brcm_m1_stop() }
		0x5705 {
			mut data := [4]u8{}
			if !usercopy.copy_from_user(&data[0], u64(arg), 4) {
				errno.set(errno.efault)
				return none
			}
			result = C.brcm_m1_radio(&data[0])
		}
		0x5706 { result = C.brcm_m1_scan() }
		0x5707 {
			mut data := [1552]u8{}
			result = C.brcm_m1_networks(&data[0])
			if result == 0 && !usercopy.copy_to_user(u64(arg), &data[0], 1552) {
				errno.set(errno.efault)
				return none
			}
		}
		else {
			errno.set(errno.enotty)
			return none
		}
	}
	if result != 0 {
		error_code(result)
		return none
	}
	return 0
}

fn (mut d WifiDevice) unref(_ voidptr) ? {
	katomic.dec(mut &d.refcount)
}

fn (mut d WifiDevice) link(_ voidptr) ? {
	katomic.inc(mut &d.stat.nlink)
}

fn (mut d WifiDevice) unlink(_ voidptr) ? {
	katomic.dec(mut &d.stat.nlink)
}
