// SPDX-License-Identifier: GPL-2.0-or-later
module sessiondaemon

import desktop.sessioncore
import desktop.sessionipc

struct SessionRequest {
	peer       sessionipc.SessionCredentials
	fields     sessioncore.Fields
	compositor bool
mut:
	message sessionipc.SessionMessage
}

type SessionHandler = fn (mut SessionDaemon, mut SessionRequest) !string

struct SessionRoute {
	operation   sessioncore.SessionOperation
	handler     SessionHandler @[required]
	raw_payload bool
}

// Private, immutable function mapping, indexed by the authorized operation.
// Requests cannot retrieve handlers or change this registry.
const session_routes = [
	SessionRoute{.invalid, session_handle_invalid, false},
	SessionRoute{.ping, session_handle_ping, false},
	SessionRoute{.attach, session_handle_attach, false},
	SessionRoute{.clipboard_offer, session_handle_clipboard_offer, true},
	SessionRoute{.clipboard_read, session_handle_clipboard_read, false},
	SessionRoute{.clipboard_request, session_handle_clipboard_request, false},
	SessionRoute{.exchange_take, session_handle_exchange_take, false},
	SessionRoute{.policy, session_handle_policy, false},
	SessionRoute{.time_offset, session_handle_time_offset, false},
	SessionRoute{.settings_status, session_handle_settings_status, false},
	SessionRoute{.dialog_open, session_handle_dialog_open, false},
	SessionRoute{.dialog_take, session_handle_dialog_take, false},
	SessionRoute{.services, session_handle_services, false},
	SessionRoute{.notify, session_handle_notify, false},
	SessionRoute{.alarm, session_handle_alarm, false},
	SessionRoute{.alarm_cancel, session_handle_alarm_cancel, false},
	SessionRoute{.action, session_handle_action, false},
	SessionRoute{.history, session_handle_history, false},
	SessionRoute{.clipboard_promote, session_handle_clipboard_promote, false},
	SessionRoute{.clipboard_snapshot, session_handle_clipboard_snapshot, false},
	SessionRoute{.clipboard_clear, session_handle_clipboard_clear, false},
	SessionRoute{.exchange_grant, session_handle_exchange_grant, false},
	SessionRoute{.dialog_result, session_handle_dialog_result, false},
	SessionRoute{.settings_set, session_handle_settings_set, false},
	SessionRoute{.policy_set, session_handle_policy_set, false},
	SessionRoute{.take, session_handle_take, false},
	SessionRoute{.quiet, session_handle_quiet, false},
	SessionRoute{.dismiss, session_handle_dismiss, false},
	SessionRoute{.alarm_remove, session_handle_alarm_remove, false},
	SessionRoute{.service_import, session_handle_service_import, false},
	SessionRoute{.service_remove, session_handle_service_remove, false},
	SessionRoute{.service_enable, session_handle_service_enable, false},
	SessionRoute{.shutdown, session_handle_shutdown, false},
]!

fn session_handle_invalid(mut _ SessionDaemon, mut _ SessionRequest) !string {
	return error_sentinel
}

fn session_handle_ping(mut _ SessionDaemon, mut _ SessionRequest) !string {
	return 'ok'
}

fn session_handle_attach(mut _ SessionDaemon, mut _ SessionRequest) !string {
	// Authorization already requires the inherited compositor connection.
	return 'ok'
}

