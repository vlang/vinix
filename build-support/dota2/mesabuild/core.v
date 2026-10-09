// SPDX-License-Identifier: GPL-2.0-or-later
module mesabuild

import androidhost as ah

fn digest(path string) !string {
	hasher := call('hashlib.sha256')!
	manager := method(path, 'open', [v(ah.Value('rb'))], {})!
	stream := enter(manager)!
	owned_digest_body(manager, hasher, stream)!
	return method(hasher, 'hexdigest', [], {})!
}

fn owned_digest_body(manager string, hasher string, stream string) ! {
	digest_body(hasher, stream) or {
		cause := err
		if !retire(manager, cause)! { return cause }
		return
	}
	retire(manager, none)!
}

fn digest_body(hasher string, stream string) ! {
	reader := call('_mesa_reader', o(stream), v(ah.Value('read')), o(collection('tuple', [literal(ah.Value(1024 * 1024))!])!))!
	empty := callback('literal', {
		'value': ah.Value([ah.Value('bytes'), ah.Value('')])
	})!.text()
	chunks := iterator(call('iter', o(reader), o(empty))!)!
	for {
		chunk := next(chunks)!
		if chunk.done { break }
		method(hasher, 'update', [o(chunk.value)], {})!
	}
}

fn tool(name string) !string {
	value := call('shutil.which', o(name))!
	if !truth(value)! {
		failure('SystemExit', [v(ah.Value('missing build tool: ' + text(name)!))])!
	}
	return value
}

fn load_resolver() !string {
	spec := call('importlib.util.spec_from_file_location', v(ah.Value('vinix_debian_root')), o(join(constant('REPO')!, 'build-support/debian-root.py')!))!
	resolver := call('importlib.util.module_from_spec', o(spec))!
	set_item(constant('sys.modules')!, o(attribute(spec, 'name')!), o(resolver))!
	method(attribute(spec, 'loader')!, 'exec_module', [o(resolver)], {})!
	return resolver
}

fn load_inputs(path string) !string {
	inputs := call('json.loads', o(method(path, 'read_text', [], {})!))!
	invoke('_native_request', [v(ah.Value('mesa-pin')), o(call('builtins.bytes')!)], {
		'data': o(call('_policy_value', o(inputs))!)
		'path': o(call('str', o(path))!)
	})!
	return inputs
}

fn llvm_bin() !string {
	configured := method(constant('os.environ')!, 'get', [v(ah.Value('VINIX_DOTA2_LLVM_BIN'))], {})!
	if truth(configured)! { return call('Path', o(configured))! }
	homebrew := call('Path', v(ah.Value('/opt/homebrew/opt/llvm/bin')))!
	if truth(method(join(homebrew, 'clang')!, 'is_file', [], {})!)! { return homebrew }
	return attribute(call('Path', o(call('tool', v(ah.Value('clang')))!))!, 'parent')!
}

fn base_identity(base string) !string {
	hasher := call('hashlib.sha256')!
	for directory in ['lib/x86_64-linux-gnu', 'usr/lib/x86_64-linux-gnu', 'usr/lib/gcc/x86_64-linux-gnu'] {
		root := join(base, directory)!
		if !truth(method(root, 'is_dir', [], {})!)! { continue }
		entries := iterator(call('sorted', o(method(root, 'rglob', [v(ah.Value('*'))], {})!))!)!
		for {
			entry := next(entries)!
			if entry.done { break }
			relative := method(method(entry.value, 'relative_to', [o(base)], {})!, 'as_posix', [], {})!
			mut line := ''
			if truth(method(entry.value, 'is_symlink', [], {})!)! {
				line = text(relative)! + ' -> ' + text(call('os.readlink', o(entry.value))!)! + '\n'
			} else if truth(method(entry.value, 'is_file', [], {})!)! {
				line = text(relative)! + ' ' + text(attribute(method(entry.value, 'stat', [], {})!, 'st_size')!)! + '\n'
			} else {
				continue
			}
			method(hasher, 'update', [o(method(literal(ah.Value(line))!, 'encode', [], {})!)], {})!
		}
	}
	return method(hasher, 'hexdigest', [], {})!
}

fn logged(command string, directory string, log string, environment string) ! {
	manager := method(log, 'open', [v(ah.Value('w'))], {})!
	output := enter(manager)!
	result := invoke('subprocess.run', [o(command)], {
		'cwd':    o(directory)
		'env':    o(environment)
		'stdout': o(output)
		'stderr': o(constant('subprocess.STDOUT')!)
	}) or {
		cause := err
		if !retire(manager, cause)! { return cause }
		callback('unbound_local', {
			'name': ah.Value('result')
		})!
		return
	}
	retire(manager, none)!
	if truth(attribute(result, 'returncode')!)! {
		content := method(log, 'read_text', [], {
			'errors': v(ah.Value('replace'))
		})!
		lines := method(content, 'splitlines', [], {})!
		last := item(lines, o(call('builtins.slice', v(ah.Value(-35)), o(null()!))!))!
		message := method(literal(ah.Value('\n'))!, 'join', [o(last)], {})!
		invoke('print', [o(message)], {
			'file': o(constant('sys.stderr')!)
		})!
		failure('SystemExit', [v(ah.Value('Lavapipe build failed; see ' + text(log)!))])!
	}
}

fn apply_patch(source string, patch string, label string) ! {
	command := collection('list', [call('tool', v(ah.Value('patch')))!, literal(ah.Value('-p1'))!,
		literal(ah.Value('--batch'))!, literal(ah.Value('--forward'))!])!
	result := invoke('subprocess.run', [o(command)], {
		'cwd':    o(source)
		'input':  o(patch)
		'stdout': o(constant('subprocess.PIPE')!)
		'stderr': o(constant('subprocess.STDOUT')!)
	})!
	if truth(attribute(result, 'returncode')!)! {
		invoke('print', [o(method(attribute(result, 'stdout')!, 'decode', [], {
			'errors': v(ah.Value('replace'))
		})!)], {
			'file': o(constant('sys.stderr')!)
		})!
		failure('SystemExit', [v(ah.Value('patch does not apply to the pinned Mesa source: ' + text(label)!))])!
	}
}

fn check_sources(source string, expected string, label string) ! {
	entries := iterator(method(expected, 'items', [], {})!)!
	for {
		entry := next(entries)!
		if entry.done { break }
		pair := callback('unpack_pair', {
			'owner': ah.Value(entry.value)
		})!.items().map(it.text())
		path := call('operator.truediv', o(source), o(pair[0]))!
		if !truth(method(path, 'is_file', [], {})!)! || compare('ne', call('digest', o(path))!, pair[1])! {
			failure('SystemExit', [v(ah.Value(text(label)! + ' Mesa source has an unexpected hash: ' + text(pair[0])!))])!
		}
	}
}
