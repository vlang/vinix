// SPDX-License-Identifier: MIT
module n64build

import androidhost as ah

fn append(id string, item string) ! { method(id, 'append', [o(item)], {})! }

fn extend(id string, items string) ! { method(id, 'extend', [o(items)], {})! }

fn parser_policy() ![]string {
	parser := invoke('argparse.ArgumentParser', [], {
		'description': o(global('__doc__')!)
	})!
	for row in [['--output', 'build/n64'], ['--sysroot', 'build-aarch64-userland/staging']] {
		method(parser, 'add_argument', [v(ah.Value(row[0]))], {
			'type':    o(global('Path')!)
			'default': o(join(global('ROOT')!, row[1])!)
		})!
	}
	linux := env('VINIX_AARCH64_LINUX_HEADERS', str(join(global('ROOT')!, 'build-aarch64-userland/sysroot/include')!)!)!
	method(parser, 'add_argument', [v(ah.Value('--linux-headers'))], {
		'type':    o(global('Path')!)
		'default': o(call('Path', o(linux))!)
	})!
	method(parser, 'add_argument', [v(ah.Value('--llvm-bin'))], {
		'type':    o(global('Path')!)
		'default': o(call('Path', o(env('LLVM_BIN', lit('/opt/homebrew/opt/llvm/bin')!)!))!)
	})!
	cpu := call('os.cpu_count')!
	jobs := if truth(cpu)! { cpu } else { literal(ah.Value(2))! }
	method(parser, 'add_argument', [v(ah.Value('--jobs'))], {
		'type':    o(global('int')!)
		'default': o(call('min', o(jobs), v(ah.Value(8)))!)
	})!
	method(parser, 'add_argument', [v(ah.Value('--host'))], {
		'action': v(ah.Value('store_true'))
		'help':   v(ah.Value('build a native host archive for emulator smoke tests'))
	})!
	args := method(parser, 'parse_args', [], {})!
	output := method(attribute(args, 'output')!, 'resolve', [], {})!
	sysroot := method(attribute(args, 'sysroot')!, 'resolve', [], {})!
	llvm := method(attribute(args, 'llvm_bin')!, 'resolve', [], {})!
	if compare('lt', attribute(args, 'jobs')!, literal(ah.Value(1))!)! {
		method(parser, 'error', [v(ah.Value('--jobs must be positive'))], {})!
	}
	return [parser, args, output, sysroot, llvm]
}

