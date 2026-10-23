// SPDX-License-Identifier: GPL-2.0-or-later
// Private UNBUILT draft. No runtime or allocation qualification is claimed.
module semwaitfixture

#include <alloca.h>
#include <fcntl.h>
#include <string.h>

fn C.alloca(usize) voidptr
fn C.open(&char, i32, ...) i32
fn C.fcntl(i32, i32, ...) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.snprintf(&char, usize, &char, ...) i32
fn C.sscanf(&char, &char, ...) i32
struct C.FILE {}
fn C.fdopen(i32, &char) &C.FILE
fn C.fgets(&char, i32, &C.FILE) &char
fn C.ferror(&C.FILE) i32
fn C.fclose(&C.FILE) i32

struct OutcomeReader {
mut:
	outcome Outcome
	received usize
	broken bool
}

struct LifecycleCounts {
mut:
	started i32
	sleeping i32
	reaped i32
	signal_attempts i32
}

fn storage_nonblocking(worker Worker) {
	flags := C.fcntl(worker.fd, C.F_GETFL)
	if flags < 0 || C.fcntl(worker.fd, C.F_SETFL, flags | C.O_NONBLOCK) != 0 { fatal(918) }
}

// A single atomic pipe write carries each outcome, but handle partial reads
// explicitly so the repeated-signal path never needs a blocking read.
fn storage_read(worker Worker, reader &OutcomeReader) bool {
	unsafe {
		mut result := &OutcomeReader(reader)
		if result.received == sizeof(Outcome) { return true }
		if result.broken { return false }
		buffer := voidptr(usize(&result.outcome) + result.received)
		amount := C.read(worker.fd, buffer, sizeof(Outcome) - result.received)
		if amount > 0 {
			result.received += usize(amount)
		} else if amount == 0 {
			result.broken = true
		} else if *C.__errno_location() != C.EAGAIN && *C.__errno_location() != C.EINTR {
			result.broken = true
		}
		return result.received == sizeof(Outcome)
	}
}

// ready follows signal setup and precedes the syscall. The child has no other
// explicit blocking operation after ready. Observing S adds an actual sleep
// checkpoint without depending on the GETNCNT/GETZCNT behavior under test.
fn storage_await_sleep(worker Worker, reader &OutcomeReader) bool {
	unsafe {
		mut path := [64]char{}
		length := C.snprintf(&path[0], sizeof(path), c'/proc/%d/stat', worker.pid)
		if length <= 0 || length >= i32(sizeof(path)) { fatal(910) }
		fd := C.open(&path[0], C.O_RDONLY)
		if fd < 0 { fatal(911) }
		mut sleeping := false
		for _ in 0 .. 2000 {
			if storage_read(worker, reader) || reader.broken { break }
			mut data := [2048]char{}
			amount := C.pread(fd, &data[0], sizeof(data) - 1, 0)
			if amount <= 0 || amount >= isize(sizeof(data)) { break }
			mut actual_pid := i32(-1)
			if C.sscanf(&data[0], c'%d ', &actual_pid) != 1 || actual_pid != worker.pid { break }
			// The executable name may contain parentheses, so use the last ).
			mut end_name := -1
			for i in 0 .. int(amount) { if data[i] == char(41) { end_name = i } }
			if end_name >= 0 && end_name + 3 < int(amount)
				&& data[end_name + 1] == char(32) && data[end_name + 2] == char(83)
				&& data[end_name + 3] == char(32) {
				sleeping = true
				break
			}
			C.usleep(1000)
		}
		if C.close(fd) != 0 { fatal(912) }
		return sleeping
	}
}

fn storage_finish(worker Worker, reader &OutcomeReader, wanted_error i32,
	mut totals Totals, counts &LifecycleCounts) {
	unsafe {
		mut complete := storage_read(worker, reader)
		for _ in 0 .. 10000 {
			if complete || reader.broken { break }
			C.usleep(1000)
			complete = storage_read(worker, reader)
		}
		if !complete {
			// A failed checkpoint/outcome remains a failed trial; kill only to
			// bound cleanup and allow the other cohort summaries to be emitted.
			if C.kill(worker.pid, C.SIGKILL) != 0 && *C.__errno_location() != C.ESRCH { fatal(913) }
		}
		if C.close(worker.fd) != 0 { fatal(914) }
		mut status := i32(-1)
		if C.waitpid(worker.pid, &status, 0) != worker.pid { fatal(915) }
		mut progress := &LifecycleCounts(counts)
		progress.reaped++
		check(mut totals, complete && status == 0, 916)
		check(mut totals, reader.outcome.result == if wanted_error == 0 { isize(0) } else { isize(-1) }
			&& reader.outcome.code == wanted_error, 917)
	}
}

