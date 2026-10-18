// SPDX-License-Identifier: GPL-2.0-or-later
module sessiondaemon

import desktop.sessioncore
import desktop.sessionipc
import desktop.serviceprocess
import os
import time

#include <sys/file.h>

fn C.flock(int, int) int
fn C.tzset()
fn C.clock_settime(int, &C.timespec) int

__global volatile session_daemon_stop bool

fn session_stop_signal(_ os.Signal) {
	unsafe { session_daemon_stop = true }
}

struct SessionDaemon {
mut:
	notifications      sessioncore.Notifications
	supervisor         sessioncore.Supervisor
	queue              [64]sessionipc.SessionMessage
	queue_count        int
	compositor         int
	home               string
	changed            bool
	last_save          i64
	stop               bool
	stop_deadline      i64
	log_check          i64
	policy             sessioncore.Policy
	settings_result    sessioncore.Text
	operation_pid      int
	operation_deadline i64
	dialogs            [16]SessionDialogTicket
	exchange           &sessioncore.Exchange = unsafe { nil }
	offers             [8]sessioncore.Clip
	operation_lease    int
	service_leases     [32]int
}

struct SessionDialogTicket {
mut:
	pid     int
	key     sessioncore.Text
	kind    int
	path    sessioncore.Text
	status  int
	expires i64
}

fn (mut daemon SessionDaemon) handle(peer sessionipc.SessionCredentials, request string) !string {
	f := sessioncore.fields(request)!
	operation := sessioncore.authorize_session(f.values[0], f.count, sessioncore.SessionCaller{
		pid:            peer.pid
		uid:            peer.uid
		session_uid:    C.getuid()
		compositor_pid: daemon.compositor
	}, &daemon.policy)!
	route := unsafe { &session_routes[int(operation)] }
	mut request_state := &SessionRequest{peer: peer, fields: f}
	defer { unsafe { free(request_state) } }
	if !route.raw_payload {
		request_state.message.pid = peer.pid
		request_state.message.count = f.count
		request_state.message.fields[0].set(f.values[0])!
		for i in 1 .. f.count { request_state.message.fields[i] = sessioncore.unfield(f.values[i])! }
	}
	return route.handler(mut daemon, mut request_state)
}

fn (mut daemon SessionDaemon) save() ! {
	if !daemon.changed { return }
	path := '${daemon.home}/.vinix-notifications'
	record := daemon.notifications.encode()
	defer {
		unsafe {
			path.free()
			record.free()
		}
	}
	sessioncore.save(path, record)!
	daemon.changed = false
}

