// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What happens to a device that stops answering.
//
// A driver that sees a command time out, a controller report a fatal error or
// a resume fail does not decide the device's fate by itself: it reports the
// failure (report_timeout(), report_failure()) and fails the request it was
// serving. The report is taken up by a worker thread, since the reporter may
// be in an interrupt or hold the lock the repair needs. The worker tries, in
// order:
//
//  1. the driver's `reset`, which keeps the device's users attached;
//  2. unbinding and probing again, a clean start for a driver whose reset
//     did not help or that has none;
//  3. giving up: the device is marked failed and left alone.
//
// Giving up is bounded and never final. A device is reset at most reset_limit
// times in reset_window_ns, so one that fails every time does not have the
// machine resetting it for ever; and a failed device stays listed, with its
// history, and can be reset or bound again by hand through sysfs once whatever
// was wrong with it has been put right. One broken device costs the machine
// that device, not the boot.
//
// The same worker carries out the requests that cannot run where they are
// made: a removal asked for by writing to the device's own `remove` file, and
// a bus rescan.
@[has_globals]
module devcore

import event
import event.eventstruct
import katomic
import klock
import lib
import sched

// How often a device may be reset before it is given up on, and over what
// time. A reset that works buys a device its attempts back once the window
// has passed.
pub const reset_limit = u32(3)
pub const reset_window_ns = u64(60) * second

enum WorkKind {
	recover
	remove
	rescan
	retry
}

struct Work {
mut:
	kind WorkKind
	dev  &Device = unsafe { nil }
}

const work_slots = 32

__global (
	devcore_work         [work_slots]Work
	devcore_work_count   int
	devcore_work_lock    klock.Lock
	devcore_work_event   eventstruct.Event
	devcore_worker_alive bool
	// Buses that can look for devices again; see register_rescan().
	devcore_hooks Hooks
)

struct Hooks {
mut:
	rescan_pci   fn ()                                = unsafe { nil }
	dma_release  fn (mut dev Device) u64              = unsafe { nil }
	dma_block    fn (mut dev Device)                  = unsafe { nil }
	dma_describe fn (dev &Device, mut text lib.Text)  = unsafe { nil }
}

// The DMA layer sits above this module and says here how a device's memory
// is taken back when its driver goes, cut off when its driver gives up on it
// without letting go, and described in sysfs.
pub fn set_dma_hooks(release fn (mut dev Device) u64, block fn (mut dev Device), describe fn (dev &Device, mut text lib.Text)) {
	devcore_hooks.dma_release = release
	devcore_hooks.dma_block = block
	devcore_hooks.dma_describe = describe
}

// Start the worker. Called once the scheduler runs; reports made before then
// wait in the queue.
pub fn start_worker() {
	if devcore_worker_alive {
		return
	}
	devcore_worker_alive = true
	sched.new_kernel_thread(voidptr(worker), unsafe { nil }, true)
}

fn queue_work(kind WorkKind, dev &Device) bool {
	devcore_work_lock.acquire()
	if devcore_work_count >= work_slots {
		devcore_work_lock.release()
		return false
	}
	devcore_work[devcore_work_count] = Work{
		kind: kind
		dev:  unsafe { dev }
	}
	devcore_work_count++
	devcore_work_lock.release()
	event.trigger(mut devcore_work_event, false)
	return true
}

// Drop what is queued for a device that is being freed.
fn forget_work(dev &Device) {
	devcore_work_lock.acquire()
	mut kept := 0
	for i in 0 .. devcore_work_count {
		if voidptr(devcore_work[i].dev) == voidptr(dev) {
			continue
		}
		devcore_work[kept] = devcore_work[i]
		kept++
	}
	devcore_work_count = kept
	devcore_work_lock.release()
}

fn take_work() ?Work {
	devcore_work_lock.acquire()
	defer {
		devcore_work_lock.release()
	}
	if devcore_work_count == 0 {
		return none
	}
	work := devcore_work[0]
	for i := 0; i + 1 < devcore_work_count; i++ {
		devcore_work[i] = devcore_work[i + 1]
	}
	devcore_work_count--
	return work
}

fn worker() {
	for {
		generation := event.generation(mut devcore_work_event)
		work := take_work() or {
			event.await_one_from_generation(mut devcore_work_event, true, generation) or {}
			continue
		}
		match work.kind {
			.recover {
				mut dev := work.dev
				recover(mut dev, false)
			}
			.retry {
				mut dev := work.dev
				recover(mut dev, true)
			}
			.remove {
				mut dev := work.dev
				remove(mut dev)
			}
			.rescan {
				if devcore_hooks.rescan_pci != unsafe { nil } {
					devcore_hooks.rescan_pci()
				}
			}
		}
	}
}

