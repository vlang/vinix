module dhewmcore

import androidhost as ah
import runtimebuild as rb

fn download(url ah.Value, path ah.Value) ! {
	if test(path, 'is_file')! && rb.bool_object(rb.attribute(method(path, 'stat', [])!, 'st_size', true)!)! {
		return
	}
	temp := method(path, 'with_suffix', [o(rb.call('acquire', 'operator', 'add', [
		o(rb.attribute(path, 'suffix', true)!),
		v('.part'),
	], {})!)])!
	rb.call('invoke', 'subprocess', 'run', [o(rb.make_sequence([v('curl'), v('-fL'), v('--retry'),
		v('3'), v('-o'), v(py_str(temp)!), o(url)])!)], {
		'check': ah.Value(true)
	})!
	rb.method('invoke', temp, 'replace', [o(path)], {})!
}

fn fetch(downloads ah.Value, line ah.Value) !ah.Value {
	pair := unpack_pair(method(line, 'split', [])!)!
	path := rb.method('acquire', downloads, '__truediv__', [o(pair[1])], {})!
	url := text(global('MIRROR')!)! + '/' + text(pair[0])! + '/aarch64/' + text(pair[1])!
	pinned_download(literal(url)!, path)!
	return path
}

fn header(records ah.Value, name string) !ah.Value {
	iter := rb.iter_object(records)!
	for {
		record := rb.next(iter)!
		if record == rb.null() { break }
		candidate := rb.call('acquire', 'operator', 'add', [o(record), v('\n')], {})!
		if rb.bool_object(rb.call('acquire', 'operator', 'contains', [o(candidate),
			v('P:' + name + '\n')], {})!)! {
			return record
		}
	}
	return rb.callback('raise', {
		'kind': ah.Value('StopIteration')
	})!
}

fn version(record ah.Value) !ah.Value {
	iter := rb.iter_object(method(record, 'splitlines', [])!)!
	for {
		line := rb.next(iter)!
		if line == rb.null() { break }
		if rb.bool_object(method(line, 'startswith', [v('V:')])!)! {
			selection := rb.call('acquire', 'builtins', 'slice', [
				rb.ordinary(ah.Value(2)),
				rb.ordinary(rb.null()),
			], {})!
			return method(line, '__getitem__', [o(selection)])!
		}
	}
	return rb.callback('raise', {
		'kind': ah.Value('StopIteration')
	})!
}

fn environment(name string, fallback string) !ah.Value {
	return method(rb.attribute(global('os')!, 'environ', true)!, 'get', [v(name), v(fallback)])!
}

fn configure(source ah.Value, sysroot ah.Value, cmake ah.Value) ! {
	run(['cmake', '-S', py_str(join(source, 'neo')!)!, '-B', py_str(cmake)!, '-G', 'Ninja',
		'-DCMAKE_SYSTEM_NAME=Linux', '-DCMAKE_SYSTEM_PROCESSOR=aarch64',
		'-DCMAKE_C_COMPILER=' + text(environment('VINIX_DHEWM3_CC', 'aarch64-linux-musl-gcc')!)!,
		'-DCMAKE_CXX_COMPILER=' + text(environment('VINIX_DHEWM3_CXX', 'aarch64-linux-musl-g++')!)!,
		'-DCMAKE_BUILD_TYPE=Release', '-DD3XP=OFF', '-DREPRODUCIBLE_BUILD=ON',
		'-DOPENAL_INCLUDE_DIR=' + text(sysroot)! + '/usr/include',
		'-DOPENAL_LIBRARY=' + text(sysroot)! + '/usr/lib/libopenal.so',
		'-DSDL2_INCLUDE_DIR=' + text(sysroot)! + '/usr/include/SDL2',
		'-DSDL2_LIBRARY=' + text(sysroot)! + '/usr/lib/libSDL2.so',
		'-DCURL_INCLUDE_DIR=' + text(sysroot)! + '/usr/include',
		'-DCURL_LIBRARY=' + text(sysroot)! + '/usr/lib/libcurl.so',
		'-DCMAKE_CXX_FLAGS=-I' + text(global('X11')!)! + '/sysroot/usr/include -g -fno-omit-frame-pointer',
		'-DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined'], false)!
	// The jobs value stays the actual caller-owned environment value.
	rb.call('invoke', 'subprocess', 'run', [o(rb.make_sequence([v('cmake'), v('--build'),
		v(py_str(cmake)!), v('-j'), o(environment('VINIX_DHEWM3_JOBS', '8')!)])!)], {
		'check': ah.Value(true)
	})!
}