pub fn run(home string, owner int) {
	sessionipc.desktop_ignore_broken_pipe()
	directory := sessionipc.session_runtime_directory()
	defer { unsafe { directory.free() } }
	if !sessionipc.session_private_directory(directory) {
		eprintln('vinix-session: unsafe runtime directory')
		return
	}
	lock_path := '${directory}/lock'
	path := '${directory}/broker'
	defer {
		unsafe {
			lock_path.free()
			path.free()
		}
	}
	lease_fd := C.open(&char(lock_path.str), C.O_RDWR | C.O_CREAT | C.O_NOFOLLOW | C.O_CLOEXEC, u32(0o600))
	if lease_fd < 0 { return }
	defer { sessionipc.desktop_close(lease_fd) }
	if C.flock(lease_fd, C.LOCK_EX | C.LOCK_NB) != 0 { return }
	addr := sessionipc.session_address(path) or { return }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return }
	defer {
		sessionipc.desktop_close(fd)
		C.unlink(&char(path.str))
	}
	sessionipc.desktop_set_cloexec(fd, true)
	sessionipc.desktop_set_nonblocking(fd, true)
	C.unlink(&char(path.str))
	if C.bind(fd, voidptr(&addr), u32(sizeof(sessionipc.SessionAddress))) != 0 || C.listen(fd, 16) != 0 {
		return
	}
	os.chmod(path, 0o600) or { return }
	mut daemon := &SessionDaemon{ home: home, compositor: owner }
	daemon.exchange = &sessioncore.Exchange{}
	policy_path := '${home}/.vinix-shell-policy'
	policy_record := sessioncore.load(policy_path, 32768) or { '' }
	daemon.policy = sessioncore.decode_policy(policy_record) or { sessioncore.Policy{} }
	if daemon.policy.timezone.len > 0 {
		os.setenv('TZ', daemon.policy.timezone.str(), true)
		C.tzset()
		daemon.policy.timezone_minutes = time.offset() / 60
	}
	unsafe {
		policy_path.free()
		policy_record.free()
	}
	daemon.load_services()
	os.signal_opt(.term, session_stop_signal) or {}
	os.signal_opt(.int, session_stop_signal) or {}
	state_path := '${home}/.vinix-notifications'
	record := sessioncore.load(state_path, 256 * 1024) or { '' }
	daemon.notifications = sessioncore.decode_notifications(record) or { sessioncore.Notifications{} }
	unsafe {
		state_path.free()
		record.free()
	}
	for {
		if daemon.policy.timezone.len > 0 { daemon.policy.timezone_minutes = time.offset() / 60 }
		if unsafe { session_daemon_stop } {
			if !daemon.stop { daemon.stop_deadline = sessionipc.monotonic_millis() + 30000 }
			daemon.stop = true
			daemon.supervisor.stopping = true
		}
		epoch, _ := sessionipc.desktop_realtime()
		if daemon.notifications.tick(epoch, sessionipc.monotonic_millis()) { daemon.changed = true }
		daemon.services_tick()
		if daemon.changed && sessionipc.monotonic_millis() - daemon.last_save >= 1000 {
			daemon.last_save = sessionipc.monotonic_millis()
			daemon.save() or { session_log_error('vinix-session: ', err) }
		}
		if daemon.stop && daemon.operation_pid == 0 && daemon.supervisor.finished() {
			daemon.save() or { session_log_error('vinix-session: ', err) }
			return
		}
		mut readiness := C.pollfd{ fd: fd, events: C.POLLIN }
		if C.poll(&readiness, 1, 100) <= 0 { continue }
		client := C.accept(fd, unsafe { nil }, unsafe { nil })
		if client < 0 { continue }
		sessionipc.desktop_set_cloexec(client, true)
		sessionipc.desktop_set_nonblocking(client, true)
		daemon.serve_client(client)
	}
}

fn (mut daemon SessionDaemon) serve_client(client int) {
	peer := sessionipc.session_peer(client) or {
		sessionipc.desktop_close(client)
		return
	}
	request := sessionipc.session_receive(client) or {
		session_release_error(err, err.msg())
		sessionipc.desktop_close(client)
		return
	}
	mut reply := daemon.handle(peer, request) or {
		session_log_error('vinix-session: request rejected: ', err)
		'error\tdenied'
	}
	// Alarm registration/cancellation is durable before acknowledging it.
	if daemon.changed {
		daemon.save() or {
			session_log_error('vinix-session: state publication failed: ', err)
			if reply != 'ok' && reply != 'empty' && reply != 'error\tdenied' {
				unsafe { reply.free() }
			}
			reply = 'error\tdenied'
		}
	}
	_ = sessionipc.session_send_message(client, reply)
	sessionipc.desktop_close(client)
	unsafe {
		request.free()
		if reply.len > 0 && reply != 'ok' && reply != 'empty' && reply != 'error\tdenied' {
			reply.free()
		}
	}
}

