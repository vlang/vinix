// SPDX-License-Identifier: GPL-2.0-or-later
module venusbuild

import androidhost as ah

fn load_lavapipe_builder() !string {
	spec := call('importlib.util.spec_from_file_location', v(ah.Value('vinix_dota2_mesa_build')), o(method(call('Path', o(constant('__file__')!))!, 'with_name', [v(ah.Value('mesa-build.py'))], {})!))!
	builder := call('importlib.util.module_from_spec', o(spec))!
	set_item(constant('sys.modules')!, o(attribute(spec, 'name')!), o(builder))!
	method(attribute(spec, 'loader')!, 'exec_module', [o(builder)], {})!
	return builder
}

fn write_cross_file(work string, tools string, lavapipe string) !string {
	sysroot := join(work, 'sysroot')!
	gcc := item(call('sorted', o(method(join(sysroot, 'usr/lib/gcc/x86_64-linux-gnu')!, 'iterdir', [], {})!))!, v(ah.Value(-1)))!
	flags := words(['--target=x86_64-linux-gnu', '--sysroot=' + text(sysroot)!,
		'--gcc-install-dir=' + text(gcc)!])!
	links := words(['-fuse-ld=lld',
		'-Wl,-rpath-link,' + text(join(sysroot, 'usr/lib/x86_64-linux-gnu')!)!,
		'-Wl,-rpath-link,' + text(join(sysroot, 'lib/x86_64-linux-gnu')!)!])!
	cross := join(work, 'cross.ini')!
	c_args := collection('list', [call('str', o(join(tools, 'clang')!))!])!
	extend(c_args, o(flags))!
	cpp_args := collection('list', [call('str', o(join(tools, 'clang++')!))!])!
	extend(cpp_args, o(flags))!
	content := '[binaries]\nc = ' + text(call('builtins.repr', o(c_args))!)! + '\ncpp = ' + text(call('builtins.repr', o(cpp_args))!)! + '\n' +
		"ar = '" + text(join(tools, 'llvm-ar')!)! + "'\nstrip = '" + text(join(tools, 'llvm-strip')!)! + "'\npkg-config = '" + text(method(lavapipe, 'tool', [v(ah.Value('pkg-config'))], {})!)! + "'\n" +
		"[host_machine]\nsystem = 'linux'\ncpu_family = 'x86_64'\ncpu = 'x86_64'\nendian = 'little'\n[properties]\nneeds_exe_wrapper = true\nsys_root = '" + text(sysroot)! + "'\n" +
		"pkg_config_libdir = ['" + text(join(sysroot, 'usr/lib/x86_64-linux-gnu/pkgconfig')!)! + "', '" + text(join(sysroot, 'usr/share/pkgconfig')!)! + "']\n" +
		"[built-in options]\nc_args = ['-D__vinix__']\ncpp_args = ['-D__vinix__']\nc_link_args = " + text(call('builtins.repr', o(links))!)! + '\ncpp_link_args = ' + text(call('builtins.repr', o(links))!)! + '\n'
	method(cross, 'write_text', [v(ah.Value(content))], {})!
	return cross
}

fn prepare_source(lavapipe string, downloads string, source string) ! {
	archive := join(downloads, 'mesa-' + text(constant('VERSION')!)! + '.tar.xz')!
	if !truth(method(archive, 'is_file', [], {})!)! || compare('ne', method(lavapipe, 'digest', [o(archive)], {})!, constant('SOURCE_SHA256')!)! {
		partial := renamed(archive, '.partial')!
		command := collection('list', [method(lavapipe, 'tool', [v(ah.Value('curl'))], {})!])!
		extend(command, o(words(['--fail', '--location', '--retry', '3', '--silent', '--show-error',
			'--output'])!))!
		append(command, o(call('str', o(partial))!))!
		append(command, o(constant('SOURCE_URL')!))!
		invoke('subprocess.run', [o(command)], {
			'check': v(ah.Value(true))
		})!
		if compare('ne', method(lavapipe, 'digest', [o(partial)], {})!, constant('SOURCE_SHA256')!)! {
			method(partial, 'unlink', [], {})!
			failure('SystemExit', [v(ah.Value('Mesa ' + text(constant('VERSION')!)! + ' has an unexpected hash: ' + text(constant('SOURCE_URL')!)!))])!
		}
		method(partial, 'replace', [o(archive)], {})!
	}
	pending := renamed(source, '.pending')!
	if truth(method(pending, 'exists', [], {})!)! { call('shutil.rmtree', o(pending))! }
	method(pending, 'mkdir', [], {
		'parents': v(ah.Value(true))
	})!
	command := collection('list', [
		method(lavapipe, 'tool', [v(ah.Value('tar'))], {})!,
		literal(ah.Value('xJf'))!,
		call('str', o(archive))!,
		literal(ah.Value('-C'))!,
		call('str', o(pending))!,
		literal(ah.Value('--strip-components=1'))!,
	])!
	invoke('subprocess.run', [o(command)], {
		'check': v(ah.Value(true))
	})!
	entries := iterator(method(constant('PATCHES')!, 'items', [], {})!)!
	for {
		entry := next(entries)!
		if entry.done { break }
		pair := callback('unpack_pair', {
			'owner': ah.Value(entry.value)
		})!.items().map(it.text())
		patch := pair[0]
		expected := pair[1]
		if truth(expected)! && compare('ne', method(lavapipe, 'digest', [o(patch)], {})!, expected)! {
			failure('SystemExit', [v(ah.Value('Venus patch has an unexpected hash: ' + text(patch)!))])!
		}
		method(lavapipe, 'apply_patch', [o(pending), o(method(patch, 'read_bytes', [], {})!),
			o(attribute(patch, 'name')!)], {})!
	}
	method(lavapipe, 'check_sources', [o(pending), o(constant('PATCHED_SOURCE_SHA256')!),
		v(ah.Value('patched Venus'))], {})!
	if truth(method(source, 'exists', [], {})!)! { call('shutil.rmtree', o(source))! }
	method(pending, 'rename', [o(source)], {})!
}
