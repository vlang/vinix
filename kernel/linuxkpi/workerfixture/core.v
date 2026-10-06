// SPDX-License-Identifier: GPL-2.0-only
// Independent anonymous-worker constructor, scheduler and retirement fixture.
@[translated]
module workerfixture

#include "linuxkpi_worker_fixture_v_contract.h"
struct C.completion {}

struct C.workqueue_struct {}

@[typedef]
struct C.pthread_t {}

type WorkerFn = fn (voidptr) voidptr

fn C.vinix_linuxkpi_fixture_worker_once(voidptr) voidptr
fn C.vinix_linuxkpi_fixture_worker_context(voidptr) voidptr
fn C.pthread_create(voidptr, voidptr, WorkerFn, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.__atomic_add_fetch(&u32, u32, i32) u32
fn C.__atomic_load_n(&u32, i32) u32
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.vinix_linuxkpi_test_worker_oom(i32)
fn C.alloc_workqueue(&char, u32, i32, ...) &C.workqueue_struct
fn C.destroy_workqueue(&C.workqueue_struct)
fn C.vinix_linuxkpi_percpu_count() u32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_worker_bind(u32) i32
fn C.vinix_linuxkpi_worker_set_nice(i32) i32
fn C.vinix_linuxkpi_worker_nice() i32
fn C.vinix_linuxkpi_worker_timeslice() usize
fn C.vinix_linuxkpi_may_sleep() bool
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_preempt_count() u32
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable()
fn C.cond_resched() i32
fn C.msleep(u32)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.kprintf(&char, ...) i32

@[c_extern]
__global C.jiffies usize

@[c_extern]
__global (
	C.VKF_WORKER_TRACE bool
	C.WQ_UNBOUND       u32
	C.WQ_HIGHPRI       u32
	C.EIO              i32
	C.ENOMEM           i32
	C.EAGAIN           i32
	C.EINVAL           i32
	C.EWOULDBLOCK      i32
)

const exit_value = usize(0x51a9)

struct WorkerResult {
mut:
	calls        u32
	result       i32
	nice_ready   C.completion
	nice_release C.completion
}

@[export: 'vinix_linuxkpi_fixture_worker_once']
pub fn once(argument voidptr) voidptr {
	unsafe {
		mut test := &WorkerResult(argument)
		C.__atomic_add_fetch(&test.calls, 1, 0)
		C.pthread_exit(voidptr(exit_value))
		return nil
	}
}

fn join(native_thread C.pthread_t, test &WorkerResult) i32 {
	unsafe {
		mut value := voidptr(nil)
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace join begin ticks=%lu\n', C.jiffies)
		}
		if C.pthread_join(native_thread, &value) != 0 { return -C.EIO }
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace join complete ticks=%lu calls=%u result=%d value_ok=%u\n', C.jiffies, C.__atomic_load_n(&test.calls, 2), test.result, u32(usize(value) == exit_value))
		}
		return if usize(value) == exit_value && C.__atomic_load_n(&test.calls, 2) == 1 && test.result == 0 {
			i32(0)
		} else {
			-C.EIO
		}
	}
}

