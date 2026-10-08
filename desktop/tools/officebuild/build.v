// SPDX-License-Identifier: GPL-2.0-or-later
module officebuild

import androidhost as ah

fn compile_app(args string, vroot string, module_root string, tls_objects string, name string) ! {
	source := call('operator.truediv', o(attribute(args, 'office_source')!), o(item(constant('APPS')!, o(name))!))!
	generated := call('operator.truediv', o(attribute(args, 'work')!), o(call('operator.add', o(name), v(ah.Value('.c')))!))!
	output := call('operator.truediv', o(attribute(args, 'work')!), o(call('operator.add', v(ah.Value('voffice-')), o(name))!))!
	command := call('builtins.list')!
	append(command, o(attribute(args, 'v')!))!
	for word in ['-new-compiler', '--no-parallel', '-no-memory-limit', '-os', 'linux', '-arch'] {
		append(command, v(ah.Value(word)))!
	}
	append(command, o(attribute(args, 'arch')!))!
	for word in ['-gc', 'none', '-manualfree', '-enable-globals', '-prod', '-d', 'glibc', '-d',
		'no_backtrace', '-d', 'ui2_headless', '-path'] {
		append(command, v(ah.Value(word)))!
	}
	append(command, o(call('operator.mod', v(ah.Value('@vlib|%s')), o(module_root))!))!
	append(command, v(ah.Value('-o')))!
	append(command, o(generated))!
	append(command, o(source))!
	invoke('run', [o(command)], {
		'quiet': v(ah.Value(true))
	})!
	command_cc := call('cc_base', o(args), o(vroot))!
	set_item(command_cc, o(call('builtins.slice', v(ah.Value(1)), v(ah.Value(1)))!), o(literal(ah.Value([
		'-static',
		'-nostdlib',
	].map(ah.Value(it))))!))!
	append(command_cc, v(ah.Value('-I')))!
	append(command_cc, o(attribute(args, 'office_source')!))!
	append(command_cc, v(ah.Value('-Wno-error=incompatible-function-pointer-types')))!
	append(command_cc, o(join(attribute(args, 'sysroot')!, 'usr/lib/crt1.o')!))!
	append(command_cc, o(join(attribute(args, 'sysroot')!, 'usr/lib/crti.o')!))!
	append(command_cc, o(join(attribute(args, 'gcclib')!, 'crtbeginT.o')!))!
	append(command_cc, o(generated))!
	extend(command_cc, o(tls_objects))!
	append(command_cc, o(call('operator.add', v(ah.Value('-L')), o(call('str', o(join(attribute(args, 'sysroot')!, 'usr/lib')!))!))!))!
	append(command_cc, o(call('operator.add', v(ah.Value('-L')), o(call('str', o(attribute(args, 'gcclib')!))!))!))!
	for word in ['-lgcc_eh', '-lc', '-lgcc', '-lm'] { append(command_cc, v(ah.Value(word)))! }
	append(command_cc, o(join(attribute(args, 'gcclib')!, 'crtend.o')!))!
	append(command_cc, o(join(attribute(args, 'sysroot')!, 'usr/lib/crtn.o')!))!
	append(command_cc, v(ah.Value('-fuse-ld=lld')))!
	if truth(attribute(args, 'llvm_bin')!)! {
		append(command_cc, o(call('operator.add', v(ah.Value('-B')), o(call('str', o(attribute(args, 'llvm_bin')!))!))!))!
	}
	append(command_cc, v(ah.Value('-o')))!
	append(command_cc, o(output))!
	invoke('run', [o(command_cc)], {
		'quiet': v(ah.Value(true))
	})!
	strip := collection('list', [attribute(args, 'strip')!, output])!
	invoke('run', [o(strip)], {
		'quiet': v(ah.Value(true))
	})!
	call('os.replace', o(output), o(call('output_binary', o(attribute(args, 'output')!), o(name))!))!
	invoke('print', [o(call('operator.mod', v(ah.Value('    built VOffice %s')), o(method(name, 'capitalize', [], {})!))!)], {
		'flush': v(ah.Value(true))
	})!
}

fn validate_inputs(args string) ! {
	required := [join(attribute(args, 'office_source')!, 'v.mod')!,
		join(attribute(args, 'office_source')!, 'cmd/excel/main.v')!,
		join(attribute(args, 'office_source')!, 'cmd/word/main.v')!,
		join(attribute(args, 'office_source')!, 'assets/logo.png')!,
		join(attribute(args, 'ui2_source')!, 'v.mod')!]
	missing := call('builtins.list')!
	for path in required {
		if !truth(method(path, 'is_file', [], {})!)! {
			append(missing, o(call('str', o(path))!))!
		}
	}
	if truth(missing)! {
		failure('RuntimeError', [v(ah.Value('missing VOffice/ui2 input: ' + text(method(literal(ah.Value(', '))!, 'join', [o(missing)], {})!)!))])!
	}
}

