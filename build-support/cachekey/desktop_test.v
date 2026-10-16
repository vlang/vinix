// SPDX-License-Identifier: GPL-2.0-or-later
module cachekey

import os

#include <fcntl.h>
#include <stdlib.h>

fn C.utimensat(i32, &char, &C.timespec, i32) i32
fn C.mkdtemp(&u8) &char

fn fixture_write(path string, text string) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, text)!
}

fn desktop_fixture(root string) !(string, map[string]string) {
	v := root + '/tools/v'
	fixture_write(v, 'compiler\n')!
	os.chmod(v, 0o755)!
	llvm := root + '/tools/llvm'
	for name in ['clang', 'llvm-strip'] {
		fixture_write(llvm + '/' + name, name + '\n')!
		os.chmod(llvm + '/' + name, 0o755)!
	}
	for name in ['ld.lld', 'host-clang', 'ld64.lld'] {
		fixture_write(root + '/tools/' + name, name + '\n')!
		os.chmod(root + '/tools/' + name, 0o755)!
	}
	for item in [
		['desktop/main.v', 'module main\n'],
		['third_party/ui2/v.mod', "Module { name: 'ui2' }\n"],
		['build-aarch64-x11/staging/usr/lib/libx.so', 'one\n'],
		['build-aarch64-x11/sysroot/usr/lib/Scrt1.o', 'crt\n'],
		['build-aarch64-userland/staging/usr/lib/libc.a', 'libc\n'],
		['build-support/init-aarch64/initramfs.tar', 'base\n'],
		['build-aarch64-minecraft/staging/usr/bin/minecraft', 'game\n'],
	] {
		fixture_write(root + '/' + item[0], item[1])!
	}
	mut env := os.environ()
	env.delete('VINIX_PACKAGE_IMAGE_CONFIG')
	env.delete('VINIX_PACKAGE_IMAGE_REPOSITORIES')
	for name, value in {
		'LLVM_BIN':                         llvm
		'LD_LLD':                           root + '/tools/ld.lld'
		'CLANG':                            root + '/tools/host-clang'
		'LD64_LLD':                         root + '/tools/ld64.lld'
		'VINIX_AARCH64_USERLAND_BUILD_DIR': root + '/build-aarch64-userland'
		'VINIX_X11_STAGING':                root + '/build-aarch64-x11/staging'
		'VINIX_GPU_SYSROOT':                root + '/build-aarch64-x11/sysroot'
	} {
		env[name] = value
	}
	return v, env
}

fn desktop_temporary() !string {
	mut pattern := (os.temp_dir().trim_right('/') + '/vinix-desktop-key-XXXXXX\x00').bytes()
	if isnil(C.mkdtemp(pattern.data)) { return file_error(pattern.bytestr()) }
	return pattern[..pattern.len - 1].bytestr()
}

fn fixture_key(root string, v string, env map[string]string) !string {
	input := desktop_prepare(root, v, env, os.executable())!
	return desktop_native_complete(input, env, 'fixture platform', '', 'missing')
}

fn test_cache_native_producer_dependencies_invalidate() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, env := desktop_fixture(root)!
	for name in ['build-support/cachecli/core.v', 'build-support/cachekey/shell_words.v',
		'build-support/content-key', 'build-support/content-key.v',
		'build-support/staging-cache', 'build-support/staging-cache.v',
		'build-support/desktop-build-key', 'build-support/desktop-build-key.v',
		'desktop/tools/officenative/core.v', 'desktop/tools/build_voffice.v'] {
		path := root + '/' + name
		fixture_write(path, 'original native producer\n')!
		first := fixture_key(root, v, env)!
		fixture_write(path, 'changed native producer\n')!
		assert first != fixture_key(root, v, env)!, name
	}
}

fn test_source_content_change_invalidates() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, env := desktop_fixture(root)!
	first := fixture_key(root, v, env)!
	fixture_write(root + '/desktop/main.v', 'module main\nconst changed = true\n')!
	assert first != fixture_key(root, v, env)!
}

fn test_release_package_configuration_content_and_selection_invalidate() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, mut env := desktop_fixture(root)!
	unenrolled := fixture_key(root, v, env)!
	configuration := root + '/release/config.json'
	fixture_write(configuration, 'first reviewed release configuration\n')!
	env['VINIX_PACKAGE_IMAGE_CONFIG'] = configuration
	first := fixture_key(root, v, env)!
	assert first != unenrolled
	mut state := C.vinix_cache_stat{}
	assert C.vinix_cache_lstat(&char(configuration.str), &state) == 0
	fixture_write(configuration, 'other reviewed release configuration\n')!
	stamps := [C.timespec{state.st_atime, state.vinix_cache_atime_nsec}, C.timespec{state.st_mtime, state.vinix_cache_mtime_nsec}]!
	assert C.utimensat(C.AT_FDCWD, &char(configuration.str), &stamps[0], 0) == 0
	assert first != fixture_key(root, v, env)!
	env.delete('VINIX_PACKAGE_IMAGE_CONFIG')
	assert fixture_key(root, v, env)! == unenrolled
}

