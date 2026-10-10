// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The device core: what hardware the machine has, and which driver has it.
//
// Drivers used to be functions kmain called in a fixed order, each of which
// went looking for its own hardware. Nothing recorded what was found, two
// drivers could take the same card, and a device could be neither released
// nor told that the machine was about to sleep or stop. Here a bus says what
// is on it (add()), a driver says what it drives and how (register_driver()),
// and the core brings the two together: it probes, binds, unbinds and removes,
// and it is the one place that can walk every device in order to suspend,
// resume, shut down or reset it.
//
// Order is registration order. A bus adds a device after the device it hangs
// off, and kmain registers drivers in the order it used to start them, so
// "suspend in reverse, resume forwards" needs no dependency graph: a disk is
// quiesced before the controller it is on, and comes back after it.
//
// A driver is a table of function pointers, all optional but `probe`:
//
//	matches   whether it drives this device
//	probe     take the device; false leaves it unbound
//	remove    give it back: stop it, free what probe made
//	suspend   quiesce for system sleep, keeping what resume needs
//	resume    bring it back after sleep
//	shutdown  stop DMA and interrupts and flush, before power off or reset
//	reset     recover a device that stopped answering
//
// A driver with no `remove` cannot be unbound, and says so in sysfs rather
// than pretending. A driver that was not written against this core still
// records itself (claim()), so that the list of devices and drivers is the
// truth about the machine either way.
//
// Locking: everything that changes a binding runs under the gate, a sleeping
// lock, because a probe waits for hardware. It is recursive, as a bridge's
// probe adds the devices behind it. The device table itself is guarded by a
// spinlock so that an interrupt or a sysfs read can look a device up.
@[has_globals]
module devcore

import acpisync
import klock
import pci

pub enum Bus {
	platform
	pci
	acpi
	virtio
	usb
}

pub enum State {
	// Present, with no driver.
	unbound
	// A driver has it.
	bound
	// A driver had it and gave up on it: it stopped answering and could not be
	// reset. It stays listed, and can be bound again by hand.
	failed
	// Taken out of the machine.
	removed
}

pub struct Driver {
pub mut:
	name     string
	bus      Bus
	matches  fn (dev &Device) bool     = unsafe { nil }
	probe    fn (mut dev Device) bool  = unsafe { nil }
	remove   fn (mut dev Device)       = unsafe { nil }
	suspend  fn (mut dev Device) bool  = unsafe { nil }
	resume   fn (mut dev Device) bool  = unsafe { nil }
	shutdown fn (mut dev Device)       = unsafe { nil }
	reset    fn (mut dev Device) bool  = unsafe { nil }
	// How many devices it has.
	bound int
}

@[heap]
pub struct Device {
pub mut:
	bus    Bus
	// Owned: "0000:00:1f.2", "a003c00.virtio_mmio", "PNP0C0A:00".
	name   string
	parent &Device = unsafe { nil }

	// What a driver matches on. PCI fills in the numbers; a platform or ACPI
	// device has its compatible string or hardware ID, which the device owns.
	vendor     u16
	device     u16
	class      u8
	subclass   u8
	prog_if    u8
	revision   u8
	compatible string
	pci        &pci.PCIDevice = unsafe { nil }
	// Whatever else the bus keeps for it.
	bus_data   voidptr

	driver      &Driver = unsafe { nil }
	// The driver's own state for this device.
	driver_data voidptr
	state       State

	// Sleep. `suspended` is set between a successful suspend and its resume;
	// a wakeup-capable device may end a system sleep when wakeup is enabled.
	suspended       bool
	wakeup_capable  bool
	wakeup_enabled  bool
	wakeups         u64

	// Health, for the recovery in recovery.v and for anyone reading sysfs.
	timeouts       u64
	resets         u64
	failures       u64
	probe_failures u64
	last_reset_ns  u64
	recent_resets  u32
	recovering     u32

	// The DMA domain the dma module gave it, if any.
	dma voidptr

	// Where it is under /sys/devices once published; owned.
	sysfs_path string
	published  bool
}

pub const max_drivers = 64
pub const max_devices = 512

__global (
	devcore_drivers      [max_drivers]Driver
	devcore_driver_count int
	devcore_devices      [max_devices]&Device
	devcore_device_count int
	// Guards the two tables above.
	devcore_table_lock klock.Lock
	// The gate: see the top of this file.
	devcore_gate       voidptr
	devcore_gate_owner u64
	devcore_gate_depth int
)

