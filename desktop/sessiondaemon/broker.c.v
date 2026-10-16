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
	if operation == .clipboard_offer {
		kind := unsafe { sessioncore.DataKind(sessioncore.number(f.values[1], 0, 3)!) }
		sensitive := sessioncore.number(f.values[2], 0, 1)! == 1
		data := sessioncore.decode_data(f.values[3])!
		defer { unsafe { data.free() } }
		mut slot := -1
		for i in 0 .. daemon.offers.len {
			if daemon.offers[i].owner_pid == 0 || daemon.offers[i].owner_pid == peer.pid {
				slot = i
				break
			}
		}
		if slot < 0 { return error('too many clipboard offers') }
		mut offer := sessioncore.Clip{ owner_uid: peer.uid, owner_pid: peer.pid, kind: kind, sensitive: sensitive, len: data.len }
		for i, byte in data { offer.bytes[i] = byte }
		daemon.offers[slot] = offer
		if peer.pid == daemon.compositor {
			daemon.exchange.history_enabled = daemon.policy.clipboard_history
			daemon.exchange.copy(peer.uid, peer.pid, kind, data, sensitive)!
			return 'ok'
		}
		if daemon.queue_count == daemon.queue.len { return error('action queue full') }
		mut action := sessionipc.SessionMessage{ pid: peer.pid, count: 2 }
		action.fields[0].set('action')!
		action.fields[1].set('clipboard.offer')!
		daemon.queue[daemon.queue_count] = action
		daemon.queue_count++
		return 'ok'
	}
	if f.count > 24 { return error('too many session arguments') }
	// Text.str() borrows message storage. Keep it alive for this request and
	// copy queued records before releasing it on every return path.
	mut message := &sessionipc.SessionMessage{ pid: peer.pid, count: f.count }
	defer { unsafe { free(message) } }
	message.fields[0].set(f.values[0])!
	for i in 1 .. f.count { message.fields[i] = sessioncore.unfield(f.values[i])! }
	if operation == .ping { return 'ok' }
	if operation == .clipboard_read {
		token := u64(sessioncore.number(message.fields[1].str(), 1, 9223372036854775807)!)
		clip := &daemon.exchange.current
		daemon.exchange.consume(token, peer.uid, clip.owner_pid, peer.pid, clip.kind, sessionipc.monotonic_millis())!
		mut w := sessioncore.Writer{}
		w.add('data\t')
		w.number(int(clip.kind))
		w.add('\t')
		w.field(clip.data())
		return w.finish()
	}
	if operation == .clipboard_request {
		if daemon.queue_count == daemon.queue.len { return error('action queue full') }
		message.fields[0].set('action')!
		message.fields[1].set('clipboard.request')!
		message.count = 2
		daemon.queue[daemon.queue_count] = *message
		daemon.queue_count++
		return 'ok'
	}
	if operation == .exchange_take {
		for i in 0 .. sessioncore.grant_limit {
			g := daemon.exchange.grants[i]
			if g.target_pid == peer.pid && !g.consumed && g.expires > sessionipc.monotonic_millis() {
				mut w := sessioncore.Writer{}
				w.add('token\t')
				w.number(i64(g.token))
				return w.finish()
			}
		}
		return 'empty'
	}
	if operation == .policy { return daemon.policy.encode() }
	if operation == .time_offset {
		return (daemon.policy.timezone_minutes * 60).str()
	}
	if operation == .settings_status {
		return daemon.settings_status(message.fields[1].str())
	}
	if operation == .dialog_open {
		if !sessioncore.identifier(message.fields[1].str()) || !message.fields[4].str().starts_with('/') {
			return error('invalid dialog request')
		}
		kind := int(sessioncore.number(message.fields[2].str(), 0, 2)!)
		mut slot := -1
		for i in 0 .. daemon.dialogs.len {
			if daemon.dialogs[i].pid == peer.pid && daemon.dialogs[i].key == message.fields[1] {
				return error('dialog already open')
			}
			if daemon.dialogs[i].pid == 0 || daemon.dialogs[i].expires <= sessionipc.monotonic_millis() {
				slot = i
			}
		}
		if slot < 0 || daemon.queue_count == daemon.queue.len { return error('too many dialogs') }
		daemon.dialogs[slot] = SessionDialogTicket{ pid: peer.pid, key: message.fields[1], kind: kind, expires: sessionipc.monotonic_millis() + 300000 }
		for i := 6; i >= 1; i-- { message.fields[i + 1] = message.fields[i] }
		message.fields[0].set('action')!
		message.fields[1].set('dialog')!
		message.count = 8
		daemon.queue[daemon.queue_count] = *message
		daemon.queue_count++
		return 'ok'
	}
	if operation == .dialog_take {
		for i in 0 .. daemon.dialogs.len {
			ticket := daemon.dialogs[i]
			if ticket.pid != peer.pid || ticket.key != message.fields[1] { continue }
			if ticket.status == 0 && ticket.expires > sessionipc.monotonic_millis() {
				return 'pending'
			}
			daemon.dialogs[i] = SessionDialogTicket{}
			if ticket.status != 1 { return 'cancelled' }
			mut w := sessioncore.Writer{}
			w.add('selected\t')
			w.field(ticket.path.str())
			return w.finish()
		}
		return 'cancelled'
	}
	if operation == .services {
		mut w := sessioncore.Writer{}
		w.add('vinix-service-status\t1\n')
		for i in 0 .. daemon.supervisor.count {
			v := daemon.supervisor.services[i]
			w.add('service\t')
			w.number(i)
			w.add('\t')
			w.field(v.name.str())
			for value in [int(v.state), v.pid, v.exit_status, int(v.enabled), v.failures]! {
				w.add('\t')
				w.number(value)
			}
			w.add('\n')
		}
		return w.finish()
	}
	if operation == .attach {
		// Only an existing compositor may replace its own lease while alive.
		if daemon.compositor != 0 && daemon.compositor != peer.pid && C.kill(daemon.compositor, 0) == 0 {
			return error('compositor already attached')
		}
		daemon.compositor = peer.pid
		return 'ok'
	}
	if operation == .notify {
		owner := 'pid.${peer.pid}'
		defer { unsafe { owner.free() } }
		epoch, _ := sessionipc.desktop_realtime()
		_ = daemon.notifications.post(owner, message.fields[1].str(), message.fields[2].str(), message.fields[3].str(), unsafe { sessioncore.Urgency(sessioncore.number(message.fields[4].str(), 0, 2)!) }, int(sessioncore.number(message.fields[5].str(), -1, 100)!), message.fields[6].str(), epoch)!
		daemon.changed = true
		return 'ok'
	}
	if operation == .alarm {
		owner := 'pid.${peer.pid}'
		defer { unsafe { owner.free() } }
		delay := sessioncore.number(message.fields[3].str(), 1, 31536000)!
		repeat := int(sessioncore.number(message.fields[4].str(), 0, 31536000)!)
		epoch, _ := sessionipc.desktop_realtime()
		daemon.notifications.schedule(owner, message.fields[1].str(), message.fields[2].str(), epoch + delay, sessionipc.monotonic_millis() + delay * 1000, repeat)!
		daemon.changed = true
		return 'ok'
	}
	if operation == .alarm_cancel {
		owner := 'pid.${peer.pid}'
		defer { unsafe { owner.free() } }
		_ = daemon.notifications.cancel(owner, message.fields[1].str())
		daemon.changed = true
		return 'ok'
	}
	if operation == .action {
		if daemon.queue_count == daemon.queue.len { return error('session action queue full') }
		daemon.queue[daemon.queue_count] = *message
		daemon.queue_count++
		return 'ok'
	}
	if operation == .history {
		return daemon.notifications.encode()
	}
	if operation == .clipboard_promote {
		pid := int(sessioncore.number(message.fields[1].str(), 1, 2147483647)!)
		for i in 0 .. daemon.offers.len {
			c := &daemon.offers[i]
			if c.owner_pid == pid {
				daemon.exchange.history_enabled = daemon.policy.clipboard_history
				daemon.exchange.copy(peer.uid, pid, c.kind, c.data(), c.sensitive)!
				return 'ok'
			}
		}
		return error('clipboard offer expired')
	}
	if operation == .clipboard_snapshot {
		if daemon.exchange.current.len == 0 { return 'empty' }
		c := &daemon.exchange.current
		mut w := sessioncore.Writer{}
		w.add('data\t')
		w.number(int(c.kind))
		w.add('\t')
		w.field(c.data())
		w.add('\t')
		w.number(int(c.sensitive))
		w.add('\t')
		w.number(c.owner_pid)
		return w.finish()
	}
	if operation == .clipboard_clear {
		daemon.exchange.clear()
		daemon.offers = [8]sessioncore.Clip{}
		return 'ok'
	}
	if operation == .exchange_grant {
		if !daemon.policy.clipboard_apps || daemon.exchange.current.len == 0 {
			return error('clipboard access disabled')
		}
		pid := int(sessioncore.number(message.fields[1].str(), 1, 2147483647)!)
		token := session_random_token()!
		daemon.exchange.grant(token, peer.uid, daemon.exchange.current.owner_pid, pid, daemon.exchange.current.kind, sessionipc.monotonic_millis())!
		mut w := sessioncore.Writer{}
		w.add('token\t')
		w.number(i64(token))
		return w.finish()
	}
	if operation == .dialog_result {
		pid := int(sessioncore.number(message.fields[1].str(), 1, 2147483647)!)
		for i in 0 .. daemon.dialogs.len {
			if daemon.dialogs[i].pid != pid || daemon.dialogs[i].key != message.fields[2] {
				continue
			}
			path := message.fields[3].str()
			if path.len > 0 && !path.starts_with('/') {
				return error('dialog result is not absolute')
			}
			daemon.dialogs[i].path = message.fields[3]
			daemon.dialogs[i].status = if path.len > 0 { 1 } else { 2 }
			return 'ok'
		}
		return error('dialog request expired')
	}
	if operation == .settings_set {
		daemon.settings_apply(*message) or {
			daemon.settings_result.set(err.msg()) or {}
			return err
		}
		return 'ok'
	}
	if operation == .policy_set {
		new_policy := sessioncore.decode_policy(message.fields[1].str())!
		path := '${daemon.home}/.vinix-shell-policy'
		record := new_policy.encode()
		defer {
			unsafe {
				path.free()
				record.free()
			}
		}
		sessioncore.save(path, record)!
		daemon.policy = new_policy
		// Revocation removes issued grants as well as refusing new requests, so
		// re-enabling access cannot resurrect a token from the previous policy.
		if !new_policy.clipboard_apps {
			daemon.exchange.clear()
			daemon.offers = [8]sessioncore.Clip{}
		} else if !new_policy.clipboard_history {
			daemon.exchange.history = [sessioncore.clipboard_history_limit]sessioncore.Clip{}
			daemon.exchange.count = 0
		}
		daemon.exchange.history_enabled = new_policy.clipboard_history
		return 'ok'
	}
	if operation == .take {
		if daemon.queue_count == 0 { return 'empty' }
		a := unsafe { &daemon.queue[0] }
		mut w := &sessioncore.Writer{}
		defer { unsafe { free(w) } }
		w.add('action\t')
		w.number(a.pid)
		for i in 1 .. a.count {
			w.add('\t')
			w.field(a.fields[i].str())
		}
		// Encode while the first slot is still intact. The reply owns its bytes
		// before shifting the queue can overwrite the borrowed record.
		reply := w.finish()
		for i in 1 .. daemon.queue_count { daemon.queue[i - 1] = daemon.queue[i] }
		daemon.queue_count--
		return reply
	}
	if operation == .quiet {
		daemon.notifications.mode = unsafe { sessioncore.Focus(sessioncore.number(message.fields[1].str(), 0, 2)!) }
		duration := sessioncore.number(message.fields[2].str(), 0, 86400)!
		epoch, _ := sessionipc.desktop_realtime()
		daemon.notifications.focus_until = if duration == 0 { i64(0) } else { epoch + duration }
		daemon.changed = true
		return 'ok'
	}
	if operation == .dismiss {
		_ = daemon.notifications.dismiss(sessioncore.number(message.fields[1].str(), 1, 9223372036854775806)!)
		daemon.changed = true
		return 'ok'
	}
	if operation == .alarm_remove {
		i := int(sessioncore.number(message.fields[1].str(), 0, daemon.notifications.alarm_count - 1)!)
		daemon.notifications.alarms[i].active = false
		daemon.changed = true
		return 'ok'
	}
	if operation == .service_import {
		if daemon.stop { return error('session is shutting down') }
		name := message.fields[1].str()
		path := message.fields[2].str()
		if !path.starts_with('/') { return error('unit path must be absolute') }
		unit := sessioncore.load(path, 64 * 1024)!
		defer { unsafe { unit.free() } }
		service := sessioncore.import_linux_service(name, unit,
			sessioncore.number(message.fields[3].str(), 0, 1)! != 0)!
		if daemon.supervisor.count == sessioncore.max_services {
			return error('service registry full')
		}
		for i in 0 .. daemon.supervisor.count {
			if daemon.supervisor.services[i].name.str() == name {
				return error('service already installed')
			}
		}
		// Publish the candidate before making it eligible for process launch.
		mut candidate := daemon.supervisor
		candidate.services[candidate.count] = service
		candidate.count++
		candidate.validate()!
		record := candidate.encode()
		config := '${daemon.home}/.vinix-services'
		defer { unsafe {
			record.free()
			config.free()
		}
		 }
		sessioncore.save(config, record)!
		daemon.supervisor = candidate
		return 'ok'
	}
	if operation == .service_remove {
		mut index := -1
		for i in 0 .. daemon.supervisor.count {
			if daemon.supervisor.services[i].name.str() == message.fields[1].str() {
				index = i
				break
			}
		}
		if index < 0 { return error('unknown service') }
		service := daemon.supervisor.services[index]
		if service.enabled || service.pid != 0 || service.state !in [.stopped, .failed] {
			return error('disable and stop the service before removal')
		}
		for i in 0 .. daemon.supervisor.count {
			if daemon.supervisor.services[i].dependencies & (u32(1) << index) != 0 {
				return error('service has installed dependents')
			}
		}
		mut candidate := daemon.supervisor
		for i in index + 1 .. candidate.count { candidate.services[i - 1] = candidate.services[i] }
		candidate.count--
		candidate.services[candidate.count] = sessioncore.Service{}
		for i in 0 .. candidate.count {
			mask := candidate.services[i].dependencies
			lower := (u32(1) << index) - 1
			candidate.services[i].dependencies = (mask & lower) | ((mask >> 1) & ~lower)
		}
		candidate.validate()!
		record := candidate.encode()
		config := '${daemon.home}/.vinix-services'
		defer { unsafe {
			record.free()
			config.free()
		}
		 }
		sessioncore.save(config, record)!
		daemon.supervisor = candidate
		for i in index + 1 .. daemon.supervisor.count + 1 {
			daemon.service_leases[i - 1] = daemon.service_leases[i]
		}
		daemon.service_leases[daemon.supervisor.count] = 0
		return 'ok'
	}
	if operation == .service_enable {
		index := int(sessioncore.number(message.fields[1].str(), 0, daemon.supervisor.count - 1)!)
		previous := daemon.supervisor.services[index].enabled
		daemon.supervisor.enable(index, sessioncore.number(message.fields[2].str(), 0, 1)! != 0)!
		daemon.save_services() or {
			daemon.supervisor.enable(index, previous) or {}
			return err
		}
		return 'ok'
	}
	if operation == .shutdown {
		daemon.stop = true
		daemon.supervisor.stopping = true
		daemon.stop_deadline = sessionipc.monotonic_millis() + 30000
		return 'ok'
	}
	return error('unknown session operation')
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
			daemon.save() or { eprintln('vinix-session: ${err}') }
		}
		if daemon.stop && daemon.operation_pid == 0 && daemon.supervisor.finished() {
			daemon.save() or { eprintln('vinix-session: ${err}') }
			return
		}
		mut readiness := C.pollfd{ fd: fd, events: C.POLLIN }
		if C.poll(&readiness, 1, 100) <= 0 { continue }
		client := C.accept(fd, unsafe { nil }, unsafe { nil })
		if client < 0 { continue }
		sessionipc.desktop_set_cloexec(client, true)
		sessionipc.desktop_set_nonblocking(client, true)
		peer := sessionipc.session_peer(client) or {
			sessionipc.desktop_close(client)
			continue
		}
		request := sessionipc.session_receive(client) or {
			sessionipc.desktop_close(client)
			continue
		}
		mut reply := daemon.handle(peer, request) or {
			eprintln('vinix-session: request rejected: ${err}')
			'error\tdenied'
		}
		// Alarm registration/cancellation is durable before acknowledging it.
		if daemon.changed {
			daemon.save() or {
				eprintln('vinix-session: state publication failed: ${err}')
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
		eprintln('vinix-session: refusing invalid service configuration: ${err}')
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
