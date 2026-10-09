// SPDX-License-Identifier: GPL-2.0-or-later
module venusbuild

import androidhost as ah

fn generation(lavapipe string, mesa_inputs string, base string, tools string) !string {
	fields := dictionary()!
	set_item(fields, v(ah.Value('version')), o(constant('VERSION')!))!
	set_item(fields, v(ah.Value('source')), o(constant('SOURCE_SHA256')!))!
	set_item(fields, v(ah.Value('builder')), o(method(lavapipe, 'digest', [o(call('Path', o(constant('__file__')!))!)], {})!))!
	native_policy := dictionary()!
	sources := callback('function', {
		'target': ah.Value(item(attribute(lavapipe, '_native')!, v(ah.Value('policy_sources')))!)
		'args':   ah.Value([]ah.Value{})
	})!.text()
	paths := iterator(sources)!
	for {
		path := next(paths)!
		if path.done { break }
		relative := call('str', o(method(path.value, 'relative_to', [o(constant('REPO')!)], {})!))!
		set_item(native_policy, o(relative), o(method(lavapipe, 'digest', [o(path.value)], {})!))!
	}
	set_item(fields, v(ah.Value('native_policy')), o(native_policy))!
	set_item(fields, v(ah.Value('native_builder')), o(source_key(lavapipe)!))!
	set_item(fields, v(ah.Value('sysroot_packages')), o(get(mesa_inputs, 'packages')!))!
	patches := dictionary()!
	entries := iterator(constant('PATCHES')!)!
	for {
		patch := next(entries)!
		if patch.done { break }
		set_item(patches, o(attribute(patch.value, 'name')!), o(method(lavapipe, 'digest', [o(patch.value)], {})!))!
	}
	set_item(fields, v(ah.Value('patches')), o(patches))!
	set_item(fields, v(ah.Value('options')), o(constant('MESON_OPTIONS')!))!
	set_item(fields, v(ah.Value('python_packages')), o(constant('PYTHON_PACKAGES')!))!
	command := collection('list', [call('str', o(join(tools, 'clang')!))!,
		literal(ah.Value('--version'))!])!
	set_item(fields, v(ah.Value('clang')), o(invoke('subprocess.check_output', [o(command)], {
		'text': v(ah.Value(true))
	})!))!
	set_item(fields, v(ah.Value('base')), o(method(lavapipe, 'base_identity', [o(base)], {})!))!
	encoded := method(invoke('json.dumps', [o(fields)], {
		'sort_keys': v(ah.Value(true))
	})!, 'encode', [], {})!
	return method(call('hashlib.sha256', o(encoded))!, 'hexdigest', [], {})!
}

