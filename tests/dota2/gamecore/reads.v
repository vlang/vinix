// SPDX-License-Identifier: GPL-2.0-or-later
module gamecore

import androidhost as ah
import gapcore as gc

fn reads_init(self string, source string) ! {
	set_attr(self, 'read', o(attr(source, 'read')!))!
	set_attr(self, 'started', o(call('time.monotonic')!))!
	set_attr(self, 'lock', o(call('threading.Lock')!))!
	for name in ['requests', 'bytes', 'errors'] { set_attr(self, name, n(0))! }
	set_attr(self, 'failures', o(list()!))!
	set_attr(source, 'read', o(attr(self, 'observe')!))!
}

fn increment(self string, name string, amount ah.Value) ! {
	set_attr(self, name, o(call('operator.iadd', o(attr(self, name)!), amount)!))!
}

fn request_count(self string) ! {
	manager := attr(self, 'lock')!
	enter(manager)!
	increment(self, 'requests', n(1)) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return
	}
	retire(manager, none)!
}

fn reads_observe(self string, offset string, count string) !string {
	request_count(self)!
	data := method(self, 'read', [o(offset), o(count)], {}) or {
		failure := err
		gc.activate(failure, true)!
		if !exception_is(failure, 'OSError')! { return failure }
		record_read_error(self, offset, count, failure)!
		return failure
	}
	manager := attr(self, 'lock')!
	enter(manager)!
	increment(self, 'bytes', o(call('builtins.len', o(data))!)) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return data
	}
	retire(manager, none)!
	return data
}

struct Saved {
mut:
	id string
}

fn retain_read_error(self string, record string, mut saved Saved) ! {
	increment(self, 'errors', n(1))!
	saved.id = call('operator.lt', o(call('builtins.len', o(attr(self, 'failures')!))!), n(32))!
	if truth(saved.id)! { append(attr(self, 'failures')!, o(record))! }
}

fn record_read_error(self string, offset string, count string, cause IError) ! {
	if cause is gc.BindingError {
		error_object := gc.callback('error_object', {
			'error': ah.Value(cause.value)
		})!.text()
		record := dict()!
		set(record, 'elapsed_seconds', o(call('builtins.round', o(call('operator.sub', o(call('time.monotonic')!), o(attr(self, 'started')!))!), n(3))!))!
		set(record, 'offset', o(offset))!
		set(record, 'length', o(count))!
		set(record, 'errno', o(attr(error_object, 'errno')!))!
		set(record, 'message', o(call('builtins.str', o(error_object))!))!
		manager := attr(self, 'lock')!
		enter(manager)!
		mut saved := Saved{}
		mut retired := false
		retain_read_error(self, record, mut saved) or {
			failure := err
			retired = true
			if !retire(manager, failure)! { return failure }
		}
		if !retired { retire(manager, none)! }
		if saved.id == '' {
			gc.callback('raise_builtin', {
				'kind':  ah.Value('UnboundLocalError')
				'value': s("local variable 'saved' referenced before assignment")
			})!
		}
		if truth(saved.id)! {
			message := call('operator.add', s('DOTA2-EXPORT-READ-ERROR: '), o(call('json.dumps', o(record))!))!
			invoke('builtins.print', [o(message)], {
				'flush': v(ah.Value(true))
			})!
		}
	}
}

fn reads_report(self string) !string {
	manager := attr(self, 'lock')!
	enter(manager)!
	result := read_report_fields(self) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return null_id()!
	}
	retire(manager, none)!
	return result
}

fn read_report_fields(self string) !string {
	result := dict()!
	for row in [['requests', 'requests'], ['bytes', 'bytes'], ['error_count', 'errors']] {
		set(result, row[0], o(attr(self, row[1])!))!
	}
	set(result, 'failures', o(call('builtins.list', o(attr(self, 'failures')!))!))!
	return result
}
