module runtimebuild

import androidhost as ah
import boothost
import json2
import os

struct Engine {
	constants map[string]ah.Value
	source    string
	root      string
	support   string
}

fn null() ah.Value { return ah.Value(json2.null) }

fn typed(kind string, value ah.Value) ah.Value { return ah.Value([ah.Value(kind), value]) }

fn object(value ah.Value) ah.Value { return typed('object', value) }

fn ordinary(value ah.Value) ah.Value { return typed('value', value) }

fn bytes(value string) ah.Value { return typed('bytes', ah.Value(value)) }

fn strings(values []string) ah.Value { return ah.Value(values.map(ah.Value(it))) }

fn text(row map[string]ah.Value, name string) string { return ah.field(row, name).text() }

fn fail(message string) IError { return boothost.PolicyError{'RuntimeError', message} }

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
	if 'error' in row { return boothost.BindingError{ah.field(row, 'error').object()} }
	return ah.field(row, 'value')
}

fn borrow(name string) !ah.Value {
	return callback('borrow', {
		'name': ah.Value(name)
	})!
}

fn get(id ah.Value, key string) !ah.Value {
	return method('acquire', id, '__getitem__', [ordinary(ah.Value(key))], {})!
}

fn get_default(id ah.Value, key string) !ah.Value {
	return method('acquire', id, 'get', [ordinary(ah.Value(key))], {})!
}

fn bool_object(id ah.Value) !bool {
	return truth(call('invoke', 'builtins', 'bool', [object(id)], {})!)
}

fn eq(left ah.Value, right ah.Value) !bool {
	return bool_object(call('acquire', 'operator', 'eq', [object(left), object(right)], {})!)
}

fn eq_value(left ah.Value, right ah.Value) !bool {
	return bool_object(call('acquire', 'operator', 'eq', [object(left), ordinary(right)], {})!)
}

fn make_sequence(values []ah.Value) !ah.Value {
	return callback('sequence', {
		'arguments': ah.Value(values)
	})!
}

fn dictionary(keys []ah.Value, values []ah.Value) !ah.Value {
	return callback('dictionary', {
		'keys':   ah.Value(keys)
		'values': ah.Value(values)
	})!
}

fn put(id ah.Value, key string, value ah.Value) ! {
	method('invoke', id, '__setitem__', [ordinary(ah.Value(key)), value], {})!
}

fn length(id ah.Value) !int {
	return int(ah.integer(call('invoke', 'builtins', 'len', [object(id)], {})!) or { return error('invalid library length') })
}

fn iter_object(id ah.Value) !ah.Value {
	return call('acquire', 'builtins', 'iter', [object(id)], {})!
}

fn next(id ah.Value) !ah.Value {
	row := callback('iterate', {
		'id': id
	})!.object()
	return if truth(ah.field(row, 'done')) { null() } else { ah.field(row, 'value') }
}

fn print_flush(data string) ! {
	callback('print', {
		'data':    ah.Value(data)
		'options': ah.Value({
			'flush': ah.Value(true)
		})
	})!
}

fn json_text(id ah.Value, options map[string]ah.Value) !string {
	return call('invoke', 'json', 'dumps', [object(id)], options)!.text()
}

fn write_json(path ah.Value, id ah.Value) ! {
	encoded := call('acquire', 'json', 'dumps', [object(id)], {
		'indent': ah.Value(2)
	})!
	line := call('acquire', 'operator', 'add', [object(encoded), ordinary(ah.Value('\n'))], {})!
	method('invoke', path, 'write_text', [object(line)], {})!
}

fn pool_map(operation string, records ah.Value, shared map[string]ah.Value) !ah.Value {
	return callback('pool_map', {
		'operation': ah.Value(operation)
		'records':   records
		'shared':    ah.Value(shared)
		'workers':   ah.Value(6)
	})!
}

fn (e Engine) root_path(name string) !ah.Value {
	return join(callback('borrow_global', {'name': ah.Value('ROOT')})!, name)!
}

fn (e Engine) support_path(name string) !ah.Value {
	return join(callback('borrow_global', {'name': ah.Value('SUPPORT')})!, name)!
}

fn call(mode string, provider string, name string, arguments []ah.Value, options map[string]ah.Value) !ah.Value {
	return callback(mode, {
		'module':    ah.Value(provider)
		'name':      ah.Value(name)
		'arguments': ah.Value(arguments)
		'options':   ah.Value(options)
	})!
}

fn method(mode string, id ah.Value, name string, arguments []ah.Value, options map[string]ah.Value) !ah.Value {
	return callback(mode, {
		'id':        id
		'name':      ah.Value(name)
		'arguments': ah.Value(arguments)
		'options':   ah.Value(options)
	})!
}

fn attribute(id ah.Value, name string, acquire bool) !ah.Value {
	return callback('getattr', {
		'id':     id
		'name':   ah.Value(name)
		'object': ah.Value(acquire)
	})!
}

fn join(id ah.Value, name string) !ah.Value {
	return method('acquire', id, '__truediv__', [ordinary(ah.Value(name))], {})!
}

fn str(id ah.Value) !string { return call('invoke', 'builtins', 'str', [object(id)], {})!.text() }

fn format_object(id ah.Value) !string {
	return call('invoke', 'builtins', 'format', [object(id), ordinary(ah.Value(''))], {})!.text()
}

fn test(id ah.Value, name string) !bool {
	return bool_object(method('acquire', id, name, [], {})!)!
}

fn read_strip(path ah.Value) !string {
	return method('invoke', method('acquire', path, 'read_text', [], {})!, 'strip', [], {})!.text()
}

fn unlink(id ah.Value, missing_ok bool) ! {
	method('invoke', id, 'unlink', [], if missing_ok {
		{
			'missing_ok': ah.Value(true)
		}
	} else {
		map[string]ah.Value{}
	})!
}

fn api(name string, arguments []ah.Value, options map[string]ah.Value, acquire bool) !ah.Value {
	return callback('function', {
		'name':      ah.Value(name)
		'arguments': ah.Value(arguments)
		'options':   ah.Value(options)
		'object':    ah.Value(acquire)
	})!
}

fn error_is(cause IError, kinds []string) !bool {
	if cause is boothost.BindingError {
		return truth(callback('exception_is', {
			'error': ah.Value(cause.value)
			'kinds': strings(kinds)
		})!)
	}
	if cause is boothost.PolicyError { return cause.kind in kinds }
	return false
}

fn exit_context(owner ah.Value, failed bool, cause IError) !bool {
	return truth(callback('exit', {
		'id':    owner
		'error': if failed { ah.Value(boothost.failure(cause)) } else { null() }
	})!)
}

fn (e Engine) c(name string) ah.Value { return ah.field(e.constants, name) }

fn result_object(id ah.Value) ah.Value {
	return ah.Value({
		'object_result': id
	})
}

fn unbound(name string) !ah.Value {
	version := call('invoke', 'sys', '__getattribute__', [ordinary(ah.Value('version_info'))], {})!.items()
	message := if (ah.integer(version[1]) or { u64(0) }) >= 11 {
		"cannot access local variable '" + name + "' where it is not associated with a value"
	} else {
		"local variable '" + name + "' referenced before assignment"
	}
	return boothost.PolicyError{'UnboundLocalError', message}
}