fn gate_enter() {
	if devcore_gate == unsafe { nil } {
		// Made before the second CPU and the scheduler exist, by whichever of
		// PCI enumeration and the first driver comes first.
		devcore_gate = acpisync.create(true)
		if devcore_gate == unsafe { nil } {
			panic('devcore: no memory for the binding gate')
		}
	}
	me := acpisync.thread_id()
	if devcore_gate_owner == me && devcore_gate_depth > 0 {
		devcore_gate_depth++
		return
	}
	acpisync.wait(devcore_gate, 0xffff)
	devcore_gate_owner = me
	devcore_gate_depth = 1
}

fn gate_leave() {
	devcore_gate_depth--
	if devcore_gate_depth == 0 {
		devcore_gate_owner = 0
		acpisync.signal(devcore_gate)
	}
}

// Hold off every probe, bind, unbind and removal: for a caller that walks the
// devices and must find them as it left them, such as a system suspend.
pub fn freeze_bindings() {
	gate_enter()
}

pub fn thaw_bindings() {
	gate_leave()
}

pub fn bus_name(bus Bus) string {
	return match bus {
		.platform { 'platform' }
		.pci { 'pci' }
		.acpi { 'acpi' }
		.virtio { 'virtio' }
		.usb { 'usb' }
	}
}

pub fn state_name(state State) string {
	return match state {
		.unbound { 'unbound' }
		.bound { 'bound' }
		.failed { 'failed' }
		.removed { 'removed' }
	}
}

// ── Drivers ─────────────────────────────────────────────────────────────────

// Add a driver and give it every unbound device it matches. The record is
// copied; the pointer returned is the core's own and good for the life of the
// machine. None when the table is full or the name is taken.
pub fn register_driver(driver Driver) ?&Driver {
	gate_enter()
	defer {
		gate_leave()
	}
	devcore_table_lock.acquire()
	for i in 0 .. devcore_driver_count {
		if devcore_drivers[i].bus == driver.bus && devcore_drivers[i].name == driver.name {
			devcore_table_lock.release()
			return none
		}
	}
	if devcore_driver_count >= max_drivers {
		devcore_table_lock.release()
		C.kprintf(c'devcore: driver table full, %.*s not registered\n', i32(driver.name.len),
			driver.name.str)
		return none
	}
	mut slot := unsafe { &devcore_drivers[devcore_driver_count] }
	unsafe {
		*slot = driver
	}
	slot.bound = 0
	devcore_driver_count++
	devcore_table_lock.release()
	publish_driver(slot)

	if slot.matches != unsafe { nil } && slot.probe != unsafe { nil } {
		// Not a `for dev in`: a probe may add devices, and they are tried too.
		for i := 0; i < devcore_device_count; i++ {
			mut dev := devcore_devices[i]
			if dev.bus == slot.bus && dev.state == .unbound && slot.matches(dev) {
				bind_locked(mut dev, mut slot)
			}
		}
	}
	return slot
}

pub fn find_driver(bus Bus, name string) ?&Driver {
	devcore_table_lock.acquire()
	defer {
		devcore_table_lock.release()
	}
	for i in 0 .. devcore_driver_count {
		if devcore_drivers[i].bus == bus && devcore_drivers[i].name == name {
			return unsafe { &devcore_drivers[i] }
		}
	}
	return none
}

// ── Devices ─────────────────────────────────────────────────────────────────

// A new device record for a bus to fill in and hand to add(). `name` is
// copied.
pub fn new_device(bus Bus, name string) &Device {
	// Freed by remove().
	mut dev := &Device{
		bus: bus
	} @[freed]
	dev.name = name.clone()
	return dev
}

// Put a device on its bus and offer it to that bus's drivers. False when the
// table is full or the bus already has a device by that name; the record is
// then still the caller's.
pub fn add(mut dev Device) bool {
	gate_enter()
	defer {
		gate_leave()
	}
	devcore_table_lock.acquire()
	for i in 0 .. devcore_device_count {
		if devcore_devices[i].bus == dev.bus && devcore_devices[i].name == dev.name {
			devcore_table_lock.release()
			return false
		}
	}
	if devcore_device_count >= max_devices {
		devcore_table_lock.release()
		C.kprintf(c'devcore: device table full, %.*s not added\n', i32(dev.name.len), dev.name.str)
		return false
	}
	dev.state = .unbound
	devcore_devices[devcore_device_count] = unsafe { dev }
	devcore_device_count++
	devcore_table_lock.release()
	publish_device(mut dev)
	offer_locked(mut dev)
	return true
}

