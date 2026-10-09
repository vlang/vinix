@[has_globals]
module time

import event.eventstruct
import klock
import katomic

pub const timer_frequency = u64(1000)

pub const clock_type_realtime = 0
pub const clock_type_monotonic = 1

pub struct TimeSpec {
pub mut:
	tv_sec  i64
	tv_nsec i64
}

pub fn (mut this TimeSpec) add(interval TimeSpec) {
	if this.tv_nsec + interval.tv_nsec > 999999999 {
		diff := (this.tv_nsec + interval.tv_nsec) - 1000000000
		this.tv_nsec = diff
		this.tv_sec++
	} else {
		this.tv_nsec += interval.tv_nsec
	}
	this.tv_sec += interval.tv_sec
}

pub fn (mut this TimeSpec) sub(interval TimeSpec) bool {
	if interval.tv_nsec > this.tv_nsec {
		diff := interval.tv_nsec - this.tv_nsec
		this.tv_nsec = 1000000000 - diff
		if this.tv_sec == 0 {
			this.tv_sec = 0
			this.tv_nsec = 0
			return true
		}
		this.tv_sec--
	} else {
		this.tv_nsec -= interval.tv_nsec
	}
	if interval.tv_sec > this.tv_sec {
		this.tv_sec = 0
		this.tv_nsec = 0
		return true
	}
	this.tv_sec -= interval.tv_sec
	if this.tv_sec == 0 && this.tv_nsec == 0 {
		return true
	}
	return false
}

__global (
	monotonic_clock TimeSpec
	realtime_clock  TimeSpec
	// Counter reading the clocks were last brought up to date with, for
	// advance_to_ns.
	clock_last_ns   = u64(0)
	clock_tick_lock klock.Lock
	clock_lock klock.Lock
	clock_control ClockDiscipline
	clock_generation u64
)

// Return a stable snapshot of a clock for interfaces, such as absolute futex
// deadlines, that need to translate a point in time into a timer duration.
pub fn clock_now(clock_id int) ?TimeSpec {
	clock_lock.acquire()
	defer { clock_lock.release() }
	raw := raw_clock_now()
	clock_control.sample(raw)
	match clock_id {
		clock_type_realtime { return clock_control.realtime }
		clock_type_monotonic { return clock_control.monotonic }
		4 { return raw }
		else { return none }
	}
}

pub fn clock_coarse_now(clock_id int) ?TimeSpec {
	clock_lock.acquire()
	defer { clock_lock.release() }
	match clock_id {
		clock_type_realtime { return realtime_clock }
		clock_type_monotonic { return monotonic_clock }
		else { return none }
	}
}

// Call during architecture initialization, before enabling timer interrupts.
fn initialize_clocks(epoch i64) {
	monotonic_clock = TimeSpec{}
	realtime_clock = TimeSpec{epoch, 0}
	clock_control = ClockDiscipline{ realtime: realtime_clock }
}

// The caller validates the ABI value and supplies the securelevel policy.
pub fn set_realtime(value TimeSpec, forbid_backwards bool) bool {
	clock_lock.acquire()
	clock_control.sample(raw_clock_now())
	if !clock_control.set_realtime(value, forbid_backwards) {
		clock_lock.release()
		return false
	}
	realtime_clock = clock_control.realtime
	clock_generation++
	clock_lock.release()
	expire_timers()
	run_tick_hooks()
	deadline_changed()
	return true
}

pub fn realtime_generation() u64 {
	clock_lock.acquire()
	value := clock_generation
	clock_lock.release()
	return value
}

// Mode 0 reads state, 1 changes frequency, 2 replaces a pending phase slew,
// and 3 changes both. The syscall layer validates inputs before this call.
pub fn adjust_clock(mode int, frequency i64, slew i64) (i64, i64) {
	clock_lock.acquire()
	defer { clock_lock.release() }
	clock_control.sample(raw_clock_now())
	previous := clock_control.slew_remaining
	if mode & 1 != 0 { clock_control.set_frequency(frequency) }
	if mode & 2 != 0 { clock_control.set_slew(slew) }
	return clock_control.frequency, previous
}

fn C.event__trigger(mut event eventstruct.Event, drop bool) u64

// A periodic interrupt samples the counter rather than counting deliveries:
// hardware can merge multiple ticks while interrupts are disabled.
pub fn timer_handler() {
	advance_to_ns(counter_now_ns())
}

