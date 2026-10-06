// SPDX-License-Identifier: GPL-2.0-only
// Independent native PCI fixture; original workload and watchdogs are retained.
@[translated]
module pciconfigfixture

#include "linuxkpi_pci_fixture_v_contract.h"

struct C.completion {}

@[typedef]
struct C.pthread_t {}

struct C.task_struct {
	__state      u32
	vinix_thread voidptr
	in_iowait    i32
}

type PciThread = fn (voidptr) voidptr

fn C.vinix_linuxkpi_fixture_pci_thread(voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, PciThread, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.complete_all(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.get_task_struct(&C.task_struct) &C.task_struct
fn C.put_task_struct(&C.task_struct)
fn C.task_is_running(&C.task_struct) bool

@[c: '__atomic_store_n']
fn C.pci_store_ptr(&voidptr, voidptr, i32)

@[c: '__atomic_load_n']
fn C.pci_load_ptr(&voidptr, i32) voidptr

@[c: '__atomic_store_n']
fn C.pci_store_bool(&bool, bool, i32)

@[c: '__atomic_load_n']
fn C.pci_load_bool(&bool, i32) bool

fn C.__atomic_load_n(&u32, i32) u32
fn C.vinix_linuxkpi_worker_bind(u32) i32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_percpu_count() u32
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_preempt_count() u32
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable_no_resched()
fn C.vinix_linuxkpi_test_alloc_oom(i32)
fn C.vinix_linuxkpi_test_worker_oom(u32)
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_clock_ns() u64
fn C.vinix_linuxkpi_test_task_time_waiters(&C.task_struct) usize
fn C.vinix_linuxkpi_test_thread_reap_ready(voidptr) bool
fn C.vinix_linuxkpi_test_reap_quiescent() bool
fn C.vinix_linuxkpi_pci_identity(u32, &u32, &u32, &u32) i32
fn C.vinix_pci_config_read(u32, u32, u32, u32, u64, u32, &u32) i32
fn C.vinix_pci_config_write(u32, u32, u32, u32, u64, u32, u32) i32
fn C.vinix_pci_config_update_command(u32, u32, u32, u32, u16, u16) i32
fn C.msleep(u32)
fn C.cond_resched() i32
fn C.BUG()
fn C.BUG_ON(bool)
fn C.kprintf(&char, ...) i32

@[c_extern]
__global C.current &C.task_struct

@[c_extern]
__global C.TASK_DEAD u32

@[c_extern]
__global C.VINIX_PCI_CONFIG_OK i32

@[c_extern]
__global C.VINIX_PCI_CONFIG_BAD_REGISTER i32

@[c_extern]
__global C.VINIX_PCI_CONFIG_UNAVAILABLE i32

struct PciIdentity {
mut:
	bdf            u32
	identity       u32
	class_revision u32
}

struct PciWorker {
mut:
	devices         &PciIdentity = unsafe { nil }
	task            voidptr      = unsafe { nil }
	thread          C.pthread_t
	entered         C.completion
	go              C.completion
	done            C.completion
	cpu             u32
	reasons         u32
	reads           u32
	failed_width    u32
	failed_offset   u64
	failed_value    u32
	failed_expected u32
	failed_status   i32
	initialized     bool
	started         bool
	cancel          bool
}

struct PciBadCase {
	domain   u32
	bus      u32
	slot     u32
	function u32
	offset   u64
	width    u32
	status   i32
}

struct PciBadUpdate {
	domain   u32
	bus      u32
	slot     u32
	function u32
	status   i32
}

fn pci_failed(worker &PciWorker, reason u32, offset u64, width u32, status i32, value u32, expected u32) {
	unsafe {
		if worker.reasons == 0 {
			worker.failed_offset = offset
			worker.failed_width = width
			worker.failed_status = status
			worker.failed_value = value
			worker.failed_expected = expected
		}
		worker.reasons |= reason
	}
}

fn pci_context(worker &PciWorker, flags usize, depth u32) {
	if C.vinix_linuxkpi_irq_flags() != flags || C.vinix_linuxkpi_preempt_count() != depth {
		pci_failed(worker, 4, 0, 0, 0, 0, 0)
	}
	if C.vinix_linuxkpi_cpu_id() != worker.cpu {
		pci_failed(worker, 8, 0, 0, 0, C.vinix_linuxkpi_cpu_id(), worker.cpu)
	}
}

fn pci_read(worker &PciWorker, device &PciIdentity, offset u64, width u32, expected u32, flags usize, depth u32) {
	unsafe {
		mut value := u32(0x5aa55aa5)
		status := C.vinix_pci_config_read(0, device.bdf >> 8, (device.bdf >> 3) & 31, device.bdf & 7, offset, width, &value)
		if status != C.VINIX_PCI_CONFIG_OK || value != expected {
			pci_failed(worker, if status != 0 { u32(1) } else { u32(2) }, offset, width, status, value, expected)
		}
		worker.reads++
		pci_context(worker, flags, depth)
	}
}

fn pci_read_identity(worker &PciWorker, device &PciIdentity, flags usize, depth u32) {
	pci_read(worker, device, 0, 4, device.identity, flags, depth)
	pci_read(worker, device, 0, 2, device.identity & 0xffff, flags, depth)
	pci_read(worker, device, 2, 2, device.identity >> 16, flags, depth)
	for b := u32(0); b < 4; b++ {
		pci_read(worker, device, b, 1, (device.identity >> (b * 8)) & 0xff, flags, depth)
	}
	pci_read(worker, device, 8, 4, device.class_revision, flags, depth)
	pci_read(worker, device, 8, 2, device.class_revision & 0xffff, flags, depth)
	pci_read(worker, device, 10, 2, device.class_revision >> 16, flags, depth)
	for b := u32(0); b < 4; b++ {
		pci_read(worker, device, 8 + b, 1, (device.class_revision >> (b * 8)) & 0xff, flags, depth)
	}
}

fn pci_errors(worker &PciWorker, flags usize, depth u32) {
	unsafe {
		bad := C.VINIX_PCI_CONFIG_BAD_REGISTER
		unavailable := C.VINIX_PCI_CONFIG_UNAVAILABLE
		cases := [PciBadCase{0, 0, 0, 0, 0, 0, bad}, PciBadCase{0, 0, 0, 0, 0, 3, bad},
			PciBadCase{0, 0, 0, 0, 0, 8, bad}, PciBadCase{0, 0, 0, 0, 1, 2, bad},
			PciBadCase{0, 0, 0, 0, 2, 4, bad}, PciBadCase{0, 256, 0, 0, 0, 4, bad},
			PciBadCase{0, 0, 32, 0, 0, 4, bad}, PciBadCase{0, 0, 0, 8, 0, 4, bad},
			PciBadCase{1, 0, 0, 0, 0, 4, unavailable}, PciBadCase{1, 0, 0, 0, 1, 2, bad},
			PciBadCase{0, 0, 0, 0, 256, 1, bad}, PciBadCase{0, 0, 0, 0, 256, 4, bad},
			PciBadCase{0, 0, 0, 0, 0x100000000, 4, bad}, PciBadCase{0, 0, 0, 0, ~u64(0), 1, bad},
			PciBadCase{0, 0, 0, 0, ~u64(0) - 3, 4, bad}]!
		for item in cases {
			mut value := u32(0x5aa55aa5)
			mut status := C.vinix_pci_config_read(item.domain, item.bus, item.slot, item.function, item.offset, item.width, &value)
			if status != item.status || value != 0x5aa55aa5 {
				pci_failed(worker, 32, item.offset, item.width, status, value, 0x5aa55aa5)
			}
			pci_context(worker, flags, depth)
			status = C.vinix_pci_config_write(item.domain, item.bus, item.slot, item.function, item.offset, item.width, 0xffffffff)
			if status != item.status {
				pci_failed(worker, 32, item.offset, item.width, status, 0, 0)
			}
			pci_context(worker, flags, depth)
		}
		mut status := C.vinix_pci_config_read(0, 0, 0, 0, 0, 4, nil)
		if status != bad { pci_failed(worker, 32, 0, 4, status, 0, 0) }
		pci_context(worker, flags, depth)
		updates := [PciBadUpdate{0, 256, 0, 0, bad}, PciBadUpdate{0, 0, 32, 0, bad},
			PciBadUpdate{0, 0, 0, 8, bad}, PciBadUpdate{1, 0, 0, 0, unavailable}]!
		for item in updates {
			status = C.vinix_pci_config_update_command(item.domain, item.bus, item.slot, item.function, 0xffff, 0xffff)
			if status != item.status { pci_failed(worker, 32, 4, 2, status, 0, 0) }
			pci_context(worker, flags, depth)
		}
	}
}

@[export: 'vinix_linuxkpi_fixture_pci_thread']
pub fn pci_thread(argument voidptr) voidptr {
	unsafe {
		mut worker := &PciWorker(argument)
		C.pci_store_ptr(&worker.task, voidptr(C.get_task_struct(C.current)), 3)
		if C.vinix_linuxkpi_worker_bind(worker.cpu) != 0 { pci_failed(worker, 16, 0, 0, 0, 0, 0) }
		C.complete(&worker.entered)
		C.wait_for_completion(&worker.go)
		if !C.pci_load_bool(&worker.cancel, 2) {
			mut completed := true
			mut round := u32(0)
			for round < 32 {
				if C.pci_load_bool(&worker.cancel, 2) {
					completed = false
					break
				}
				original_flags := C.vinix_linuxkpi_irq_flags()
				original_depth := C.vinix_linuxkpi_preempt_count()
				mut saved_flags := usize(0)
				if (round & 1) != 0 {
					saved_flags = C.vinix_linuxkpi_irq_save()
					C.vinix_linuxkpi_preempt_disable()
					C.vinix_linuxkpi_preempt_disable()
				}
				flags := C.vinix_linuxkpi_irq_flags()
				depth := C.vinix_linuxkpi_preempt_count()
				C.vinix_linuxkpi_test_alloc_oom(0)
				for i := u32(0); i < 2; i++ {
					pci_read_identity(worker, &worker.devices[(i + round + worker.cpu) & 1], flags, depth)
				}
				if round < 2 { pci_errors(worker, flags, depth) }
				C.vinix_linuxkpi_test_alloc_oom(-1)
				if (round & 1) != 0 {
					C.vinix_linuxkpi_preempt_enable_no_resched()
					C.vinix_linuxkpi_preempt_enable_no_resched()
					C.vinix_linuxkpi_irq_restore(saved_flags)
				}
				pci_context(worker, original_flags, original_depth)
				if (round & 7) == 7 {
					C.msleep(1)
					pci_context(worker, original_flags, original_depth)
				}
				round++
			}
			if completed && worker.reads != 32 * 2 * 14 {
				pci_failed(worker, 128, 0, 0, 0, worker.reads, 32 * 2 * 14)
			}
		}
		C.vinix_linuxkpi_test_alloc_oom(-1)
		if !C.task_is_running(C.current) || !C.vinix_linuxkpi_may_sleep() || C.current.in_iowait != 0 {
			pci_failed(worker, 64, 0, 0, 0, 0, 0)
		}
		C.complete_all(&worker.done)
		C.pthread_exit(nil)
		return nil
	}
}

fn pci_retire(workers &PciWorker, count u32) i32 {
	unsafe {
		mut result := i32(0)
		for i := u32(0); i < count; i++ {
			if workers[i].initialized {
				C.pci_store_bool(&workers[i].cancel, true, 3)
				C.complete_all(&workers[i].go)
			}
		}
		for i := u32(0); i < count; i++ {
			if !workers[i].started { continue }
			if C.wait_for_completion_timeout(&workers[i].done, 500) == 0 {
				C.kprintf(c'linuxkpi: PCI worker=%u did not finish before cleanup watchdog\n', i)
				C.BUG()
			}
			C.BUG_ON(C.pthread_join(workers[i].thread, nil) != 0)
		}
		retirement_started := C.vinix_linuxkpi_clock_ns()
		for i := u32(0); i < count; i++ {
			if !workers[i].started { continue }
			task := &C.task_struct(C.pci_load_ptr(&workers[i].task, 2))
			C.BUG_ON(task == nil)
			if workers[i].reasons != 0 {
				C.kprintf(c'linuxkpi: PCI worker=%u reasons=0x%x offset=%lu width=%u status=%d value=%08x expected=%08x\n', i, workers[i].reasons, usize(workers[i].failed_offset), workers[i].failed_width, workers[i].failed_status, workers[i].failed_value, workers[i].failed_expected)
				result = -5
			}
			for C.__atomic_load_n(&task.__state, 2) != C.TASK_DEAD {
				if C.vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000 { C.BUG() }
				C.cond_resched()
			}
			C.BUG_ON(C.vinix_linuxkpi_test_task_time_waiters(task) != 0)
		}
		for i := u32(0); i < count; i++ {
			if !workers[i].started { continue }
			for !C.vinix_linuxkpi_test_thread_reap_ready((&C.task_struct(workers[i].task)).vinix_thread) {
				if C.vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000 { C.BUG() }
				C.cond_resched()
			}
		}
		for i := u32(0); i < count; i++ {
			if workers[i].started {
				C.put_task_struct(&C.task_struct(workers[i].task))
				workers[i].started = false
			}
		}
		for !C.vinix_linuxkpi_test_reap_quiescent() {
			if C.vinix_linuxkpi_clock_ns() - retirement_started >= 1000000000 { C.BUG() }
			C.cond_resched()
		}
		return result
	}
}

fn pci_start_group(devices &PciIdentity, workers &PciWorker, fail_after u32, oom_stage u32) i32 {
	unsafe {
		C.BUG_ON(oom_stage != 0 && (oom_stage > 4 || fail_after >= 4))
		for i := u32(0); i < 4; i++ {
			mut worker := &workers[i]
			worker.devices = devices
			worker.cpu = i
			C.init_completion(&worker.entered)
			C.init_completion(&worker.go)
			C.init_completion(&worker.done)
			worker.initialized = true
			if oom_stage != 0 && i == fail_after { C.vinix_linuxkpi_test_worker_oom(oom_stage) }
			error := C.pthread_create(&worker.thread, nil, C.vinix_linuxkpi_fixture_pci_thread, worker)
			C.vinix_linuxkpi_test_worker_oom(0)
			if error == 0 { worker.started = true }
			if oom_stage != 0 && i == fail_after {
				return if error != 11 || worker.started { i32(-5) } else { i32(0) }
			}
			if error != 0 { return -12 }
			if C.wait_for_completion_timeout(&worker.entered, 500) == 0 { return -5 }
		}
		for i in 0 .. 4 { C.complete(&workers[i].go) }
		for i in 0 .. 4 {
			if C.wait_for_completion_timeout(&workers[i].done, 500) == 0 { return -5 }
		}
		return 0
	}
}

fn pci_group(devices &PciIdentity, fail_after u32, oom_stage u32) i32 {
	unsafe {
		mut workers := [4]PciWorker{}
		mut result := pci_start_group(devices, &workers[0], fail_after, oom_stage)
		if pci_retire(&workers[0], 4) != 0 { result = -5 }
		return result
	}
}

@[export: 'vinix_linuxkpi_pci_config_native_selftest']
pub fn pci_selftest() i32 {
	unsafe {
		if C.vinix_linuxkpi_percpu_count() < 4 { return -5 }
		mut devices := [2]PciIdentity{}
		for i := u32(0); i < 2; i++ {
			if C.vinix_linuxkpi_pci_identity(i, &devices[i].bdf, &devices[i].identity, &devices[i].class_revision) != 0 || devices[i].bdf > 0xffff || (devices[i].identity & 0xffff) == 0xffff {
				return -5
			}
		}
		if devices[0].bdf == devices[1].bdf { return -5 }
		mut result := i32(0)
		for stage := u32(1); stage < 5; stage++ {
			for before := u32(0); before < 4; before++ {
				if pci_group(&devices[0], before, stage) != 0 {
					C.kprintf(c'linuxkpi: PCI constructor rollback stage=%u after=%u failed\n', stage, before)
					result = -5
				}
			}
		}
		if pci_group(&devices[0], 0, 0) != 0 { result = -5 }
		return result
	}
}
