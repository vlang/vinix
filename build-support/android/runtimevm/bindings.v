module runtimevm

import androidhost as ah
import boothost
import runtimebuild as rb

fn o(value ah.Value) ah.Value { return rb.object(value) }
fn v(value string) ah.Value { return rb.ordinary(ah.Value(value)) }
fn global(name string) !ah.Value { return rb.callback('borrow_global', {'name': ah.Value(name)})! }
fn attr(value ah.Value, name string) !ah.Value { return rb.attribute(value, name, true)! }
fn method(value ah.Value, name string, args []ah.Value) !ah.Value { return rb.method('acquire', value, name, args, {})! }
fn builtin(name string, args []ah.Value) !ah.Value {
	mut parameters := [v(name)]
	for value in args { parameters << value }
	return rb.api('_call_name', parameters, {}, true)!
}
fn text(value ah.Value) !string { return rb.format_object(value)! }
fn str(value ah.Value) !ah.Value { return builtin('str', [o(value)])! }
fn join(path ah.Value, name string) !ah.Value { return rb.call('acquire', 'operator', 'truediv', [o(path), v(name)], {})! }
fn join_object(path ah.Value, name ah.Value) !ah.Value { return rb.call('acquire', 'operator', 'truediv', [o(path), o(name)], {})! }
fn flag(value ah.Value) !bool { return rb.bool_object(value)! }
fn literal(value string) !ah.Value { return rb.callback('retain', {'value': v(value)})! }
fn add(left ah.Value, right ah.Value) !ah.Value { return rb.call('acquire', 'operator', 'add', [o(left), o(right)], {})! }
fn append(list ah.Value, value ah.Value) ! { rb.method('invoke', list, 'append', [o(value)], {})! }
fn put(dict ah.Value, key ah.Value, value ah.Value) ! { rb.method('invoke', dict, '__setitem__', [o(key), o(value)], {})! }
fn mkdir(path ah.Value, exist_ok bool) ! {
	rb.method('invoke', path, 'mkdir', [], if exist_ok {
		{'parents': ah.Value(true), 'exist_ok': ah.Value(true)}
	} else { {'parents': ah.Value(true)} })!
}
fn copy(source ah.Value, target ah.Value) ! { rb.call('invoke', 'shutil', 'copy2', [o(source), o(target)], {})! }
fn raise(name string, args []ah.Value) !ah.Value {
	return rb.callback('raise_existing', {'id': builtin(name, args)!})!
}
fn native(name string) !bool {
	return rb.callback('function_is', {'name': ah.Value(name), 'reference': ah.Value('_native_' + name)})! == ah.Value(true)
}
fn existing(target ah.Value, args []ah.Value) !ah.Value {
 mut values := [o(target)]
 for value in args { values << value }
 return rb.api('_invoke_existing', values, {}, true)!
}
fn load(name ah.Value, path ah.Value) !ah.Value {
 first := attr(global('importlib')!, 'util')!
 spec_factory := attr(first, 'spec_from_file_location') or {
  cause := err
  release([first])!
  return cause
 }
 release([first])!
 spec := existing(spec_factory, [o(name), o(path)]) or {
  cause := err
  release([spec_factory])!
  return cause
 }
 release([spec_factory])!
 second := attr(global('importlib')!, 'util')!
 module_factory := attr(second, 'module_from_spec') or {
  cause := err
  release([second])!
  return cause
 }
 release([second])!
 module_ := existing(module_factory, [o(spec)]) or {
  cause := err
  release([module_factory])!
  return cause
 }
 release([module_factory])!
 loader := attr(spec, 'loader')!
 executor := attr(loader, 'exec_module') or {
  cause := err
  release([loader])!
  return cause
 }
 release([loader])!
 result := existing(executor, [o(module_)]) or {
  cause := err
  release([executor])!
  return cause
 }
 release([executor, result, spec])!
 return module_
}

fn load_api(name string, path ah.Value) !ah.Value {
	if native('load')! { return load(literal(name)!, path)! }
	return rb.api('load', [v(name), o(path)], {}, true)!
}
fn release(ids []ah.Value) ! {
 rb.callback('release', {'ids': ah.Value(ids)})!
}

fn digest_contents(factory ah.Value, contents ah.Value) !ah.Value {
 hasher := rb.api('_invoke_existing', [o(factory), o(contents)], {}, true) or {
  cause := err
  release([factory, contents])!
  return cause
 }
 rb.callback('release', {'ids': ah.Value([factory, contents])})!
 result := method(hasher, 'hexdigest', []) or {
  cause := err
  release([hasher])!
  return cause
 }
 rb.callback('release', {'ids': ah.Value([hasher])})!
 return result
}
fn digest(path ah.Value) !ah.Value {
 factory := attr(global('hashlib')!, 'sha256')!
 contents := method(path, 'read_bytes', []) or {
  cause := err
  release([factory])!
  return cause
 }
 return digest_contents(factory, contents)!
}

fn digest_api(path ah.Value) !ah.Value {
	if native('digest')! { return digest(path)! }
	return rb.api('digest', [o(path)], {}, true)!
}
fn run(argv ah.Value, options map[string]ah.Value) ! { rb.call('invoke', 'subprocess', 'run', [o(argv)], options)! }
fn items(value ah.Value) !ah.Value { return rb.iter_object(method(value, 'items', [])!)! }
fn unpack(value ah.Value) ![]ah.Value { return rb.callback('unpack_pair', {'id': value})!.items() }
fn write_json(path ah.Value, value ah.Value) ! {
 writer := attr(path, 'write_text')!
 encoded := rb.call('acquire', 'json', 'dumps', [o(value)], {'indent': ah.Value(2)}) or {
  cause := err
  release([writer])!
  return cause
 }
 line := add(encoded, literal('\n')!) or {
  cause := err
  release([writer, encoded])!
  return cause
 }
 release([encoded])!
 result := rb.api('_invoke_existing', [o(writer), o(line)], {}, true) or {
  cause := err
  release([writer, line])!
  return cause
 }
 release([writer, line, result])!
}

fn exit(owner ah.Value, failed bool, cause IError) !bool {
	return rb.callback('exit', {'id': owner, 'error': if failed { ah.Value(boothost.failure(cause)) } else { rb.null() }})! == ah.Value(true)
}
