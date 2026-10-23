// SPDX-License-Identifier: GPL-2.0-or-later
// Private UNBUILT allocation-cohort draft. Original fixed fixture preserved separately.
module semwaitfixture

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <sys/sem.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

@[packed]
struct SemOp {
 number u16
 adjustment i16
 flags i16
}
struct C.timespec { tv_sec isize tv_nsec isize }
struct Outcome { result isize code i32 }
struct Worker { pid i32 fd i32 }
struct Totals { mut: checks i32 failures i32 }

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.pipe2(&i32, i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.kill(i32, i32) i32
fn C.signal(i32, fn(i32)) voidptr
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C._exit(i32)

fn fatal(stage i32) {
 C.printf(c'LINUX SEMWAIT FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil })
 C._exit(90)
}

fn check(mut totals Totals, good bool, stage i32) {
 totals.checks++
 if !good {
  totals.failures++
  C.printf(c'LINUX SEMWAIT MISMATCH: stage=%d\n', stage)
 }
}

fn ctl(id i32, number i32, command i32, argument isize) isize {
 return C.syscall(isize(C.SYS_semctl), isize(id), isize(number), isize(command), argument)
}

fn set_value(id i32, number i32, value i32) {
 if ctl(id, number, C.SETVAL, isize(value)) != 0 { fatal(1) }
}

fn create(values [3]i32) i32 {
 id := i32(C.syscall(isize(C.SYS_semget), isize(C.IPC_PRIVATE), isize(3), isize(0o600)))
 if id < 0 { fatal(2) }
 for number in 0 .. 3 { set_value(id, i32(number), unsafe { values[number] }) }
 return id
}

fn remove(id i32) { if ctl(id, 0, C.IPC_RMID, 0) != 0 { fatal(3) } }

fn signal_handler(_ i32) {}

fn start(id i32, operations [3]SemOp, count i32, timeout_ms i32) Worker {
 mut channel := [i32(-1), i32(-1)]!
 if C.pipe2(unsafe { &channel[0] }, 0) != 0 { fatal(4) }
 child := C.fork()
 if child < 0 { fatal(5) }
 if child == 0 {
  C.close(channel[0])
  if C.signal(C.SIGUSR1, signal_handler) == voidptr(-1) { C._exit(91) }
  C.alarm(90)
  ready := u8(0x5a)
  if C.write(channel[1], &ready, 1) != 1 { C._exit(92) }
  mut ops := [operations[0], operations[1], operations[2]]!
  mut duration := C.timespec{ tv_sec: isize(timeout_ms / 1000), tv_nsec: isize(timeout_ms % 1000) * 1000000 }
  errno_ptr := C.__errno_location()
  unsafe { *errno_ptr = 0 }
  result := if timeout_ms < 0 {
   C.syscall(isize(C.SYS_semop), isize(id), unsafe { &ops[0] }, isize(count))
  } else {
   C.syscall(isize(C.SYS_semtimedop), isize(id), unsafe { &ops[0] }, isize(count), &duration)
  }
  outcome := Outcome{ result: result, code: unsafe { *C.__errno_location() } }
  if C.write(channel[1], &outcome, sizeof(Outcome)) != isize(sizeof(Outcome)) { C._exit(93) }
  C._exit(0)
 }
 if C.close(channel[1]) != 0 { fatal(6) }
 mut ready := u8(0)
 if C.read(channel[0], &ready, 1) != 1 || ready != 0x5a { fatal(7) }
 return Worker{ pid: child, fd: channel[0] }
}

fn finish(worker Worker, wanted_error i32, mut totals Totals, stage i32) {
 mut outcome := Outcome{}
 received := C.read(worker.fd, &outcome, sizeof(Outcome))
 if C.close(worker.fd) != 0 { fatal(8) }
 mut status := i32(-1)
 if C.waitpid(worker.pid, &status, 0) != worker.pid { fatal(9) }
 check(mut totals, received == isize(sizeof(Outcome)) && status == 0, stage)
 check(mut totals, outcome.result == if wanted_error == 0 { isize(0) } else { isize(-1) }
  && outcome.code == wanted_error, stage + 1)
}

fn grid(id i32, negative [3]i32, zero [3]i32) bool {
 for number in 0 .. 3 {
  if ctl(id, i32(number), C.GETNCNT, 0) != unsafe { negative[number] }
   || ctl(id, i32(number), C.GETZCNT, 0) != unsafe { zero[number] } { return false }
 }
 return true
}

fn await_grid(id i32, negative [3]i32, zero [3]i32, mut totals Totals, stage i32) {
 mut good := false
 for _ in 0 .. 2000 {
  if grid(id, negative, zero) { good = true; break }
  C.usleep(1000)
 }
 check(mut totals, good, stage)
}

fn values(id i32, wanted [3]i32, mut totals Totals, stage i32) {
 for number in 0 .. 3 {
  check(mut totals, ctl(id, i32(number), C.GETVAL, 0) == unsafe { wanted[number] }, stage + i32(number))
 }
}

fn empty(id i32, mut totals Totals, stage i32) {
 check(mut totals, grid(id, [i32(0), 0, 0]!, [i32(0), 0, 0]!), stage)
}

fn one(number u16, adjustment i16) [3]SemOp {
 return [SemOp{ number: number, adjustment: adjustment }, SemOp{}, SemOp{}]!
}

fn independent(mut totals Totals) {
 id := create([i32(0), 0, 1]!)
 first := start(id, one(0, -1), 1, -1)
 second := start(id, one(1, -1), 1, -1)
 await_grid(id, [i32(1), 1, 0]!, [i32(0), 0, 0]!, mut totals, 100)
 values(id, [i32(0), 0, 1]!, mut totals, 101)
 set_value(id, 0, 1)
 finish(first, 0, mut totals, 105)
 await_grid(id, [i32(0), 1, 0]!, [i32(0), 0, 0]!, mut totals, 107)
 set_value(id, 1, 1)
 finish(second, 0, mut totals, 108)
 empty(id, mut totals, 110)
 values(id, [i32(0), 0, 1]!, mut totals, 111)
 remove(id)

 zero_id := create([i32(0), 1, 1]!)
 zero_first := start(zero_id, one(1, 0), 1, -1)
 zero_second := start(zero_id, one(2, 0), 1, -1)
 await_grid(zero_id, [i32(0), 0, 0]!, [i32(0), 1, 1]!, mut totals, 120)
 set_value(zero_id, 1, 0)
 finish(zero_first, 0, mut totals, 121)
 await_grid(zero_id, [i32(0), 0, 0]!, [i32(0), 0, 1]!, mut totals, 123)
 set_value(zero_id, 2, 0)
 finish(zero_second, 0, mut totals, 124)
 empty(zero_id, mut totals, 126)
 remove(zero_id)

 many := create([i32(0), 0, 0]!)
 a := start(many, one(0, -1), 1, -1)
 b := start(many, one(0, -1), 1, -1)
 c := start(many, one(0, -1), 1, -1)
 await_grid(many, [i32(3), 0, 0]!, [i32(0), 0, 0]!, mut totals, 130)
 set_value(many, 0, 3)
 finish(a, 0, mut totals, 131)
 finish(b, 0, mut totals, 133)
 finish(c, 0, mut totals, 135)
 empty(many, mut totals, 137)
 values(many, [i32(0), 0, 0]!, mut totals, 138)
 remove(many)
}

fn changing_blocker(mut totals Totals) {
 id := create([i32(0), 1, 0]!)
 ops := [SemOp{ number: 0, adjustment: -1 }, SemOp{ number: 1 }, SemOp{ number: 2, adjustment: -1 }]!
 worker := start(id, ops, 3, -1)
 await_grid(id, [i32(1), 0, 0]!, [i32(0), 0, 0]!, mut totals, 200)
 values(id, [i32(0), 1, 0]!, mut totals, 201)
 set_value(id, 0, 1)
 await_grid(id, [i32(0), 0, 0]!, [i32(0), 1, 0]!, mut totals, 204)
 values(id, [i32(1), 1, 0]!, mut totals, 205)
 set_value(id, 1, 0)
 await_grid(id, [i32(0), 0, 1]!, [i32(0), 0, 0]!, mut totals, 208)
 values(id, [i32(1), 0, 0]!, mut totals, 209)
 set_value(id, 2, 1)
 finish(worker, 0, mut totals, 212)
 empty(id, mut totals, 214)
 values(id, [i32(0), 0, 0]!, mut totals, 215)
 remove(id)

 repeated := create([i32(1), 0, 0]!)
 repeat_ops := [SemOp{ adjustment: -1 }, SemOp{ adjustment: -1 }, SemOp{}]!
 repeat_worker := start(repeated, repeat_ops, 2, -1)
 await_grid(repeated, [i32(1), 0, 0]!, [i32(0), 0, 0]!, mut totals, 220)
 values(repeated, [i32(1), 0, 0]!, mut totals, 221)
 set_value(repeated, 0, 2)
 finish(repeat_worker, 0, mut totals, 224)
 empty(repeated, mut totals, 226)
 values(repeated, [i32(0), 0, 0]!, mut totals, 227)
 remove(repeated)
}

fn refusals(mut totals Totals) {
 id := create([i32(0), 0, 0]!)
 mut ops := [SemOp{ adjustment: 1 }, SemOp{ number: 1, adjustment: -1, flags: i16(C.IPC_NOWAIT) }, SemOp{}]!
 errno_ptr := C.__errno_location()
 unsafe { *errno_ptr = 0 }
 result := C.syscall(isize(C.SYS_semop), isize(id), unsafe { &ops[0] }, isize(2))
 check(mut totals, result == -1 && unsafe { *C.__errno_location() } == C.EAGAIN, 300)
 empty(id, mut totals, 301)
 values(id, [i32(0), 0, 0]!, mut totals, 302)
 immediate := start(id, one(0, -1), 1, 0)
 finish(immediate, C.EAGAIN, mut totals, 305)
 empty(id, mut totals, 307)
 delayed := start(id, one(2, -1), 1, 3000)
 await_grid(id, [i32(0), 0, 1]!, [i32(0), 0, 0]!, mut totals, 308)
 finish(delayed, C.EAGAIN, mut totals, 309)
 empty(id, mut totals, 311)
 values(id, [i32(0), 0, 0]!, mut totals, 312)
 remove(id)
}

fn interrupted(mut totals Totals) {
 id := create([i32(0), 1, 0]!)
 ops := [SemOp{ adjustment: -1 }, SemOp{ number: 1 }, SemOp{}]!
 worker := start(id, ops, 2, -1)
 await_grid(id, [i32(1), 0, 0]!, [i32(0), 0, 0]!, mut totals, 400)
 set_value(id, 0, 1)
 await_grid(id, [i32(0), 0, 0]!, [i32(0), 1, 0]!, mut totals, 401)
 if C.kill(worker.pid, C.SIGUSR1) != 0 { fatal(10) }
 finish(worker, C.EINTR, mut totals, 402)
 empty(id, mut totals, 404)
 values(id, [i32(1), 1, 0]!, mut totals, 405)
 remove(id)
}

fn removed(mut totals Totals) {
 id := create([i32(0), 1, 0]!)
 negative := start(id, one(0, -1), 1, -1)
 zero := start(id, one(1, 0), 1, -1)
 await_grid(id, [i32(1), 0, 0]!, [i32(0), 1, 0]!, mut totals, 500)
 remove(id)
 finish(negative, C.EIDRM, mut totals, 501)
 finish(zero, C.EIDRM, mut totals, 503)
 errno_ptr := C.__errno_location()
 unsafe { *errno_ptr = 0 }
 result := ctl(id, 0, C.GETNCNT, 0)
 check(mut totals, result == -1 && unsafe { *C.__errno_location() } == C.EINVAL, 505)
 fresh := create([i32(0), 0, 0]!)
 empty(fresh, mut totals, 506)
 remove(fresh)
}

pub fn run(reference bool, allocation_only bool) int {
 C.alarm(if reference { u32(300) } else { u32(3600) })
 mut totals := Totals{}
 if !allocation_only {
  independent(mut totals)
  changing_blocker(mut totals)
  refusals(mut totals)
  interrupted(mut totals)
  removed(mut totals)
  queued_competition(mut totals)
  queued_dependencies(mut totals)
  lifetime_many(mut totals)
  lifetime_completion(mut totals)
  lifetime_forced_exit(mut totals)
 }
 if !reference {
  observer := C.open(c'/proc/slabinfo', 0)
  if observer < 0 { fatal(900) }
  tracker := C.open(c'/proc/allocstart', 0)
  tracked := tracker >= 0
  if tracked && C.close(tracker) != 0 { fatal(901) }
  for kind in 0 .. 4 { storage_cohort(i32(kind), observer, tracked, mut totals) }
  if C.close(observer) != 0 { fatal(902) }
 }
 C.alarm(0)
 C.printf(c'LINUX SEMWAIT SUMMARY: checks=%d failures=%d\n', totals.checks, totals.failures)
 if totals.failures != 0 { C.puts(c'LINUX SEMWAIT: FAIL'); C.fflush(unsafe { nil }); return 1 }
 C.puts(if reference { c'LINUX SEMWAIT REFERENCE: PASS' } else if allocation_only { c'LINUX SEMWAIT STORAGE-ONLY: PASS' } else { c'LINUX SEMWAIT: PASS' })
 C.fflush(unsafe { nil })
 for { C.pause() }
 return 0
}

#include <string.h>
fn C.strcmp(&char, &char) i32
@[export: 'main']
pub fn entry(argc i32, argv &&char) i32 {
 return run(argc == 2 && unsafe { C.strcmp(argv[1], c'--reference') == 0 }, argc == 2 && unsafe { C.strcmp(argv[1], c'--storage-only') == 0 })
}
