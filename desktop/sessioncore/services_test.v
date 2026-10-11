// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

fn services_fixture() Supervisor {
	mut s := Supervisor{ count: 3 }
	for i in 0 .. 3 {
		s.services[i] = Service{ name: text('service.${i}') or { panic(err) }, executable: text('/usr/bin/example') or { panic(err) }, restart: .on_failure }
	}
	s.services[1].dependencies = 1
	s.services[2].dependencies = 2
	s.validate() or { panic(err) }
	return s
}

fn test_dependency_start_and_reverse_shutdown() {
	mut s := services_fixture()
	mut commands := s.tick(1000)
	assert commands.count == 1 && commands.items[0].index == 0
	s.started(0, 10, 1000)
	commands = s.tick(1001)
	assert commands.count == 1 && commands.items[0].index == 1
	s.started(1, 11, 1001)
	commands = s.tick(1002)
	assert commands.count == 1 && commands.items[0].index == 2
	s.started(2, 12, 1002)
	s.stopping = true
	commands = s.tick(2000)
	assert commands.count == 1 && commands.items[0] == ServiceCommand{2, .terminate}
	s.exited(2, 0, 2000)
	commands = s.tick(2001)
	assert commands.items[0].index == 1
	s.exited(1, 0, 2001)
	commands = s.tick(2002)
	assert commands.items[0].index == 0
	s.exited(0, 0, 2002)
	assert s.finished()
}

fn test_provider_crash_stops_consumer_and_bounds_restarts() {
	mut s := services_fixture()
	for i in 0 .. 3 {
		_ = s.tick(1000 + i)
		s.started(i, 10 + i, 1000 + i)
	}
	s.exited(0, 9, 2000)
	commands := s.tick(2001)
	assert commands.count == 1 && commands.items[0].index == 2
	assert s.services[0].state == .backoff && s.services[0].deadline == 3000
	s.exited(2, 0, 2001)
	assert s.tick(2002).items[0].index == 1
	s.exited(1, 0, 2002)
	s.services[0].restart_limit = 1
	_ = s.tick(3000)
	s.started(0, 20, 3000)
	s.exited(0, 9, 3001)
	assert s.services[0].state == .failed
	s.enable(0, true) or { panic(err) }
	assert s.services[0].failures == 0 && s.services[0].state == .stopped
}

fn test_invalid_graph_and_stop_timeout() {
	mut s := services_fixture()
	s.services[0].dependencies = 4
	if _ := s.validate() {
		assert false
	}
	s.services[0].dependencies = 8
	if _ := s.validate() {
		assert false
	}
	s.services[0].dependencies = 0
	s.validate() or { panic(err) }
	_ = s.tick(1000)
	s.started(0, 10, 1000)
	s.stopping = true
	_ = s.tick(2000)
	assert s.tick(7000).items[0].operation == .kill
}
