// SPDX-License-Identifier: MIT
module ps2build

import androidhost as ah

fn error_argument(parser string, message string) ! {
	method(parser, 'error', [v(ah.Value(message))], {})!
}

fn stage_source(archive string, source string, output string) ! {
	stamp := join(source, '.vinix-source')!
	if is_file(stamp)! && compare('eq', method(stamp, 'read_text', [], {})!, global('SOURCE_SHA256')!)! {
		return
	}
	temporary := call('Path', o(invoke('tempfile.mkdtemp', [], {
		'prefix': v(ah.Value('iris-source-'))
		'dir':    o(output)
	})!))!
	own_function(temporary, 'shutil.rmtree', 'exists')!
	stage_source_body(archive, temporary, source) or {
		cause := err
		close(temporary, cause)!
		return cause
	}
	close(temporary, none)!
}

fn stage_source_body(archive string, temporary string, source string) ! {
	public('unpack', [archive, temporary], {})!
	method(join(temporary, '.vinix-source')!, 'write_text', [o(global('SOURCE_SHA256')!)], {})!
	if exists(source)! { call('shutil.rmtree', o(source))! }
	method(temporary, 'replace', [o(source)], {})!
}

fn select_files(source string) !string {
	src := join(source, 'src')!
	c := call('sorted', o(method(src, 'rglob', [v(ah.Value('*.c'))], {})!))!
	cpp := call('sorted', o(method(src, 'rglob', [v(ah.Value('*.cpp'))], {})!))!
	all := call('operator.add', o(c), o(cpp))!
	files := list([])!
	iter := iterator(all)!
	for {
		entry := next(iter)!
		if entry.done { break }
		name := attribute(entry.value, 'name')!
		if truth(call('operator.contains', o(collection('tuple', [
			lit('ee_uncached.c')!,
			lit('ps2_elf.c')!,
			lit('ioman.cpp')!,
		])!), o(name))!)! {
			continue
		}
		if truth(call('operator.contains', o(attribute(entry.value, 'parts')!), v(ah.Value('renderer')))!)! && !compare('eq', name, lit('software.cpp')!)! {
			continue
		}
		append(files, entry.value)!
	}
	append(files, join(global('SUPPORT')!, 'bridge.c')!)!
	append(files, join(global('SUPPORT')!, 'ioman.cpp')!)!
	return files
}

fn common_flags(sysroot string, gcc string, source string) !string {
	return words(['--target=aarch64-linux-musl', '--sysroot=' + text(sysroot)!,
		'--gcc-install-dir=' + text(gcc)!, '-O2', '-fno-stack-protector', '-ffunction-sections',
		'-fdata-sections', '-funwind-tables', '-fexceptions', '-D_GNU_SOURCE', '-Wno-everything',
		'-I' + text(join(source, 'src')!)!, '-I' + text(join(global('SUPPORT')!, 'include')!)!])!
}

fn main_policy(args string, parser string, output string, sysroot string, llvm string) ! {
	versions := call('sorted', o(method(join(sysroot, 'usr/lib/gcc/aarch64-alpine-linux-musl')!, 'glob', [v(ah.Value('*'))], {})!))!
	if !truth(versions)! || !is_file(join(sysroot, 'usr/lib/libc.a')!)! {
		error_argument(parser, 'ARM64 musl sysroot missing; run scripts/build-userland-aarch64.sh')!
	}
	gcc := call('operator.getitem', o(versions), v(ah.Value(-1)))!
	cpp := call('operator.truediv', o(join(sysroot, 'usr/include/c++')!), o(attribute(gcc, 'name')!))!
	for input in [join(cpp, 'vector')!, join(sysroot, 'usr/lib/libstdc++.a')!, join(llvm, 'clang')!,
		join(llvm, 'clang++')!, join(llvm, 'llvm-ar')!] {
		if !is_file(input)! { error_argument(parser, 'build input missing: ' + text(input)!)! }
	}
	mkdir(output, true)!
	archive, source := join(output, 'iris-source.tar.gz')!, join(output, 'source')!
	public('fetch', [archive], {})!
	stage_source(archive, source, output)!
	obj := join(output, 'obj')!
	mkdir(obj, false)!
	common := common_flags(sysroot, gcc, source)!
	cxx := words(['-std=c++20', '-nostdinc++', '-isystem' + text(cpp)!,
		'-isystem' + text(join(cpp, 'aarch64-alpine-linux-musl')!)!,
		'-isystem' + text(join(cpp, 'backward')!)!])!
	files := select_files(source)!
	context := call('builtins.dict')!
	for row in [['source', source], ['obj', obj], ['llvm', llvm], ['common', common], ['cxx', cxx]] {
		set(context, row[0], row[1])!
	}
	worker := call('_worker', o(context))!
	compiler := method(call('subprocess.check_output', o(list([
		str(join(llvm, 'clang')!)!,
		lit('--version')!,
	])!))!, 'decode', [], {})!
	libc := public('sha256', [join(sysroot, 'usr/lib/libc.a')!], {})!
	set(context, 'compiler', compiler)!
	set(context, 'libc', libc)!
	results := pool_policy(files, worker, attribute(args, 'jobs')!, join(output, 'core-build.log')!)!
	finish(output, obj, source, llvm, common, results)!
}

