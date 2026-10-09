module runtimevm

import androidhost as ah
import runtimebuild as rb

fn loader_name(args ah.Value) !ah.Value {
	return add(add(literal('ld-musl-')!, attr(args, 'arch')!)!, literal('.so.1')!)!
}

fn runtime_dependencies(runtime ah.Value, files ah.Value) ! {
	pending := rb.make_sequence([v('libc_bio.so.0')])!
	added := builtin('set', [])!
	for flag(pending)! {
		name := method(pending, 'pop', [])!
		if flag(rb.call('acquire', 'operator', 'contains', [o(added), o(name)], {})!)! { continue }
		rb.method('invoke', added, 'add', [o(name)], {})!
		if rb.eq_value(name, ah.Value('libc.musl-aarch64.so.1'))! { continue }
		left := join(runtime, 'usr/lib')!
		right := join(runtime, 'lib') or {
			cause := err
			release([left])!
			return cause
		}
		directories := rb.callback('tuple', {'arguments': ah.Value([o(left), o(right)])})!
		generator := rb.api('_iter_project_test', [o(directories), o(name), v('is_file')], {}, true) or {
			cause := err
			release([directories, left, right])!
			return cause
		}
		rb.callback('release', {'ids': ah.Value([directories, left, right])})!
		source := builtin('next', [o(generator), rb.ordinary(rb.null())]) or {
			cause := err
			release([generator])!
			return cause
		}
		rb.callback('release', {'ids': ah.Value([generator])})!
		if rb.callback('is_none', {'id': source})! == ah.Value(true) {
			message := add(literal('Missing native Bionic dependency: ')!, name)!
			raise('RuntimeError', [o(message)])!
		}
		put(files, add(literal('runtime/lib/')!, name)!, source)!
		argv := rb.make_sequence([v('aarch64-linux-musl-readelf'), v('-d'), o(str(source)!)])!
		dynamic := rb.call('acquire', 'subprocess', 'check_output', [o(argv)], {'text': ah.Value(true)})!
		found := rb.call('acquire', 're', 'findall', [v(r'Shared library: \[([^]]+)\]'), o(dynamic)], {})!
		rb.method('invoke', pending, 'extend', [o(found)], {})!
	}
}

fn archive(root ah.Value, output ah.Value, arm ah.Value) ! {
	tar := rb.callback('enter', {
		'module': ah.Value('tarfile')
		'name': ah.Value('open')
		'arguments': ah.Value([o(output), v(if flag(arm)! { 'w:gz' } else { 'w' })])
		'keyword_objects': ah.Value({'format': attr(global('tarfile')!, 'USTAR_FORMAT')!})
	})!
	mut failed := false
	mut cause := IError(none)
	rb.method('invoke', tar, 'add', [o(root)], {'arcname': ah.Value('.')}) or { failed = true; cause = err }
	suppressed := exit(tar, failed, cause)!
	if failed && !suppressed { return cause }
}