fn test_image_repository_content_and_selection_invalidate() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, mut env := desktop_fixture(root)!
	unenrolled := fixture_key(root, v, env)!
	bundle := root + '/release/repositories'
	object := bundle + '/native/objects/payload'
	fixture_write(object, 'first offline application payload\n')!
	env['VINIX_PACKAGE_IMAGE_REPOSITORIES'] = bundle
	first := fixture_key(root, v, env)!
	assert first != unenrolled
	mut state := C.vinix_cache_stat{}
	assert C.vinix_cache_lstat(&char(object.str), &state) == 0
	fixture_write(object, 'other offline application payload\n')!
	stamps := [C.timespec{state.st_atime, state.vinix_cache_atime_nsec}, C.timespec{state.st_mtime, state.vinix_cache_mtime_nsec}]!
	assert C.utimensat(C.AT_FDCWD, &char(object.str), &stamps[0], 0) == 0
	assert first != fixture_key(root, v, env)!
	env.delete('VINIX_PACKAGE_IMAGE_REPOSITORIES')
	assert fixture_key(root, v, env)! == unenrolled
}

fn test_v_launcher_change_invalidates() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, env := desktop_fixture(root)!
	launcher := root + '/build-support/v-command'
	fixture_write(launcher, 'old launcher\n')!
	first := fixture_key(root, v, env)!
	fixture_write(launcher, 'new launcher\n')!
	assert first != fixture_key(root, v, env)!
}

fn test_wifi_native_producer_dependencies_invalidate() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, env := desktop_fixture(root)!
	for name in ['tools/m1-wifi/compile-v.v', 'tools/m1-wifi/wifihost/generator.v',
		'tests/linuxkpi/hosttest/module_text.v', 'tools/m1-wifi/core/native.v'] {
		path := root + '/' + name
		fixture_write(path, 'original producer source\n')!
		first := fixture_key(root, v, env)!
		fixture_write(path, 'changed producer source\n')!
		assert first != fixture_key(root, v, env)!, name
	}
}

fn test_m1_triangle_source_change_invalidates() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, env := desktop_fixture(root)!
	triangle := root + '/gl-triangle/eglcore/core.v'
	fixture_write(triangle, 'module egltri\nfn main() { return 0 }\n')!
	first := fixture_key(root, v, env)!
	fixture_write(triangle, 'module egltri\nfn main() { return 1 }\n')!
	assert first != fixture_key(root, v, env)!
}

fn test_dictionary_native_producer_dependencies_invalidate() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, env := desktop_fixture(root)!
	for name in ['build-support/dictionary/prepare.v',
		'build-support/dictionary/dictionarycore/core.v', 'tools/sourcecommand/core.v'] {
		path := root + '/' + name
		fixture_write(path, 'original dictionary producer\n')!
		first := fixture_key(root, v, env)!
		fixture_write(path, 'changed dictionary producer\n')!
		assert first != fixture_key(root, v, env)!, name
	}
}

fn test_musl_native_producer_dependencies_invalidate() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, env := desktop_fixture(root)!
	for name in ['build-support/musl/stage', 'build-support/musl/stage.v',
		'build-support/muslnative/publication.v'] {
		path := root + '/' + name
		fixture_write(path, 'original musl producer\n')!
		first := fixture_key(root, v, env)!
		fixture_write(path, 'changed musl producer\n')!
		assert first != fixture_key(root, v, env)!, name
	}
}

fn test_nested_x11_rewrite_invalidates_in_place() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, env := desktop_fixture(root)!
	library := root + '/build-aarch64-x11/staging/usr/lib/libx.so'
	first := fixture_key(root, v, env)!
	mut state := C.vinix_cache_stat{}
	assert C.vinix_cache_lstat(&char(library.str), &state) == 0
	fixture_write(library, 'two\n')!
	stamps := [C.timespec{state.st_atime, state.vinix_cache_atime_nsec},
		C.timespec{state.st_mtime, state.vinix_cache_mtime_nsec}]!
	assert C.utimensat(C.AT_FDCWD, &char(library.str), &stamps[0], 0) == 0
	mut restored := C.vinix_cache_stat{}
	assert C.vinix_cache_lstat(&char(library.str), &restored) == 0
	assert restored.st_mtime == state.st_mtime && restored.vinix_cache_mtime_nsec == state.vinix_cache_mtime_nsec
	assert first != fixture_key(root, v, env)!
}

fn test_replaced_layer_root_invalidates() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, env := desktop_fixture(root)!
	staging := root + '/build-aarch64-minecraft/staging'
	first := fixture_key(root, v, env)!
	os.rename_dir(staging, root + '/old-staging')!
	os.mkdir_all(staging)!
	fixture_write(staging + '/usr/bin/minecraft', 'game\n')!
	assert first != fixture_key(root, v, env)!
}

fn test_replaced_v_layer_invalidates() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, env := desktop_fixture(root)!
	staging := root + '/build-aarch64-v/staging'
	fixture_write(staging + '/usr/bin/v', 'first compiler\n')!
	first := fixture_key(root, v, env)!
	os.rename_dir(staging, root + '/old-v-staging')!
	fixture_write(staging + '/usr/bin/v', 'second compiler\n')!
	assert first != fixture_key(root, v, env)!
}

fn test_compiler_generation_invalidates() {
	root := desktop_temporary()!
	defer { os.rmdir_all(root) or { panic(err) } }
	v, env := desktop_fixture(root)!
	first := fixture_key(root, v, env)!
	replacement := root + '/tools/v-new'
	fixture_write(replacement, 'compiler two\n')!
	os.chmod(replacement, 0o755)!
	os.rename(replacement, v)!
	assert first != fixture_key(root, v, env)!
}