fn main_policy() ! {
	parsed := parser_policy()!
	parser, args, output, sysroot, llvm := parsed[0], parsed[1], parsed[2], parsed[3], parsed[4]
	common := words(['-O2', '-DNDEBUG', '-D_GNU_SOURCE', '-DNO_ASM', '-DVINIX_NO_FALLOC', '-fcommon',
		'-fno-stack-protector', '-ffunction-sections', '-fdata-sections', '-Wno-everything'])!
	mut cxx := list([])!
	if !truth(attribute(args, 'host')!)! {
		versions := call('sorted', o(method(join(sysroot, 'usr/lib/gcc/aarch64-alpine-linux-musl')!, 'glob', [v(ah.Value('*'))], {})!))!
		if !truth(versions)! || !is_file(join(sysroot, 'usr/lib/libc.a')!)! {
			method(parser, 'error', [v(ah.Value('ARM64 musl sysroot missing; run scripts/build-userland-aarch64.sh'))], {})!
		}
		gcc := call('operator.getitem', o(versions), v(ah.Value(-1)))!
		cpp := call('operator.truediv', o(join(sysroot, 'usr/include/c++')!), o(attribute(gcc, 'name')!))!
		for path in [join(cpp, 'vector')!, join(sysroot, 'usr/lib/libstdc++.a')!] {
			if !is_file(path)! {
				method(parser, 'error', [v(ah.Value('build input missing: ' + text(path)!))], {})!
			}
		}
		extend(common, words(['--target=aarch64-linux-musl', '--sysroot=' + text(sysroot)!,
			'--gcc-install-dir=' + text(gcc)!])!)!
		linux := method(attribute(args, 'linux_headers')!, 'resolve', [], {})!
		if !is_file(join(linux, 'linux/futex.h')!)! {
			method(parser, 'error', [v(ah.Value('Linux headers missing; run scripts/build-userland-aarch64.sh'))], {})!
		}
		extend(common, list([lit('-idirafter')!, str(linux)!])!)!
		cxx = words(['-nostdinc++', '-isystem' + text(cpp)!,
			'-isystem' + text(join(cpp, 'aarch64-alpine-linux-musl')!)!,
			'-isystem' + text(join(cpp, 'backward')!)!])!
	}
	for name in ['clang', 'clang++', 'llvm-ar'] {
		path := join(llvm, name)!
		if !is_file(path)! {
			method(parser, 'error', [v(ah.Value('build input missing: ' + text(path)!))], {})!
		}
	}
	mkdir(output, true)!
	archive, source := join(output, 'parallel-source.tar.gz')!, join(output, 'source')!
	public('fetch', [archive], {})!
	source_stamp := call('operator.add', o(global('SOURCE_SHA256')!), o(global('PATCH_VERSION')!))!
	prepare_source(output, archive, source, source_stamp, 'n64-source-', true)!
	manifest := join(output, 'manifest.mk')!
	method(manifest, 'write_text', [v(ah.Value('vinix-manifest:\n\t@echo C_SOURCES=$(SOURCES_C)\n\t@echo CXX_SOURCES=$(SOURCES_CXX)\n\t@echo C_FLAGS=$(CFLAGS)\n\t@echo CXX_FLAGS=$(CXXFLAGS)\n'))], {})!
	command := list([lit('make')!, lit('--no-print-directory')!, lit('-s')!, lit('-f')!,
		lit('Makefile')!, lit('-f')!, str(manifest)!, lit('vinix-manifest')!])!
	extend(command, words(['platform=unix', 'WITH_DYNAREC=', 'HAVE_OPENGL=0', 'HAVE_THR_AL=1',
		'HAVE_PARALLEL=0', 'HAVE_PARALLEL_RSP=0', 'HAVE_LTCG=0', 'STATIC_LINKING=0', 'UNAME=Linux',
		'ARCH=aarch64', 'CPUOPTS=-O2', 'GIT_VERSION=' + text(revision()!)!,
		'CC=' + text(join(llvm, 'clang')!)!])!)!
	lines := method(method(invoke('subprocess.check_output', [o(command)], {
		'cwd': o(source)
	})!, 'decode', [], {})!, 'splitlines', [], {})!
	values := manifest_values(lines)!
	files := list([])!
	for spec in [['C_SOURCES', '0'], ['CXX_SOURCES', '1']] {
		entries := iterator(method(get(values, spec[0])!, 'split', [], {})!)!
		for {
			item := next(entries)!
			if item.done { break }
			path := call('operator.truediv', o(source), o(item.value))!
			append(files, tuple(path, literal(ah.Value(spec[1] == '1'))!)!)!
		}
	}
	zlib_archive, zlib_source := join(output, 'zlib-source.tar.gz')!, join(output, 'zlib-source')!
	public('fetch', [zlib_archive, global('ZLIB_URL')!, global('ZLIB_SHA256')!], {})!
	prepare_source(output, zlib_archive, zlib_source, global('ZLIB_SHA256')!, 'zlib-source-', false)!
	for name in ['adler32', 'compress', 'crc32', 'deflate', 'gzclose', 'gzlib', 'gzread', 'gzwrite',
		'inflate', 'infback', 'inftrees', 'inffast', 'trees', 'uncompr', 'zutil'] {
		append(files, tuple(join(zlib_source, name + '.c')!, literal(ah.Value(false))!)!)!
	}
	append(common, lit('-I' + text(zlib_source)!)!)!
	obj := join(output, 'obj')!
	mkdir(obj, false)!
	compiler := method(call('subprocess.check_output', o(list([
		str(join(llvm, 'clang')!)!,
		lit('--version')!,
	])!))!, 'decode', [], {})!
	mut headers := call('operator.add', o(call('operator.add', o(global('SOURCE_SHA256')!), o(global('PATCH_VERSION')!))!), o(global('ZLIB_SHA256')!))!
	for name in ['bridge.h', 'budget.h'] {
		headers = call('operator.add', o(headers), o(public('sha256', [join(global('SUPPORT')!, name)!], {})!))!
	}
	libc := if truth(attribute(args, 'host')!)! {
		lit('host')!
	} else {
		public('sha256', [join(sysroot, 'usr/lib/libc.a')!], {})!
	}
	context := context_dict(source, obj, llvm, values, common, cxx, headers, compiler, libc)!
	log := join(output, 'core-build.log')!
	results := pool_policy(files, context, attribute(args, 'jobs')!, log)!
	bridge_objects(source, output, obj, llvm, sysroot, values, common, args, results)!
	library := finish_archive(output, llvm, results)!
	notices_and_source(output, archive, zlib_archive)!
	call('print', v(ah.Value('Built paraLLEl-N64 ' + text(revision()!)! + ' (pure CPU/LLE RSP/synchronous Angrylion): ' + text(library)!)))!
}