// Ticks may coalesce or arrive after a variable scheduler timeslice. Sample
// the precise hardware clock and apply the same discipline as clock_now(),
// keeping the coarse snapshots and timers on that clock. A contended tick
// leaves clock_last_ns untouched so the next sample includes the interval.
pub fn advance_to_ns(now_ns u64) {
	if clock_tick_lock.test_and_acquire() == false {
		return
	}
	last := clock_last_ns
	if now_ns <= last {
		clock_tick_lock.release()
		return
	}
	clock_last_ns = now_ns
	clock_lock.acquire()
	clock_control.sample(raw_clock_now())
	monotonic_clock = clock_control.monotonic
	realtime_clock = clock_control.realtime
	clock_lock.release()
	clock_tick_lock.release()

	// Events and hooks may take scheduler locks. Keep them outside the clock
	// update lock; timers compare absolute deadlines if another tick wins.
	expire_timers()
	run_tick_hooks()
}

// Anything that has to look at the clock every tick registers here. The
// scheduler cannot call into the file module directly — file reaches sched
// through event — so a timerfd notices its deadline by leaving a hook behind
// instead.
const max_tick_hooks = 8

__global (
	tick_hooks      [max_tick_hooks]fn ()
	tick_hooks_len  = int(0)
	tick_hooks_lock klock.Lock
	deadline_hooks [max_tick_hooks]fn () u64
	deadline_hooks_len int
	deadline_wakeup fn () = unsafe { nil }
)

// Providers return time remaining in nanoseconds. They run outside the timer
// list lock and must not deliver events or retain borrowed object pointers.
pub fn register_deadline_hook(hook fn () u64) bool {
	tick_hooks_lock.acquire()
	defer { tick_hooks_lock.release() }
	for i in 0 .. deadline_hooks_len { if deadline_hooks[i] == hook { return true } }
	if deadline_hooks_len == max_tick_hooks { return false }
	deadline_hooks[deadline_hooks_len] = hook
	katomic.store(mut &deadline_hooks_len, deadline_hooks_len + 1)
	return true
}

pub fn register_tick_deadline_hook(tick fn (), deadline fn () u64) bool {
 return register_tick_hook(tick) && register_deadline_hook(deadline)
}

pub fn register_deadline_wakeup(wakeup fn ()) { deadline_wakeup = wakeup }

pub fn deadline_changed() {
	if deadline_wakeup != unsafe { nil } { deadline_wakeup() }
}

// The architecture supplies a maintenance/input ceiling. Due deadlines use
// one microsecond, never zero (which several hardware timers interpret as off).
pub fn next_wakeup_us(ceiling u64) u64 {
	mut remaining := if ceiling > ~u64(0) / 1000 { ~u64(0) } else { ceiling * 1000 }
	if !timers_lock.test_and_acquire() { return if ceiling < 1000 { ceiling } else { u64(1000) } }
	now := monotonic_ns()
	wall := clock_now(clock_type_realtime) or { TimeSpec{} }
	for timer in armed_timers {
		if timer.fired { continue }
		mut delay := if timer.deadline_ns > now { timer.deadline_ns - now } else { u64(0) }
		if timer.absolute_realtime {
			mut interval := timer.when
			if interval.sub(wall) { delay = 0 }
			else {
				seconds := u64(interval.tv_sec)
				nanos := u64(interval.tv_nsec)
				delay = if seconds > (~u64(0) - nanos) / 1000000000 { ~u64(0) }
					else { seconds * 1000000000 + nanos }
			}
		}
		if delay < remaining { remaining = delay }
	}
	timers_lock.release()
	for i in 0 .. katomic.load(&deadline_hooks_len) {
		delay := deadline_hooks[i]()
		if delay < remaining { remaining = delay }
	}
	return if remaining < 1000 { u64(1) } else { remaining / 1000 + if remaining % 1000 == 0 { u64(0) } else { u64(1) } }
}

pub fn register_tick_hook(hook fn ()) bool {
	tick_hooks_lock.acquire()
	defer {
		tick_hooks_lock.release()
	}

	for i in 0 .. tick_hooks_len { if tick_hooks[i] == hook { return true } }
	if tick_hooks_len == max_tick_hooks {
		return false
	}
	tick_hooks[tick_hooks_len] = hook
	katomic.store(mut &tick_hooks_len, tick_hooks_len + 1)
	return true
}