fn main_workflow(args ah.Value, work ah.Value) ! {
	mkdir(work, false)!
	arm := rb.call('acquire', 'operator', 'eq', [o(attr(args, 'arch')!), v('aarch64')], {})!
	mut runtime := attr(args, 'runtime')!
	if !flag(runtime)! {
		runtime = join(global('ROOT')!, if flag(arm)! {
			'build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64'
		} else { 'build-aarch64-android/staging/opt/vinix-android' })!
	}
	mut native_root := attr(args, 'native_root')!
	if !flag(native_root)! { native_root = join(global('ROOT')!, if flag(arm)! { 'build-aarch64-userland/staging' } else { 'build-amd64-userland/staging' })! }
	key := if flag(arm)! { 'CC_ARM' } else { 'CC_X86' }
	cc := method(attr(global('os')!, 'environ')!, 'get', [v(key), o(add(attr(args, 'arch')!, literal('-linux-musl-gcc')!)!)])!
	tools := load_api('android_v_runtime', join(global('ROOT')!, 'build-support/android/compile-v-runtime.py')!)!
	rb.method('invoke', tools, 'build', [o(join(work, 'compat-v.so')!), o(cc), o(join(work, 'generated')!), v(if flag(arm)! { 'arm64' } else { 'amd64' })], {})!
	variants := rb.make_sequence([v('v')])!
	if flag(attr(args, 'baseline')!)! {
		copy(attr(args, 'baseline')!, join(work, 'baseline.c')!)!
		argv := rb.make_sequence([o(cc), v('-O2'), v('-Wall'), v('-Wextra'), v('-Werror'), v('-shared'), v('-fPIC'),
			v('-I'), o(str(join(global('ROOT')!, 'build-support/android')!)!), o(str(join(work, 'baseline.c')!)!), v('-ldl'), v('-o'), o(str(join(work, 'compat-c.so')!)!)])!
		run(argv, {'check': ah.Value(true)})!
		rb.method('invoke', variants, 'insert', [rb.ordinary(ah.Value(0)), v('c')], {})!
	}
	mut probes := ['runtime-stack-probe', 'memory-probe']
	if flag(arm)! { probes << ['atfork-test', 'fortify-test', 'mallinfo-test'] }
	root := join(work, 'root')!
	busybox := join(native_root, 'bin/busybox')!
	native_key := add(add(literal('lib/ld-musl-')!, attr(args, 'arch')!)!, literal('.so.1')!)!
	native_loader := join_object(join(native_root, 'lib')!, loader_name(args)!)!
	files := rb.dictionary([v('bin/busybox'), o(native_key)], [o(busybox), o(native_loader)])!
	for probe in probes {
		source := join(join(global('ROOT')!, 'tests/android')!, probe + '.c')!
		copy(source, join_object(work, attr(source, 'name')!)!)!
		target := join(work, probe)!
		argv := rb.make_sequence([o(cc), v('-O2'), v('-Wall'), v('-Wextra'), v('-Werror'), v('-I'),
			o(str(join(global('ROOT')!, 'build-support/android')!)!), o(str(join_object(work, attr(source, 'name')!)!)!),
			v('-ldl'), v('-pthread'), v('-o'), o(str(target)!)])!
		run(argv, {'check': ah.Value(true)})!
		put(files, literal('usr/bin/' + probe)!, target)!
	}
	variant_iter := rb.iter_object(variants)!
	for {
		variant := rb.next(variant_iter)!
		if variant == rb.null() { break }
		key_ := add(add(literal('runtime/compat-')!, variant)!, literal('.so')!)!
		filename := add(add(literal('compat-')!, variant)!, literal('.so')!)!
		put(files, key_, join_object(work, filename)!)!
	}
	private_loader := join_object(join(runtime, 'lib')!, loader_name(args)!)!
	put(files, add(add(literal('runtime/lib/ld-musl-')!, attr(args, 'arch')!)!, literal('.so.1')!)!, private_loader)!
	put(files, add(add(literal('runtime/lib/libc.musl-')!, attr(args, 'arch')!)!, literal('.so.1')!)!, private_loader)!
	if flag(arm)! { runtime_dependencies(runtime, files)! }
	file_iter := items(files)!
	for {
		pair := rb.next(file_iter)!
		if pair == rb.null() { break }
		values := unpack(pair)!
		target := join_object(root, values[0])!
		mkdir(attr(target, 'parent')!, true)!
		copy(values[1], target)!
	}
	for directory in ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root'] { mkdir(join(root, directory)!, true)! }
	for name in ['sh', 'sleep', 'mount'] { rb.method('invoke', join(join(root, 'bin')!, name)!, 'symlink_to', [v('busybox')], {})! }
	loader := add(add(literal('/runtime/lib/ld-musl-')!, attr(args, 'arch')!)!, literal('.so.1')!)!
	mut script := literal('#!/bin/sh\nset -eu\nexport PATH=/bin:/usr/bin VINIX_ALLOW_WX=1\nunset LD_PRELOAD LD_LIBRARY_PATH\nmount -t proc proc /proc 2>/dev/null || true\nulimit -s 32768\n')!
	if !flag(arm)! { script = rb.call('acquire', 'operator', 'iadd', [o(script), v('exec >/dev/com1 2>&1\n')], {})! }
	expected := rb.make_sequence([])!
	script_variants := rb.iter_object(variants)!
	for {
		variant_ := rb.next(script_variants)!
		if variant_ == rb.null() { break }
		variant := text(variant_)!
		script = rb.call('acquire', 'operator', 'iadd', [o(script), v('echo ANDROID-RUNTIME-BEGIN:' + variant + '\n')], {})!
		for probe in probes {
			mut probe_arguments := if probe in ['fortify-test', 'mallinfo-test'] { ' /runtime/compat-' + variant + '.so' } else { '' }
			if probe == 'fortify-test' { probe_arguments += ' /runtime/lib/libc_bio.so.0' }
			mut line := add(literal('LD_PRELOAD=/runtime/compat-' + variant + '.so ')!, loader)!
			for part in [' --library-path /runtime/lib /usr/bin/', probe, probe_arguments, '\n', 'echo ANDROID-RUNTIME-PASS:', variant, ':', probe, '\n'] { line = add(line, literal(part)!)! }
			script = rb.call('acquire', 'operator', 'iadd', [o(script), o(line)], {})!
			append(expected, literal('ANDROID-RUNTIME-PASS:' + variant + ':' + probe)!)!
		}
	}
	script = rb.call('acquire', 'operator', 'iadd', [o(script), v('echo ANDROID-RUNTIME-GUEST-END\nwhile :; do sleep 60; done\n')], {})!
	append(expected, literal('ANDROID-RUNTIME-GUEST-END')!)!
	rb.method('invoke', join(root, 'sbin/init')!, 'write_text', [o(script)], {})!
	rb.method('invoke', join(root, 'sbin/init')!, 'chmod', [rb.ordinary(ah.Value(0o755))], {})!
	kernel := join(work, 'kernel/bin/vinix')!
	mkdir(attr(kernel, 'parent')!, false)!
	copy(attr(args, 'kernel')!, kernel)!
	archive_ := join(work, if flag(arm)! { 'initramfs.tar.gz' } else { 'initramfs.tar' })!
	archive(root, archive_, arm)!
	inputs := input_record(args, work, root, kernel, archive_, tools, variants, probes, files)!
	write_json(join(work, 'inputs.json')!, inputs)!
	env := rb.callback('mapping_unpack', {'id': attr(global('os')!, 'environ')!})!
	command := vm_plan(work, kernel, archive_, arm, env)!
	runner := load_api('android_kernel_guest', join(global('ROOT')!, 'tests/kernel-gaps/run.py')!)!
	result := method(runner, 'boot', [o(command), o(env), o(work), o(expected), o(rb.make_sequence([
		v('KERNEL PANIC'), v('ANDROID-STACK-FAIL'), v('ANDROID-MEMORY-FAIL'), v('ANDROID-ATFORK-FAIL'), v('ANDROID-FORTIFY-FAIL'), v('ANDROID-MALLINFO-FAIL'),
	])!), o(attr(args, 'timeout')!)])!
	results := rb.callback('mapping_unpack', {'id': inputs})!
	put(results, literal('exit_code')!, result)!
	put(results, literal('expected_markers')!, expected)!
	write_json(join(work, 'results.json')!, results)!
	raise('SystemExit', [o(result)])!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	return match ah.field(row, 'operation').text() {
		'load' { rb.result_object(load(rb.borrow('name')!, rb.borrow('path')!)!) }
		'digest' { rb.result_object(digest(rb.borrow('path')!)!) }
		'main' { main_workflow(rb.borrow('args')!, rb.borrow('work')!)!; rb.null() }
		else { return error('Unknown Android runtime VM operation') }
	}
}
