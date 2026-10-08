module runhost

import androidhost as ah
import boothost
import json2
import os

pub struct BindingError {
pub:
	value map[string]ah.Value
}

pub fn (e BindingError) msg() string { return ah.field(e.value, 'message').text() }

pub fn (e BindingError) code() int { return 0 }

pub struct PolicyError {
pub:
	kind    string
	message string
}

pub fn (e PolicyError) msg() string { return e.message }

pub fn (e PolicyError) code() int { return 0 }

fn failure(message string) IError { return PolicyError{'SystemExit', message} }

fn null() ah.Value { return ah.Value(json2.null) }

fn strings(items []string) ah.Value { return ah.Value(items.map(ah.Value(it))) }

fn text(row map[string]ah.Value, name string) string { return ah.field(row, name).text() }

fn truth(value ah.Value) bool {
	return match value {
		json2.Null { false }
		bool { value }
		string { value.len != 0 }
		[]ah.Value { value.len != 0 }
		map[string]ah.Value { value.len != 0 }
		else { ah.encode(value) !in ['0', '0.0', '-0', '-0.0'] }
	}
}

fn callback(operation string, arguments map[string]ah.Value) !ah.Value {
	println(ah.encode(boothost.pack(ah.Value({
		'callback':  ah.Value(operation)
		'arguments': ah.Value(arguments)
	}))))
	row := boothost.unpack(json2.decode[ah.Value](os.get_raw_line())!)!.object()
	if 'error' in row { return BindingError{ah.field(row, 'error').object()} }
	return ah.field(row, 'value')
}

fn join(parts []string) !string {
	return callback('join', {
		'parts': strings(parts)
	})!.text()
}

fn path(method string, value string, arguments []ah.Value, options map[string]ah.Value) !ah.Value {
	return callback('path', {
		'path':      ah.Value(value)
		'method':    ah.Value(method)
		'arguments': ah.Value(arguments)
		'options':   ah.Value(options)
	})!
}

fn resolve(value string) !string {
	return path('resolve', value, []ah.Value{}, map[string]ah.Value{})!.text()
}

fn test(method string, value string) !bool {
	return truth(path(method, value, []ah.Value{}, map[string]ah.Value{})!)
}

fn write(value string, content string) ! {
	path('write_text', value, [ah.Value(content)], map[string]ah.Value{})!
}

fn mkdir(value string, parents bool, exist_ok bool) ! {
	path('mkdir', value, []ah.Value{}, {
		'parents':  ah.Value(parents)
		'exist_ok': ah.Value(exist_ok)
	})!
}

fn chmod(value string, mode int) ! {
	path('chmod', value, [ah.Value(mode)], map[string]ah.Value{})!
}

fn unlink(value string) ! { path('unlink', value, []ah.Value{}, map[string]ah.Value{})! }

fn copy(source string, target string) ! {
	callback('copy2', {
		'arguments': strings([source, target])
	})!
}

fn rmtree(value string) ! {
	callback('rmtree', {
		'arguments': strings([value])
	})!
}

fn list(operation string, value string, arguments []ah.Value) ![]string {
	return callback(operation, {
		'path':      ah.Value(value)
		'arguments': ah.Value(arguments)
	})!.items().map(it.text())
}

fn args_set(mut args map[string]ah.Value, name string, value ah.Value, kind string) ! {
	args[name] = value
	callback('args_set', {
		'name':  ah.Value(name)
		'value': value
		'kind':  ah.Value(kind)
	})!
}

fn parser_error(message string) ! {
	callback('parser_error', {
		'message': ah.Value(message)
	})!
}

fn default_path(mut args map[string]ah.Value, name string, default_value string) ! {
	value := if truth(ah.field(args, name)) { text(args, name) } else { default_value }
	args_set(mut args, name, ah.Value(resolve(value)!), 'path')!
}

fn attribute(args map[string]ah.Value, name string) !ah.Value {
	return args[name] or {
		callback('attribute', {
			'name': ah.Value(name)
		})!
	}
}

fn attribute_text(args map[string]ah.Value, name string) !string {
	return attribute(args, name)!.text()
}

fn attribute_string(name string) !ah.Value {
	return callback('str_attribute', {
		'name': ah.Value(name)
	})!
}

fn error_value(cause IError) ah.Value {
	if cause is BindingError { return ah.Value(cause.value) }
	if cause is PolicyError {
		return ah.Value({
			'kind':    ah.Value(cause.kind)
			'message': ah.Value(cause.message)
		})
	}
	return json2.decode[ah.Value](ah.error_json(cause)) or {
		ah.Value({
			'kind':    ah.Value('RuntimeError')
			'message': ah.Value(cause.msg())
		})
	}
}

fn retire(operation string, owner ah.Value, failed bool, cause IError) !bool {
	return truth(callback(operation, {
		'id':    owner
		'error': if failed { error_value(cause) } else { null() }
	})!)
}
