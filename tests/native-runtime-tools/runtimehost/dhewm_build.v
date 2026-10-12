// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import crypto.md5
import gamehost
import hosttest
import os
import tarstream

pub const doom_commit = '455b88e8dff2be822f08eb498f51b383e851fa38'
pub const doom_demo_url = 'https://files.holarse-linuxgaming.de/native/Spiele/Doom%203/Demo/doom3-linux-1.1.1286-demo.x86.run'
pub const doom_demo_md5 = '70c2c63ef1190158f1ebd6c255b22d8e'

fn md5_digest(name string) !string {
	mut file := os.open(name)!
	defer { file.close() }
	mut hash := md5.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { 0 } else { return err } }
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

fn private_directory(base string) !string {
	mut pattern := (gamehost.path(base, '.vinix-runtime.XXXXXX') + '\x00').bytes()
	if C.mkdtemp(pattern.data) == unsafe { nil } { return os.error_posix() }
	return pattern.bytestr().all_before('\x00')
}

pub fn install_doom_demo(installer string, destination string) ! {
	directory := private_directory(gamehost.parent(installer))!
	defer { gamehost.remove(directory) or {} }
	mut file := os.open(installer)!
	defer { file.close() }
	mut byte := []u8{len: 1}
	mut lines := 0
	for lines < 373 {
		count := file.read(mut byte) or { if err is os.Eof { 0 } else { return err } }
		if count == 0 { break }
		if byte[0] == `\n` { lines++ }
	}
	compressed := directory + '/payload.gz'
	mut output := os.create(compressed)!
	defer { output.close() }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { 0 } else { return err } }
		if count == 0 { break }
		unsafe { output.write_full_buffer(buffer.data, usize(count))! }
	}
	output.close()
	mut reader := tarstream.open(compressed)!
	defer { reader.close() }
	for {
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		if member.name != 'demo/demo00.pk4' { continue }
		mut demo := os.create(destination)!
		defer { demo.close() }
		for {
			count := reader.read(mut buffer)!
			if count == 0 { break }
			unsafe { demo.write_full_buffer(buffer.data, usize(count))! }
		}
		return
	}
}

fn doom_headers(records string, requested []string, repo string) ![]string {
	mut result := []string{}
	for name in requested {
		mut found := false
		for record in records.split('\n\n') {
			if !(record + '\n').contains('P:' + name + '\n') { continue }
			versions := record.split_into_lines().filter(it.starts_with('V:'))
			if versions.len == 0 { return error('package version missing: ' + name) }
			result << '${repo}\t${name}-${versions[0][2..]}.apk'
			found = true
			break
		}
		if !found { return error('development package not found: ' + name) }
	}
	return result
}

