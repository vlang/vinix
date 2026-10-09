module benchtest

import androidhost as ah
import boothost
import runtimebuild as rb

fn o(id ah.Value) ah.Value { return rb.object(id) }
fn v(value string) ah.Value { return rb.ordinary(ah.Value(value)) }
fn n(value int) ah.Value { return rb.ordinary(ah.Value(value)) }
fn bytes(value string) ah.Value { return ah.Value([ah.Value('bytes'), ah.Value(value.bytes().hex())]) }
fn literal(value string) !ah.Value { return rb.callback('retain', {'value': v(value)})! }
fn release(ids []ah.Value) ! { rb.callback('release', {'ids': ah.Value(ids.filter(it != rb.null()))})! }
fn discard(id ah.Value) ! { release([id])! }
fn target(name string) !ah.Value { return rb.api('_target', [v(name)], {}, true)! }
fn attr(id ah.Value, name string) !ah.Value { return rb.attribute(id, name, true)! }
fn factory(provider string, name string) !ah.Value {
	module_ := target(provider)!
	value := attr(module_, name) or { release([module_])!; return err }
	release([module_])!
	return value
}
fn temp(id ah.Value) ah.Value { return ah.Value([ah.Value('temporary'), id]) }
fn consume_args(args []ah.Value) ([]ah.Value, []ah.Value) {
    mut values := []ah.Value{}
    mut temps := []ah.Value{}
    for argument in args {
        parts := argument.items()
        if parts[0].text() == 'temporary' {
            values << o(parts[1])
            temps << parts[1]
        } else { values << argument }
    }
    return values, temps
}
fn raw_invoke(target_ ah.Value, args []ah.Value, opts map[string]ah.Value, objects map[string]ah.Value) !ah.Value {
    arguments, temps := consume_args(args)
    mut values := [o(target_)]
    for argument in arguments { values << argument }
    result := rb.callback('function', {'name': ah.Value('_invoke_actual'), 'arguments': ah.Value(values),
        'options': ah.Value(opts), 'keyword_objects': ah.Value(objects), 'object': ah.Value(true)}) or {
        cause := err
        release(temps)!
        return cause
    }
    release(temps)!
    return result
}
fn invoke(target_ ah.Value, args []ah.Value, opts map[string]ah.Value) !ah.Value {
	result := raw_invoke(target_, args, opts, {}) or { release([target_])!; return err }
	release([target_])!
	return result
}
fn temporary_call(target_ ah.Value, args []ah.Value, opts map[string]ah.Value, objects map[string]ah.Value, temps []ah.Value) !ah.Value {
	result := raw_invoke(target_, args, opts, objects) or {
		cause := err
		release(temps)!
		release([target_])!
		return cause
	}
	release(temps)!
	release([target_])!
	return result
}
fn call(name string, args []ah.Value) !ah.Value { return invoke(target(name)!, args, {})! }
fn method(id ah.Value, name string, args []ah.Value) !ah.Value { return invoke(attr(id, name)!, args, {})! }
fn statement(target_ ah.Value, args []ah.Value, opts map[string]ah.Value) ! { discard(invoke(target_, args, opts)!)! }
fn truth(id ah.Value) !bool { return rb.api('_truth', [o(id)], {}, false)! == ah.Value(true) }
fn truth_value(id ah.Value) !bool {
	value := truth(id) or { release([id])!; return err }
	release([id])!
	return value
}
fn op(name string, left ah.Value, right ah.Value) !ah.Value { return invoke(factory('_operator', name)!, [o(left), right], {})! }
fn join(left ah.Value, name string) !ah.Value { return op('truediv', left, v(name))! }
fn str(id ah.Value) !ah.Value { return call('str', [o(id)])! }
fn path_str(left ah.Value, name string) !ah.Value {
	str_ := target('str')!
	path := join(left, name) or { release([left, str_])!; return err }
	release([left])!
	return temporary_call(str_, [o(path)], {}, {}, [path])!
}
fn plus(left ah.Value, right string) !ah.Value { return op('add', left, v(right))! }
fn get(id ah.Value, name string) !ah.Value { return op('getitem', id, v(name))! }
fn get_index(id ah.Value, index int) !ah.Value { return op('getitem', id, n(index))! }
fn list(values []ah.Value) !ah.Value {
    arguments, temps := consume_args(values)
    result := rb.make_sequence(arguments) or { release(temps)!; return err }
    release(temps)!
    return result
}
fn append(id ah.Value, value ah.Value) ! { discard(method(id, 'append', [o(value)])!)! }
fn append_text(id ah.Value, value string) ! { discard(method(id, 'append', [v(value)])!)! }
fn extend(id ah.Value, values ah.Value) ! { discard(method(id, 'extend', [o(values)])!)! }
fn put(id ah.Value, name string, value ah.Value) ! { discard(method(id, '__setitem__', [v(name), o(value)])!)! }
fn item_iter(id ah.Value) !ah.Value { return rb.iter_object(id)! }
fn dict(keys []string, values []ah.Value) !ah.Value {
    arguments, temps := consume_args(values)
    result := rb.dictionary(keys.map(v(it)), arguments) or { release(temps)!; return err }
    release(temps)!
    return result
}
fn tuple(values []ah.Value) !ah.Value {
    arguments, temps := consume_args(values)
    result := rb.callback('tuple', {'arguments': ah.Value(arguments)}) or { release(temps)!; return err }
    release(temps)!
    return result
}
fn format(id ah.Value) !ah.Value { return rb.api('_fstring', [o(id)], {}, true)! }
fn fail_message(id ah.Value) ! { rb.api('_assert_message', [o(id)], {}, false)! }
fn fail_plain() ! { rb.api('_assert_false', [], {}, false)! }
fn digest(id ah.Value) !ah.Value {
	ctor := factory('hashlib', 'sha256')!
	content := method(id, 'read_bytes', []) or { release([ctor])!; return err }
	return digest_content(ctor, content)!
}
fn digest_content(ctor ah.Value, content ah.Value) !ah.Value {
	hasher := temporary_call(ctor, [o(content)], {}, {}, [content])!
	method_ := attr(hasher, 'hexdigest') or { release([hasher])!; return err }
	release([hasher])!
	return invoke(method_, [], {})!
}
fn digest_bytes(content ah.Value) !ah.Value {
	// The content is an existing named local in the comparison loop.
	hasher := invoke(factory('hashlib', 'sha256')!, [o(content)], {})!
	method_ := attr(hasher, 'hexdigest') or { release([hasher])!; return err }
	release([hasher])!
	return invoke(method_, [], {})!
}
fn write_json(path ah.Value, data ah.Value) ! {
	writer := receiver(path, 'write_text')!
	encoder := factory('json', 'dumps') or { release([writer])!; return err }
	encoded := invoke(encoder, [o(data)], {'indent': ah.Value(2)}) or { release([writer])!; return err }
	line := plus(encoded, '\n') or { release([encoded, writer])!; return err }
	release([encoded])!
	discard(temporary_call(writer, [o(line)], {}, {}, [line])!)!
}
fn generated(path ah.Value, source ah.Value, arch ah.Value) !ah.Value {
	loader := factory('runpy', 'run_path')!
	text := str(path) or { release([loader])!; return err }
	module_ := temporary_call(loader, [o(text)], {}, {}, [text])!
	generate := get(module_, 'generate') or { release([module_])!; return err }
	release([module_])!
	return invoke(generate, [o(source), o(arch)], {})!
}
struct Frame {
mut:
	names map[string]ah.Value
}
fn (mut f Frame) named(name string, value ah.Value) !ah.Value {
	old := f.names[name] or { rb.null() }
	f.names[name] = value
	if old != rb.null() && old != value { release([old])! }
	return value
}
fn exit(manager ah.Value, cause ?IError) !bool {
	result := rb.callback('exit', {'id': manager, 'error': if e := cause { ah.Value(boothost.failure(e)) } else { rb.null() }})!
	return result == ah.Value(true)
}

