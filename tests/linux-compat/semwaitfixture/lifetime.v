// Private lifetime controls. Runtime behavior remains unqualified.
module semwaitfixture

#include <pthread.h>
struct C.pthread_t {}
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32

// Eighty simultaneous pending calls exceed the old shared event's 64 slots.
// Half wait for a decrement, half for zero; both groups require exact outcomes.
fn lifetime_many(mut totals Totals) {
	unsafe {
		id := create([i32(0), 1, 0]!)
		mut workers := [80]Worker{}
		for index in 0 .. 80 {
			workers[index] = start(id, one(if index % 2 == 0 { u16(0) } else { u16(1) },
				if index % 2 == 0 { i16(-1) } else { i16(0) }), 1, -1)
		}
		await_grid(id, [i32(40), 0, 0]!, [i32(0), 40, 0]!, mut totals, 700)
		set_value(id, 0, 40)
		check(mut totals, grid(id, [i32(0), 0, 0]!, [i32(0), 40, 0]!), 701)
		values(id, [i32(0), 1, 0]!, mut totals, 702)
		set_value(id, 1, 0)
		empty(id, mut totals, 705)
		for index in 0 .. 80 { finish(workers[index], 0, mut totals, 706) }
		empty(id, mut totals, 708)
		values(id, [i32(0), 0, 0]!, mut totals, 709)
		remove(id)
		C.puts(c'LINUX SEMWAIT LIFETIME: queued=80 negative=40 zero=40 checked')
	}
}

// Queue entry is observed before grant. Repeating the immediate following
// action exercises completion/unwind races without presuming child scheduling.
// The timer variant also waits beyond the original deadline before reaping.
fn lifetime_completion(mut totals Totals) {
	for kind in 0 .. 3 {
		trials := if kind == 2 { 8 } else { 32 }
		for _ in 0 .. trials {
			id := create([i32(0), 0, 0]!)
			worker := start(id, one(0, -1), 1, if kind == 2 { i32(1000) } else { i32(-1) })
			await_grid(id, [i32(1), 0, 0]!, [i32(0), 0, 0]!, mut totals, 720)
			set_value(id, 0, 1)
			empty(id, mut totals, 721)
			values(id, [i32(0), 0, 0]!, mut totals, 722)
			if kind == 0 {
				remove(id)
			} else if kind == 1 {
				// An unreaped child cannot have its PID reused. ESRCH permits
				// completion that already reached exit; the result stays strict.
				if C.kill(worker.pid, C.SIGUSR1) != 0 && unsafe { *C.__errno_location() } != C.ESRCH { fatal(940) }
			} else {
				C.usleep(1100000)
			}
			finish(worker, 0, mut totals, 725)
			if kind != 0 { empty(id, mut totals, 727); remove(id) }
		}
		C.printf(c'LINUX SEMWAIT LIFETIME: completion_action=%d trials=%d checked\n', kind, trials)
	}
}

struct ExitRequest {
	id i32
	ready i32
}

fn lifetime_pending_thread(argument voidptr) voidptr {
	unsafe {
		request := &ExitRequest(argument)
		ready := u8(0x6b)
		if C.write(request.ready, &ready, 1) != 1 { C._exit(94) }
		mut ops := [SemOp{ adjustment: -1 }]!
		C.syscall(isize(C.SYS_semop), isize(request.id), &ops[0], isize(1))
		// A forced group exit must not return to this user frame.
		C._exit(95)
		return nil
	}
}

// A sibling calls exit_group while its peer owns a queued operation frame.
// The second variant kills the whole group from the observing parent.
fn lifetime_forced_exit(mut totals Totals) {
	unsafe {
		for kind in 0 .. 2 {
			for _ in 0 .. 16 {
				id := create([i32(0), 0, 0]!)
				mut ready := [i32(-1), -1]!
				mut door := [i32(-1), -1]!
				if C.pipe2(&ready[0], 0) != 0 || C.pipe2(&door[0], 0) != 0 { fatal(941) }
				child := C.fork()
				if child < 0 { fatal(942) }
				if child == 0 {
					C.close(ready[0]); C.close(door[1]); C.alarm(90)
					request := &ExitRequest(C.alloca(sizeof(ExitRequest)))
					*request = ExitRequest{ id: id, ready: ready[1] }
					mut handle := C.pthread_t{}
					if C.pthread_create(&handle, nil, lifetime_pending_thread, request) != 0 { C._exit(96) }
					mut byte := u8(0)
					if C.read(door[0], &byte, 1) != 1 || byte != 0x7c { C._exit(97) }
					C.syscall(isize(C.SYS_exit_group), isize(37))
					C._exit(98)
				}
				if C.close(ready[1]) != 0 || C.close(door[0]) != 0 { fatal(943) }
				mut byte := u8(0)
				if C.read(ready[0], &byte, 1) != 1 || byte != 0x6b || C.close(ready[0]) != 0 { fatal(944) }
				await_grid(id, [i32(1), 0, 0]!, [i32(0), 0, 0]!, mut totals, 740)
				if kind == 0 {
					if C.write(door[1], c'|', 1) != 1 { fatal(945) }
				} else if C.kill(child, C.SIGKILL) != 0 { fatal(946) }
				if C.close(door[1]) != 0 { fatal(947) }
				mut status := i32(-1)
				check(mut totals, C.waitpid(child, &status, 0) == child
					&& status == if kind == 0 { i32(37 << 8) } else { i32(C.SIGKILL) }, 741)
				await_grid(id, [i32(0), 0, 0]!, [i32(0), 0, 0]!, mut totals, 742)
				values(id, [i32(0), 0, 0]!, mut totals, 743)
				set_value(id, 0, 1)
				empty(id, mut totals, 746)
				values(id, [i32(1), 0, 0]!, mut totals, 747)
				remove(id)
			}
			C.printf(c'LINUX SEMWAIT LIFETIME: forced_exit=%d trials=16 checked\n', kind)
		}
	}
}