fn manifest_values(lines string) !string {
	rows := list([])!
	iter := iterator(lines)!
	for {
		item := next(iter)!
		if item.done { break }
		if truth(call('operator.contains', o(item.value), v(ah.Value('=')))!)! {
			append(rows, method(item.value, 'split', [v(ah.Value('=')), v(ah.Value(1))], {})!)!
		}
	}
	return call('dict', o(rows))!
}

fn prepare_source(output string, archive string, source string, source_stamp string, prefix string, do_patch bool) ! {
	stamp := join(source, '.vinix-source')!
	if is_file(stamp)! && !compare('ne', method(stamp, 'read_text', [], {})!, source_stamp)! {
		return
	}
	temporary := call('Path', o(invoke('tempfile.mkdtemp', [], {
		'prefix': v(ah.Value(prefix))
		'dir':    o(output)
	})!))!
	own_function(temporary, 'shutil.rmtree', 'exists')!
	source_body(archive, source, source_stamp, temporary, do_patch) or {
		failure := err
		close(temporary, failure)!
		return failure
	}
	close(temporary, none)!
}

fn source_body(archive string, source string, stamp string, temporary string, do_patch bool) ! {
	public('unpack', [archive, temporary], {})!
	if do_patch { public('patch', [temporary], {})! }
	method(join(temporary, '.vinix-source')!, 'write_text', [o(stamp)], {})!
	if exists(source)! { call('shutil.rmtree', o(source))! }
	method(temporary, 'replace', [o(source)], {})!
}

fn bridge_objects(source string, output string, obj string, llvm string, sysroot string, values string, common string, args string, results string) ! {
	bridge := join(global('SUPPORT')!, 'bridgecore')!
	generated := join(output, 'bridge.generated.c')!
	generate := get(call('runpy.run_path', o(str(join(global('ROOT')!, 'build-support/compile-v-module.py')!)!))!, 'generate')!
	machine := attribute(call('os.uname')!, 'machine')!
	host_arm := truth(call('operator.contains', o(collection('tuple', [lit('arm64')!, lit('aarch64')!])!), o(machine))!)!
	architecture := if !truth(attribute(args, 'host')!)! || host_arm { 'arm64' } else { 'amd64' }
	callback('function', {
		'target': ah.Value(generate)
		'args':   ah.Value([o(bridge), o(generated), v(ah.Value(architecture))])
	})!
	bridge_flags := flags(values, false)!
	iter := iterator(common)!
	for {
		item := next(iter)!
		if item.done { break }
		if !compare('eq', item.value, lit('-Wno-everything')!)! {
			append(bridge_flags, item.value)!
		}
	}
	extend(bridge_flags, words(['-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-parameter', '-I' + text(bridge)!])!)!
	bridge_object, abi_object := join(obj, 'bridge-v.o')!, join(obj, 'bridge-abi.o')!
	command := call('operator.add', o(list([str(join(llvm, 'clang')!)!])!), o(bridge_flags))!
	extend(command, list([lit('-c')!, str(generated)!, lit('-o')!, str(bridge_object)!])!)!
	invoke('subprocess.run', [o(command)], {
		'cwd':   o(source)
		'check': v(ah.Value(true))
	})!
	abi_flags := if truth(attribute(args, 'host')!)! {
		list([])!
	} else {
		words(['--target=aarch64-linux-musl', '--sysroot=' + text(sysroot)!])!
	}
	abi_command := call('operator.add', o(list([str(join(llvm, 'clang')!)!])!), o(abi_flags))!
	extend(abi_command, list([lit('-c')!, str(join(bridge, 'varargs.S')!)!, lit('-o')!,
		str(abi_object)!])!)!
	invoke('subprocess.run', [o(abi_command)], {
		'check': v(ah.Value(true))
	})!
	extend(results, list([tuple(bridge_object, bytes('')!)!, tuple(abi_object, bytes('')!)!])!)!
}