// Try each driver of the device's bus on it, in registration order.
fn offer_locked(mut dev Device) bool {
	for i := 0; i < devcore_driver_count; i++ {
		mut driver := unsafe { &devcore_drivers[i] }
		if driver.bus != dev.bus || driver.matches == unsafe { nil } || driver.probe == unsafe { nil } {
			continue
		}
		if dev.state != .unbound {
			break
		}
		if driver.matches(dev) && bind_locked(mut dev, mut driver) {
			return true
		}
	}
	return false
}

fn bind_locked(mut dev Device, mut driver Driver) bool {
	if dev.state == .bound || dev.state == .removed {
		return false
	}
	dev.driver = unsafe { driver }
	dev.driver_data = unsafe { nil }
	if !driver.probe(mut dev) {
		// A probe that fails half way must not leave the device able to
		// reach memory.
		release_dma(mut dev, driver)
		dev.driver = unsafe { nil }
		dev.driver_data = unsafe { nil }
		dev.probe_failures++
		return false
	}
	dev.state = .bound
	dev.suspended = false
	driver.bound++
	publish_binding(dev)
	return true
}

// Take back whatever memory the driver left the device able to reach. A
// driver that cleans up after itself leaves nothing.
fn release_dma(mut dev Device, driver &Driver) {
	if devcore_hooks.dma_release == unsafe { nil } {
		return
	}
	left := devcore_hooks.dma_release(mut dev)
	if left != 0 {
		C.kprintf(c'devcore: %.*s left %llu pages mapped for %.*s; taken back\n', i32(driver.name.len),
			driver.name.str, left, i32(dev.name.len), dev.name.str)
	}
}

// Record that `driver` has `dev` without asking it to probe: for a driver that
// found its own hardware the old way and is telling the core afterwards.
pub fn claim(mut dev Device, mut driver Driver) bool {
	gate_enter()
	defer {
		gate_leave()
	}
	if dev.state == .bound || dev.state == .removed {
		return false
	}
	dev.driver = unsafe { driver }
	dev.state = .bound
	driver.bound++
	publish_binding(dev)
	return true
}

// Bind `dev` to the driver called `name`. For sysfs and for recovery.
pub fn bind(mut dev Device, name string) bool {
	gate_enter()
	defer {
		gate_leave()
	}
	mut driver := find_driver(dev.bus, name) or { return false }
	if driver.probe == unsafe { nil } {
		return false
	}
	if driver.matches != unsafe { nil } && !driver.matches(dev) {
		return false
	}
	if dev.state == .failed {
		dev.state = .unbound
	}
	return bind_locked(mut dev, mut driver)
}

// Take `dev` from its driver. False when it has none, or one that cannot give
// a device back.
pub fn unbind(mut dev Device) bool {
	gate_enter()
	defer {
		gate_leave()
	}
	return unbind_locked(mut dev)
}

fn unbind_locked(mut dev Device) bool {
	if dev.state != .bound || dev.driver == unsafe { nil } {
		return false
	}
	mut driver := dev.driver
	if driver.remove == unsafe { nil } {
		return false
	}
	unpublish_binding(dev)
	driver.remove(mut dev)
	release_dma(mut dev, driver)
	driver.bound--
	dev.driver = unsafe { nil }
	dev.driver_data = unsafe { nil }
	dev.state = .unbound
	dev.suspended = false
	return true
}