fn (mut daemon SessionDaemon) services_tick() {
	// Runtime process ownership is kept separate from the dependency policy.
	now := sessionipc.monotonic_millis()
	if daemon.stop && now >= daemon.stop_deadline {
		for i in 0 .. daemon.supervisor.count {
			if daemon.supervisor.services[i].pid > 0 {
				C.kill(-daemon.supervisor.services[i].pid, C.SIGKILL)
			}
		}
	}
	if now - daemon.log_check >= 5000 {
		daemon.log_check = now
		for i in 0 .. daemon.supervisor.count {
			session_limit_service_log(daemon.home, daemon.supervisor.services[i].name.str())
		}
		session_limit_service_log(daemon.home, 'settings-operation')
	}
	for i in 0 .. daemon.offers.len {
		if daemon.offers[i].owner_pid > 0 && C.kill(daemon.offers[i].owner_pid, 0) != 0 {
			daemon.exchange.revoke(daemon.offers[i].owner_pid)
			daemon.offers[i] = sessioncore.Clip{}
		}
	}
	if daemon.operation_pid > 0 {
		mut status := 0
		if daemon.stop || now >= daemon.operation_deadline {
			C.kill(-daemon.operation_pid, C.SIGKILL)
		}
		if C.waitpid(daemon.operation_pid, &status, C.WNOHANG) == daemon.operation_pid {
			status = serviceprocess.status(daemon.operation_lease, status)
			daemon.operation_lease = 0
			C.kill(-daemon.operation_pid, C.SIGKILL)
			daemon.operation_pid = 0
			daemon.settings_result.set(if status == 0 {
				'Operation completed. View settings-operation.log for details.'
			} else {
				'Operation failed. View settings-operation.log for details.'
			}) or {}
		}
	}
	for i in 0 .. daemon.supervisor.count {
		pid := daemon.supervisor.services[i].pid
		if pid <= 0 { continue }
		mut status := 0
		if C.waitpid(pid, &status, C.WNOHANG) == pid {
			status = serviceprocess.status(daemon.service_leases[i], status)
			daemon.service_leases[i] = 0
			// A dead service leader must not strand descendants through restart.
			C.kill(-pid, C.SIGKILL)
			daemon.supervisor.exited(i, status, now)
		}
	}
	commands := daemon.supervisor.tick(now)
	for slot in 0 .. commands.count {
		command := commands.items[slot]
		service := daemon.supervisor.services[command.index]
		match command.operation {
			.terminate { C.kill(-service.pid, C.SIGTERM) }
			.kill { C.kill(-service.pid, C.SIGKILL) }
			.start {
				process := serviceprocess.start(service, daemon.home)
				daemon.service_leases[command.index] = process.lease
				daemon.supervisor.started(command.index, process.pid, now)
			}
		}
	}
}

fn (mut daemon SessionDaemon) load_services() {
	path := '${daemon.home}/.vinix-services'
	defer { unsafe { path.free() } }
	record := sessioncore.load(path, 64 * 1024) or {
		if C.getuid() == 0 {
			executable := sessionipc.helper_path('vinix-timesync')
			defer { unsafe { executable.free() } }
			mut service := sessioncore.Service{ name: sessioncore.text('clock-sync') or { return }, executable: sessioncore.text(executable) or { return }, system: true, restart: .on_failure }
			daemon.supervisor.services[0] = service
			daemon.supervisor.count = 1
			daemon.supervisor.validate() or { return }
		}
		return
	}
	defer { unsafe { record.free() } }
	daemon.supervisor = sessioncore.decode_services(record, C.getuid() == 0) or {
		session_log_error('vinix-session: refusing invalid service configuration: ', err)
		return
	}
	daemon.migrate_clock_service()
}

fn (daemon &SessionDaemon) save_services() ! {
	path := '${daemon.home}/.vinix-services'
	record := daemon.supervisor.encode()
	defer {
		unsafe {
			path.free()
			record.free()
		}
	}
	sessioncore.save(path, record)!
}

fn session_limit_service_log(home string, name string) {
	path := '${home}/.vinix-service-logs/${name}.log'
	defer { unsafe { path.free() } }
	mut info := C.stat{}
	if C.lstat(&char(path.str), &info) != 0 || u32(info.st_mode) & C.S_IFMT != C.S_IFREG || info.st_size <= 1024 * 1024 {
		return
	}
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_TRUNC | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	if fd < 0 { return }
	defer { sessionipc.desktop_close(fd) }
	message := 'vinix-session: log exceeded 1 MiB; older output discarded\n'
	C.write(fd, message.str, usize(message.len))
}

fn session_random_token() !u64 {
	mut file := os.open('/dev/urandom')!
	defer { file.close() }
	mut bytes := []u8{len: 8}
	defer { unsafe { bytes.free() } }
	if file.read(mut bytes)! != 8 { return error('exchange randomness unavailable') }
	mut token := u64(0)
	for i in 0 .. 8 { token |= u64(bytes[i]) << (8 * i) }
	token &= 0x7fffffffffffffff
	if token == 0 { return error('invalid random exchange token') }
	return token
}
