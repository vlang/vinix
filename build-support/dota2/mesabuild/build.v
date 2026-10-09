// SPDX-License-Identifier: GPL-2.0-or-later
module mesabuild

import androidhost as ah

fn generation(inputs string, base string, tools string) !string {
	fields := dictionary()!
	set_item(fields, v(ah.Value('inputs')), o(inputs))!
	set_item(fields, v(ah.Value('builder')), o(call('digest', o(call('Path', o(constant('__file__')!))!))!))!
	native_policy := dictionary()!
	return generation_fields(fields, native_policy, inputs, base, tools)!
}

fn generation_fields(fields string, native_policy string, inputs string, base string, tools string) !string {
	sources := callback('function', {
		'target': ah.Value(item(constant('_native')!, v(ah.Value('policy_sources')))!)
		'args':   ah.Value([]ah.Value{})
	})!.text()
	paths := iterator(sources)!
	for {
		path := next(paths)!
		if path.done { break }
		relative := call('str', o(method(path.value, 'relative_to', [o(constant('REPO')!)], {})!))!
		set_item(native_policy, o(relative), o(call('digest', o(path.value))!))!
	}
	set_item(fields, v(ah.Value('native_policy')), o(native_policy))!
	// Original ordered provenance remains intact. New maintained builder inputs
	// are hashed separately so editing native source cannot reuse an old artifact.
	set_item(fields, v(ah.Value('native_builder')), o(source_key()!))!
	patches := dictionary()!
	names := iterator(get(inputs, 'patches')!)!
	for {
		name := next(names)!
		if name.done { break }
		path := call('operator.truediv', o(constant('SUPPORT')!), o(name.value))!
		set_item(patches, o(name.value), o(call('digest', o(path))!))!
	}
	set_item(fields, v(ah.Value('patches')), o(patches))!
	set_item(fields, v(ah.Value('options')), o(constant('MESON_OPTIONS')!))!
	set_item(fields, v(ah.Value('python_packages')), o(constant('PYTHON_PACKAGES')!))!
	command := collection('list', [call('str', o(join(tools, 'clang')!))!,
		literal(ah.Value('--version'))!])!
	set_item(fields, v(ah.Value('clang')), o(invoke('subprocess.check_output', [o(command)], {
		'text': v(ah.Value(true))
	})!))!
	set_item(fields, v(ah.Value('base')), o(call('base_identity', o(base))!))!
	encoded := method(invoke('json.dumps', [o(fields)], {
		'sort_keys': v(ah.Value(true))
	})!, 'encode', [], {})!
	return method(call('hashlib.sha256', o(encoded))!, 'hexdigest', [], {})!
}

