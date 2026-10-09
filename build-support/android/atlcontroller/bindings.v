module atlcontroller

import androidhost as ah
import boothost
import runtimebuild as rb

fn is_global(value ah.Value) bool {
	if value is map[string]ah.Value { return '_global' in value }
	return false
}
fn o(value ah.Value) ah.Value {
	if value is map[string]ah.Value {
		if '_global' in value { return ah.Value([ah.Value('attribute'), ah.Value([ah.field(value, '_namespace'), ah.field(value, '_global')])]) }
	}
	return rb.object(value)
}
fn v(value string) ah.Value { return rb.ordinary(ah.Value(value)) }
fn g(name string) !ah.Value {
	return ah.Value({'_global': ah.Value(name), '_namespace': rb.callback('borrow_global', {'name': ah.Value('_namespace')})!})
}
fn actual(value ah.Value) !ah.Value {
	if value is map[string]ah.Value {
		if '_global' in value { return rb.attribute(ah.field(value, '_namespace'), ah.field(value, '_global').text(), true)! }
	}
	return value
}
fn attr(value ah.Value, name string) !ah.Value {
	if is_global(value) {
		borrowed := actual(value)!
		result := rb.attribute(borrowed, name, true) or {
			cause := err
			release([borrowed])!
			return cause
		}
		release([borrowed])!
		return result
	}
	return rb.attribute(value, name, true)!
}
fn factory(module_ string, name string) !ah.Value { return attr(g(module_)!, name)! }
fn release(ids []ah.Value) ! {
	mut plain := []ah.Value{}
	for value in ids { if !is_global(value) { plain << value } }
	rb.callback('release', {'ids': ah.Value(plain)})!
}
struct Names {}
fn (mut names Names) named(name string, value ah.Value) !ah.Value {
	rb.api('_publish', [v(name), o(value)], {}, false)!
	release([value])!
	return g(name)!
}
fn invoke(target ah.Value, args []ah.Value, options map[string]ah.Value) !ah.Value {
	return invoke_objects(target, args, options, {})!
}
fn invoke_objects(target ah.Value, args []ah.Value, options map[string]ah.Value, objects map[string]ah.Value) !ah.Value {
	result := raw_invoke(target, args, options, objects) or {
		cause := err
		release([target])!
		return cause
	}
	release([target])!
	return result
}
fn raw_invoke(target ah.Value, args []ah.Value, options map[string]ah.Value, objects map[string]ah.Value) !ah.Value {
	mut values := [o(target)]
	mut temporaries := []ah.Value{}
	for value in args {
		parts := value.items()
		if parts[0].text() == 'temporary' {
			values << o(parts[1])
			temporaries << parts[1]
		} else { values << value }
	}
	mut keyword_objects := map[string]ah.Value{}
	for key, value in objects {
		if is_global(value) {
			borrowed := actual(value) or { cause := err; release(temporaries)!; return cause }
			keyword_objects[key] = borrowed
			temporaries << borrowed
		} else { keyword_objects[key] = value }
	}
	result := rb.callback('function', {'name': ah.Value('_invoke_existing'), 'arguments': ah.Value(values),
		'options': ah.Value(options), 'keyword_objects': ah.Value(keyword_objects), 'object': ah.Value(true)}) or {
		cause := err
		release(temporaries)!
		return cause
	}
	release(temporaries)!
	return result
}
fn temporary_call(target ah.Value, args []ah.Value, options map[string]ah.Value, objects map[string]ah.Value, temporaries []ah.Value) !ah.Value {
	result := raw_invoke(target, args, options, objects) or {
		cause := err
		release(temporaries)!
		release([target])!
		return cause
	}
	release(temporaries)!
	release([target])!
	return result
}
fn method(value ah.Value, name string, args []ah.Value) !ah.Value {
	return invoke(attr(value, name)!, args, {})!
}
fn discard(value ah.Value) ! { release([value])! }
fn statement(target ah.Value, args []ah.Value, options map[string]ah.Value) ! {
	discard(invoke(target, args, options)!)!
}
fn name_target(name string) !ah.Value { return rb.api('_name_target', [v(name)], {}, true)! }
fn name_call(name string, args []ah.Value) !ah.Value {
	return invoke(name_target(name)!, args, {})!
}
fn literal(value string) !ah.Value { return rb.callback('retain', {'value': v(value)})! }
fn str(value ah.Value) !ah.Value { return name_call('str', [o(value)])! }
fn add(left ah.Value, right ah.Value) !ah.Value { return rb.call('acquire', 'operator', 'add', [o(left), o(right)], {})! }
fn plus(left ah.Value, right string) !ah.Value { return add(left, literal(right)!)! }
fn join(left ah.Value, right string) !ah.Value { return rb.call('acquire', 'operator', 'truediv', [o(left), v(right)], {})! }
fn join_id(left ah.Value, right ah.Value) !ah.Value { return rb.call('acquire', 'operator', 'truediv', [o(left), o(right)], {})! }
fn temp(value ah.Value) ah.Value { return ah.Value([ah.Value('temporary'), value]) }
fn seq(values []ah.Value) !ah.Value {
	mut arguments := []ah.Value{}
	mut temporaries := []ah.Value{}
	for value in values {
		parts := value.items()
		if parts[0].text() == 'temporary' {
			arguments << o(parts[1])
			temporaries << parts[1]
		} else { arguments << value }
	}
	result := rb.make_sequence(arguments) or {
		cause := err
		release(temporaries)!
		return cause
	}
	release(temporaries)!
	return result
}
fn items(value ah.Value) !ah.Value {
	view := method(value, 'items', [])!
	result := iterator(view) or { cause := err; release([view])!; return cause }
	release([view])!
	return result
}
fn flag(value ah.Value) !bool { return rb.call('invoke', 'builtins', 'bool', [o(value)], {})! == ah.Value(true) }
fn equal(left ah.Value, right ah.Value) !bool { return flag(rb.call('acquire', 'operator', 'eq', [o(left), o(right)], {})!)! }
fn iterator(value ah.Value) !ah.Value { return rb.call('acquire', 'builtins', 'iter', [o(value)], {})! }
fn pair(value ah.Value) ![]ah.Value { return rb.callback('unpack_pair', {'id': value})!.items() }
fn append(list ah.Value, value ah.Value) ! { discard(method(list, 'append', [o(value)])!)! }
fn put(dict ah.Value, key ah.Value, value ah.Value) ! { discard(method(dict, '__setitem__', [o(key), o(value)])!)! }
fn mkdir(path ah.Value, exist_ok bool) ! {
	statement(attr(path, 'mkdir')!, [], if exist_ok { {'parents': ah.Value(true), 'exist_ok': ah.Value(true)} } else { {'parents': ah.Value(true)} })!
}
fn copy(source ah.Value, target ah.Value) ! { statement(factory('shutil', 'copy2')!, [o(source), o(target)], {})! }
fn raise(name string, args []ah.Value) !ah.Value {
	return rb.callback('raise_existing', {'id': name_call(name, args)!})!
}
fn digest(path ah.Value) !ah.Value {
	ctor := factory('hashlib', 'sha256')!
	content := method(path, 'read_bytes', []) or {
		cause := err
		release([ctor])!
		return cause
	}
	hasher := temporary_call(ctor, [o(content)], {}, {}, [content])!
	hexdigest := attr(hasher, 'hexdigest') or {
		cause := err
		release([hasher])!
		return cause
	}
	release([hasher])!
	return invoke(hexdigest, [], {})!
}
fn apply_digest(target ah.Value, path ah.Value) !ah.Value {
	argument := rb.callback('retain', {'value': o(path)})!
	native := actual(g('_native_digest')!)!
	is_native := flag(rb.call('acquire', 'operator', 'is_', [o(target), o(native)], {})!)!
	release([native])!
	result := selected_digest(is_native, target, argument) or {
		cause := err
		release([argument, target])!
		return cause
	}
	release([argument, target])!
	return result
}
fn selected_digest(native bool, target ah.Value, argument ah.Value) !ah.Value {
	if native { return digest(argument)! }
	return raw_invoke(target, [o(argument)], {}, {})!
}
fn digest_api(path ah.Value) !ah.Value { return apply_digest(actual(g('digest')!)!, path)! }
fn digest_join(base ah.Value, name string) !ah.Value {
	target := actual(g('digest')!)!
	path := join(base, name) or { cause := err; release([target])!; return cause }
	result := apply_digest(target, path) or { cause := err; release([path])!; return cause }
	release([path])!
	return result
}
fn write_json(path ah.Value, metadata ah.Value) ! {
	writer := attr(path, 'write_text')!
	release([path])!
	encoder := factory('json', 'dumps') or {
		cause := err
		release([writer])!
		return cause
	}
	encoded := invoke(encoder, [o(metadata)], {'indent': ah.Value(2)}) or {
		cause := err
		release([writer])!
		return cause
	}
	line := plus(encoded, '\n') or {
		cause := err
		release([writer, encoded])!
		return cause
	}
	release([encoded])!
	discard(temporary_call(writer, [o(line)], {}, {}, [line])!)!
}
fn archive(root ah.Value, archive_ ah.Value, mut names Names) ! {
	open := factory('tarfile', 'open')!
	manager := invoke_objects(open, [o(archive_), v('w:gz')], {}, {'format': attr(g('tarfile')!, 'USTAR_FORMAT')!})!
	tar := rb.callback('enter_existing', {'id': manager}) or {
		cause := err
		release([manager])!
		return cause
	}
	release([manager])!
	names.named('tar', tar)!
	mut failed := false
	mut cause := IError(none)
	statement(attr(tar, 'add')!, [o(root)], {'arcname': ah.Value('.')}) or { failed = true; cause = err }
	suppressed := rb.callback('exit', {'id': tar, 'error': if failed { ah.Value(boothost.failure(cause)) } else { rb.null() }})! == ah.Value(true)
	release([tar])!
	if failed && !suppressed { return cause }
}
