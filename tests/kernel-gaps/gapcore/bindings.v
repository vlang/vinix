// SPDX-License-Identifier: GPL-2.0-or-later
module gapcore

import androidhost as ah
import boothost
import json2
import os
import strconv

#include <signal.h>

fn C.signal(int, voidptr) voidptr

pub fn ignore_interrupt() {
	unsafe { C.signal(C.SIGINT, C.SIG_IGN) }
}

pub struct BindingError {
pub:
	value map[string]ah.Value
}

pub fn (e BindingError) msg() string { return ah.field(e.value, 'message').text() }

pub fn (e BindingError) code() int { return 0 }

fn callback(name string, arguments map[string]ah.Value) !ah.Value {
	println(ah.encode(boothost.pack(ah.Value({
		'callback':  ah.Value(name)
		'arguments': ah.Value(arguments)
	}))))
	reply := boothost.unpack(json2.decode[ah.Value](os.get_raw_line())!)!.object()
	if 'error' in reply { return BindingError{ah.field(reply, 'error').object()} }
	return ah.field(reply, 'value')
}

pub fn finished() ! { callback('finished', {})! }

fn null() ah.Value { return ah.Value(json2.Null{}) }

fn v(value ah.Value) ah.Value { return ah.Value([ah.Value('value'), value]) }

fn p(value string) ah.Value { return ah.Value([ah.Value('path'), ah.Value(value)]) }

fn b(value string) ah.Value { return ah.Value([ah.Value('bytes'), ah.Value(value)]) }

fn owner(value string) ah.Value { return ah.Value([ah.Value('owner'), ah.Value(value)]) }

fn invoke(name string, args []ah.Value, kwargs map[string]ah.Value, mode string) !ah.Value {
	return callback('function', {
		'name':   ah.Value(name)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
		'result': ah.Value(mode)
	})!
}

fn call(name string, args ...ah.Value) !ah.Value { return invoke(name, args, {}, 'value')! }

fn method(id string, name string, args []ah.Value, kwargs map[string]ah.Value, mode string) !ah.Value {
	return callback('function', {
		'owner':  ah.Value(id)
		'method': ah.Value(name)
		'args':   ah.Value(args)
		'kwargs': ah.Value(kwargs)
		'result': ah.Value(mode)
	})!
}

fn path_method(location string, name string, args []ah.Value, kwargs map[string]ah.Value, mode string) !ah.Value {
	id := invoke('Path', [v(ah.Value(location))], {}, 'owner')!.text()
	return method(id, name, args, kwargs, mode)!
}

fn join(base string, child string) !string {
	return invoke('operator.truediv', [p(base), v(ah.Value(child))], {}, 'path')!.text()
}

fn resolve(location string) !string {
	return path_method(location, 'resolve', [], {}, 'path')!.text()
}

fn mkdir(location string) ! {
	path_method(location, 'mkdir', [], {
		'parents':  v(ah.Value(true))
		'exist_ok': v(ah.Value(true))
	}, 'value')!
}

fn flag(value ah.Value) bool {
	if value is bool { return value }
	return false
}

fn integer(value ah.Value) int {
	return match value {
		ah.Number { value.text.int() }
		int { value }
		i64 { int(value) }
		u64 { int(value) }
		else { 0 }
	}
}

fn number(value ah.Value) f64 {
	return match value {
		ah.Number { strconv.atof64(value.text) or { 0.0 } }
		int { f64(value) }
		i64 { f64(value) }
		u64 { f64(value) }
		else { 0.0 }
	}
}

fn now() !f64 { return number(call('time.monotonic')!) }

fn kind(err IError, name string) bool {
	if err is BindingError { return flag(ah.field(err.value, name)) }
	return false
}

fn errno(err IError, expected int) bool {
	if err is BindingError { return integer(ah.field(err.value, 'errno')) == expected }
	return false
}

fn environment(name string, default_value string) !string {
	return call('os.environ.get', v(ah.Value(name)), v(ah.Value(default_value)))!.text()
}

fn run(command []string, env ah.Value) ! {
	mut keywords := {
		'check': v(ah.Value(true))
	}
	if env !is json2.Null { keywords['env'] = v(env) }
	invoke('subprocess.run', [v(ah.Value(command.map(ah.Value(it))))], keywords, 'owner')!
}

fn print_text(text string) ! {
	invoke('builtins.print', [v(ah.Value(text))], {
		'flush': v(ah.Value(true))
	}, 'value')!
}

fn parser_error(message string) ! {
	method('parser', 'error', [v(ah.Value(message))], {}, 'value')!
}

fn error_detail(cause IError) ah.Value {
	if cause is BindingError { return ah.Value(cause.value) }
	return ah.Value({
		'kind':    ah.Value('RuntimeError')
		'message': ah.Value(cause.msg())
	})
}

fn activate(cause IError, failed bool) ! {
	callback('active_error', {
		'error': if failed { error_detail(cause) } else { null() }
	})!
}
