// SPDX-License-Identifier: GPL-2.0-or-later
module gothicbuild

import androidhost as ah

fn env(name string, fallback string) !string {
	return invoke('os.environ.get', [v(ah.Value(name)), o(fallback)], {})!
}

fn lit(value string) !string { return literal(ah.Value(value))! }

fn unpack_pair(id string) ![]string {
	return callback('unpack_pair', {
		'owner': ah.Value(id)
	})!.items().map(it.text())
}

fn fetch(downloads string, line string) !string {
	pair := unpack_pair(method(line, 'split', [], {})!)!
	path := call('operator.truediv', o(downloads), o(pair[1]))!
	public('download', [
		lit('${text(global('MIRROR')!)!}/${text(pair[0])!}/aarch64/${text(pair[1])!}')!,
		path,
	], {})!
	return path
}

fn archive_index(archive string, index string) ! {
	manager := call('tarfile.open', o(archive))!
	stream := enter(manager)!
	index_body(stream, index) or {
		if retire(manager, err)! { return }
		return err
	}
	retire(manager, none)!
}

fn index_body(stream string, index string) ! {
	data := method(method(stream, 'extractfile', [v(ah.Value('APKINDEX'))], {})!, 'read', [], {})!
	method(index, 'write_bytes', [o(data)], {})!
}

// Pool result is returned before retiring its context manager, exactly as the
// original list(pool.map(...)) expression completes inside its with block.
fn fetch_archives(downloads string, packages string, development string) !string {
	manager := invoke('concurrent.futures.ThreadPoolExecutor', [], {
		'max_workers': v(ah.Value(6))
	})!
	pool := enter(manager)!
	result := fetch_pool_body(pool, downloads, packages, development) or {
		if retire(manager, err)! { return '' }
		return err
	}
	retire(manager, none)!
	return result
}

fn fetch_pool_body(pool string, downloads string, packages string, development string) !string {
	fetcher := call('functools.partial', o(global('_fetch')!), o(downloads))!
	lines := call('operator.add', o(packages), o(development))!
	return call('list', o(method(pool, 'map', [o(fetcher), o(lines)], {})!))!
}

