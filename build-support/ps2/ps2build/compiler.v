// SPDX-License-Identifier: MIT
module ps2build

import androidhost as ah

fn str(id string) !string { return call('str', o(id))! }

fn append(id string, value string) ! { method(id, 'append', [o(value)], {})! }

fn extend(id string, value string) ! { method(id, 'extend', [o(value)], {})! }

fn pair(id string) ![]string {
	return callback('unpack_pair', {
		'owner': ah.Value(id)
	})!.items().map(it.text())
}

fn tuple(a string, b string) !string { return collection('tuple', [a, b])! }

fn compile_one(path string, context string) !string {
	source := get(context, 'source')!
	name := attribute(path, 'name')!
	cpp := compare('eq', attribute(path, 'suffix')!, lit('.cpp')!)! || compare('eq', name, lit('bridge.c')!)!
	relative := if truth(call('operator.contains', o(attribute(path, 'parents')!), o(source))!)! {
		method(path, 'relative_to', [o(source)], {})!
	} else {
		call('Path', o(name))!
	}
	target := call('operator.truediv', o(get(context, 'obj')!), o(call('operator.add', o(method(str(relative)!, 'replace', [
		v(ah.Value('/')),
		v(ah.Value('_')),
	], {})!), v(ah.Value('.o')))!))!
	command := call('operator.add', o(list([str(join(get(context, 'llvm')!, if cpp {
		'clang++'
	} else {
		'clang'
	})!)!])!), o(get(context, 'common')!))!
	if cpp { extend(command, get(context, 'cxx')!)! }
	if compare('eq', name, lit('bridge.c')!)! {
		extend(command, words(['-x', 'c++'])!)!
	} else {
		extend(command, list([lit('-include')!, str(join(global('SUPPORT')!, 'include/core.h')!)!,
			lit('-D__assert_fail=vinix_ps2_core_assert')!])!)!
	}
	if compare('eq', name, lit('spu2.c')!)! {
		extend(command, words(['-Dps2_spu2_init=vinix_ps2_unused_spu2_init',
			'-Dps2_spu2_destroy=vinix_ps2_unused_spu2_destroy'])!)!
	}
	extend(command, list([lit('-c')!, str(path)!, lit('-o')!, str(target)!])!)!
	record := call('builtins.dict')!
	set(record, 'command', command)!
	set(record, 'source', public('sha256', [path], {})!)!
	set(record, 'headers', global('SOURCE_SHA256')!)!
	for row in [['shim', 'include/SDL3/SDL.h'], ['exit_shim', 'include/core.h'],
		['bridge_header', 'bridge.h'], ['native_abi', 'vbridge/native-abi.h']] {
		set(record, row[0], public('sha256', [join(global('SUPPORT')!, row[1])!], {})!)!
	}
	set(record, 'compiler', get(context, 'compiler')!)!
	set(record, 'libc', get(context, 'libc')!)!
	fingerprint := invoke('json.dumps', [o(record)], {
		'sort_keys': v(ah.Value(true))
	})!
	stamp := method(target, 'with_suffix', [v(ah.Value('.stamp'))], {})!
	if exists(target)! && exists(stamp)! && compare('eq', method(stamp, 'read_text', [], {})!, fingerprint)! {
		return tuple(target, bytes('')!)!
	}
	process := invoke('subprocess.run', [o(command)], {
		'stdout': o(global('subprocess.PIPE')!)
		'stderr': o(global('subprocess.STDOUT')!)
	})!
	if truth(attribute(process, 'returncode')!)! {
		output := method(attribute(process, 'stdout')!, 'decode', [], {
			'errors': v(ah.Value('replace'))
		})!
		failed('RuntimeError', 'compile failed: ' + text(path)! + '\n' + text(output)!, none)!
	}
	method(stamp, 'write_text', [o(fingerprint)], {})!
	return tuple(target, attribute(process, 'stdout')!)!
}

fn compile_pool(files string, worker string, jobs string) !string {
	manager := invoke('ThreadPoolExecutor', [], {
		'max_workers': o(jobs)
	})!
	pool := enter(manager)!
	value := pool_body(pool, files, worker) or {
		if !retire(manager, err)! { return err }
		return ''
	}
	retire(manager, none)!
	return value
}

fn pool_body(pool string, files string, worker string) !string {
	return call('list', o(method(pool, 'map', [o(worker), o(files)], {})!))!
}

fn pool_policy(files string, worker string, jobs string, log string) !string {
	value := compile_pool(files, worker, jobs) or {
		cause := err
		if !(callback('exception_matches', {
			'error': detail(cause)
			'class': ah.Value(global('Exception')!)
		})! as bool) {
			return cause
		}
		activate(cause)!
		original := callback('error_object', {
			'error': detail(cause)
		})!.text()
		method(log, 'write_text', [o(str(original)!)], {})!
		return cause
	}
	if value == '' {
		callback('unbound_local', {
			'name': ah.Value('results')
		})!
	}
	chunks := list([])!
	items := iterator(value)!
	for {
		item := next(items)!
		if item.done { break }
		parts := pair(item.value)!
		append(chunks, parts[1])!
	}
	method(log, 'write_bytes', [o(method(bytes('')!, 'join', [o(chunks)], {})!)], {})!
	return value
}
