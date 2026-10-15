// SPDX-License-Identifier: GPL-2.0-or-later
// User session broker. A separate process owns alarms, notices and services;
// clients authenticate with kernel peer credentials, never payload identities.
module main

import desktop.sessioncore
import os
import net as _
import time

#include <sys/file.h>
#include <sys/socket.h>
#include <sys/un.h>

$if linux {
	#include <sys/prctl.h>
}

fn C.flock(int, int) int
fn C.execv(&char, &&char) int
fn C.getpeereid(int, &u32, &u32) int
fn C.prctl(int, usize, usize, usize, usize) int
// socketpair writes two C int slots; V's int can be wider on this backend.
fn C.socketpair(i32, i32, i32, &i32) i32

__global volatile session_daemon_stop bool
__global session_child_pid int

fn session_stop_signal(_ os.Signal) {
	unsafe { session_daemon_stop = true }
}

struct SessionAddress {
mut:
	prefix [2]u8
	path   [100]u8
}

struct SessionCredentials {
	pid i32
	uid u32
	gid u32
}

struct SessionMessage {
mut:
	pid    int
	fields [24]sessioncore.Text
	count  int
}

struct SessionDaemon {
mut:
	notifications      sessioncore.Notifications
	supervisor         sessioncore.Supervisor
	queue              [64]SessionMessage
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

fn session_runtime_directory() string {
	base := os.getenv_opt('VINIX_SESSION_RUNTIME') or { '/run' }
	defer { unsafe { base.free() } }
	mut writer := &sessioncore.Writer{}
	defer { unsafe { free(writer) } }
	writer.add(base)
	writer.add('/vinix-session.')
	writer.number(C.getuid())
	return writer.finish()
}

fn session_address(path string) ?SessionAddress {
	mut addr := SessionAddress{}
	if path.len >= addr.path.len { return none }
	$if macos {
		addr.prefix[0] = u8(sizeof(SessionAddress))
		addr.prefix[1] = u8(C.AF_UNIX)
	} $else {
		addr.prefix[0] = u8(C.AF_UNIX)
		addr.prefix[1] = u8(C.AF_UNIX >> 8)
	}
	for i, byte in path { addr.path[i] = byte }
	return addr
}

fn session_private_directory(directory string) bool {
	if C.mkdir(&char(directory.str), u32(0o700)) != 0 && C.errno != C.EEXIST { return false }
	mut info := &C.stat{}
	defer { unsafe { free(info) } }
	return unsafe { C.lstat(&char(directory.str), info) } == 0 && u32(info.st_mode) & C.S_IFMT == C.S_IFDIR
		&& u32(info.st_uid) == C.getuid() && u32(info.st_mode) & 0o077 == 0
}

fn session_connect() ?int {
	directory := session_runtime_directory()
	path := '${directory}/broker'
	defer {
		unsafe {
			directory.free()
			path.free()
		}
	}
	if !session_private_directory(directory) { return none }
	addr := session_address(path) or { return none }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return none }
	desktop_set_cloexec(fd, true)
	desktop_set_nonblocking(fd, true)
	connected := C.connect(fd, voidptr(&addr), u32(sizeof(SessionAddress)))
	if connected != 0 && C.errno != C.EINPROGRESS {
		desktop_close(fd)
		return none
	}
	if connected != 0 {
		mut readiness := C.pollfd{ fd: fd, events: C.POLLOUT }
		if C.poll(&readiness, 1, 100) <= 0 {
			desktop_close(fd)
			return none
		}
		mut error_code := 0
		mut length := u32(sizeof(int))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_ERROR, &error_code, &length) != 0 || error_code != 0 {
			desktop_close(fd)
			return none
		}
	}
	return fd
}

fn session_send(fd int, data string) bool {
	mut offset := 0
	deadline := monotonic_millis() + 100
	for offset < data.len {
		mut readiness := C.pollfd{ fd: fd, events: C.POLLOUT }
		remaining := deadline - monotonic_millis()
		if remaining <= 0 || C.poll(&readiness, 1, int(remaining)) <= 0 { return false }
		$if macos {
			signal_option := i32(1)
			C.setsockopt(fd, C.SOL_SOCKET, C.SO_NOSIGPIPE, &signal_option, u32(sizeof(i32)))
		}
		flags := $if macos { 0 } $else { C.MSG_NOSIGNAL }
		n := unsafe { C.send(fd, &data.str[offset], usize(data.len - offset), flags) }
		if n <= 0 { return false }
		offset += n
	}
	return true
}

fn session_receive(fd int) !string {
	return session_receive_timeout(fd, 100)
}

