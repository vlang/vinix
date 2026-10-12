// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import gamehost
import hosttest
import json2
import os

pub fn llvm_tools() !string {
	configured := os.getenv('VINIX_DOTA2_LLVM_BIN')
	if configured != '' { return configured }
	if os.is_file('/opt/homebrew/opt/llvm/bin/clang') { return '/opt/homebrew/opt/llvm/bin' }
	return gamehost.parent(os.find_abs_path_of_executable('clang')!)
}

fn meson_string(value string) string {
	return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('\r', '\\r') + "'"
}

fn meson_list(values []string) string { return '[' + values.map(meson_string(it)).join(', ') + ']' }

pub fn write_driver_configuration(tools gamehost.Tools, work string, inputs map[string]json2.Any, compiler_tools string, venus bool) !string {
	sysroot := gamehost.path(work, 'sysroot')
	mut versions := os.ls(sysroot + '/usr/lib/gcc/x86_64-linux-gnu')!
	versions.sort()
	if versions.len == 0 { return error('no GCC development directory in sysroot') }
	gcc := sysroot + '/usr/lib/gcc/x86_64-linux-gnu/' + versions.last()
	flags := ['--target=x86_64-linux-gnu', '--sysroot=' + sysroot, '--gcc-install-dir=' + gcc]
	links := ['-fuse-ld=lld', '-Wl,-rpath-link,' + sysroot + '/usr/lib/x86_64-linux-gnu',
		'-Wl,-rpath-link,' + sysroot + '/lib/x86_64-linux-gnu']
	mut text := '[binaries]\nc = ' + meson_list([compiler_tools + '/clang', ...flags]) + '\ncpp = ' + meson_list([
		compiler_tools + '/clang++',
		...flags,
	]) + '\n'
	text += 'ar = ' + meson_string(compiler_tools + '/llvm-ar') + '\nstrip = ' + meson_string(compiler_tools + '/llvm-strip') + '\npkg-config = ' + meson_string(os.find_abs_path_of_executable('pkg-config')!) + '\n'
	if !venus {
		config := work + '/llvm-config'
		os.write_file(work + '/.llvm-config-version', text_field(inputs, 'llvm_version') + '\n')!
		tools.run([tools.root + '/build-support/run-v-tool.sh',
			tools.root + '/tests/native-runtime-tools/llvm-config.v', '--install', config])!
		text += 'llvm-config = ' + meson_string(config) + '\n'
	}
	text += "[host_machine]\nsystem = 'linux'\ncpu_family = 'x86_64'\ncpu = 'x86_64'\nendian = 'little'\n[properties]\nneeds_exe_wrapper = true\nsys_root = " + meson_string(sysroot) + '\n'
	text += 'pkg_config_libdir = ' + meson_list([
		sysroot + '/usr/lib/x86_64-linux-gnu/pkgconfig',
		sysroot + '/usr/share/pkgconfig',
	]) + '\n[built-in options]\n'
	if venus { text += "c_args = ['-D__vinix__']\ncpp_args = ['-D__vinix__']\n" }
	text += 'c_link_args = ' + meson_list(links) + '\ncpp_link_args = ' + meson_list(links) + '\n'
	os.write_file(work + '/cross.ini', text)!
	return work + '/cross.ini'
}

fn text_field(row map[string]json2.Any, name string) string { return field(row, name).str() }

fn driver_options(venus bool) []string {
	common := ['--prefix=/usr', '--libdir=lib/x86_64-linux-gnu', '--buildtype=release',
		'-Db_ndebug=true', '-Dplatforms=x11']
	if venus {
		return [...common, '-Dgallium-drivers=', '-Dvulkan-drivers=virtio', '-Dglx=disabled',
			'-Degl=disabled', '-Dgbm=disabled', '-Dopengl=false', '-Dgles1=disabled', '-Dgles2=disabled',
			'-Dllvm=disabled', '-Dshader-cache=disabled', '-Dxmlconfig=disabled', '-Dbuild-tests=false',
			'-Dtools=', '-Dvulkan-layers=', '-Dvalgrind=disabled', '-Dlibunwind=disabled']
	}
	return [...common, '-Dvulkan-drivers=swrast', '-Dgallium-drivers=swrast', '-Dglx=disabled',
		'-Degl=disabled', '-Dgbm=disabled', '-Dopengl=false', '-Dgles1=disabled', '-Dgles2=disabled',
		'-Dllvm=enabled', '-Dshared-llvm=enabled', '-Dbuild-tests=false', '-Dtools=', '-Dvulkan-layers=',
		'-Dvalgrind=disabled', '-Dlibunwind=disabled', '-Dlmsensors=disabled',
		'-Dgallium-vdpau=disabled', '-Dgallium-va=disabled', '-Dgallium-xa=disabled',
		'-Dgallium-omx=disabled', '-Dgallium-nine=false']
}

fn normalized_driver_paths(base string, work string) !(string, string) {
	source := hosttest.module_resolve(base)!
	destination := hosttest.module_resolve(work)!
	if source == destination || source.starts_with(destination + '/') || destination.starts_with(source + '/') {
		return error('the driver work directory must be separate from its base root')
	}
	return source, destination
}
