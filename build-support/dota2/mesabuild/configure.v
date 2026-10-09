// SPDX-License-Identifier: GPL-2.0-or-later
module mesabuild

import androidhost as ah

fn write_configuration(work string, inputs string, tools string) !string {
	sysroot := join(work, 'sysroot')!
	config := join(work, 'llvm-config')!
	version := dictionary()!
	set_item(version, v(ah.Value('version')), o(get(inputs, 'llvm_version')!))!
	method(config, 'write_text', [o(call('operator.mod', o(constant('LLVM_CONFIG')!), o(version))!)], {})!
	method(config, 'chmod', [v(ah.Value(0o755))], {})!
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
	content := '[binaries]\n' +
		'c = ' + text(call('builtins.repr', o(c_args))!)! + '\n' +
		'cpp = ' + text(call('builtins.repr', o(cpp_args))!)! + '\n' +
		"ar = '" + text(join(tools, 'llvm-ar')!)! + "'\n" +
		"strip = '" + text(join(tools, 'llvm-strip')!)! + "'\n" +
		"pkg-config = '" + text(call('tool', v(ah.Value('pkg-config')))!)! + "'\n" +
		"llvm-config = '" + text(config)! + "'\n" +
		"[host_machine]\nsystem = 'linux'\ncpu_family = 'x86_64'\ncpu = 'x86_64'\nendian = 'little'\n" +
		"[properties]\nneeds_exe_wrapper = true\nsys_root = '" + text(sysroot)! + "'\n" +
		"pkg_config_libdir = ['" + text(join(sysroot, 'usr/lib/x86_64-linux-gnu/pkgconfig')!)! + "', '" + text(join(sysroot, 'usr/share/pkgconfig')!)! + "']\n" +
		'[built-in options]\nc_link_args = ' + text(call('builtins.repr', o(links))!)! + '\n' +
		'cpp_link_args = ' + text(call('builtins.repr', o(links))!)! + '\n'
	method(cross, 'write_text', [v(ah.Value(content))], {})!
	return cross
}

fn native_sources() !string {
	sources := call('builtins.list')!
	for relative in ['build-support/dota2/mesa_query.v', 'build-support/dota2/mesabuild',
		'build-support/dota2/androidhost', 'build-support/dota2/boothost',
		'build-support/dota2/packagestore', 'tools/packagestore', 'tools/_package_store_native.py',
		'build-support/native_host.py', 'build-support/android/_boot_native.py',
		'build-support/run-v-tool.sh', 'build-support/find-v.sh'] {
		path := join(constant('REPO')!, relative)!
		append(sources, o(path))!
		if truth(method(path, 'is_dir', [], {})!)! {
			entries := iterator(call('sorted', o(method(path, 'rglob', [v(ah.Value('*'))], {})!))!)!
			for {
				entry := next(entries)!
				if entry.done { break }
				if truth(method(entry.value, 'is_file', [], {})!)! {
					append(sources, o(entry.value))!
				}
			}
		}
	}
	return sources
}

fn source_key() !string {
	hashes := dictionary()!
	paths := iterator(native_sources()!)!
	for {
		path := next(paths)!
		if path.done { break }
		relative := call('str', o(method(path.value, 'relative_to', [o(constant('REPO')!)], {})!))!
		if truth(method(path.value, 'is_symlink', [], {})!)! {
			set_item(hashes, o(relative), o(call('os.readlink', o(path.value))!))!
		} else if truth(method(path.value, 'is_file', [], {})!)! {
			set_item(hashes, o(relative), o(call('digest', o(path.value))!))!
		}
	}
	return hashes
}