fn storage_operation(kind i32, index i32, mut totals Totals, counts &LifecycleCounts) {
	unsafe {
		id := create([i32(0), 1, 0]!)
		zero_waiter := index % 2 != 0
		ops := one(if zero_waiter { u16(1) } else { u16(0) }, if zero_waiter { i16(0) } else { i16(-1) })
		// One second makes a genuine timeout wait observable. A missed
		// checkpoint rejects the trial; it is never accepted as proof of wait.
		worker := start(id, ops, 1, if kind == 1 { i32(1000) } else { i32(-1) })
		storage_nonblocking(worker)
		reader := &OutcomeReader(C.alloca(sizeof(OutcomeReader)))
		*reader = OutcomeReader{}
		mut progress := &LifecycleCounts(counts)
		progress.started++
		sleeping := storage_await_sleep(worker, reader)
		if sleeping { progress.sleeping++ }
		check(mut totals, sleeping, 919)
		mut wanted_error := i32(0)
		match kind {
			0 { set_value(id, if zero_waiter { i32(1) } else { i32(0) }, if zero_waiter { i32(0) } else { i32(1) }) }
			1 { wanted_error = C.EAGAIN }
			2 {
				wanted_error = C.EINTR
				// ready alone is not an entry barrier. Keep signalling until the
				// nonblocking outcome read succeeds, covering a signal delivered
				// immediately before the actual semop entry.
				for _ in 0 .. 10000 {
					if storage_read(worker, reader) || reader.broken { break }
					if C.kill(worker.pid, C.SIGUSR1) != 0 && *C.__errno_location() != C.ESRCH { fatal(920) }
					progress.signal_attempts++
					C.usleep(1000)
				}
			}
			3 { wanted_error = C.EIDRM; remove(id) }
			else { fatal(921) }
		}
		storage_finish(worker, reader, wanted_error, mut totals, counts)
		if kind != 3 {
			empty(id, mut totals, 922)
			wanted := if kind == 0 && zero_waiter { [i32(0), 0, 0]! } else { [i32(0), 1, 0]! }
			values(id, wanted, mut totals, 923)
			remove(id)
		} else {
			errno_ptr := C.__errno_location()
			*errno_ptr = 0
			result := ctl(id, 0, C.GETNCNT, 0)
			check(mut totals, result == -1 && *C.__errno_location() == C.EINVAL, 926)
		}
	}
}

fn storage_prune() {
	if C.open(c'/proc/2147483647/ns/ipc', C.O_RDONLY) != -1 || unsafe { *C.__errno_location() } != C.ENOENT { fatal(927) }
}

// This diagnostic runs only after both strict snapshots have been recorded.
// It cannot make a growing cohort pass or alter the compared measurements.
fn storage_allocsites(kind i32) {
	unsafe {
		fd := C.open(c'/proc/allocsites', C.O_RDONLY)
		if fd < 0 { fatal(932) }
		stream := C.fdopen(fd, c'r')
		if stream == nil { C.close(fd); fatal(933) }
		mut line := [2048]char{}
		for C.fgets(&line[0], i32(sizeof(line)), stream) != nil {
			C.printf(c'PERF-SITE program=semwait cohort=%d %s', kind, &line[0])
		}
		if C.ferror(stream) != 0 || C.fclose(stream) != 0 { fatal(934) }
		C.fflush(nil)
	}
}

fn storage_cohort(kind i32, observer i32, tracked bool, mut totals Totals) {
	unsafe {
		failures_before := totals.failures
		counts := &LifecycleCounts(C.alloca(sizeof(LifecycleCounts)))
		*counts = LifecycleCounts{}
		for index in 0 .. 200 { storage_operation(kind, i32(index), mut totals, counts) }
		// Reading child stat makes proc nodes. Use the final Q2 procfs base on
		// both sides, prune dead entries identically, then use the same grace
		// and exact slab/page/taint comparison as the qualified procns probe.
		storage_prune()
		C.usleep(26000000)
		before := &Slabs(C.alloca(sizeof(Slabs)))
		after := &Slabs(C.alloca(sizeof(Slabs)))
		if !storage_snapshot(observer, before) { fatal(928) }
		if tracked {
			reset := C.open(c'/proc/allocstart', 0)
			mut data := [8]char{}
			if reset < 0 || C.pread(reset, &data[0], 7, 0) <= 0 || C.close(reset) != 0 { fatal(929) }
		}
		for index in 0 .. 200 { storage_operation(kind, i32(index), mut totals, counts) }
		storage_prune()
		C.usleep(26000000)
		if !storage_snapshot(observer, after) { fatal(930) }
		mut good := before.rows == after.rows && before.large == after.large
		good = good && before.tainted == 0 && after.tainted == 0
		good = good && totals.failures == failures_before && counts.started == 400 && counts.sleeping == 400 && counts.reaped == 400
		for i in 0 .. int(before.rows) {
			if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { good = false }
			C.printf(c'LINUX SEMWAIT SLAB: kind=%d size=%lu live=%lu/%lu cycles=200\n', kind, before.sizes[i], before.live[i], after.live[i])
		}
		C.printf(c'LINUX SEMWAIT LIFECYCLE: kind=%d warmup=200 cycles=200 negative_per_phase=100 zero_per_phase=100 started=%d sleeping=%d reaped=%d signal_attempts=%d\n', kind, counts.started, counts.sleeping, counts.reaped, counts.signal_attempts)
		C.printf(c'LINUX SEMWAIT STORAGE: kind=%d cycles=200 big_pages=%lu/%lu written_after_free=%lu/%lu errors=%d %s\n', kind, before.large, after.large, before.tainted, after.tainted, totals.failures - failures_before, if good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil)
		check(mut totals, good, 931)
		if !good && tracked { storage_allocsites(kind) }
	}
}