// Counter deadlines include every interval even when a tick loses this lock.
fn expire_timers() {
	if timers_lock.test_and_acquire() == true {
		// One counter read covers this pass. A newly armed timer cannot enter
		// the list until this lock is released.
		now := monotonic_ns()
		wall := clock_now(clock_type_realtime) or { TimeSpec{} }
		for i := 0; i < armed_timers.len; i++ {
			mut timer := armed_timers[i]
			if timer.fired == true {
				continue
			}
			expired := if timer.absolute_realtime {
				!timespec_before(wall, timer.when)
			} else { now >= timer.deadline_ns }
			if expired {
				C.event__trigger(mut &timer.event, false)
				timer.fired = true
			}
		}

		timers_lock.release()
	}

}

fn run_tick_hooks() {
	count := katomic.load(&tick_hooks_len)
	for i := 0; i < count; i++ {
		tick_hooks[i]()
	}
}

pub struct Timer {
pub mut:
	when  TimeSpec
	event eventstruct.Event
	index int
	fired bool
	// Deadlines use the disciplined monotonic clock on both architectures.
	// A frequency change affects an armed sleep without changing its deadline.
	deadline_ns u64
	absolute_realtime bool
	// Coalesce only relative ordinary waits, within the caller's allowance.
	slack_ns u64
}

__global (
	timers_lock  klock.Lock
	armed_timers []&Timer
)

pub fn (mut this Timer) disarm() {
	timers_lock.acquire()
	defer {
		timers_lock.release()
	}

	if armed_timers.len == 0 || this.index == -1 {
		return
	}
	if this.index >= armed_timers.len {
		return
	}

	armed_timers[this.index] = armed_timers[armed_timers.len - 1]
	armed_timers[this.index].index = this.index
	armed_timers.delete_last()
	this.index = -1
}

pub fn (mut this Timer) arm() {
	if this.index >= 0 { this.disarm() }
	timers_lock.acquire()

	this.fired = false
	this.deadline_ns = timer_deadline(this.when)
	if !this.absolute_realtime && this.slack_ns != 0 {
		room := ~u64(0) - this.deadline_ns
		limit := this.deadline_ns + if this.slack_ns < room { this.slack_ns } else { room }
		for other in armed_timers {
			if !other.fired && !other.absolute_realtime && other.deadline_ns >= this.deadline_ns
				&& other.deadline_ns <= limit { this.deadline_ns = other.deadline_ns; break }
		}
	}
	this.index = armed_timers.len
	armed_timers.flags |= .noslices
	armed_timers << this

	timers_lock.release()
	deadline_changed()
}

// The caller owns the returned timer. After the wait has detached every event
// listener, it must disarm and free the timer; disarming only removes it from
// the global schedule and does not release the heap allocation.
pub fn new_timer(when TimeSpec) &Timer {
	return make_timer(when, false, 0)
}

pub fn new_coalesced_timer(when TimeSpec, slack_ns u64) &Timer {
	return make_timer(when, false, slack_ns)
}

pub fn new_realtime_timer(when TimeSpec) &Timer {
	return make_timer(when, true, 0)
}

fn make_timer(when TimeSpec, absolute_realtime bool, slack_ns u64) &Timer {
	mut timer := &Timer{
		when:  when
		fired: false
		index: -1
		absolute_realtime: absolute_realtime
		slack_ns: slack_ns
	}

	timer.arm()

	return timer
}

// Obtain one locked snapshot from the architecture's precise hardware counter.
pub fn monotonic_ns() u64 {
	now := clock_now(clock_type_monotonic) or { return 0 }
	if now.tv_sec < 0 || now.tv_nsec < 0 { return 0 }
	return u64(now.tv_sec) * 1000000000 + u64(now.tv_nsec)
}

fn timer_deadline(duration TimeSpec) u64 {
	now := monotonic_ns()
	if duration.tv_sec < 0 || duration.tv_nsec < 0 { return now }
	room := ~u64(0) - now
	if u64(duration.tv_sec) > room / 1000000000 { return ~u64(0) }
	whole := u64(duration.tv_sec) * 1000000000
	if u64(duration.tv_nsec) > room - whole { return ~u64(0) }
	return now + whole + u64(duration.tv_nsec)
}
