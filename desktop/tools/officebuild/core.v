// SPDX-License-Identifier: GPL-2.0-or-later
module officebuild

import androidhost as ah

fn run(command string, quiet string) ! {
	normalized := call('builtins.list')!
	iter := iterator(command)!
	for {
		row := next(iter)!
		if row.done { break }
		append(normalized, o(call('str', o(row.value))!))!
	}
	result := invoke('subprocess.run', [o(normalized)], {
		'text':   v(ah.Value(true))
		'stdout': o(if truth(quiet)! { constant('subprocess.PIPE')! } else { null()! })
		'stderr': o(if truth(quiet)! { constant('subprocess.STDOUT')! } else { null()! })
	})!
	if truth(attribute(result, 'returncode')!)! {
		if truth(quiet)! && truth(attribute(result, 'stdout')!)! {
			method(constant('sys.stderr')!, 'write', [o(attribute(result, 'stdout')!)], {})!
		}
		failure('subprocess.CalledProcessError', [o(attribute(result, 'returncode')!), o(command)])!
	}
}

fn load_build_state(output string) !string {
	state := read_state(output) or {
		if matches(err, ['FileNotFoundError', 'json.JSONDecodeError', 'OSError'])! {
			return dictionary()!
		}
		return err
	}
	if compare('ne', method(state, 'get', [v(ah.Value('version'))], {})!, constant('CACHE_VERSION')!)! {
		return dictionary()!
	}
	if !truth(call('isinstance', o(method(state, 'get', [v(ah.Value('apps'))], {})!), o(constant('dict')!))!)! {
		return dictionary()!
	}
	return state
}

fn matches(cause IError, names []string) !bool {
	mut classes := []string{}
	for name in names { classes << constant(name)! }
	return callback('exception_matches', {
		'error': detail(cause)
		'class': ah.Value(collection('tuple', classes)!)
	})! as bool
}

fn read_state(output string) !string {
	return call('json.loads', o(method(join(output, text(constant('CACHE_STATE_NAME')!)!)!, 'read_text', [], {})!))!
}

fn write_build_state(output string, shared string, apps string) ! {
	state := dictionary()!
	set_item(state, v(ah.Value('version')), o(constant('CACHE_VERSION')!))!
	set_item(state, v(ah.Value('shared_key')), o(shared))!
	set_item(state, v(ah.Value('apps')), o(apps))!
	temporary := call('operator.truediv', o(output), o(call('operator.add', o(constant('CACHE_STATE_NAME')!), o(call('operator.mod', v(ah.Value('.tmp.%d')), o(call('os.getpid')!))!))!))!
	content := call('operator.add', o(invoke('json.dumps', [o(state)], {
		'indent':    v(ah.Value(2))
		'sort_keys': v(ah.Value(true))
	})!), v(ah.Value('\n')))!
	method(temporary, 'write_text', [o(content)], {})!
	call('os.replace', o(temporary), o(join(output, text(constant('CACHE_STATE_NAME')!)!)!))!
}

fn output_binary(output string, name string) !string {
	return call('operator.truediv', o(output), o(call('operator.add', v(ah.Value('voffice-')), o(name))!))!
}

fn usable_cached_binary(output string, name string) !string {
	binary := call('output_binary', o(output), o(name))!
	return cached_binary(binary) or {
		if matches(err, ['OSError'])! { return literal(ah.Value(false))! }
		return err
	}
}

fn cached_binary(binary string) !string {
	mut result := method(binary, 'is_file', [], {})!
	if truth(result)! {
		result = call('operator.gt', o(attribute(method(binary, 'stat', [], {})!, 'st_size')!), v(ah.Value(0)))!
	}
	if truth(result)! { result = call('os.access', o(binary), o(constant('os.X_OK')!))! }
	return result
}

fn reset_directory(path string, protected string) ! {
	resolved := method(path, 'resolve', [], {})!
	if truth(call('operator.contains', o(protected), o(resolved))!)! || compare('eq', resolved, call('Path', o(attribute(resolved, 'anchor')!))!)! {
		failure('RuntimeError', [v(ah.Value('refusing unsafe VOffice build directory: ' + text(resolved)!))])!
	}
	if truth(method(path, 'exists', [], {})!)! { call('shutil.rmtree', o(path))! }
	method(path, 'mkdir', [], {
		'parents': v(ah.Value(true))
	})!
}

fn compiler_root(compiler string) !string {
	root := attribute(method(compiler, 'resolve', [], {})!, 'parent')!
	required := [join(root, 'vlib')!, join(root, 'thirdparty/mbedtls')!]
	mut all := true
	for path in required {
		if !truth(method(path, 'is_dir', [], {})!)! {
			all = false
			break
		}
	}
	if !all {
		failure('RuntimeError', [v(ah.Value(text(compiler)! + ' must be an executable in a V source checkout with bundled mbedTLS'))])!
	}
	return root
}