fn build_main(args string) ! {
	call('validate_inputs', o(args))!
	command := collection('list', [call('str', o(attribute(args, 'clang')!))!,
		literal(ah.Value('--print-resource-dir'))!])!
	resource := method(invoke('subprocess.check_output', [o(command)], {
		'text': v(ah.Value(true))
	})!, 'strip', [], {})!
	set_attr(args, 'clang_resource_include', o(join(call('Path', o(resource))!, 'include')!))!
	if !truth(method(attribute(args, 'clang_resource_include')!, 'is_dir', [], {})!)! {
		failure('RuntimeError', [v(ah.Value('Clang resource headers not found at ' + text(attribute(args, 'clang_resource_include')!)!))])!
	}
	vroot := call('compiler_root', o(attribute(args, 'v')!))!
	protected := collection('set', [method(call('Path.home')!, 'resolve', [], {})!,
		method(attribute(args, 'repo')!, 'resolve', [], {})!,
		method(attribute(args, 'office_source')!, 'resolve', [], {})!,
		method(attribute(args, 'ui2_source')!, 'resolve', [], {})!, method(vroot, 'resolve', [], {})!])!
	if compare('eq', method(attribute(args, 'output')!, 'resolve', [], {})!, method(attribute(args, 'work')!, 'resolve', [], {})!)! {
		failure('RuntimeError', [v(ah.Value('VOffice output and work directories must be different'))])!
	}
	output_resolved := method(attribute(args, 'output')!, 'resolve', [], {})!
	if truth(call('operator.contains', o(protected), o(output_resolved))!)! || compare('eq', output_resolved, call('Path', o(attribute(output_resolved, 'anchor')!))!)! {
		failure('RuntimeError', [v(ah.Value('refusing unsafe VOffice output directory: ' + text(output_resolved)!))])!
	}
	method(attribute(args, 'output')!, 'mkdir', [], {
		'parents':  v(ah.Value(true))
		'exist_ok': v(ah.Value(true))
	})!
	expected := call('builtins.set')!
	apps := constant('APPS')!
	app_iter := iterator(apps)!
	for {
		row := next(app_iter)!
		if row.done { break }
		method(expected, 'add', [o(call('operator.add', v(ah.Value('voffice-')), o(row.value))!)], {})!
	}
	binaries := iterator(method(attribute(args, 'output')!, 'glob', [v(ah.Value('voffice-*'))], {})!)!
	for {
		row := next(binaries)!
		if row.done { break }
		if !truth(call('operator.contains', o(expected), o(attribute(row.value, 'name')!))!)! && truth(method(row.value, 'is_file', [], {})!)! {
			method(row.value, 'unlink', [], {})!
		}
	}
	mut names := attribute(args, 'only')!
	if !truth(names)! { names = call('list', o(constant('APPS')!))! }
	shared := call('shared_build_key', o(args), o(vroot))!
	keys := dictionary()!
	key_names := iterator(names)!
	for {
		row := next(key_names)!
		if row.done { break }
		set_item(keys, o(row.value), o(call('app_build_key', o(args), o(shared), o(row.value))!))!
	}
	state := call('load_build_state', o(attribute(args, 'output')!))!
	mut cached := dictionary()!
	original_cached := method(state, 'get', [v(ah.Value('apps')), o(dictionary()!)], {})!
	entries := iterator(method(original_cached, 'items', [], {})!)!
	for {
		row := next(entries)!
		if row.done { break }
		pair := callback('unpack_pair', {
			'owner': ah.Value(row.value)
		})!.items().map(it.text())
		if truth(call('operator.contains', o(constant('APPS')!), o(pair[0]))!)! {
			set_item(cached, o(pair[0]), o(pair[1]))!
		}
	}
	if compare('ne', method(state, 'get', [v(ah.Value('shared_key'))], {})!, shared)! {
		cached = dictionary()!
	}
	dirty := call('builtins.list')!
	dirty_names := iterator(names)!
	for {
		row := next(dirty_names)!
		if row.done { break }
		if compare('ne', method(cached, 'get', [o(row.value)], {})!, item(keys, o(row.value))!)! || !truth(call('usable_cached_binary', o(attribute(args, 'output')!), o(row.value))!)! {
			append(dirty, o(row.value))!
		}
	}
	if !truth(dirty)! {
		call('print', o(call('operator.mod', v(ah.Value('    reusing %d cached VOffice applications')), o(call('len', o(names))!))!))!
		return
	}
	call('reset_directory', o(attribute(args, 'work')!), o(protected))!
	module_root := join(attribute(args, 'work')!, 'vmodules')!
	stage := collection('list', [constant('sys.executable')!,
		join(attribute(args, 'repo')!, 'desktop/tools/stage_ui2.py')!, join(module_root, 'ui2')!,
		attribute(args, 'ui2_source')!,
		join(attribute(args, 'repo')!, 'desktop/tools/ui2_vinix_backend.v')!])!
	call('run', o(stage))!
	call('os.symlink', o(method(attribute(args, 'office_source')!, 'resolve', [], {})!), o(join(module_root, 'office')!))!
	tls_objects := call('build_mbedtls', o(args), o(vroot))!
	builds := iterator(dirty)!
	for {
		row := next(builds)!
		if row.done { break }
		call('compile_app', o(args), o(vroot), o(module_root), o(tls_objects), o(row.value))!
	}
	if compare('ne', method(state, 'get', [v(ah.Value('shared_key'))], {})!, shared)! {
		cached = dictionary()!
	}
	completed := iterator(dirty)!
	for {
		row := next(completed)!
		if row.done { break }
		set_item(cached, o(row.value), o(item(keys, o(row.value))!))!
	}
	call('write_build_state', o(attribute(args, 'output')!), o(shared), o(cached))!
	reused := call('operator.sub', o(call('len', o(names))!), o(call('len', o(dirty))!))!
	if truth(reused)! {
		call('print', o(call('operator.mod', v(ah.Value('    built %d VOffice applications; reused %d cached')), o(collection('tuple', [
			call('len', o(dirty))!,
			reused,
		])!))!))!
	} else {
		call('print', o(call('operator.mod', v(ah.Value('    built %d VOffice applications')), o(call('len', o(dirty))!))!))!
	}
}