fn finish(output string, obj string, source string, llvm string, common string, results string) ! {
	bridge := join(global('SUPPORT')!, 'vbridge')!
	generated := join(output, 'bridge.generated.c')!
	generate := call('operator.getitem', o(call('runpy.run_path', o(str(join(global('ROOT')!, 'build-support/compile-v-module.py')!)!))!), v(ah.Value('generate')))!
	callback('function', {
		'target': ah.Value(generate)
		'args':   ah.Value([o(bridge), o(generated), v(ah.Value('arm64'))])
	})!
	flags := list([])!
	items := iterator(common)!
	for {
		item := next(items)!
		if item.done { break }
		if !compare('eq', item.value, lit('-Wno-everything')!)! { append(flags, item.value)! }
	}
	extend(flags, words(['-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
		'-I' + text(bridge)!])!)!
	bridge_obj, unwind_obj := join(obj, 'bridge-v.o')!, join(obj, 'bridge-unwind.o')!
	command := call('operator.add', o(list([str(join(llvm, 'clang')!)!])!), o(flags))!
	extend(command, list([lit('-c')!, str(generated)!, lit('-o')!, str(bridge_obj)!])!)!
	invoke('subprocess.run', [o(command)], {
		'check': v(ah.Value(true))
	})!
	unwind := call('operator.add', o(list([str(join(llvm, 'clang')!)!])!), o(common))!
	extend(unwind, list([lit('-c')!, str(join(bridge, 'unwind-arm.S')!)!, lit('-o')!, str(unwind_obj)!])!)!
	invoke('subprocess.run', [o(unwind)], {
		'check': v(ah.Value(true))
	})!
	final_results := call('operator.iadd', o(results), o(list([tuple(bridge_obj, bytes('')!)!,
		tuple(unwind_obj, bytes('')!)!])!))!
	library, temporary := join(output, 'libvinix_ps2.a')!, join(output, 'libvinix_ps2.new.a')!
	method(temporary, 'unlink', [], {
		'missing_ok': v(ah.Value(true))
	})!
	archive_command := list([str(join(llvm, 'llvm-ar')!)!, lit('rcs')!, str(temporary)!])!
	iter := iterator(final_results)!
	for {
		item := next(iter)!
		if item.done { break }
		parts := pair(item.value)!
		append(archive_command, str(parts[0])!)!
	}
	invoke('subprocess.run', [o(archive_command)], {
		'check': v(ah.Value(true))
	})!
	method(temporary, 'replace', [o(library)], {})!
	notices := join(output, 'staging/usr/share/licenses/vinix-ps2')!
	mkdir(notices, true)!
	call('shutil.copyfile', o(join(source, 'LICENSE')!), o(join(notices, 'Iris-LICENSE')!))!
	call('shutil.copyfile', o(join(global('SUPPORT')!, 'README.md')!), o(join(notices, 'SOURCES.md')!))!
	for name in ['Play-LICENSE', 'Play-Framework-LICENSE', 'THIRD-PARTY-NOTICES'] {
		call('shutil.copyfile', o(join(global('SUPPORT')!, name)!), o(join(notices, name)!))!
	}
	revision := slice(global('REVISION')!, null()!, literal(ah.Value(7))!)!
	call('print', v(ah.Value('Built Iris 0.15-alpha ' + text(revision)! + ' (interpreter/software GS): ' + text(library)!)))!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'sha256' { return ah.Value(sha256(args[0])!) }
		'fetch' { fetch(args[0])! }
		'unpack' { unpack(args[0], args[1])! }
		'compile_one' { return ah.Value(compile_one(args[0], args[1])!) }
		'main' { main_policy(args[0], args[1], args[2], args[3], args[4])! }
		else { return error('unknown PS2 build policy') }
	}
	return ah.Value(null()!)
}