fn environ_get() !ah.Value {
    module_ := target('os')!
    environ := attr(module_, 'environ') or { release([module_])!; return err }
    release([module_])!
    getter := attr(environ, 'get') or { release([environ])!; return err }
    release([environ])!
    return getter
}
fn receiver(id ah.Value, name string) !ah.Value {
    value := attr(id, name) or { release([id])!; return err }
    release([id])!
    return value
}
fn digest_attr(id ah.Value, name string) !ah.Value {
    ctor := factory('hashlib', 'sha256')!
    content := attr(id, name) or { release([ctor])!; return err }
    return digest_content(ctor, content)!
}
fn attr_true(id ah.Value, name string) !bool { return truth_value(attr(id, name)!)! }
fn attr_equal(id ah.Value, name string, value string) !bool {
    attr_ := attr(id, name)!
    compared := temporary_call(factory('_operator', 'eq')!, [o(attr_), v(value)], {}, {}, [attr_])!
    return truth_value(compared)!
}

fn attr_compare(id ah.Value, name string, operator string, right ah.Value) !bool {
    value := attr(id, name)!
    result := temporary_call(factory('_operator', operator)!, [o(value), right], {}, {}, [value])!
    return truth_value(result)!
}

fn attr_str(id ah.Value, name string) !ah.Value {
    formatter := target('str')!
    value := attr(id, name) or { release([formatter])!; return err }
    return temporary_call(formatter, [o(value)], {}, {}, [value])!
}
fn join_global(name string, child string) !ah.Value {
    parent := target(name)!
    value := join(parent, child) or { release([parent])!; return err }
    release([parent])!
    return value
}