fn build(base_arg string, work_arg string, jobs string, refresh string) !string {
	lavapipe := call('load_lavapipe_builder')!
	base := method(base_arg, 'resolve', [], {})!
	work := method(work_arg, 'resolve', [], {})!
	if compare('eq', work, base)! || truth(call('operator.contains', o(attribute(base, 'parents')!), o(work))!)! || truth(call('operator.contains', o(attribute(work, 'parents')!), o(base))!)! {
		failure('SystemExit', [v(ah.Value('the Venus work directory must be separate from its base root'))])!
	}
	mesa_inputs := method(lavapipe, 'load_inputs', [], {})!
	tools := method(lavapipe, 'llvm_bin', [], {})!
	for name in ['clang', 'clang++', 'llvm-ar', 'llvm-strip', 'llvm-readelf'] {
		if !truth(method(join(tools, name)!, 'is_file', [], {})!)! {
			failure('SystemExit', [v(ah.Value('missing LLVM tool ' + name + ' in ' + text(tools)! + '; set VINIX_DOTA2_LLVM_BIN'))])!
		}
	}
	key := generation(lavapipe, mesa_inputs, base, tools)!
	output := join(work, 'out/libvulkan_virtio.so')!
	manifest := join(work, 'out/virtio_icd.x86_64.json')!
	marker := join(work, 'out/generation')!
	if !truth(refresh)! && truth(method(output, 'is_file', [], {})!)! && truth(method(manifest, 'is_file', [], {})!)! && truth(method(marker, 'is_file', [], {})!)! && compare('eq', method(method(marker, 'read_text', [], {})!, 'strip', [], {})!, literal(ah.Value(text(key)! + ' ' + text(method(lavapipe, 'digest', [o(output)], {})!)!))!)! {
		return collection('tuple', [output, manifest])!
	}
	downloads := join(work, 'downloads')!
	method(downloads, 'mkdir', [], {
		'parents':  v(ah.Value(true))
		'exist_ok': v(ah.Value(true))
	})!
	source := join(work, 'source')!
	objects := join(work, 'obj')!
	stamp := join(work, '.prepared-generation')!
	if truth(refresh)! || !truth(method(stamp, 'is_file', [], {})!)! || compare('ne', method(method(stamp, 'read_text', [], {})!, 'strip', [], {})!, key)! {
		invoke('print', [v(ah.Value('Preparing Mesa Venus source and amd64 development libraries'))], {
			'flush': v(ah.Value(true))
		})!
		call('prepare_source', o(lavapipe), o(downloads), o(source))!
		method(lavapipe, 'prepare_sysroot', [
			o(method(lavapipe, 'load_resolver', [], {})!),
			o(mesa_inputs),
			o(base),
			o(downloads),
			o(join(work, 'sysroot')!),
		], {})!
		if truth(method(objects, 'exists', [], {})!)! { call('shutil.rmtree', o(objects))! }
		method(stamp, 'write_text', [o(add(key, literal(ah.Value('\n'))!)!)], {})!
	}
	method(lavapipe, 'check_sources', [o(source), o(constant('PATCHED_SOURCE_SHA256')!),
		v(ah.Value('prepared Venus'))], {})!
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
		method(package_stamp, 'write_text', [o(add(method(literal(ah.Value('\n'))!, 'join', [o(constant('PYTHON_PACKAGES')!)], {})!, literal(ah.Value('\n'))!)!)], {})!
	}
	environment := call('_venus_mapping', o(constant('os.environ')!))!
	set_item(environment, v(ah.Value('PATH')), v(ah.Value(text(join(venv, 'bin')!)! + ':' + text(get(constant('os.environ')!, 'PATH')!)!)))!
	if !truth(method(join(objects, 'build.ninja')!, 'is_file', [], {})!)! {
		invoke('print', [v(ah.Value('Configuring amd64 Venus'))], {
			'flush': v(ah.Value(true))
		})!
		cross := call('write_cross_file', o(work), o(tools), o(lavapipe))!
		command := collection('list', [call('str', o(join(venv, 'bin/meson')!))!,
			literal(ah.Value('setup'))!, call('str', o(objects))!, call('str', o(source))!,
			literal(ah.Value('--cross-file'))!, call('str', o(cross))!])!
		extend(command, o(constant('MESON_OPTIONS')!))!
		method(lavapipe, 'logged', [o(command), o(work), o(join(work, 'configure.log')!),
			o(environment)], {})!
	}
	invoke('print', [v(ah.Value('Building amd64 Venus'))], {
		'flush': v(ah.Value(true))
	})!
	command := collection('list', [
		method(lavapipe, 'tool', [v(ah.Value('ninja'))], {})!,
		literal(ah.Value('-C'))!,
		call('str', o(objects))!,
		literal(ah.Value('-j'))!,
		call('str', o(jobs))!,
		constant('TARGET')!,
		literal(ah.Value('src/virtio/vulkan/virtio_icd.x86_64.json'))!,
	])!
	method(lavapipe, 'logged', [o(command), o(work), o(join(work, 'build.log')!), o(environment)], {})!
	built := call('operator.truediv', o(objects), o(constant('TARGET')!))!
	method(lavapipe, 'verify_library', [o(built), o(base), o(tools)], {})!
	method(attribute(output, 'parent')!, 'mkdir', [], {
		'exist_ok': v(ah.Value(true))
	})!
	for pair in [[built, output],
		[join(objects, 'src/virtio/vulkan/virtio_icd.x86_64.json')!, manifest]] {
		source_path := pair[0]
		destination := pair[1]
		partial := method(destination, 'with_name', [v(ah.Value('.' + text(attribute(destination, 'name')!)! + '.partial'))], {})!
		call('shutil.copy2', o(source_path), o(partial))!
		method(partial, 'replace', [o(destination)], {})!
	}
	method(marker, 'write_text', [v(ah.Value(text(key)! + ' ' + text(method(lavapipe, 'digest', [o(output)], {})!)! + '\n'))], {})!
	return collection('tuple', [output, manifest])!
}