fn main_workflow() ! {
	build := global('BUILD')!
	downloads := join(build, 'downloads')!
	sysroot := join(build, 'sysroot')!
	runtime := join(build, 'runtime')!
	stage := join(build, 'staging')!
	if test(runtime, 'exists')! { remove(runtime)! }
	for path in [downloads, sysroot, runtime] { mkdir(path)! }
	source := join(build, 'source')!
	if !test(source, 'exists')! {
		run(['git', 'clone', '--depth', '1', '--branch', text(global('TAG')!)!,
			'https://github.com/dhewm/dhewm3.git', py_str(source)!], false)!
	}
	head := method(output(['git', '-C', py_str(source)!, 'rev-parse', 'HEAD'])!, 'strip', [])!
	if !rb.eq(head, global('COMMIT')!)! {
		return failure('dhewm3 source is not the pinned 1.5.5 commit')
	}
	if !test(join(global('X11')!, 'sysroot/usr/include/GL/gl.h')!, 'is_file')! {
		return failure('Build the X11 layer first with scripts/build-x11-aarch64.sh')
	}
	mut command := ['python3', py_str(join(global('ROOT')!, 'build-support/alpine-resolve.py')!)!]
	for repo in ['main', 'community'] {
		archive := join(downloads, repo + '_APKINDEX.tar.gz')!
		pinned_download(literal(text(global('MIRROR')!)! + '/' + repo + '/aarch64/APKINDEX.tar.gz')!, archive)!
		index := join(downloads, repo + '_APKINDEX')!
		unpack_index(archive, index)!
		command << ['--index', repo, py_str(index)!]
	}
	command << ['sdl2', 'openal-soft-libs', 'libcurl', 'libstdc++', 'libbsd', 'xz-libs', 'gmp',
		'libuuid', 'libpciaccess', 'wayland-libs-client']
	packages := output(command)!
	rb.method('invoke', join(build, 'packages.tsv')!, 'write_text', [o(packages)], {})!
	headers := rb.call('acquire', 'builtins', 'list', [], {})!
	for repo in ['main', 'community'] {
		records := method(method(join(downloads, repo + '_APKINDEX')!, 'read_text', [])!, 'split', [v('\n\n')])!
		for name in if repo == 'main' { ['curl-dev'] } else { ['sdl2-dev', 'openal-soft-dev'] } {
			entry := repo + '\t' + name + '-' + text(version(header(records, name)!)!)! + '.apk'
			rb.method('invoke', headers, 'append', [v(entry)], {})!
		}
	}
	lines := rb.call('acquire', 'operator', 'add', [
		o(method(packages, 'splitlines', [])!),
		o(headers),
	], {})!
	archives := rb.callback('pool_function', {
		'factory': ah.Value('_pool')
		'name':    ah.Value('_fetch')
		'before':  ah.Value([o(downloads)])
		'workers': ah.Value(6)
		'id':      lines
	})!
	iter := rb.iter_object(archives)!
	mut i := 0
	for {
		archive := rb.next(iter)!
		if archive == rb.null() { break }
		run(['tar', '--ignore-zeros', '-xzf', py_str(archive)!, '-C', py_str(sysroot)!], true)!
		if i < rb.length(method(packages, 'splitlines', [])!)! {
			run(['tar', '--ignore-zeros', '-xzf', py_str(archive)!, '-C', py_str(runtime)!], true)!
		}
		i++
	}
	cmake := join(build, 'cmake')!
	configure(source, sysroot, cmake)!
	for folder in ['lib', 'usr/lib'] {
		if test(join(stage, folder)!, 'exists')! { remove(join(stage, folder)!)! }
	}
	for name in ['usr/bin', 'usr/lib/dhewm3', 'lib', 'usr/share/games/dhewm3/demo'] {
		mkdir(join(stage, name)!)!
	}
	copy(join(cmake, 'dhewm3')!, join(stage, 'usr/bin/dhewm3')!)!
	copy(join(cmake, 'base.so')!, join(stage, 'usr/lib/dhewm3/base.so')!)!
	copy(join(global('ROOT')!, 'build-support/dhewm3/run-dhewm3')!, join(stage, 'usr/bin/run-dhewm3')!)!
	gui := join(stage, 'usr/share/games/dhewm3/demo/guis/map/loading.gui')!
	mkdir(rb.attribute(gui, 'parent', true)!)!
	copy(join(global('ROOT')!, 'build-support/dhewm3/loading.gui')!, gui)!
	for folder in ['lib', 'usr/lib'] {
		paths := rb.iter_object(method(join(runtime, folder)!, 'glob', [v('*.so*')])!)!
		for {
			path := rb.next(paths)!
			if path == rb.null() { break }
			dest := rb.method('acquire', join(stage, folder)!, '__truediv__', [o(rb.attribute(path, 'name', true)!)], {})!
			mkdir(rb.attribute(dest, 'parent', true)!)!
			if test(dest, 'exists')! || test(dest, 'is_symlink')! {
				rb.method('invoke', dest, 'unlink', [], {})!
			}
			if test(path, 'is_symlink')! {
				rb.method('invoke', dest, 'symlink_to', [o(rb.call('acquire', 'os', 'readlink', [o(path)], {})!)], {})!
			} else {
				copy(path, dest)!
			}
		}
	}
	demo := join(stage, 'usr/share/games/dhewm3/demo/demo00.pk4')!
	if !test(demo, 'exists')! {
		installer := join(downloads, 'doom3-linux-1.1.1286-demo.x86.run')!
		pinned_download(global('DEMO_URL')!, installer)!
		install_demo(installer, demo)!
	}
	if !rb.eq_value(rb.attribute(method(demo, 'stat', [])!, 'st_size', true)!, ah.Value(483535485))! || !rb.eq(method(rb.call('acquire', 'hashlib', 'md5', [o(method(demo, 'read_bytes', [])!)], {})!, 'hexdigest', [])!, global('DEMO_MD5')!)! {
		return failure('Doom 3 Linux demo checksum mismatch')
	}
	provenance := 'dhewm3 ' + text(global('TAG')!)! + ' ' + text(global('COMMIT')!)! + '\n' + text(global('DEMO_URL')!)! + '\ndemo00.pk4 MD5 ' + text(global('DEMO_MD5')!)! + '\n'
	rb.method('invoke', join(stage, 'usr/share/games/dhewm3/SOURCES.txt')!, 'write_text', [v(provenance)], {})!
	rb.callback('print', {
		'data': ah.Value('Staged dhewm3 and verified demo: ' + text(stage)!)
	})!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	match ah.field(row, 'operation').text() {
		'download' { download(rb.borrow('url')!, rb.borrow('path')!)! }
		'fetch' { return rb.result_object(fetch(rb.borrow('downloads')!, rb.borrow('line')!)!) }
		'main' { main_workflow()! }
		else { return error('Unknown dhewm3 build operation') }
	}
	return rb.null()
}