fn main_policy() ! {
	parser := invoke('argparse.ArgumentParser', [], {
		'description': o(global('__doc__')!)
	})!
	group := method(parser, 'add_mutually_exclusive_group', [], {})!
	method(group, 'add_argument', [v(ah.Value('--demo'))], {
		'action': v(ah.Value('store_true'))
		'help':   v(ah.Value('download and extract the original public Gothic II demo'))
	})!
	method(group, 'add_argument', [v(ah.Value('--game'))], {
		'type':    o(global('Path')!)
		'metavar': v(ah.Value('DIR'))
		'help':    v(ah.Value('stage the Gothic II installation in DIR'))
	})!
	args := method(parser, 'parse_args', [], {})!
	if truth(attribute(args, 'game')!)! && !is_dir(attribute(args, 'game')!)! {
		failed('SystemExit', 'Not a directory: ${text(attribute(args, 'game')!)!}', none)!
	}
	build := method(call('Path', o(env('VINIX_OPENGOTHIC_BUILD_DIR', join(global('ROOT')!, 'build/opengothic')!)!))!, 'resolve', [], {})!
	downloads := join(build, 'downloads')!
	sysroot := join(build, 'sysroot')!
	staging := join(build, 'staging')!
	for path in [downloads, sysroot, staging] { mkdir(path, true)! }
	source := join(build, 'source')!
	headers := join(build, 'vulkan-headers')!
	public('checkout', [lit('https://github.com/Try/OpenGothic.git')!, source, global('COMMIT')!,
		literal(ah.Value(true))!], {})!
	public('checkout', [lit('https://github.com/KhronosGroup/Vulkan-Headers.git')!, headers,
		global('HEADERS')!], {})!
	tempest := join(source, 'lib/Tempest')!
	patches := iterator(global('PATCHES')!)!
	for {
		patch := next(patches)!
		if patch.done { break }
		public('apply_patch', [tempest, patch.value], {})!
	}
	public('apply_patch', [source, lit('worker-count.patch')!], {})!
	command_args := collection('list', [lit('python3')!,
		call('str', o(join(global('ROOT')!, 'build-support/alpine-resolve.py')!))!])!
	indexes := call('builtins.dict')!
	for repo in ['main', 'community'] {
		archive := join(downloads, '${repo}-index.tar.gz')!
		public('download', [
			lit('${text(global('MIRROR')!)!}/${repo}/aarch64/APKINDEX.tar.gz')!,
			archive,
		], {})!
		index := join(downloads, '${repo}-index')!
		archive_index(archive, index)!
		set(indexes, repo, method(read(index)!, 'split', [v(ah.Value('\n\n'))], {})!)!
		method(command_args, 'extend', [o(collection('list', [lit('--index')!, lit(repo)!,
			call('str', o(index))!])!)], {})!
	}
	method(command_args, 'extend', [o(strings(['mesa-vulkan-swrast', 'vulkan-loader', 'libx11',
		'libxcursor', 'libstdc++'])!)], {})!
	packages := method(invoke('subprocess.check_output', [o(command_args)], {
		'text': v(ah.Value(true))
	})!, 'splitlines', [], {})!
	package_text := method(lit('\n')!, 'join', [o(packages)], {})!
	method(join(build, 'packages.tsv')!, 'write_text', [o(call('operator.add', o(package_text), v(ah.Value('\n')))!)], {})!
	development := collection('list', [])!
	for name in ['vulkan-loader-dev', 'libx11-dev', 'libxcursor-dev', 'libxfixes-dev', 'libxrender-dev',
		'xorgproto'] {
		mut found := false
		items := iterator(method(indexes, 'items', [], {})!)!
		for {
			item := next(items)!
			if item.done { break }
			pair := unpack_pair(item.value)!
			records := iterator(pair[1])!
			mut record := null()!
			for {
				candidate := next(records)!
				if candidate.done { break }
				extra := call('operator.add', o(candidate.value), v(ah.Value('\n')))!
				if truth(call('operator.contains', o(extra), v(ah.Value('P:${name}\n')))!)! {
					record = candidate.value
					break
				}
			}
			if truth(record)! {
				lines := iterator(method(record, 'splitlines', [], {})!)!
				mut version := ''
				for {
					line := next(lines)!
					if line.done {
						call('builtins.next', o(iterator(collection('tuple', [])!)!))!
						break
					}
					if truth(method(line.value, 'startswith', [v(ah.Value('V:'))], {})!)! {
						version = call('operator.getitem', o(line.value), o(call('builtins.slice', v(ah.Value(2)), o(null()!))!))!
						break
					}
				}
				method(development, 'append', [v(ah.Value('${text(pair[0])!}\t${name}-${text(version)!}.apk'))], {})!
				found = true
				break
			}
		}
		if !found { failed('SystemExit', 'Development package not found: ${name}', none)! }
	}
	archives := fetch_archives(downloads, packages, development)!
	runtime := join(build, 'runtime')!
	if exists(runtime)! { call('shutil.rmtree', o(runtime))! }
	method(runtime, 'mkdir', [], {})!
	if archives == '' {
		callback('unbound_local', {
			'name': ah.Value('archives')
		})!
	}
	iter := iterator(call('enumerate', o(archives))!)!
	for {
		entry := next(iter)!
		if entry.done { break }
		pair := unpack_pair(entry.value)!
		command([lit('tar')!, lit('--ignore-zeros')!, lit('-xzf')!, pair[1], lit('-C')!, sysroot], {
			'stderr': o(global('subprocess.DEVNULL')!)
		})!
		if compare('lt', pair[0], call('len', o(packages))!)! {
			command([lit('tar')!, lit('--ignore-zeros')!, lit('-xzf')!, pair[1], lit('-C')!, runtime], {
				'stderr': o(global('subprocess.DEVNULL')!)
			})!
		}
	}
	cc := env('VINIX_OPENGOTHIC_CC', lit('aarch64-linux-musl-gcc')!)!
	cxx := env('VINIX_OPENGOTHIC_CXX', lit('aarch64-linux-musl-g++')!)!
	command([lit('python3')!, join(global('ROOT')!, 'build-support/compile-v-module.py')!,
		join(global('ROOT')!, 'desktop/execinfocore')!, join(build, 'execinfo.c')!, lit('--arch')!,
		lit('arm64')!, lit('--header')!, join(sysroot, 'usr/include/execinfo.h')!], {})!
	command([cc, lit('-D_GNU_SOURCE')!, lit('-D__V_HAVE_EXECINFO_H=1')!, lit('-O2')!, lit('-c')!,
		join(build, 'execinfo.c')!, lit('-o')!, join(build, 'execinfo.o')!], {})!
	command([env('VINIX_OPENGOTHIC_AR', lit('aarch64-linux-musl-ar')!)!, lit('rcs')!,
		join(build, 'libexecinfo.a')!, join(build, 'execinfo.o')!], {})!
	cmakefile := join(source, 'CMakeLists.txt')!
	mut cmaketext := read(cmakefile)!
	marker := lit('# Vinix execinfo compatibility')!
	if truth(call('operator.contains', o(cmaketext), o(marker))!)! {
		position := method(cmaketext, 'index', [o(marker)], {})!
		cmaketext = call('operator.getitem', o(cmaketext), o(call('builtins.slice', o(null()!), o(position))!))!
		cmaketext = call('operator.add', o(method(cmaketext, 'rstrip', [], {})!), v(ah.Value('\n')))!
	}
	cmaketext = call('operator.add', o(cmaketext), v(ah.Value('\n${text(marker)!}\ntarget_link_libraries(OpenGothic "${text(join(build, 'libexecinfo.a')!)!}")\n')))!
	method(cmakefile, 'write_text', [o(cmaketext)], {})!
	mut validator := env('GLSLANGVALIDATOR', null()!)!
	if !truth(validator)! { validator = call('shutil.which', v(ah.Value('glslangValidator')))! }
	if !truth(validator)! { validator = call('shutil.which', v(ah.Value('glslang')))! }
	if !truth(validator)! {
		failed('SystemExit', 'Install glslang or set GLSLANGVALIDATOR to its host executable', none)!
	}
	cmake := join(build, 'cmake')!
	command([lit('cmake')!, lit('-S')!, source, lit('-B')!, cmake, lit('-G')!, lit('Ninja')!,
		lit('-DCMAKE_SYSTEM_NAME=Linux')!, lit('-DCMAKE_SYSTEM_PROCESSOR=aarch64')!,
		lit('-DCMAKE_C_COMPILER=${text(cc)!}')!, lit('-DCMAKE_CXX_COMPILER=${text(cxx)!}')!,
		lit('-DCMAKE_BUILD_TYPE=Release')!, lit('-DCMAKE_POLICY_VERSION_MINIMUM=3.5')!,
		lit('-DGLSLANGVALIDATOR=${text(validator)!}')!,
		lit('-DCMAKE_C_FLAGS=-I${text(sysroot)!}/usr/include')!,
		lit('-DCMAKE_CXX_FLAGS=-I${text(sysroot)!}/usr/include -I${text(headers)!}/include -fno-omit-frame-pointer -Wno-error=stringop-overflow')!,
		lit('-DCMAKE_EXE_LINKER_FLAGS=-L${text(sysroot)!}/usr/lib -Wl,--allow-shlib-undefined')!,
		lit('-DALSOFT_BACKEND_ALSA=OFF')!, lit('-DALSOFT_BACKEND_PULSEAUDIO=OFF')!,
		lit('-DALSOFT_BACKEND_JACK=OFF')!, lit('-DALSOFT_BACKEND_PIPEWIRE=OFF')!,
		lit('-DALSOFT_BACKEND_OSS=OFF')!], {})!
	command([lit('cmake')!, lit('--build')!, cmake, lit('--target')!, lit('Gothic2Notr')!, lit('-j')!,
		env('VINIX_OPENGOTHIC_JOBS', lit('8')!)!], {})!
	private := join(staging, 'opt/opengothic')!
	if exists(join(private, 'lib')!)! { call('shutil.rmtree', o(join(private, 'lib')!))! }
	for directory in ['lib', 'usr/lib'] {
		libs := iterator(method(join(runtime, directory)!, 'glob', [v(ah.Value('*.so*'))], {})!)!
		for {
			lib := next(libs)!
			if lib.done { break }
			public('copy_file', [lib.value,
				call('operator.truediv', o(join(private, 'lib')!), o(attribute(lib.value, 'name')!))!], {})!
		}
	}
	public('copy_file', [join(cmake, 'opengothic/Gothic2Notr')!, join(private, 'Gothic2Notr')!], {})!
	launcher := join(staging, 'usr/bin/run-opengothic')!
	public('copy_file', [
		join(global('ROOT')!, 'build-support/opengothic/run-opengothic')!,
		launcher,
	], {})!
	method(launcher, 'chmod', [v(ah.Value(0o755))], {})!
	mkdir(join(private, 'icd')!, false)!
	icd := call('json.loads', o(read(join(runtime, 'usr/share/vulkan/icd.d/lvp_icd.aarch64.json')!)!))!
	set(get(icd, 'ICD')!, 'library_path', lit('/opt/opengothic/lib/libvulkan_lvp.so')!)!
	serialized := invoke('json.dumps', [o(icd)], {
		'indent': v(ah.Value(2))
	})!
	method(join(private, 'icd/lvp.json')!, 'write_text', [o(call('operator.add', o(serialized), v(ah.Value('\n')))!)], {})!
	if truth(attribute(args, 'demo')!)! {
		installer := join(downloads, 'Gothic2_Demo_DE.exe')!
		public('download', [global('DEMO_URL')!, installer], {})!
		sha := method(call('hashlib.sha256', o(method(installer, 'read_bytes', [], {})!))!, 'hexdigest', [], {})!
		if compare('ne', sha, global('DEMO_SHA256')!)! {
			failed('SystemExit', 'Gothic II demo checksum mismatch', none)!
		}
		rewise := join(build, 'rewise')!
		public('checkout', [lit('https://codeberg.org/CYBERDEV/REWise.git')!, rewise,
			global('REWISE')!], {})!
		command([lit('make')!, lit('-C')!, rewise, lit('CC=${text(env('CC', lit('cc')!)!)!}')!,
			lit('CFLAGS=-O2 -Wall -lz')!], {})!
		extracted := join(build, 'demo')!
		mkdir(extracted, false)!
		command([join(rewise, 'rewise')!, lit('-x')!, extracted, installer], {})!
		game := join(staging, 'usr/share/games/gothic2')!
		if exists(game)! { call('shutil.rmtree', o(game))! }
		call('shutil.copytree', o(join(extracted, 'MAINDIR')!), o(game))!
		method(join(game, '.vinix-demo')!, 'write_text', [o(call('operator.add', o(global('DEMO_SHA256')!), v(ah.Value('\n')))!)], {})!
	} else if truth(attribute(args, 'game')!)! {
		public('stage_game', [method(attribute(args, 'game')!, 'resolve', [], {})!,
			join(staging, 'usr/share/games/gothic2')!], {})!
	}
	write(join(private, 'SOURCES.txt')!, 'OpenGothic ${text(global('COMMIT')!)!}\nVulkan-Headers ${text(global('HEADERS')!)!}\nMesa 24.2.8 / LLVM 19.1.4 (Alpine 3.21)\n')!
	invoke('print', [v(ah.Value('Staged OpenGothic: ${text(staging)!}'))], {
		'flush': v(ah.Value(true))
	})!
}