fn session_receive_timeout(fd int, timeout int) !string {
	mut header := [4]u8{}
	session_read_exact(fd, &header[0], 4, timeout)!
	length := int(u32(header[0]) | u32(header[1]) << 8 | u32(header[2]) << 16 | u32(header[3]) << 24)
	if length < 1 || length > 256 * 1024 { return error('invalid session message length') }
	mut bytes := []u8{len: length}
	defer { unsafe { bytes.free() } }
	session_read_exact(fd, bytes.data, length, timeout)!
	return unsafe { tos(bytes.data, length).clone() }
}

fn session_read_exact(fd int, bytes &u8, length int, timeout int) ! {
	mut count := 0
	deadline := monotonic_millis() + timeout
	for count < length {
		mut readiness := C.pollfd{ fd: fd, events: C.POLLIN }
		remaining := deadline - monotonic_millis()
		if remaining <= 0 || C.poll(&readiness, 1, int(remaining)) <= 0 {
			return error('session request timed out')
		}
		n := unsafe { C.recv(fd, &bytes[count], usize(length - count), 0) }
		if n <= 0 { return error('session connection closed') }
		count += n
	}
}

fn session_send_message(fd int, data string) bool {
	if data.len < 1 || data.len > 256 * 1024 { return false }
	length := u32(data.len)
	header := [u8(length), u8(length >> 8), u8(length >> 16), u8(length >> 24)]!
	return session_send(fd, unsafe { tos(&header[0], 4) }) && session_send(fd, data)
}

fn session_call(command string, arguments []string) !string {
	fd := session_connect() or { return error('session services unavailable') }
	defer { desktop_close(fd) }
	mut writer := sessioncore.Writer{}
	writer.add(command)
	for arg in arguments {
		writer.add('\t')
		writer.field(arg)
	}
	request := writer.finish()
	defer { unsafe { request.free() } }
	if !session_send_message(fd, request) { return error('could not send session request') }
	reply := session_receive_timeout(fd, if command in ['quiet', 'alarm', 'alarm.cancel', 'settings.set',
		'policy.set', 'service.enable', 'service.import', 'service.remove', 'dismiss'] {
		2000
	} else {
		300
	})!
	if reply.starts_with('error\t') {
		unsafe { reply.free() }
		return error('session request rejected')
	}
	return reply
}

fn session_call_ok(command string, arguments []string) bool {
	reply := session_call(command, arguments) or { return false }
	defer { unsafe { reply.free() } }
	return reply == 'ok' || reply.starts_with('ok\t')
}

fn session_start(home string) bool {
	if session_call_ok('ping', []) { return true }
	if session_child_pid > 0 {
		mut status := 0
		if C.waitpid(session_child_pid, &status, C.WNOHANG) == 0 { return true }
		session_child_pid = 0
	}
	executable := os.executable()
	home_arg := '--session-home=${home}'
	owner_arg := '--session-owner=${C.getpid()}'
	defer { unsafe { owner_arg.free() } }
	argv := [&char(executable.str), c'--session-services', &char(home_arg.str), &char(owner_arg.str),
		&char(unsafe { nil })]!
	defer {
		unsafe {
			executable.free()
			home_arg.free()
		}
	}
	pid := C.fork()
	if pid < 0 { return false }
	if pid == 0 {
		C.setsid()
		for fd in 3 .. 4096 { C.close(fd) }
		C.execv(&char(executable.str), &argv[0])
		C._exit(127)
	}
	// No startup wait on the compositor's input thread. Later polls connect.
	session_child_pid = pid
	return true
}

fn session_peer(fd int) ?SessionCredentials {
	$if macos {
		mut uid := u32(0)
		mut gid := u32(0)
		if C.getpeereid(fd, &uid, &gid) != 0 || uid != C.getuid() { return none }
		mut pid := 0
		mut length := u32(sizeof(int))
		if C.getsockopt(fd, C.SOL_LOCAL, C.LOCAL_PEERPID, &pid, &length) != 0 { return none }
		return SessionCredentials{ pid: pid, uid: uid, gid: gid }
	} $else {
		mut peer := SessionCredentials{}
		mut length := u32(sizeof(SessionCredentials))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_PEERCRED, &peer, &length) != 0 || length != sizeof(SessionCredentials) || peer.uid != C.getuid() {
			return none
		}
		return peer
	}
}