fn session_handle_clipboard_offer(mut daemon SessionDaemon, mut request SessionRequest) !string {
	peer := request.peer
	f := unsafe { &request.fields }
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
	if request.compositor {
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

fn session_handle_clipboard_read(mut daemon SessionDaemon, mut request SessionRequest) !string {
	peer := request.peer
	mut message := unsafe { &request.message }
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

fn session_handle_clipboard_request(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
	if daemon.queue_count == daemon.queue.len { return error('action queue full') }
	message.fields[0].set('action')!
	message.fields[1].set('clipboard.request')!
	message.count = 2
	daemon.queue[daemon.queue_count] = *message
	daemon.queue_count++
	return 'ok'
}

fn session_handle_exchange_take(mut daemon SessionDaemon, mut request SessionRequest) !string {
	peer := request.peer
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

fn session_handle_policy(mut daemon SessionDaemon, mut _ SessionRequest) !string {
	return daemon.policy.encode()
}

fn session_handle_time_offset(mut daemon SessionDaemon, mut _ SessionRequest) !string {
	return (daemon.policy.timezone_minutes * 60).str()
}

fn session_handle_settings_status(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
	return daemon.settings_status(message.fields[1].str())
}

fn session_handle_dialog_open(mut daemon SessionDaemon, mut request SessionRequest) !string {
	peer := request.peer
	mut message := unsafe { &request.message }
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

fn session_handle_dialog_take(mut daemon SessionDaemon, mut request SessionRequest) !string {
	peer := request.peer
	mut message := unsafe { &request.message }
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

fn session_handle_services(mut daemon SessionDaemon, mut _ SessionRequest) !string {
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

fn session_handle_notify(mut daemon SessionDaemon, mut request SessionRequest) !string {
	peer := request.peer
	mut message := unsafe { &request.message }
	owner := 'pid.${peer.pid}'
	defer { unsafe { owner.free() } }
	epoch, _ := sessionipc.desktop_realtime()
	_ = daemon.notifications.post(owner, message.fields[1].str(), message.fields[2].str(), message.fields[3].str(), unsafe { sessioncore.Urgency(sessioncore.number(message.fields[4].str(), 0, 2)!) }, int(sessioncore.number(message.fields[5].str(), -1, 100)!), message.fields[6].str(), epoch)!
	daemon.changed = true
	return 'ok'
}

fn session_handle_alarm(mut daemon SessionDaemon, mut request SessionRequest) !string {
	peer := request.peer
	mut message := unsafe { &request.message }
	owner := 'pid.${peer.pid}'
	defer { unsafe { owner.free() } }
	delay := sessioncore.number(message.fields[3].str(), 1, 31536000)!
	repeat := int(sessioncore.number(message.fields[4].str(), 0, 31536000)!)
	epoch, _ := sessionipc.desktop_realtime()
	daemon.notifications.schedule(owner, message.fields[1].str(), message.fields[2].str(), epoch + delay, sessionipc.monotonic_millis() + delay * 1000, repeat)!
	daemon.changed = true
	return 'ok'
}

fn session_handle_alarm_cancel(mut daemon SessionDaemon, mut request SessionRequest) !string {
	peer := request.peer
	mut message := unsafe { &request.message }
	owner := 'pid.${peer.pid}'
	defer { unsafe { owner.free() } }
	_ = daemon.notifications.cancel(owner, message.fields[1].str())
	daemon.changed = true
	return 'ok'
}

fn session_handle_action(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
	if daemon.queue_count == daemon.queue.len { return error('session action queue full') }
	daemon.queue[daemon.queue_count] = *message
	daemon.queue_count++
	return 'ok'
}

fn session_handle_history(mut daemon SessionDaemon, mut _ SessionRequest) !string {
	return daemon.notifications.encode()
}

fn session_handle_clipboard_promote(mut daemon SessionDaemon, mut request SessionRequest) !string {
	peer := request.peer
	mut message := unsafe { &request.message }
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

fn session_handle_clipboard_snapshot(mut daemon SessionDaemon, mut _ SessionRequest) !string {
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

fn session_handle_clipboard_clear(mut daemon SessionDaemon, mut _ SessionRequest) !string {
	daemon.exchange.clear()
	daemon.offers = [8]sessioncore.Clip{}
	return 'ok'
}

fn session_handle_exchange_grant(mut daemon SessionDaemon, mut request SessionRequest) !string {
	peer := request.peer
	mut message := unsafe { &request.message }
	if daemon.exchange.current.len == 0 {
		return error('clipboard is empty')
	}
	pid := int(sessioncore.number(message.fields[1].str(), 1, 2147483647)!)
	token := session_random_token()!
	daemon.exchange.grant(token, peer.uid, daemon.exchange.current.owner_pid, pid, daemon.exchange.current.kind, sessionipc.monotonic_millis())!
	mut w := sessioncore.Writer{}
	w.add('token\t')
	w.number(i64(token))
	return w.finish()
}

fn session_handle_dialog_result(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
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

fn session_handle_settings_set(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
	daemon.settings_apply(*message) or {
		daemon.settings_result.set(err.msg()) or {}
		return err
	}
	return 'ok'
}

fn session_handle_policy_set(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
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

fn session_handle_take(mut daemon SessionDaemon, mut _ SessionRequest) !string {
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

fn session_handle_quiet(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
	daemon.notifications.mode = unsafe { sessioncore.Focus(sessioncore.number(message.fields[1].str(), 0, 2)!) }
	duration := sessioncore.number(message.fields[2].str(), 0, 86400)!
	epoch, _ := sessionipc.desktop_realtime()
	daemon.notifications.focus_until = if duration == 0 { i64(0) } else { epoch + duration }
	daemon.changed = true
	return 'ok'
}

fn session_handle_dismiss(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
	_ = daemon.notifications.dismiss(sessioncore.number(message.fields[1].str(), 1, 9223372036854775806)!)
	daemon.changed = true
	return 'ok'
}

fn session_handle_alarm_remove(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
	i := int(sessioncore.number(message.fields[1].str(), 0, daemon.notifications.alarm_count - 1)!)
	daemon.notifications.alarms[i].active = false
	daemon.changed = true
	return 'ok'
}

fn session_handle_service_import(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
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
	defer {
		unsafe {
			record.free()
			config.free()
		}
	}
	sessioncore.save(config, record)!
	daemon.supervisor = candidate
	return 'ok'
}

fn session_handle_service_remove(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
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
	defer {
		unsafe {
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

fn session_handle_service_enable(mut daemon SessionDaemon, mut request SessionRequest) !string {
	mut message := unsafe { &request.message }
	index := int(sessioncore.number(message.fields[1].str(), 0, daemon.supervisor.count - 1)!)
	previous := daemon.supervisor.services[index].enabled
	daemon.supervisor.enable(index, sessioncore.number(message.fields[2].str(), 0, 1)! != 0)!
	daemon.save_services() or {
		daemon.supervisor.enable(index, previous) or {}
		return err
	}
	return 'ok'
}

fn session_handle_shutdown(mut daemon SessionDaemon, mut _ SessionRequest) !string {
	daemon.stop = true
	daemon.supervisor.stopping = true
	daemon.stop_deadline = sessionipc.monotonic_millis() + 30000
	return 'ok'
}