fn finish_archive(output string, llvm string, results string) !string {
	library, temporary := join(output, 'libvinix_n64.a')!, join(output, 'libvinix_n64.new.a')!
	method(temporary, 'unlink', [], {
		'missing_ok': v(ah.Value(true))
	})!
	command := list([str(join(llvm, 'llvm-ar')!)!, lit('rcs')!, str(temporary)!])!
	iter := iterator(results)!
	for {
		item := next(iter)!
		if item.done { break }
		parts := pair(item.value)!
		append(command, str(parts[0])!)!
	}
	invoke('subprocess.run', [o(command)], {
		'check': v(ah.Value(true))
	})!
	method(temporary, 'replace', [o(library)], {})!
	return library
}

fn notices_and_source(output string, archive string, zlib_archive string) ! {
	notices := join(output, 'staging/usr/share/licenses/vinix-n64')!
	mkdir(notices, true)!
	for name in ['README.md', 'THIRD-PARTY-NOTICES', 'GPL-2.0', 'MAME-LICENSE', 'CXD4-CC0',
		'ZLIB-LICENSE'] {
		call('shutil.copyfile', o(join(global('SUPPORT')!, name)!), o(join(notices, name)!))!
	}
	corresponding := join(output, 'staging/usr/share/vinix/n64/source')!
	if exists(corresponding)! { call('shutil.rmtree', o(corresponding))! }
	mkdir(corresponding, true)!
	for from in [archive, zlib_archive] {
		call('shutil.copyfile', o(from), o(call('operator.truediv', o(corresponding), o(attribute(from, 'name')!))!))!
	}
	for row in [[global('SUPPORT')!, 'build-support/n64'],
		[join(global('ROOT')!, 'games/n64')!, 'games/n64'],
		[join(global('ROOT')!, 'build-support/n64-homebrew')!, 'build-support/n64-homebrew']] {
		if exists(row[0])! {
			invoke('shutil.copytree', [o(row[0]), o(join(corresponding, row[1])!)], {
				'dirs_exist_ok': v(ah.Value(true))
				'ignore':        o(call('shutil.ignore_patterns', v(ah.Value('__pycache__')), v(ah.Value('*.pyc')))!)
			})!
		}
	}
	for name in ['build-n64-aarch64.sh', 'build-support/find-v.sh', 'build-support/compile-v-module.py',
		'build-support/aarch64-cc-shim', 'tools/_package_store_native.py',
		'build-support/native_host.py', 'build-support/android/_boot_native.py',
		'build-support/run-v-tool.sh', 'tests/linuxkpi/module_query.v', 'tests/linuxkpi/hosttest'] {
		relative := if name.starts_with('build-support/') || name.starts_with('tools/') || name.starts_with('tests/') {
			call('Path', v(ah.Value(name)))!
		} else {
			join(call('Path', v(ah.Value('scripts')))!, name)!
		}
		original := call('operator.truediv', o(global('ROOT')!), o(relative))!
		target := call('operator.truediv', o(corresponding), o(relative))!
		if is_dir(original)! {
			invoke('shutil.copytree', [o(original), o(target)], {
				'dirs_exist_ok': v(ah.Value(true))
			})!
		} else if exists(original)! {
			mkdir(attribute(target, 'parent')!, true)!
			call('shutil.copy2', o(original), o(target))!
		}
	}
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'sha256' { return ah.Value(sha256(args[0])!) }
		'fetch' { fetch(args[0], args[1], args[2])! }
		'unpack' { unpack(args[0], args[1])! }
		'replace' { replace(args[0], args[1], args[2])! }
		'patch' { patch(args[0])! }
		'compile_one' { return ah.Value(compile_one(args[0], args[1])!) }
		'main' { main_policy()! }
		else { return error('unknown N64 build operation') }
	}
	return ah.Value(null()!)
}