fn failures() i32 {
	unsafe {
		flags := [u32(0), u32(C.WQ_UNBOUND), u32(C.WQ_HIGHPRI), u32(C.WQ_UNBOUND | C.WQ_HIGHPRI)]!
		mut result := i32(0)
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace constructor failures begin ticks=%lu\n', C.jiffies)
		}
		for repeat in 0 .. 20 {
			for stage in 1 .. 5 {
				mut test := WorkerResult{}
				mut native_thread := C.pthread_t{}
				mut sentinel := exit_value
				C.memcpy(&native_thread, &sentinel, sizeof(C.pthread_t))
				if C.VKF_WORKER_TRACE {
					C.kprintf(c'linuxkpi: worker trace constructor repeat=%u stage=%d pthread begin ticks=%lu\n', u32(repeat), i32(stage), C.jiffies)
				}
				C.vinix_linuxkpi_test_worker_oom(i32(stage))
				error := C.pthread_create(&native_thread, nil, C.vinix_linuxkpi_fixture_worker_once, &test)
				C.vinix_linuxkpi_test_worker_oom(0)
				if C.VKF_WORKER_TRACE {
					C.kprintf(c'linuxkpi: worker trace constructor repeat=%u stage=%d pthread returned error=%d ticks=%lu\n', u32(repeat), i32(stage), error, C.jiffies)
				}
				if error == 0 {
					if join(native_thread, &test) != 0 { result = -C.EIO }
					result = -C.EIO
				} else {
					mut thread_bits := usize(0)
					C.memcpy(&thread_bits, &native_thread, sizeof(C.pthread_t))
					if error != C.EAGAIN || thread_bits != exit_value || C.__atomic_load_n(&test.calls, 2) != 0 {
						result = -C.EIO
					}
				}
				for q in 0 .. 4 {
					if C.VKF_WORKER_TRACE {
						C.kprintf(c'linuxkpi: worker trace constructor repeat=%u stage=%d queue=%u flags=0x%x begin ticks=%lu\n', u32(repeat), i32(stage), u32(q), flags[q], C.jiffies)
					}
					C.vinix_linuxkpi_test_worker_oom(i32(stage))
					queue := C.alloc_workqueue(c'vinix-worker-oom', flags[q], 2)
					C.vinix_linuxkpi_test_worker_oom(0)
					if queue != nil {
						if C.VKF_WORKER_TRACE {
							C.kprintf(c'linuxkpi: worker trace constructor unexpected queue success repeat=%u stage=%d queue=%u destroy begin ticks=%lu\n', u32(repeat), i32(stage), u32(q), C.jiffies)
						}
						C.destroy_workqueue(queue)
						result = -C.EIO
					}
				}
				if C.VKF_WORKER_TRACE {
					C.kprintf(c'linuxkpi: worker trace constructor repeat=%u stage=%d complete result=%d ticks=%lu\n', u32(repeat), i32(stage), result, C.jiffies)
				}
			}
		}
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace constructor failures complete result=%d ticks=%lu\n', result, C.jiffies)
		}
		mut recovery := WorkerResult{}
		mut native_thread := C.pthread_t{}
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace recovery pthread create begin ticks=%lu\n', C.jiffies)
		}
		if C.pthread_create(&native_thread, nil, C.vinix_linuxkpi_fixture_worker_once, &recovery) != 0 {
			return -C.ENOMEM
		}
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace recovery pthread created ticks=%lu\n', C.jiffies)
		}
		if join(native_thread, &recovery) != 0 { result = -C.EIO }
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace recovery complete result=%d ticks=%lu\n', result, C.jiffies)
		}
		return result
	}
}

fn placement(test &WorkerResult, cpu u32, nice i32) {
	unsafe {
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace placement check begin expected_cpu=%u nice=%d actual_cpu=%u ticks=%lu\n', cpu, nice, C.vinix_linuxkpi_cpu_id(), C.jiffies)
		}
		C.cond_resched()
		C.msleep(1)
		if C.vinix_linuxkpi_cpu_id() != cpu || C.vinix_linuxkpi_worker_nice() != nice || C.vinix_linuxkpi_worker_timeslice() != (if nice == -20 {
			usize(10000)
		} else {
			usize(5000)
		}) {
			test.result = -C.EIO
		}
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace placement check complete expected_cpu=%u nice=%d actual_cpu=%u result=%d ticks=%lu\n', cpu, nice, C.vinix_linuxkpi_cpu_id(), test.result, C.jiffies)
		}
	}
}

