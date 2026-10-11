// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

pub const max_services = 32

pub enum Restart {
	never
	on_failure
	always
}

pub enum ServiceState {
	stopped
	starting
	running
	stopping
	backoff
	failed
}

pub enum ServiceOperation {
	start
	terminate
	kill
}

pub struct Service {
pub mut:
	name             Text
	executable       Text
	arguments        [16]Text
	argument_count   int
	dependencies     u32
	restart          Restart
	restart_limit    int  = 5
	restart_delay_ms i64  = 1000
	stop_timeout_ms  i64  = 5000
	enabled          bool = true
	system           bool
	state            ServiceState
	pid              int
	failures         int
	exit_status      int
	deadline         i64
	started_at       i64
}

pub struct ServiceCommand {
pub:
	index     int
	operation ServiceOperation
}

pub struct ServiceCommands {
pub mut:
	items [max_services]ServiceCommand
	count int
}

pub struct Supervisor {
pub mut:
	services [max_services]Service
	count    int
	order    [max_services]int
	stopping bool
}

pub fn (mut s Supervisor) validate() ! {
	if s.count < 0 || s.count > max_services { return error('too many services') }
	mut done := u32(0)
	for i in 0 .. s.count {
		v := s.services[i]
		if !identifier(v.name.str()) || !v.executable.str().starts_with('/') || v.argument_count < 0 || v.argument_count > 16
			|| v.restart_limit < 0 || v.restart_limit > 100 || v.restart_delay_ms < 100 || v.restart_delay_ms > 60000 || v.stop_timeout_ms < 100 || v.stop_timeout_ms > 60000 {
			return error('invalid service definition')
		}
		allowed := if s.count == 32 { ~u32(0) } else { (u32(1) << s.count) - 1 }
		if v.dependencies & ~allowed != 0 { return error('missing service dependency') }
		for j in 0 .. i {
			if s.services[j].name.str() == v.name.str() { return error('duplicate service') }
		}
	}
	for rank in 0 .. s.count {
		mut next := -1
		for i in 0 .. s.count {
			if done & (u32(1) << i) == 0 && s.services[i].dependencies & ~done == 0 {
				next = i
				break
			}
		}
		if next < 0 { return error('cyclic service dependencies') }
		s.order[rank] = next
		done |= u32(1) << next
	}
}

fn (s &Supervisor) dependencies_running(index int) bool {
	for i in 0 .. s.count {
		if s.services[index].dependencies & (u32(1) << i) != 0
			&& (!s.services[i].enabled || s.services[i].state != .running || !s.dependencies_running(i)) {
			return false
		}
	}
	return true
}

fn (s &Supervisor) dependent_alive(index int) bool {
	for i in 0 .. s.count {
		if s.services[i].dependencies & (u32(1) << index) != 0 && s.services[i].state in [
			.running,
			.starting,
			.stopping,
		] {
			return true
		}
	}
	return false
}

pub fn (mut s Supervisor) tick(now i64) ServiceCommands {
	mut result := ServiceCommands{}
	// Stop consumers before providers, including when a provider disappears.
	for rank := s.count - 1; rank >= 0; rank-- {
		i := s.order[rank]
		if s.services[i].state == .stopping && now >= s.services[i].deadline {
			result.items[result.count] = ServiceCommand{i, .kill}
			result.count++
			s.services[i].deadline = now + s.services[i].stop_timeout_ms
		} else if s.services[i].state in [.running, .starting]
			&& (s.stopping || !s.services[i].enabled || !s.dependencies_running(i)) && !s.dependent_alive(i) {
			result.items[result.count] = ServiceCommand{i, .terminate}
			result.count++
			s.services[i].state = .stopping
			s.services[i].deadline = now + s.services[i].stop_timeout_ms
		}
	}
	if s.stopping { return result }
	for rank in 0 .. s.count {
		i := s.order[rank]
		if s.services[i].enabled && s.services[i].state in [.stopped, .backoff]
			&& now >= s.services[i].deadline && s.dependencies_running(i) {
			result.items[result.count] = ServiceCommand{i, .start}
			result.count++
			s.services[i].state = .starting
		}
	}
	return result
}

pub fn (mut s Supervisor) started(index int, pid int, now i64) {
	if index < 0 || index >= s.count || s.services[index].state != .starting { return }
	if pid <= 0 {
		s.exited(index, 127, now)
		return
	}
	s.services[index].pid = pid
	s.services[index].state = .running
	s.services[index].started_at = now
}

pub fn (mut s Supervisor) exited(index int, status int, now i64) {
	if index < 0 || index >= s.count { return }
	intentional := s.services[index].state == .stopping
	s.services[index].pid = 0
	s.services[index].exit_status = status
	if s.stopping || !s.services[index].enabled || intentional {
		s.services[index].state = .stopped
		s.services[index].deadline = now
		return
	}
	if s.services[index].restart == .never || (s.services[index].restart == .on_failure && status == 0) {
		s.services[index].state = .failed
		return
	}
	if now - s.services[index].started_at >= 60000 { s.services[index].failures = 0 }
	s.services[index].failures++
	if s.services[index].failures > s.services[index].restart_limit {
		s.services[index].state = .failed
		return
	}
	shift := if s.services[index].failures > 6 { 6 } else { s.services[index].failures - 1 }
	delay := s.services[index].restart_delay_ms * (i64(1) << shift)
	s.services[index].deadline = now + if delay > 60000 { i64(60000) } else { delay }
	s.services[index].state = .backoff
}

pub fn (mut s Supervisor) enable(index int, enabled bool) ! {
	if index < 0 || index >= s.count { return error('unknown service') }
	s.services[index].enabled = enabled
	if enabled && s.services[index].state == .failed {
		s.services[index].failures = 0
		s.services[index].deadline = 0
		s.services[index].state = .stopped
	}
}

pub fn (s &Supervisor) finished() bool {
	for i in 0 .. s.count {
		if s.services[i].pid > 0 || s.services[i].state in [.starting, .running, .stopping] {
			return false
		}
	}
	return true
}
