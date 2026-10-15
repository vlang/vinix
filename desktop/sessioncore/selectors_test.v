// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

fn selector_test_caller() SessionCaller {
	return SessionCaller{ pid: 100, uid: 1000, session_uid: 1000, compositor_pid: 200 }
}

fn selector_test_compositor() SessionCaller {
	return SessionCaller{ pid: 200, uid: 1000, session_uid: 1000, compositor_pid: 200 }
}

fn test_session_registry_has_unique_complete_locked_definitions() {
	// Every enum value except invalid must have exactly one definition. The
	// constant table has no runtime registration or handler retrieval API.
	assert session_rules.len == int(SessionOperation.shutdown)
	for i, rule in session_rules {
		assert rule.operation != .invalid
		assert rule.min_fields > 0 && rule.max_fields >= rule.min_fields
		assert rule.max_fields <= 24
		prefix := if rule.domain == .compositor { 'compositor/' } else { 'application/' }
		assert rule.selector.starts_with(prefix)
		for j in 0 .. i {
			assert session_rules[j].operation != rule.operation
			assert session_rules[j].command != rule.command
			assert session_rules[j].selector != rule.selector
		}
	}
}

fn test_application_selectors_keep_existing_protocol_and_reject_wrong_arity() {
	caller := selector_test_caller()
	policy := Policy{}
	for command in ['ping', 'attach', 'clipboard.offer', 'clipboard.read', 'clipboard.request',
		'exchange.take', 'policy', 'time.offset', 'settings.status', 'dialog.open', 'dialog.take',
		'services', 'notify', 'alarm', 'alarm.cancel', 'action'] {
		mut found := false
		for rule in session_rules {
			if rule.command != command { continue }
			found = true
			assert authorize_session(command, rule.min_fields, caller, &policy)! == rule.operation
			assert authorize_session(command, rule.max_fields, caller, &policy)! == rule.operation
			if _ := authorize_session(command, rule.min_fields - 1, caller, &policy) {
				assert false, command
			}
			if _ := authorize_session(command, rule.max_fields + 1, caller, &policy) {
				assert false, command
			}
		}
		assert found, command
	}
}

fn test_compositor_domain_cannot_be_reached_by_application_selectors() {
	caller := selector_test_caller()
	compositor := selector_test_compositor()
	policy := Policy{}
	for command in ['history', 'clipboard.promote', 'clipboard.snapshot', 'clipboard.clear',
		'exchange.grant', 'dialog.result', 'settings.set', 'policy.set', 'take', 'quiet', 'dismiss',
		'alarm.remove', 'service.import', 'service.remove', 'service.enable', 'shutdown'] {
		mut found := false
		for rule in session_rules {
			if rule.command != command { continue }
			found = true
			if _ := authorize_session(command, rule.min_fields, caller, &policy) {
				assert false, command
			}
			assert authorize_session(command, rule.min_fields, compositor, &policy)! == rule.operation
			if _ := authorize_session(command, rule.max_fields + 1, compositor, &policy) {
				assert false, command
			}
		}
		assert found, command
	}
}

fn test_global_identity_filter_cannot_be_overridden_even_by_root_or_compositor() {
	policy := Policy{}
	for caller in [
		SessionCaller{ pid: 0, uid: 1000, session_uid: 1000, compositor_pid: 0 },
		SessionCaller{ pid: -1, uid: 1000, session_uid: 1000, compositor_pid: -1 },
		SessionCaller{ pid: 200, uid: 0, session_uid: 1000, compositor_pid: 200 },
		SessionCaller{ pid: 200, uid: 1001, session_uid: 1000, compositor_pid: 200 },
	] {
		for rule in session_rules {
			if _ := authorize_session(rule.command, rule.min_fields, caller, &policy) {
				assert false, rule.command
			}
		}
	}
	root_session := SessionCaller{ pid: 100, uid: 0, session_uid: 0, compositor_pid: 200 }
	assert authorize_session('ping', 1, root_session, &policy)! == .ping
	if _ := authorize_session('shutdown', 1, root_session, &policy) {
		assert false, 'same-account root does not bypass the compositor domain'
	}
}

fn test_unknown_names_wildcards_and_registration_operations_fail_closed() {
	caller := selector_test_compositor()
	policy := Policy{}
	for command in ['', '*', 'clipboard.*', 'clipboard', 'clipboard.read.extra', 'clipboard.read/',
		'Clipboard.read', 'clipboard.read\x00', ' clipboard.read', 'compositor/settings/set',
		'sbp/selectors/register', 'sbp/selectors/unregister', 'sbp/selectors/overwrite',
		'sbp/selectors/fn', 'sbp/selectors/unsafe', 'sbp/domains/lock', 'sbp/filters/global/add'] {
		if _ := authorize_session(command, 2, caller, &policy) {
			assert false, 'unknown selector was accepted'
		}
	}
}

fn test_current_privacy_policy_denies_all_clipboard_transfer_endpoints() {
	caller := selector_test_compositor()
	mut policy := Policy{}
	for rule in session_rules {
		assert authorize_session(rule.command, rule.min_fields, caller, &policy)! == rule.operation
	}
	policy.clipboard_apps = false
	for command in ['clipboard.offer', 'clipboard.read', 'clipboard.request', 'exchange.take',
		'exchange.grant', 'clipboard.promote'] {
		for rule in session_rules {
			if rule.command != command { continue }
			if _ := authorize_session(command, rule.min_fields, caller, &policy) {
				assert false, command
			}
		}
	}
	// Cleanup and policy controls remain available while transfer is disabled.
	assert authorize_session('clipboard.clear', 1, caller, &policy)! == .clipboard_clear
	assert authorize_session('policy.set', 2, caller, &policy)! == .policy_set
	assert authorize_session('ping', 1, selector_test_caller(), &policy)! == .ping
	policy.clipboard_apps = true
	assert authorize_session('clipboard.read', 2, caller, &policy)! == .clipboard_read
}