@[export: 'vinix_linuxkpi_fixture_worker_context']
pub fn context(argument voidptr) voidptr {
	unsafe {
		mut test := &WorkerResult(argument)
		cpus := C.vinix_linuxkpi_percpu_count()
		C.__atomic_add_fetch(&test.calls, 1, 0)
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace context actor entered cpus=%u actual_cpu=%u ticks=%lu\n', cpus, C.vinix_linuxkpi_cpu_id(), C.jiffies)
		}
		if cpus == 0 || cpus > 64 || !C.vinix_linuxkpi_may_sleep() || C.vinix_linuxkpi_worker_nice() != 0 {
			test.result = -C.EIO
		} else {
			for cpu := u32(0); cpu < cpus; cpu++ {
				if C.VKF_WORKER_TRACE {
					C.kprintf(c'linuxkpi: worker trace context bind begin target=%u actual_cpu=%u ticks=%lu\n', cpu, C.vinix_linuxkpi_cpu_id(), C.jiffies)
				}
				if C.vinix_linuxkpi_worker_bind(cpu) != 0 { test.result = -C.EIO }
				if C.VKF_WORKER_TRACE {
					C.kprintf(c'linuxkpi: worker trace context bind complete target=%u actual_cpu=%u result=%d ticks=%lu\n', cpu, C.vinix_linuxkpi_cpu_id(), test.result, C.jiffies)
				}
				placement(test, cpu, 0)
			}
			last := cpus - 1
			other := if cpus > 1 { u32(0) } else { last }
			if C.VKF_WORKER_TRACE {
				C.kprintf(c'linuxkpi: worker trace context invalid CPU/nice checks begin ticks=%lu\n', C.jiffies)
			}
			if C.vinix_linuxkpi_worker_bind(cpus) != -C.EINVAL || C.vinix_linuxkpi_worker_bind(u32(-1)) != -C.EINVAL || C.vinix_linuxkpi_worker_set_nice(-21) != -C.EINVAL || C.vinix_linuxkpi_worker_set_nice(20) != -C.EINVAL {
				test.result = -C.EIO
			}
			placement(test, last, 0)
			if C.VKF_WORKER_TRACE {
				C.kprintf(c'linuxkpi: worker trace context IRQ-off checks begin ticks=%lu\n', C.jiffies)
			}
			irq_flags := C.vinix_linuxkpi_irq_save()
			if C.vinix_linuxkpi_worker_bind(other) != -C.EWOULDBLOCK || C.vinix_linuxkpi_worker_set_nice(-20) != -C.EWOULDBLOCK || C.vinix_linuxkpi_irq_flags() & (usize(1) << 9) != 0 || C.vinix_linuxkpi_worker_nice() != 0 || C.vinix_linuxkpi_cpu_id() != last {
				test.result = -C.EIO
			}
			C.vinix_linuxkpi_irq_restore(irq_flags)
			placement(test, last, 0)
			if C.VKF_WORKER_TRACE {
				C.kprintf(c'linuxkpi: worker trace context preempt-disabled checks begin ticks=%lu\n', C.jiffies)
			}
			C.vinix_linuxkpi_preempt_disable()
			pinned := C.vinix_linuxkpi_preempt_count()
			if pinned == 0 || C.vinix_linuxkpi_worker_bind(other) != -C.EWOULDBLOCK || C.vinix_linuxkpi_worker_set_nice(-20) != -C.EWOULDBLOCK || C.vinix_linuxkpi_preempt_count() != pinned || C.vinix_linuxkpi_worker_nice() != 0 || C.vinix_linuxkpi_cpu_id() != last {
				test.result = -C.EIO
			}
			C.vinix_linuxkpi_preempt_enable()
			placement(test, last, 0)
			if C.VKF_WORKER_TRACE {
				C.kprintf(c'linuxkpi: worker trace context high-priority nice set begin ticks=%lu\n', C.jiffies)
			}
			if C.vinix_linuxkpi_worker_set_nice(-20) != 0 { test.result = -C.EIO }
			placement(test, last, -20)
		}
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace context nice_ready publish result=%d ticks=%lu\n', test.result, C.jiffies)
		}
		C.complete(&test.nice_ready)
		C.wait_for_completion(&test.nice_release)
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace context nice_release received ticks=%lu\n', C.jiffies)
		}
		if cpus != 0 && cpus <= 64 { placement(test, cpus - 1, -20) }
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace context actor exit result=%d ticks=%lu\n', test.result, C.jiffies)
		}
		C.pthread_exit(voidptr(exit_value))
		return nil
	}
}

@[export: 'vinix_linuxkpi_worker_native_selftest']
pub fn selftest() i32 {
	unsafe {
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace batch begin ticks=%lu\n', C.jiffies)
		}
		mut result := failures()
		mut test := WorkerResult{}
		C.init_completion(&test.nice_ready)
		C.init_completion(&test.nice_release)
		if C.vinix_linuxkpi_worker_nice() != 0 || C.vinix_linuxkpi_worker_timeslice() != 5000 {
			result = -C.EIO
		}
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace controller nice check complete result=%d ticks=%lu\n', result, C.jiffies)
		}
		mut native_thread := C.pthread_t{}
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace context pthread create begin ticks=%lu\n', C.jiffies)
		}
		if C.pthread_create(&native_thread, nil, C.vinix_linuxkpi_fixture_worker_context, &test) != 0 {
			return -C.ENOMEM
		}
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace context pthread created; wait nice_ready begin ticks=%lu\n', C.jiffies)
		}
		if C.wait_for_completion_timeout(&test.nice_ready, 500) == 0 || C.vinix_linuxkpi_worker_nice() != 0 || C.vinix_linuxkpi_worker_timeslice() != 5000 {
			result = -C.EIO
		}
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace controller nice_ready wait complete result=%d ticks=%lu\n', result, C.jiffies)
		}
		C.complete(&test.nice_release)
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace controller nice_release published; join begin ticks=%lu\n', C.jiffies)
		}
		if join(native_thread, &test) != 0 || C.vinix_linuxkpi_worker_nice() != 0 || C.vinix_linuxkpi_worker_timeslice() != 5000 {
			result = -C.EIO
		}
		if C.VKF_WORKER_TRACE {
			C.kprintf(c'linuxkpi: worker trace batch complete result=%d ticks=%lu\n', result, C.jiffies)
		}
		return result
	}
}