fn cc_base(args string, vroot string) !string {
	mbedtls := join(vroot, 'thirdparty/mbedtls')!
	command := collection('list', [attribute(args, 'clang')!,
		call('operator.add', v(ah.Value('--target=')), o(attribute(args, 'target')!))!,
		literal(ah.Value('-nostdinc'))!])!
	if truth(attribute(args, 'cc_shim')!)! {
		extend(command, o(collection('list', [literal(ah.Value('-isystem'))!,
			attribute(args, 'cc_shim')!])!))!
	}
	if truth(method(attribute(args, 'target')!, 'startswith', [v(ah.Value('aarch64-'))], {})!)! {
		extend(command, o(collection('list', [literal(ah.Value('-isystem'))!,
			attribute(args, 'clang_resource_include')!])!))!
	}
	for path in [join(attribute(args, 'gcclib')!, 'include')!,
		join(attribute(args, 'sysroot')!, 'usr/include')!] {
		append(command, v(ah.Value('-isystem')))!
		append(command, o(path))!
	}
	for path in ['include', 'library', '3rdparty/everest/include', '3rdparty/everest/include/everest',
		'3rdparty/everest/include/everest/kremlib'] {
		append(command, v(ah.Value('-I')))!
		append(command, o(join(mbedtls, path)!))!
	}
	extend(command, o(literal(ah.Value(['-O2', '-fno-stack-protector', '-w'].map(ah.Value(it))))!))!
	return command
}

fn mbedtls_sources(vroot string) !string {
	manifest := join(vroot, 'vlib/net/mbedtls/mbedtls.c.v')!
	source := method(manifest, 'read_text', [], {})!
	names := call('re.findall', v(ah.Value(r'^#flag @VEXEROOT/thirdparty/mbedtls/(.+)\.o$')), o(source), o(constant('re.MULTILINE')!))!
	if !truth(names)! {
		failure('RuntimeError', [v(ah.Value('could not find bundled mbedTLS object inventory'))])!
	}
	outputs := call('builtins.list')!
	iter := iterator(names)!
	for {
		row := next(iter)!
		if row.done { break }
		append(outputs, o(call('Path', o(call('operator.add', o(row.value), v(ah.Value('.c')))!))!))!
	}
	return outputs
}

fn compile_mbedtls_source(args string, vroot string, objects string, source string) !string {
	mbedtls := join(vroot, 'thirdparty/mbedtls')!
	prefix := item(attribute(source, 'parts')!, o(call('builtins.slice', o(null()!), v(ah.Value(-1)))!))!
	stem := collection('tuple', [attribute(source, 'stem')!])!
	basename := method(literal(ah.Value('_'))!, 'join', [o(call('operator.add', o(prefix), o(stem))!)], {})!
	output := call('operator.truediv', o(objects), o(call('operator.add', o(basename), v(ah.Value('.o')))!))!
	tail := collection('list', [literal(ah.Value('-c'))!,
		call('operator.truediv', o(mbedtls), o(source))!, literal(ah.Value('-o'))!, output])!
	invoke('run', [o(call('operator.add', o(call('cc_base', o(args), o(vroot))!), o(tail))!)], {
		'quiet': v(ah.Value(true))
	})!
	return output
}

fn build_mbedtls(args string, vroot string) !string {
	objects := join(attribute(args, 'work')!, 'mbedtls')!
	method(objects, 'mkdir', [], {
		'parents': v(ah.Value(true))
	})!
	sources := call('mbedtls_sources', o(vroot))!
	workers := call('max', v(ah.Value(1)), o(attribute(args, 'jobs')!))!
	manager := invoke('concurrent.futures.ThreadPoolExecutor', [], {
		'max_workers': o(workers)
	})!
	executor := enter(manager)!
	outputs := mbedtls_workers(executor, args, vroot, objects, sources) or {
		cause := err
		if !retire(manager, cause)! { return cause }
		return callback('unbound_local', {
			'name': ah.Value('outputs')
		})!.text()
	}
	retire(manager, none)!
	invoke('print', [o(call('operator.mod', v(ah.Value('    built %d bundled mbedTLS objects')), o(call('len', o(outputs))!))!)], {
		'flush': v(ah.Value(true))
	})!
	return outputs
}

fn mbedtls_workers(executor string, args string, vroot string, objects string, sources string) !string {
	futures := call('builtins.list')!
	iter := iterator(sources)!
	for {
		row := next(iter)!
		if row.done { break }
		append(futures, o(method(executor, 'submit', [
			o(constant('compile_mbedtls_source')!),
			o(args),
			o(vroot),
			o(objects),
			o(row.value),
		], {})!))!
	}
	outputs := call('builtins.list')!
	pending := iterator(futures)!
	for {
		row := next(pending)!
		if row.done { break }
		append(outputs, o(method(row.value, 'result', [], {})!))!
	}
	return outputs
}
