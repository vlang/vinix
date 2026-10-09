module atlcontroller

import androidhost as ah
import runtimebuild as rb

fn workflow(args ah.Value, state ah.Value, debug bool) ! {
	checkpoint := rb.callback('checkpoint', {})!
	defer { rb.callback('release_since', {'id': checkpoint}) or {} }
	mut names := Names{}
	repo := g('ROOT')!
	support := names.named('support', join(repo, 'build-support/android')!)!
	art := names.named('art', join(repo, 'build-aarch64-android/aarch64/art-runtime')!)!
	native := names.named('native', join(repo, 'build-aarch64-userland/staging')!)!
	directories := names.named('directories', seq([o(join(art, 'usr/lib/art')!),
		o(join(repo, 'build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib')!),
		o(join(native, 'lib')!), o(join(native, 'usr/lib')!), o(join(repo, 'build-aarch64-x11/staging/usr/lib')!)])!)!
	provider := names.named('provider', join(state, 'src/libandroid/configuration.c')!)!
	mkdir(attr(provider, 'parent')!, false)!
	original := names.named('original_provider', join(repo, 'build-aarch64-android/source/atl/src/libandroid/configuration.c')!)!
	copy(original, provider)!
	patch_text := method(join(support, 'atl-configuration.patch')!, 'read_text', [])!
	patch_parts := method(patch_text, 'split', [v('\n--- a/'), rb.ordinary(ah.Value(1))])!
	patch_first := method(patch_parts, '__getitem__', [rb.ordinary(ah.Value(0))])!
	patch := names.named('patch', plus(patch_first, '\n')!)!
	release([patch_text, patch_parts, patch_first])!
	if debug && !flag(method(patch, 'startswith', [v('--- a/src/libandroid/configuration.c\n')])!)! { rb.api('_assert_false', [], {}, false)! }
	statement(attr(join(state, 'configuration.patch')!, 'write_text')!, [o(patch)], {})!
	patch_run := factory('subprocess', 'run')!
	patch_argv := seq([v('patch'), v('--batch'), v('--fuzz=0'), v('-p1'), v('-i'), temp(str(join(state, 'configuration.patch')!)!)])!
	discard(temporary_call(patch_run, [o(patch_argv)], {'check': ah.Value(true)}, {'cwd': state}, [patch_argv])!)!
	sysroot := names.named('sysroot', join(repo, 'build-aarch64-userland/sysroot')!)!
	sort := name_target('sorted')!
	gcc_values := method(join(native, 'usr/lib/gcc/aarch64-alpine-linux-musl')!, 'iterdir', [])!
	gcc_sorted := invoke(sort, [o(gcc_values)], {})!
	gcc := names.named('gcc', method(gcc_sorted, '__getitem__', [rb.ordinary(ah.Value(-1))])!)!
	release([gcc_sorted, gcc_values])!
	cc := names.named('cc', seq([o(method(attr(g('os')!, 'environ')!, 'get', [v('CC'), v('/opt/homebrew/opt/llvm/bin/clang')])!),
		v('--target=aarch64-linux-musl'), o(add(literal('--sysroot=')!, str(sysroot)!)!), o(add(literal('--gcc-install-dir=')!, str(gcc)!)!)])!)!
	flags := names.named('flags', seq([v('-O2'), v('-Wall'), v('-Wextra'), v('-Werror'), o(add(literal('-I')!, str(join(art, 'usr/include')!)!)!)])!)!
	provider_object := names.named('provider_object', join(state, 'configuration.o')!)!
	compile := factory('subprocess', 'run')!
	compile_argv := concat(cc, flags, [v('-D_LARGEFILE64_SOURCE'), v('-c'), temp(str(provider)!), v('-o'), temp(str(provider_object)!)])!
	discard(temporary_call(compile, [o(compile_argv)], {'check': ah.Value(true)}, {}, [compile_argv])!)!
	baseline := names.named('baseline', join(state, 'baseline.c')!)!
	writer := attr(baseline, 'write_bytes')!
	git := factory('subprocess', 'check_output')!
	git_argv := seq([v('git'), v('show'), o(plus(attr(args, 'baseline_rev')!, ':build-support/android/atl-configuration-test.c')!)])!
	baseline_bytes := temporary_call(git, [o(git_argv)], {}, {'cwd': repo}, [git_argv]) or {
		cause := err
		release([writer])!
		return cause
	}
	discard(temporary_call(writer, [o(baseline_bytes)], {}, {}, [baseline_bytes])!)!
	generated := names.named('generated', join(state, 'probe.c')!)!
	generate := factory('subprocess', 'run')!
	generate_argv := seq([v('python3'), temp(str(join(support, 'compile-v-atl-configuration.py')!)!), temp(str(generated)!)])!
	discard(temporary_call(generate, [o(generate_argv)], {'check': ah.Value(true)}, {}, [generate_argv])!)!
	x86_generated := names.named('x86_generated', join(state, 'probe-x86.c')!)!
	generate_x86 := factory('subprocess', 'run')!
	x86_argv := seq([v('python3'), temp(str(join(support, 'compile-v-atl-configuration.py')!)!), temp(str(x86_generated)!), v('--arch'), v('amd64')])!
	discard(temporary_call(generate_x86, [o(x86_argv)], {'check': ah.Value(true)}, {}, [x86_argv])!)!
	x86_compile := factory('subprocess', 'run')!
	x86_prefix := seq([o(method(attr(g('os')!, 'environ')!, 'get', [v('CC_AMD64'), v('x86_64-linux-musl-gcc')])!)])!
	x86_compile_argv := concat(x86_prefix, flags, [v('-Wno-unused-function'), v('-Wno-unused-parameter'), o(add(literal('-I')!, str(support)!)!),
		v('-c'), temp(str(x86_generated)!), v('-o'), temp(str(join(state, 'probe-x86.o')!)!)])!
	release([x86_prefix])!
	discard(temporary_call(x86_compile, [o(x86_compile_argv)], {'check': ah.Value(true)}, {}, [x86_compile_argv])!)!
	probes := names.named('probes', rb.dictionary([], [])!)!
	for index, tag in ['c', 'v'] {
		tag_ := names.named('tag', literal(tag)!)!
		source := names.named('source', rb.callback('retain', {'value': o(if index == 0 { baseline } else { generated })})!)!
		program := names.named('program', join_id(state, add(literal('probe-')!, tag_)!)!)!
		mut library_flags := seq([])!
		iterator := iterator(directories)!
		for {
			directory := rb.next(iterator)!
			if directory == rb.null() { break }
			append(library_flags, add(literal('-L')!, str(directory)!)!)!
			append(library_flags, add(literal('-Wl,-rpath-link,')!, str(directory)!)!)!
			release([directory])!
		}
		release([iterator])!
		library_flags = names.named('library_flags', library_flags)!
		link := factory('subprocess', 'run')!
		link_argv := concat(cc, flags, [v('-Wno-unused-function'), v('-Wno-unused-parameter'), o(add(literal('-I')!, str(support)!)!), temp(str(source)!), temp(str(provider_object)!)])!
		extend(link_argv, library_flags)!
		for value in ['-landroidfw', '-lpng', '-fuse-ld=lld', '-Wl,-z,max-page-size=65536', '-o'] { append(link_argv, literal(value)!)! }
		append(link_argv, str(program)!)!
		discard(temporary_call(link, [o(link_argv)], {'check': ah.Value(true)}, {}, [link_argv])!)!
		put(probes, tag_, program)!
	}
	golden := names.named('golden', literal('ATL-CONFIGURATION-PASS snapshot=asset-manager owned-copy=verified matching=androidfw\n')!)!
	if flag(attr(args, 'linux_host')!)! {
		iterator := items(probes)!
		for {
			row := rb.next(iterator)!
			if row == rb.null() { break }
			values := pair(row)!
			tag := names.named('tag', values[0])!
			program := names.named('program', values[1])!
			target := factory('subprocess', 'check_output')!
			host := attr(args, 'linux_host')!
			loader_text := str(join(native, 'lib/ld-musl-aarch64.so.1')!)!
			join_paths := attr(literal(':')!, 'join')!
			map_factory := name_target('map')!
			str_target := name_target('str')!
			mapped := invoke(map_factory, [o(str_target), o(directories)], {})!
			release([str_target])!
			paths := temporary_call(join_paths, [o(mapped)], {}, {}, [mapped])!
			argv := seq([v('limactl'), v('shell'), o(host), o(loader_text),
				v('--library-path'), o(paths), temp(str(program)!)])!
			output := names.named('output', temporary_call(target, [o(argv)], {'text': ah.Value(true)}, {}, [argv, host, loader_text, paths])!)!
			if debug && !equal(output, golden)! { rb.api('_assert_message', [o(name_call('repr', [o(output)])!)], {}, false)! }
			log := join_id(state, plus(add(literal('linux-')!, tag)!, '.log')!)!
			statement(attr(log, 'write_text')!, [o(output)], {})!
			release([row])!
		}
		release([iterator])!
	}
	root := names.named('root', join(state, 'root')!)!
	files := names.named('files', rb.dictionary([v('bin/busybox'), v('lib/ld-musl-aarch64.so.1')], [o(join(native, 'bin/busybox')!), o(join(native, 'lib/ld-musl-aarch64.so.1')!)])!)!
	pending := names.named('pending', seq([])!)!
	probes_iter := items(probes)!
	for {
		row := rb.next(probes_iter)!
		if row == rb.null() { break }
		values := pair(row)!
		tag := names.named('tag', values[0])!
		program := names.named('program', values[1])!
		put(files, add(literal('probe-')!, tag)!, program)!
		append(pending, program)!
		release([row])!
	}
	release([probes_iter])!
	seen := names.named('seen', name_call('set', [])!)!
	for flag(pending)! {
		source := names.named('source', method(pending, 'pop', [])!)!
		readelf := factory('subprocess', 'check_output')!
		argv := seq([v('aarch64-linux-musl-readelf'), v('-d'), temp(str(source)!)])!
		dynamic := names.named('dynamic', temporary_call(readelf, [o(argv)], {'text': ah.Value(true)}, {}, [argv])!)!
		found := invoke(factory('re', 'findall')!, [v(r'Shared library: \[([^]]+)\]'), o(dynamic)], {})!
		iterator := iterator(found)!
		release([found])!
		for {
			value := rb.next(iterator)!
			if value == rb.null() { break }
			name := names.named('name', value)!
			if flag(rb.call('acquire', 'operator', 'contains', [o(seen), o(name)], {})!)! { continue }
			discard(method(seen, 'add', [o(name)])!)!
			generator := rb.api('_iter_project_test', [o(directories), v('is_file')], {}, true)!
			mut dependency := name_call('next', [o(generator), rb.ordinary(rb.null())]) or {
				cause := err
				release([generator])!
				return cause
			}
			release([generator])!
			dependency = names.named('dependency', dependency)!
			if flag(rb.call('acquire', 'operator', 'is_', [o(dependency), rb.ordinary(rb.null())], {})!)! {
				raise('RuntimeError', [o(add(literal('Missing selected native provider dependency: ')!, name)!)])!
			}
			put(files, add(literal('lib/')!, name)!, dependency)!
			append(pending, dependency)!
		}
		release([iterator])!
	}
	files_iter := items(files)!
	for {
		row := rb.next(files_iter)!
		if row == rb.null() { break }
		values := pair(row)!
		name := names.named('name', values[0])!
		source := names.named('source', values[1])!
		target := names.named('target', join_id(root, name)!)!
		mkdir(attr(target, 'parent')!, true)!
		copy(source, target)!
		release([row])!
	}
	release([files_iter])!
	for directory in ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root'] {
		names.named('directory', literal(directory)!)!
		mkdir(join(root, directory)!, true)!
	}
	for name in ['sh', 'mount', 'sleep'] {
		names.named('name', literal(name)!)!
		discard(method(join(join(root, 'bin')!, name)!, 'symlink_to', [v('busybox')])!)!
	}
	mut script := names.named('script', literal('#!/bin/sh\nset -eu\nexport PATH=/bin LD_LIBRARY_PATH=/lib\nmount -t proc proc /proc 2>/dev/null || true\n')!)!
	script_iter := iterator(probes)!
	for {
		value := rb.next(script_iter)!
		if value == rb.null() { break }
		tag := names.named('tag', value)!
		mut line := add(literal('/probe-')!, tag)!
		line = plus(line, '\necho ATL-NATIVE-PASS:')!
		line = plus(add(line, tag)!, '\n')!
		script = names.named('script', rb.call('acquire', 'operator', 'iadd', [o(script), o(line)], {})!)!
	}
	release([script_iter])!
	script = names.named('script', rb.call('acquire', 'operator', 'iadd', [o(script), v('echo ATL-NATIVE-GUEST-PASS\nwhile :; do sleep 60; done\n')], {})!)!
	statement(attr(join(root, 'sbin/init')!, 'write_text')!, [o(script)], {})!
	discard(method(join(root, 'sbin/init')!, 'chmod', [rb.ordinary(ah.Value(0o755))])!)!
	archive_ := names.named('archive', join(state, 'initramfs.tar.gz')!)!
	archive(root, archive_, mut names)!
	environ := attr(g('os')!, 'environ')!
	mut env := rb.callback('mapping_unpack', {'id': environ})!
	release([environ])!
	put_env(env, 'VINIX_KERNEL_DIR', str(method(attr(args, 'kernel_dir')!, 'resolve', [])!)!)!
	put_env(env, 'VINIX_INITRAMFS', str(archive_)!)!
	put_env(env, 'VINIX_INITRAMFS_COMPRESSED', literal('1')!)!
	put_env(env, 'VINIX_BOOT_DISK', str(join(state, 'boot.img')!)!)!
	put_env(env, 'VINIX_BOOT_DISK_SIZE_MB', literal('128')!)!
	put_env(env, 'VINIX_EFIVARS', str(join(state, 'efivars.fd')!)!)!
	put_env(env, 'VINIX_QEMU_HOST_SOURCE', literal('0')!)!
	put_env(env, 'VINIX_QEMU_ROOT_DISK', literal('0')!)!
	put_env(env, 'VINIX_QEMU_PACKAGE_STORE', str(join(state, 'packages.tar')!)!)!
	put_env(env, 'VINIX_QEMU_PACKAGE_PERSIST', literal('0')!)!
	put_env(env, 'VINIX_QEMU_AUDIO', literal('off')!)!
	put_env(env, 'VINIX_QEMU_NETWORK', literal('0')!)!
	put_env(env, 'VINIX_QEMU_SMP', literal('2')!)!
	put_env(env, 'VINIX_QEMU_EXTRA', plus(add(literal('-qmp unix:')!, str(join(state, 'qmp.sock')!)!)!, ',server=on,wait=off')!)!
	env = names.named('env', env)!
	for name in ['VINIX_QEMU_GUEST_INIT', 'VINIX_QEMU_OVERLAY', 'VINIX_QEMU_MODULE_ISO', 'VINIX_QEMU_BASE_ARCHIVE', 'VINIX_QEMU_MODULE_MANIFEST', 'VINIX_QEMU_EXTRA_MODULES'] {
		name_ := names.named('name', literal(name)!)!
		discard(method(env, 'pop', [o(name_), rb.ordinary(rb.null())])!)!
	}
	expected := names.named('expected', seq([o(method(golden, 'rstrip', [])!), v('ATL-NATIVE-PASS:c'), v('ATL-NATIVE-PASS:v'), v('ATL-NATIVE-GUEST-PASS')])!)!
	loader := factory('runpy', 'run_path')!
	loaded := invoke(loader, [temp(str(join(repo, 'tests/kernel-gaps/run.py')!)!)], {})!
	boot := method(loaded, '__getitem__', [v('boot')])!
	release([loaded])!
	command := seq([temp(str(join(repo, 'scripts/run-aarch64.sh')!)!), v('--no-build'), v('--serial'), v('--no-persist'), v('--mem=1024')])!
	failed := seq([v('KERNEL PANIC'), v('Assertion failed')])!
	result := names.named('result', invoke(boot, [o(command), o(env), o(state), o(expected), o(failed), rb.ordinary(ah.Value(300))], {})!)!
	release([command, failed])!
	names.named('digest', g('_native_digest')!)!
	metadata := rb.dictionary([v('baseline_revision'), v('result'), v('expected_markers')], [o(attr(args, 'baseline_rev')!), o(result), o(expected)])!
	probe_loader := factory('runpy', 'run_path')!
	probe_module := invoke(probe_loader, [temp(str(join(support, 'art-runtime.py')!)!)], {})!
	probe_digest := method(probe_module, '__getitem__', [v('configuration_probe_digest')])!
	release([probe_module])!
	put(metadata, literal('configuration_probe_digest')!, invoke(probe_digest, [], {})!)!
	put(metadata, literal('provider_source_sha256')!, digest_api(original)!)!
	put(metadata, literal('provider_patch_sha256')!, digest_join(state, 'configuration.patch')!)!
	put(metadata, literal('provider_header_sha256')!, digest_join(art, 'usr/include/androidfw/androidfw_c_api.h')!)!
	put(metadata, literal('provider_library_sha256')!, digest_join(art, 'usr/lib/art/libandroidfw.so')!)!
	put(metadata, literal('kernel_sha256')!, digest_join(attr(args, 'kernel_dir')!, 'bin/vinix')!)!
	file_hashes := rb.dictionary([], [])!
	hash_iter := items(files)!
	for {
		row := rb.next(hash_iter)!
		if row == rb.null() { break }
		values := pair(row)!
		put(file_hashes, values[0], digest_api(values[1])!)!
		release([values[0], values[1], row])!
	}
	release([hash_iter])!
	put(metadata, literal('files')!, file_hashes)!
	metadata_ := names.named('metadata', metadata)!
	write_json(join(state, 'validation.json')!, metadata_)!
	raise('SystemExit', [o(result)])!
}

fn extend(left ah.Value, right ah.Value) ! { discard(method(left, 'extend', [o(right)])!)! }
fn put_env(env ah.Value, key string, value ah.Value) ! { put(env, literal(key)!, value)!; release([value])! }
fn concat(left ah.Value, right ah.Value, tail []ah.Value) !ah.Value {
	result := seq([])!
	extend(result, left)!
	extend(result, right)!
	for value in tail { discard(method(result, 'append', [value])!)! }
	return result
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	return match ah.field(row, 'operation').text() {
		'main' { workflow(g('a')!, g('state')!, ah.field(row, 'debug') == ah.Value(true))!; rb.null() }
		'digest' { rb.result_object(digest(rb.borrow('path')!)!) }
		'write-json' { write_json(rb.borrow('path')!, rb.borrow('value')!)!; rb.null() }
		else { return error('Unknown ATL controller operation') }
	}
}