// The device has left the machine. Its driver is told, its files go, and the
// record is freed -- unless its driver cannot let go of it, in which case the
// record is kept, marked removed, for the driver's stale pointers to land on.
pub fn remove(mut dev Device) {
	gate_enter()
	// Children first: what hangs off a bridge goes before the bridge.
	for {
		mut child := &Device(unsafe { nil })
		devcore_table_lock.acquire()
		for i in 0 .. devcore_device_count {
			if voidptr(devcore_devices[i].parent) == voidptr(dev) {
				child = devcore_devices[i]
				break
			}
		}
		devcore_table_lock.release()
		if child == unsafe { nil } {
			break
		}
		remove(mut child)
	}
	mut pinned := false
	if dev.state == .bound && !unbind_locked(mut dev) {
		pinned = true
		C.kprintf(c'devcore: %.*s removed, but driver %.*s cannot release it; its record is kept\n',
			i32(dev.name.len), dev.name.str, i32(dev.driver.name.len), dev.driver.name.str)
		unpublish_binding(dev)
		mut driver := dev.driver
		driver.bound--
	}
	unpublish_device(mut dev)
	devcore_table_lock.acquire()
	for i in 0 .. devcore_device_count {
		if voidptr(devcore_devices[i]) == voidptr(dev) {
			for j := i; j + 1 < devcore_device_count; j++ {
				devcore_devices[j] = devcore_devices[j + 1]
			}
			devcore_device_count--
			devcore_devices[devcore_device_count] = unsafe { nil }
			break
		}
	}
	dev.state = .removed
	devcore_table_lock.release()
	forget_work(dev)
	gate_leave()
	if !pinned {
		unsafe {
			dev.name.free()
			dev.sysfs_path.free()
			free(dev)
		}
	}
}

pub fn device_count() int {
	return devcore_device_count
}

pub fn driver_count() int {
	return devcore_driver_count
}

// The device at `index` in registration order, or nil past the end. The
// pointer is only good while bindings are frozen or the caller owns the bus.
pub fn device_at(index int) &Device {
	devcore_table_lock.acquire()
	defer {
		devcore_table_lock.release()
	}
	if index < 0 || index >= devcore_device_count {
		return unsafe { nil }
	}
	return devcore_devices[index]
}

pub fn driver_at(index int) &Driver {
	if index < 0 || index >= devcore_driver_count {
		return unsafe { nil }
	}
	return unsafe { &devcore_drivers[index] }
}

pub fn find(bus Bus, name string) &Device {
	devcore_table_lock.acquire()
	defer {
		devcore_table_lock.release()
	}
	for i in 0 .. devcore_device_count {
		if devcore_devices[i].bus == bus && devcore_devices[i].name == name {
			return devcore_devices[i]
		}
	}
	return unsafe { nil }
}

// ── The whole machine at once ───────────────────────────────────────────────

// Quiesce every bound device for system sleep, last added first. Stops at the
// first driver that refuses and returns that device, having resumed the ones
// already suspended; nil when all are asleep. Call with bindings frozen.
pub fn suspend_all() &Device {
	for i := devcore_device_count - 1; i >= 0; i-- {
		mut dev := devcore_devices[i]
		if dev.state != .bound || dev.driver.suspend == unsafe { nil } {
			continue
		}
		if !dev.driver.suspend(mut dev) {
			C.kprintf(c'devcore: %.*s (%.*s) refused to suspend\n', i32(dev.name.len), dev.name.str,
				i32(dev.driver.name.len), dev.driver.name.str)
			resume_from(i + 1)
			return dev
		}
		dev.suspended = true
	}
	return unsafe { nil }
}

// Bring back every suspended device, first added first. A device whose driver
// cannot resume it is handed to recovery rather than left half alive.
pub fn resume_all() {
	resume_from(0)
}

fn resume_from(first int) {
	for i := first; i < devcore_device_count; i++ {
		mut dev := devcore_devices[i]
		if !dev.suspended {
			continue
		}
		dev.suspended = false
		if dev.state != .bound || dev.driver.resume == unsafe { nil } {
			continue
		}
		if !dev.driver.resume(mut dev) {
			C.kprintf(c'devcore: %.*s (%.*s) did not resume\n', i32(dev.name.len), dev.name.str,
				i32(dev.driver.name.len), dev.driver.name.str)
			report_failure(mut dev, 'resume')
		}
	}
}

// Stop every bound device before the machine powers off or resets, last
// added first. Nothing is unbound: there is no afterwards.
pub fn shutdown_all() {
	gate_enter()
	for i := devcore_device_count - 1; i >= 0; i-- {
		mut dev := devcore_devices[i]
		if dev.state == .bound && dev.driver.shutdown != unsafe { nil } {
			dev.driver.shutdown(mut dev)
		}
	}
	gate_leave()
}
