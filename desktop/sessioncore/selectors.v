// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

// SBP's locked domains and deny filters, specialized for the session boundary.
// The registry is constant: requests cannot register, replace or retrieve a
// handler. Wire names stay compatible; canonical selectors are trusted labels.
pub enum SessionOperation {
	invalid
	ping
	attach
	clipboard_offer
	clipboard_read
	clipboard_request
	exchange_take
	policy
	time_offset
	settings_status
	dialog_open
	dialog_take
	services
	notify
	alarm
	alarm_cancel
	action
	history
	clipboard_promote
	clipboard_snapshot
	clipboard_clear
	exchange_grant
	dialog_result
	settings_set
	policy_set
	take
	quiet
	dismiss
	alarm_remove
	service_import
	service_remove
	service_enable
	shutdown
}

enum SessionDomain {
	compositor
	application
}

struct SessionRule {
	operation  SessionOperation
	command    string
	selector   string
	domain     SessionDomain
	min_fields int
	max_fields int
}

// Permission errors borrow the immutable rule itself. Returning error() or
// interpolating a label here would retain allocations under -gc none on every
// refused request. No caller may free these shared error values.
fn (rule &SessionRule) msg() string { return rule.selector }

fn (rule &SessionRule) code() int { return 1 }

struct SessionFilterError {
	message string
}

fn (e &SessionFilterError) msg() string { return e.message }

fn (e &SessionFilterError) code() int { return 1 }

const session_invalid_caller = IError(&SessionFilterError{'invalid session caller'})
const session_invalid_arguments = IError(&SessionFilterError{'invalid session argument count'})
const session_unknown_operation = IError(&SessionFilterError{'unknown session operation'})

const session_rules = [
	SessionRule{.ping, 'ping', 'application/session/ping', .application, 1, 1},
	SessionRule{.attach, 'attach', 'application/session/attach', .application, 1, 1},
	SessionRule{.clipboard_offer, 'clipboard.offer', 'application/clipboard/offer', .application, 4, 4},
	SessionRule{.clipboard_read, 'clipboard.read', 'application/clipboard/read', .application, 2, 2},
	SessionRule{.clipboard_request, 'clipboard.request', 'application/clipboard/request', .application, 1, 1},
	SessionRule{.exchange_take, 'exchange.take', 'application/exchange/take', .application, 1, 1},
	SessionRule{.policy, 'policy', 'application/policy/read', .application, 1, 1},
	SessionRule{.time_offset, 'time.offset', 'application/time/offset', .application, 1, 1},
	SessionRule{.settings_status, 'settings.status', 'application/settings/status', .application, 2, 2},
	SessionRule{.dialog_open, 'dialog.open', 'application/dialog/open', .application, 7, 7},
	SessionRule{.dialog_take, 'dialog.take', 'application/dialog/take', .application, 2, 2},
	SessionRule{.services, 'services', 'application/services/list', .application, 1, 1},
	SessionRule{.notify, 'notify', 'application/notifications/post', .application, 7, 7},
	SessionRule{.alarm, 'alarm', 'application/alarms/schedule', .application, 5, 5},
	SessionRule{.alarm_cancel, 'alarm.cancel', 'application/alarms/cancel', .application, 2, 2},
	SessionRule{.action, 'action', 'application/actions/enqueue', .application, 2, 24},
	SessionRule{.history, 'history', 'compositor/notifications/history', .compositor, 1, 1},
	SessionRule{.clipboard_promote, 'clipboard.promote', 'compositor/clipboard/promote', .compositor, 2, 2},
	SessionRule{.clipboard_snapshot, 'clipboard.snapshot', 'compositor/clipboard/snapshot', .compositor, 1, 1},
	SessionRule{.clipboard_clear, 'clipboard.clear', 'compositor/clipboard/clear', .compositor, 1, 1},
	SessionRule{.exchange_grant, 'exchange.grant', 'compositor/exchange/grant', .compositor, 2, 2},
	SessionRule{.dialog_result, 'dialog.result', 'compositor/dialog/result', .compositor, 4, 4},
	SessionRule{.settings_set, 'settings.set', 'compositor/settings/set', .compositor, 2, 24},
	SessionRule{.policy_set, 'policy.set', 'compositor/policy/set', .compositor, 2, 2},
	SessionRule{.take, 'take', 'compositor/actions/take', .compositor, 1, 1},
	SessionRule{.quiet, 'quiet', 'compositor/notifications/quiet', .compositor, 3, 3},
	SessionRule{.dismiss, 'dismiss', 'compositor/notifications/dismiss', .compositor, 2, 2},
	SessionRule{.alarm_remove, 'alarm.remove', 'compositor/alarms/remove', .compositor, 2, 2},
	SessionRule{.service_import, 'service.import', 'compositor/services/import', .compositor, 4, 4},
	SessionRule{.service_remove, 'service.remove', 'compositor/services/remove', .compositor, 2, 2},
	SessionRule{.service_enable, 'service.enable', 'compositor/services/enable', .compositor, 3, 3},
	SessionRule{.shutdown, 'shutdown', 'compositor/session/shutdown', .compositor, 1, 1},
]!

// Supplied by the broker from kernel peer credentials and its own session state,
// never from fields in a request. UID 0 receives no exception to these checks.
pub struct SessionCaller {
pub:
	pid            int
	uid            u32
	session_uid    u32
	compositor_pid int
}

// Authorize before decoding argument values or entering any operation handler.
// Filters only deny: no selector-specific rule can override another layer.
// Results, including denials, borrow immutable storage and allocate no state.
// Error values are shared for the process lifetime and must not be freed.
pub fn authorize_session(command string, field_count int, caller SessionCaller, policy &Policy) !SessionOperation {
	// Global filter: every domain requires an authenticated same-account caller.
	if caller.pid <= 0 || caller.uid != caller.session_uid {
		return session_invalid_caller
	}
	for i, rule in session_rules {
		if command != rule.command { continue }
		if field_count < rule.min_fields || field_count > rule.max_fields {
			return session_invalid_arguments
		}
		// Domain filter: privileged selectors belong to the attached compositor.
		if rule.domain == .compositor && (caller.compositor_pid <= 0 || caller.pid != caller.compositor_pid) {
			return unsafe { &session_rules[i] }
		}
		// Selector filter: check current policy even for previously issued grants.
		if !policy.clipboard_apps && rule.operation in [.clipboard_offer, .clipboard_read,
			.clipboard_request, .exchange_take, .exchange_grant, .clipboard_promote] {
			return unsafe { &session_rules[i] }
		}
		return rule.operation
	}
	// Exact names only. Neither a domain prefix nor a wildcard grants authority.
	return session_unknown_operation
}