pub fn build_dhewm(tools gamehost.Tools, build string, x11 string) ! {
	downloads := gamehost.path(build, 'downloads')
	sysroot := gamehost.path(build, 'sysroot')
	runtime := gamehost.path(build, 'runtime')
	stage := gamehost.path(build, 'staging')
	gamehost.remove(runtime)!
	for directory in [downloads, sysroot, runtime] { gamehost.mkdir(directory)! }
	source := gamehost.path(build, 'source')
	if !os.exists(source) {
		tools.run(['git', 'clone', '--depth', '1', '--branch', '1.5.5',
			'https://github.com/dhewm/dhewm3.git', source])!
	}
	if tools.output(['git', '-C', source, 'rev-parse', 'HEAD'])!.trim_space() != doom_commit {
		return error('dhewm3 source is not the pinned 1.5.5 commit')
	}
	if !os.is_file(gamehost.path(x11, 'sysroot/usr/include/GL/gl.h')) {
		return error('Build the X11 layer first with scripts/build-x11-aarch64.sh')
	}
	mut command := [gamehost.path(tools.root, 'build-support/alpine-resolve')]
	mut indexes := map[string]string{}
	for repo in ['main', 'community'] {
		compressed := gamehost.path(downloads, '${repo}_APKINDEX.tar.gz')
		index := gamehost.path(downloads, '${repo}_APKINDEX')
		tools.download('${gamehost.mirror}/${repo}/aarch64/APKINDEX.tar.gz', compressed)!
		gamehost.archive_index(compressed, index)!
		indexes[repo] = os.read_file(index)!
		command << ['--index', repo, index]
	}
	command << ['sdl2', 'openal-soft-libs', 'libcurl', 'libstdc++', 'libbsd', 'xz-libs', 'gmp',
		'libuuid', 'libpciaccess', 'wayland-libs-client']
	packages_text := tools.output(command)!
	os.write_file(gamehost.path(build, 'packages.tsv'), packages_text)!
	packages := packages_text.split_into_lines()
	development := [...doom_headers(indexes['main'], ['curl-dev'], 'main')!,
		...doom_headers(indexes['community'], ['sdl2-dev', 'openal-soft-dev'], 'community')!]
	archives := tools.fetch_archives(downloads, [...packages, ...development])!
	for index, archive in archives {
		tools.run(['tar', '--ignore-zeros', '-xzf', archive, '-C', sysroot])!
		if index < packages.len {
			tools.run(['tar', '--ignore-zeros', '-xzf', archive, '-C', runtime])!
		}
	}
	cmake := gamehost.path(build, 'cmake')
	tools.run(['cmake', '-S', gamehost.path(source, 'neo'), '-B', cmake, '-G', 'Ninja',
		'-DCMAKE_SYSTEM_NAME=Linux', '-DCMAKE_SYSTEM_PROCESSOR=aarch64',
		'-DCMAKE_C_COMPILER=' + gamehost.env('VINIX_DHEWM3_CC', 'aarch64-linux-musl-gcc'),
		'-DCMAKE_CXX_COMPILER=' + gamehost.env('VINIX_DHEWM3_CXX', 'aarch64-linux-musl-g++'),
		'-DCMAKE_BUILD_TYPE=Release', '-DD3XP=OFF', '-DREPRODUCIBLE_BUILD=ON',
		'-DOPENAL_INCLUDE_DIR=${sysroot}/usr/include',
		'-DOPENAL_LIBRARY=${sysroot}/usr/lib/libopenal.so',
		'-DSDL2_INCLUDE_DIR=${sysroot}/usr/include/SDL2',
		'-DSDL2_LIBRARY=${sysroot}/usr/lib/libSDL2.so', '-DCURL_INCLUDE_DIR=${sysroot}/usr/include',
		'-DCURL_LIBRARY=${sysroot}/usr/lib/libcurl.so',
		'-DCMAKE_CXX_FLAGS=-I${x11}/sysroot/usr/include -g -fno-omit-frame-pointer',
		'-DCMAKE_EXE_LINKER_FLAGS=-Wl,--allow-shlib-undefined'])!
	tools.run(['cmake', '--build', cmake, '-j', gamehost.env('VINIX_DHEWM3_JOBS', '8')])!
	for folder in ['lib', 'usr/lib'] { gamehost.remove(gamehost.path(stage, folder))! }
	for folder in ['usr/bin', 'usr/lib/dhewm3', 'lib', 'usr/share/games/dhewm3/demo'] {
		gamehost.mkdir(gamehost.path(stage, folder))!
	}
	for pair in [
		[gamehost.path(cmake, 'dhewm3'), gamehost.path(stage, 'usr/bin/dhewm3')],
		[gamehost.path(cmake, 'base.so'), gamehost.path(stage, 'usr/lib/dhewm3/base.so')],
		[gamehost.path(tools.root, 'build-support/dhewm3/run-dhewm3'),
			gamehost.path(stage, 'usr/bin/run-dhewm3')],
	] {
		hosttest.module_copy_file_preserving_stat(pair[0], pair[1])!
	}
	gui := gamehost.path(stage, 'usr/share/games/dhewm3/demo/guis/map/loading.gui')
	gamehost.mkdir(gamehost.parent(gui))!
	hosttest.module_copy_file_preserving_stat(gamehost.path(tools.root, 'build-support/dhewm3/loading.gui'), gui)!
	for folder in ['lib', 'usr/lib'] {
		directory := gamehost.path(runtime, folder)
		if !os.is_dir(directory) { continue }
		for name in os.ls(directory)! {
			if name.match_glob('*.so*') {
				gamehost.copy_file(gamehost.path(directory, name), gamehost.path(stage, folder + '/' + name))!
			}
		}
	}
	demo := gamehost.path(stage, 'usr/share/games/dhewm3/demo/demo00.pk4')
	if !os.exists(demo) {
		installer := gamehost.path(downloads, 'doom3-linux-1.1.1286-demo.x86.run')
		tools.download(doom_demo_url, installer)!
		install_doom_demo(installer, demo)!
	}
	if os.file_size(demo) != 483535485 || md5_digest(demo)! != doom_demo_md5 {
		return error('Doom 3 Linux demo checksum mismatch')
	}
	os.write_file(gamehost.path(stage, 'usr/share/games/dhewm3/SOURCES.txt'), 'dhewm3 1.5.5 ${doom_commit}\n${doom_demo_url}\ndemo00.pk4 MD5 ${doom_demo_md5}\n')!
	println('Staged dhewm3 and verified demo: ' + stage)
}