// A bus says how it looks for devices that came or went: what writing to its
// `rescan` file, or a hotplug interrupt, asks for.
pub fn register_rescan(bus Bus, rescan fn ()) {
	if bus == .pci {
		devcore_hooks.rescan_pci = rescan
	}
}

// Ask for the bus to be looked at again, from any context.
pub fn request_rescan(bus Bus) bool {
	if bus != .pci || devcore_hooks.rescan_pci == unsafe { nil } {
		return false
	}
	return queue_work(.rescan, unsafe { nil })
}

// Ask for `dev` to be removed, from a context that cannot do it itself.
pub fn request_remove(mut dev Device) bool {
	return queue_work(.remove, dev)
}

// A request to `dev` got no answer in the time its driver allows.
pub fn report_timeout(mut dev Device, what string) {
	katomic.inc(mut &dev.timeouts)
	report_failure(mut dev, what)
}

// `dev` is not working: `what` says what was being done. Safe from an
// interrupt and under a driver's lock. Reports made while a repair is already
// on its way are counted and otherwise ignored.
pub fn report_failure(mut dev Device, what string) {
	katomic.inc(mut &dev.failures)
	if !katomic.cas(mut &dev.recovering, u32(0), u32(1)) {
		return
	}
	C.kprintf(c'devcore: %.*s failed (%.*s); recovery queued\n', i32(dev.name.len), dev.name.str,
		i32(what.len), what.str)
	if !queue_work(.recover, dev) {
		katomic.store(mut &dev.recovering, u32(0))
	}
}

// Ask for a failed or misbehaving device to be reset now, whatever its
// history: what writing to its `reset` file does.
pub fn request_reset(mut dev Device) bool {
	if !katomic.cas(mut &dev.recovering, u32(0), u32(1)) {
		return false
	}
	if !queue_work(.retry, dev) {
		katomic.store(mut &dev.recovering, u32(0))
		return false
	}
	return true
}

fn recover(mut dev Device, by_hand bool) {
	gate_enter()
	defer {
		katomic.store(mut &dev.recovering, u32(0))
		gate_leave()
	}
	if dev.state == .removed {
		return
	}
	now := now_ns()
	if by_hand || now - dev.last_reset_ns > reset_window_ns {
		dev.recent_resets = 0
	}
	mut driver := dev.driver
	if driver == unsafe { nil } {
		// Failed and released earlier: a reset by hand is a fresh probe.
		if dev.state == .failed {
			dev.state = .unbound
			if offer_locked(mut dev) {
				C.kprintf(c'devcore: %.*s bound again\n', i32(dev.name.len), dev.name.str)
			} else {
				dev.state = .failed
			}
		}
		return
	}
	if dev.recent_resets >= reset_limit {
		give_up(mut dev)
		return
	}
	dev.recent_resets++
	dev.last_reset_ns = now
	katomic.inc(mut &dev.resets)

	if driver.reset != unsafe { nil } && driver.reset(mut dev) {
		C.kprintf(c'devcore: %.*s reset by %.*s\n', i32(dev.name.len), dev.name.str,
			i32(driver.name.len), driver.name.str)
		if dev.state == .failed {
			// Its driver never let go of it; it has it back in working order.
			dev.state = .bound
			publish_binding(dev)
		}
		return
	}
	if driver.remove != unsafe { nil } && driver.probe != unsafe { nil } {
		if dev.state == .bound {
			unbind_locked(mut dev)
		} else {
			dev.state = .unbound
		}
		if bind_locked(mut dev, mut driver) {
			C.kprintf(c'devcore: %.*s probed again by %.*s\n', i32(dev.name.len), dev.name.str,
				i32(driver.name.len), driver.name.str)
			return
		}
	}
	give_up(mut dev)
}

// Stop using the device. A driver that can let go of it does; one that cannot
// keeps it, marked failed, and is no longer asked to suspend it or shut it
// down.
fn give_up(mut dev Device) {
	if dev.state == .bound {
		if !unbind_locked(mut dev) {
			unpublish_binding(dev)
			if devcore_hooks.dma_block != unsafe { nil } {
				devcore_hooks.dma_block(mut dev)
			}
		}
	}
	dev.state = .failed
	C.kprintf(c'devcore: %.*s given up on after %llu resets; reset or bind it by hand to try again\n',
		i32(dev.name.len), dev.name.str, u64(dev.resets))
}