fn build(base_arg string, work_arg string, jobs string, refresh string) !string {
	base := method(base_arg, 'resolve', [], {})!
	work := method(work_arg, 'resolve', [], {})!
	if compare('eq', work, base)! || truth(call('operator.contains', o(attribute(base, 'parents')!), o(work))!)! || truth(call('operator.contains', o(attribute(work, 'parents')!), o(base))!)! {
		failure('SystemExit', [v(ah.Value('the Lavapipe work directory must be separate from its base root'))])!
	}
	inputs := call('load_inputs')!
	llvm := join(base, 'usr/lib/x86_64-linux-gnu/libLLVM-15.so.1')!
	if !truth(method(llvm, 'is_file', [], {})!)! || compare('ne', call('digest', o(llvm))!, get(inputs, 'llvm_runtime_sha256')!)! {
		failure('SystemExit', [v(ah.Value('the base root lacks the pinned LLVM 15 runtime: ' + text(llvm)!))])!
	}
	tools := call('llvm_bin')!
	for name in ['clang', 'clang++', 'llvm-ar', 'llvm-strip', 'llvm-readelf'] {
		if !truth(method(join(tools, name)!, 'is_file', [], {})!)! {
			failure('SystemExit', [v(ah.Value('missing LLVM tool ' + name + ' in ' + text(tools)! + '; set VINIX_DOTA2_LLVM_BIN'))])!
		}
	}
	key := generation(inputs, base, tools)!
	output := join(work, 'out/libvulkan_lvp.so')!
	marker := join(work, 'out/generation')!
	if !truth(refresh)! && truth(method(output, 'is_file', [], {})!)! && truth(method(marker, 'is_file', [], {})!)! && compare('eq', method(method(marker, 'read_text', [], {})!, 'strip', [], {})!, literal(ah.Value(text(key)! + ' ' + text(call('digest', o(output))!)!))!)! {
		return output
	}
	resolver := call('load_resolver')!
	downloads := join(work, 'downloads')!
	method(downloads, 'mkdir', [], {
		'parents':  v(ah.Value(true))
		'exist_ok': v(ah.Value(true))
	})!
	source := join(work, 'source')!
	objects := join(work, 'obj')!
	stamp := join(work, '.prepared-generation')!
	if truth(refresh)! || !truth(method(stamp, 'is_file', [], {})!)! || compare('ne', method(method(stamp, 'read_text', [], {})!, 'strip', [], {})!, key)! {
		invoke('print', [v(ah.Value('Preparing pinned Mesa source and amd64 development libraries'))], {
			'flush': v(ah.Value(true))
		})!
		call('prepare_source', o(resolver), o(inputs), o(downloads), o(source))!
		call('prepare_sysroot', o(resolver), o(inputs), o(base), o(downloads), o(join(work, 'sysroot')!))!
		if truth(method(objects, 'exists', [], {})!)! { call('shutil.rmtree', o(objects))! }
		method(stamp, 'write_text', [o(add(key, literal(ah.Value('\n'))!)!)], {})!
	}
	call('check_sources', o(source), o(get(inputs, 'patched_source_sha256')!), v(ah.Value('prepared')))!
	venv := join(work, 'host-venv')!
	python := join(venv, 'bin/python3')!
	if !truth(method(python, 'exists', [], {})!)! {
		command := collection('list', [constant('sys.executable')!, literal(ah.Value('-m'))!,
			literal(ah.Value('venv'))!, call('str', o(venv))!])!
		invoke('subprocess.run', [o(command)], {
			'check': v(ah.Value(true))
		})!
	}
	package_stamp := join(venv, '.dota2-packages')!
	if !truth(method(package_stamp, 'is_file', [], {})!)! || compare('ne', method(method(package_stamp, 'read_text', [], {})!, 'splitlines', [], {})!, call('list', o(constant('PYTHON_PACKAGES')!))!)! {
		command := collection('list', [call('str', o(python))!, literal(ah.Value('-m'))!,
			literal(ah.Value('pip'))!, literal(ah.Value('install'))!, literal(ah.Value('--quiet'))!])!
		extend(command, o(constant('PYTHON_PACKAGES')!))!
		invoke('subprocess.run', [o(command)], {
			'check': v(ah.Value(true))
		})!
		text_packages := add(method(literal(ah.Value('\n'))!, 'join', [o(constant('PYTHON_PACKAGES')!)], {})!, literal(ah.Value('\n'))!)!
		method(package_stamp, 'write_text', [o(text_packages)], {})!
	}
	environment := call('_mesa_mapping', o(constant('os.environ')!))!
	path := text(join(venv, 'bin')!)! + ':' + text(get(constant('os.environ')!, 'PATH')!)!
	set_item(environment, v(ah.Value('PATH')), v(ah.Value(path)))!
	if !truth(method(join(objects, 'build.ninja')!, 'is_file', [], {})!)! {
		invoke('print', [v(ah.Value('Configuring amd64 Lavapipe'))], {
			'flush': v(ah.Value(true))
		})!
		cross := call('write_configuration', o(work), o(inputs), o(tools))!
		command := collection('list', [call('str', o(join(venv, 'bin/meson')!))!,
			literal(ah.Value('setup'))!, call('str', o(objects))!, call('str', o(source))!,
			literal(ah.Value('--cross-file'))!, call('str', o(cross))!])!
		extend(command, o(constant('MESON_OPTIONS')!))!
		call('logged', o(command), o(work), o(join(work, 'configure.log')!), o(environment))!
	}
	invoke('print', [v(ah.Value('Building amd64 Lavapipe'))], {
		'flush': v(ah.Value(true))
	})!
	command := collection('list', [call('tool', v(ah.Value('ninja')))!, literal(ah.Value('-C'))!,
		call('str', o(objects))!, literal(ah.Value('-j'))!, call('str', o(jobs))!, constant('TARGET')!])!
	call('logged', o(command), o(work), o(join(work, 'build.log')!), o(environment))!
	built := call('operator.truediv', o(objects), o(constant('TARGET')!))!
	call('verify_library', o(built), o(base), o(tools))!
	method(attribute(output, 'parent')!, 'mkdir', [], {
		'exist_ok': v(ah.Value(true))
	})!
	partial := method(output, 'with_name', [v(ah.Value('.libvulkan_lvp.so.partial'))], {})!
	call('shutil.copy2', o(built), o(partial))!
	method(partial, 'replace', [o(output)], {})!
	record := text(key)! + ' ' + text(call('digest', o(output))!)! + '\n'
	method(marker, 'write_text', [v(ah.Value(record))], {})!
	return output
}
