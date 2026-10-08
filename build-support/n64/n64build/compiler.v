// SPDX-License-Identifier: MIT
module n64build

import androidhost as ah

fn pair(id string) ![]string {
	return callback('unpack_pair', {
		'owner': ah.Value(id)
	})!.items().map(it.text())
}

fn str(id string) !string { return call('str', o(id))! }

fn tuple(a string, b string) !string { return collection('tuple', [a, b])! }

fn flags(values string, cpp bool) !string {
	raw := call('shlex.split', o(get(values, if cpp { 'CXX_FLAGS' } else { 'C_FLAGS' })!))!
	result := list([])!
	iter := iterator(raw)!
	for {
		item := next(iter)!
		if item.done { break }
		if !compare('eq', item.value, lit('-MMD')!)! && !truth(method(item.value, 'startswith', [v(ah.Value('-DGIT_VERSION='))], {})!)! {
			method(result, 'append', [o(item.value)], {})!
		}
	}
	return result
}

fn revision() !string { return slice(global('REVISION')!, null()!, literal(ah.Value(7))!)! }

fn compile_one(item string, context string) !string {
	items := pair(item)!
	path, cpp := items[0], truth(items[1])!
	source := get(context, 'source')!
	relative := if truth(call('operator.contains', o(attribute(path, 'parents')!), o(source))!)! {
		method(path, 'relative_to', [o(source)], {})!
	} else {
		call('Path', o(attribute(path, 'name')!))!
	}
	name := call('operator.add', o(method(str(relative)!, 'replace', [
		v(ah.Value('/')),
		v(ah.Value('_')),
	], {})!), v(ah.Value('.o')))!
	target := call('operator.truediv', o(get(context, 'obj')!), o(name))!
	command_flags := flags(get(context, 'values')!, cpp)!
	method(command_flags, 'append', [o(lit('-DGIT_VERSION=" ' + text(revision()!)! + '"')!)], {})!
	command := list([str(join(get(context, 'llvm')!, if cpp { 'clang++' } else { 'clang' })!)!])!
	command_with_flags := call('operator.add', o(command), o(command_flags))!
	mut actual := call('operator.add', o(command_with_flags), o(get(context, 'common')!))!
	if cpp { method(actual, 'extend', [o(get(context, 'cxx')!)], {})! }
	name_id := attribute(path, 'name')!
	if compare('eq', name_id, lit('pure_interp.c')!)! || compare('eq', name_id, lit('rsp.c')!)! {
		method(actual, 'extend', [o(words(['-include', text(join(global('SUPPORT')!, 'budget.h')!)!])!)], {})!
	}
	method(actual, 'extend', [o(list([lit('-c')!, str(path)!, lit('-o')!, str(target)!])!)], {})!
	fingerprints := call('builtins.dict')!
	set(fingerprints, 'command', actual)!
	set(fingerprints, 'source', public('sha256', [path], {})!)!
	for key in ['headers', 'compiler', 'libc'] { set(fingerprints, key, get(context, key)!)! }
	fingerprint := invoke('json.dumps', [o(fingerprints)], {
		'sort_keys': v(ah.Value(true))
	})!
	stamp := method(target, 'with_suffix', [v(ah.Value('.stamp'))], {})!
	if exists(target)! && exists(stamp)! && compare('eq', method(stamp, 'read_text', [], {})!, fingerprint)! {
		return tuple(target, bytes('')!)!
	}
	process := invoke('subprocess.run', [o(actual)], {
		'cwd':    o(source)
		'stdout': o(global('subprocess.PIPE')!)
		'stderr': o(global('subprocess.STDOUT')!)
	})!
	if truth(attribute(process, 'returncode')!)! {
		output := invoke_member_decode(attribute(process, 'stdout')!)!
		failed('RuntimeError', 'compile failed: ' + text(path)! + '\n' + text(output)!, none)!
	}
	method(stamp, 'write_text', [o(fingerprint)], {})!
	return tuple(target, attribute(process, 'stdout')!)!
}

fn invoke_member_decode(data string) !string {
	return method(data, 'decode', [], {
		'errors': v(ah.Value('replace'))
	})!
}

fn context_dict(source string, obj string, llvm string, values string, common string, cxx string, headers string, compiler string, libc string) !string {
	result := call('builtins.dict')!
	for row in [['source', source], ['obj', obj], ['llvm', llvm], ['values', values],
		['common', common], ['cxx', cxx], ['headers', headers], ['compiler', compiler], ['libc',
			libc]] {
		set(result, row[0], row[1])!
	}
	return result
}

fn compile_files(files string, context string, jobs string) !string {
	manager := invoke('ThreadPoolExecutor', [], {
		'max_workers': o(jobs)
	})!
	pool := enter(manager)!
	result := compile_pool(pool, files, context) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return ''
	}
	retire(manager, none)!
	return result
}

fn compile_pool(pool string, files string, context string) !string {
	worker := invoke('functools.partial', [o(global('_compile_one')!)], {
		'context': o(context)
	})!
	return call('list', o(method(pool, 'map', [o(worker), o(files)], {})!))!
}

fn pool_policy(files string, context string, jobs string, log string) !string {
	result := compile_files(files, context, jobs) or {
		failure := err
		if !callback('exception_matches', {
			'error': detail(failure)
			'class': ah.Value(global('Exception')!)
		})! as bool {
			return failure
		}
		activate(failure)!
		error_object := callback('error_object', {
			'error': detail(failure)
		})!.text()
		method(log, 'write_text', [o(str(error_object)!)], {})!
		return failure
	}
	if result == '' {
		callback('unbound_local', {
			'name': ah.Value('results')
		})!
	}
	chunks := list([])!
	iter := iterator(result)!
	for {
		item := next(iter)!
		if item.done { break }
		parts := pair(item.value)!
		method(chunks, 'append', [o(parts[1])], {})!
	}
	method(log, 'write_bytes', [o(method(bytes('')!, 'join', [o(chunks)], {})!)], {})!
	return result
}