fn (mut daemon SessionDaemon) handle(peer SessionCredentials, request string) !string {
	f := sessioncore.fields(request)!
	operation := sessioncore.authorize_session(f.values[0], f.count, sessioncore.SessionCaller{
		pid: peer.pid
		uid: peer.uid
		session_uid: C.getuid()
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
		mut action := SessionMessage{ pid: peer.pid, count: 2 }
		action.fields[0].set('action')!
		action.fields[1].set('clipboard.offer')!
		daemon.queue[daemon.queue_count] = action
		daemon.queue_count++
		return 'ok'
	}
	if f.count > 24 { return error('too many session arguments') }
	// Text.str() borrows message storage. Keep it alive for this request and
	// copy queued records before releasing it on every return path.
	mut message := &SessionMessage{ pid: peer.pid, count: f.count }
	defer { unsafe { free(message) } }
	message.fields[0].set(f.values[0])!
	for i in 1 .. f.count { message.fields[i] = sessioncore.unfield(f.values[i])! }
	if operation == .ping { return 'ok' }
	if operation == .clipboard_read {
		token := u64(sessioncore.number(message.fields[1].str(), 1, 9223372036854775807)!)
		clip := &daemon.exchange.current
		daemon.exchange.consume(token, peer.uid, clip.owner_pid, peer.pid, clip.kind, monotonic_millis())!
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
			if g.target_pid == peer.pid && !g.consumed && g.expires > monotonic_millis() {
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
			if daemon.dialogs[i].pid == 0 || daemon.dialogs[i].expires <= monotonic_millis() {
				slot = i
			}
		}
		if slot < 0 || daemon.queue_count == daemon.queue.len { return error('too many dialogs') }
		daemon.dialogs[slot] = SessionDialogTicket{ pid: peer.pid, key: message.fields[1], kind: kind, expires: monotonic_millis() + 300000 }
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
			if ticket.status == 0 && ticket.expires > monotonic_millis() { return 'pending' }
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
		epoch, _ := desktop_realtime()
		_ = daemon.notifications.post(owner, message.fields[1].str(), message.fields[2].str(), message.fields[3].str(), unsafe { sessioncore.Urgency(sessioncore.number(message.fields[4].str(), 0, 2)!) }, int(sessioncore.number(message.fields[5].str(), -1, 100)!), message.fields[6].str(), epoch)!
		daemon.changed = true
		return 'ok'
	}
	if operation == .alarm {
		owner := 'pid.${peer.pid}'
		defer { unsafe { owner.free() } }
		delay := sessioncore.number(message.fields[3].str(), 1, 31536000)!
		repeat := int(sessioncore.number(message.fields[4].str(), 0, 31536000)!)
		epoch, _ := desktop_realtime()
		daemon.notifications.schedule(owner, message.fields[1].str(), message.fields[2].str(), epoch + delay, monotonic_millis() + delay * 1000, repeat)!
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
		daemon.exchange.grant(token, peer.uid, daemon.exchange.current.owner_pid, pid, daemon.exchange.current.kind, monotonic_millis())!
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
		epoch, _ := desktop_realtime()
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
		if daemon.supervisor.count == sessioncore.max_services { return error('service registry full') }
		for i in 0 .. daemon.supervisor.count {
			if daemon.supervisor.services[i].name.str() == name { return error('service already installed') }
		}
		// Publish the candidate before making it eligible for process launch.
		mut candidate := daemon.supervisor
		candidate.services[candidate.count] = service
		candidate.count++
		candidate.validate()!
		record := candidate.encode()
		config := '${daemon.home}/.vinix-services'
		defer { unsafe { record.free(); config.free() } }
		sessioncore.save(config, record)!
		daemon.supervisor = candidate
		return 'ok'
	}
	if operation == .service_remove {
		mut index := -1
		for i in 0 .. daemon.supervisor.count {
			if daemon.supervisor.services[i].name.str() == message.fields[1].str() { index = i; break }
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
		defer { unsafe { record.free(); config.free() } }
		sessioncore.save(config, record)!
		daemon.supervisor = candidate
		for i in index + 1 .. daemon.supervisor.count + 1 { daemon.service_leases[i - 1] = daemon.service_leases[i] }
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
		daemon.stop_deadline = monotonic_millis() + 30000
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

fn run_session_services(home string, owner int) {
	desktop_ignore_broken_pipe()
	directory := session_runtime_directory()
	defer { unsafe { directory.free() } }
	if !session_private_directory(directory) {
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
	defer { desktop_close(lease_fd) }
	if C.flock(lease_fd, C.LOCK_EX | C.LOCK_NB) != 0 { return }
	addr := session_address(path) or { return }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return }
	defer {
		desktop_close(fd)
		C.unlink(&char(path.str))
	}
	desktop_set_cloexec(fd, true)
	desktop_set_nonblocking(fd, true)
	C.unlink(&char(path.str))
	if C.bind(fd, voidptr(&addr), u32(sizeof(SessionAddress))) != 0 || C.listen(fd, 16) != 0 {
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
			if !daemon.stop { daemon.stop_deadline = monotonic_millis() + 30000 }
			daemon.stop = true
			daemon.supervisor.stopping = true
		}
		epoch, _ := desktop_realtime()
		if daemon.notifications.tick(epoch, monotonic_millis()) { daemon.changed = true }
		daemon.services_tick()
		if daemon.changed && monotonic_millis() - daemon.last_save >= 1000 {
			daemon.last_save = monotonic_millis()
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
		desktop_set_cloexec(client, true)
		desktop_set_nonblocking(client, true)
		peer := session_peer(client) or {
			desktop_close(client)
			continue
		}
		request := session_receive(client) or {
			desktop_close(client)
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
		_ = session_send_message(client, reply)
		desktop_close(client)
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
	now := monotonic_millis()
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
			status = session_service_status(daemon.operation_lease, status)
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
			status = session_service_status(daemon.service_leases[i], status)
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
				process := session_spawn_service(service, daemon.home)
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
			executable := os.executable()
			defer { unsafe { executable.free() } }
			mut service := sessioncore.Service{ name: sessioncore.text('clock-sync') or { return }, executable: sessioncore.text(executable) or { return }, system: true, restart: .on_failure }
			service.arguments[0].set('--time-service') or { return }
			service.argument_count = 1
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

struct SessionServiceProcess {
	pid   int
	lease int
}

fn session_service_status(lease int, fallback int) int {
	if lease <= 0 { return fallback }
	defer { desktop_close(lease) }
	mut status := fallback
	if C.read(lease, &status, sizeof(int)) != sizeof(int) { return fallback }
	return status
}

fn session_spawn_service(service sessioncore.Service, home string) SessionServiceProcess {
	mut argv := unsafe { [18]&char{} }
	argv[0] = &char(service.executable.str().str)
	for i in 0 .. service.argument_count { argv[i + 1] = &char(service.arguments[i].str().str) }
	log_directory := '${home}/.vinix-service-logs'
	if !session_private_directory(log_directory) {
		unsafe { log_directory.free() }
		return SessionServiceProcess{-1, -1}
	}
	log_path := '${log_directory}/${service.name.str()}.log'
	defer {
		unsafe {
			log_path.free()
			log_directory.free()
		}
	}
	log := C.open(&char(log_path.str), C.O_WRONLY | C.O_CREAT | C.O_APPEND | C.O_NOFOLLOW | C.O_CLOEXEC, u32(0o600))
	if log < 0 { return SessionServiceProcess{-1, -1} }
	defer { desktop_close(log) }
	mut lease := [i32(-1), i32(-1)]!
	if C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &lease[0]) != 0 {
		return SessionServiceProcess{-1, -1}
	}
	desktop_set_cloexec(lease[0], true)
	desktop_set_cloexec(lease[1], true)
	desktop_set_nonblocking(lease[0], true)
	desktop_set_nonblocking(lease[1], true)
	pid := C.fork()
	if pid == 0 {
		if C.setsid() < 0 { C._exit(127) }
		input := C.open(c'/dev/null', C.O_RDONLY, 0)
		if input >= 0 { C.dup2(input, 0) }
		C.dup2(log, 1)
		C.dup2(log, 2)
		for fd in 3 .. 4096 { if fd != lease[1] { C.close(fd) } }
		guardian := C.getpid()
		child := C.fork()
		if child == 0 {
			$if linux {
				if C.prctl(1, usize(C.SIGKILL), 0, 0, 0) != 0 || C.getppid() != guardian {
					C._exit(127)
				}
			}
			C.close(lease[1])
			C.execv(argv[0], &argv[0])
			C._exit(127)
		}
		if child < 0 { C._exit(127) }
		for {
			mut status := 0
			if C.waitpid(child, &status, C.WNOHANG) == child {
				C.write(lease[1], &status, sizeof(int))
				C.kill(-guardian, C.SIGKILL)
				C._exit(0)
			}
			mut readiness := C.pollfd{ fd: lease[1], events: C.POLLIN | C.POLLHUP }
			if C.poll(&readiness, 1, 100) > 0 {
				mut byte := u8(0)
				if C.read(lease[1], &byte, 1) == 0 {
					C.kill(-guardian, C.SIGKILL)
					C._exit(0)
				}
			}
		}
	}
	C.close(lease[1])
	if pid < 0 {
		C.close(lease[0])
		return SessionServiceProcess{-1, -1}
	}
	return SessionServiceProcess{pid, lease[0]}
}
