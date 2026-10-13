// SPDX-License-Identifier: GPL-2.0-or-later
module fontkit

import cachecli
import crypto.sha256
import json2
import os
import sourcecommand
import time

#include <sys/file.h>

fn C.flock(i32, i32) i32

const sources = {
	'freetype': [
		'https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-3.tar.gz',
		'bc5c898e4756d373e0d991bab053036c5eb2aa7c0d5c67e8662ddc6da40c4103',
	]
	'harfbuzz': [
		'https://github.com/harfbuzz/harfbuzz/releases/download/14.5.0/harfbuzz-14.5.0.tar.xz',
		'b7132e148358a45185c9feafd049dbaf243649d3c44414b3534d9c95d18592b9',
	]
}

fn checked(argv []string, log string) ! {
	r := sourcecommand.capture_full(argv, os.environ(), -1, 32 * 1024 * 1024, cachecli.cancelled)!
	text := r.stdout + r.stderr
	os.write_file(log, text)!
	if r.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:',
		'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('font command failed; see ' + log)
	}
}

fn hashes(directory string, relative string, mut files map[string]string) ! {
	for name in os.ls(directory + '/' + relative)!.sorted() {
		path := if relative == '' { name } else { relative + '/' + name }
		if os.is_dir(directory + '/' + path) {
			hashes(directory, path, mut files)!
		} else {
			files[path] = sha256.sum(os.read_bytes(directory + '/' + path)!).hex()
		}
	}
}

fn ready(prefix string) bool {
	row := json2.decode[json2.Any](os.read_file(prefix + '/receipt.json') or { return false }) or { return false }
	data := row.as_map()
	if (data['recipe'] or { json2.Any(0) }).int() != 1 { return false }
	files := (data['files'] or { json2.Null{} }).as_map()
	if files.len == 0 { return false }
	for path, value in files {
		bytes := os.read_bytes(prefix + '/' + path) or { return false }
		if sha256.sum(bytes).hex() != value.str() { return false }
	}
	return true
}

fn build(root string, prefix string, arch string) ! {
	work := sourcecommand.temporary('vinix-font-sdk')!
	defer { os.rmdir_all(work) or {} }
	stage := work + '/sdk'
	for name in ['freetype', 'harfbuzz'] {
		archive := root + '/' + name + '.archive'
		pin := sources[name]
		if !os.exists(archive) || sha256.sum(os.read_bytes(archive)!).hex() != pin[1] {
			part := archive + '.partial'
			defer { if os.exists(part) { os.rm(part) or {} } }
			checked(['curl', '--fail', '--location', '--silent', '--show-error', '--connect-timeout',
				'60', '--speed-limit', '1', '--speed-time', '120', '--output', part, pin[0]], root + '/' + name + '-download.log')!
			if sha256.sum(os.read_bytes(part)!).hex() != pin[1] {
				return error('font SDK source checksum mismatch: ' + name)
			}
			if C.rename(part.str, archive.str) != 0 { return os.error_posix() }
		}
		source, output := work + '/' + name, work + '/' + name + '-build'
		os.mkdir(source)!
		checked(['tar', '-xf', archive, '--strip-components=1', '-C', source], root + '/' + name + '-extract.log')!
		mut options := []string{}
		if name == 'freetype' {
			options = ['-DFT_DISABLE_ZLIB=TRUE', '-DFT_DISABLE_BZIP2=TRUE', '-DFT_DISABLE_PNG=TRUE',
				'-DFT_DISABLE_HARFBUZZ=TRUE', '-DFT_DISABLE_BROTLI=TRUE']
		} else {
			options = ['-DHB_HAVE_FREETYPE=ON', '-DHB_HAVE_GLIB=OFF', '-DHB_HAVE_GOBJECT=OFF',
				'-DHB_HAVE_ICU=OFF', '-DHB_BUILD_SUBSET=ON', '-DHB_BUILD_UTILS=OFF',
				'-DHB_BUILD_TESTS=OFF',
				'-DFREETYPE_INCLUDE_DIR_freetype2=' + stage + '/include/freetype2',
				'-DFREETYPE_INCLUDE_DIR_ft2build=' + stage + '/include/freetype2',
				'-DFREETYPE_LIBRARY_RELEASE=' + stage + '/lib/libfreetype.a']
		}
		$if macos {
			options << '-DCMAKE_OSX_ARCHITECTURES=' + arch
		}
		checked(['cmake', '-S', source, '-B', output, '-DCMAKE_BUILD_TYPE=Release',
			'-DCMAKE_INSTALL_PREFIX=' + stage, '-DBUILD_SHARED_LIBS=OFF', '-DBUILD_TESTING=OFF',
			'-DCMAKE_DISABLE_FIND_PACKAGE_Python3=TRUE',
			'-DCMAKE_DISABLE_FIND_PACKAGE_PythonInterp=TRUE', ...options], root + '/' + name + '-configure.log')!
		checked(['cmake', '--build', output, '--parallel', '4'], root + '/' + name + '-build.log')!
		checked(['cmake', '--install', output], root + '/' + name + '-install.log')!
		if name == 'harfbuzz' {
			os.cp(source + '/src/hb-subset-depend.h', stage + '/include/harfbuzz/hb-subset-depend.h')!
		}
	}
	// Publish only relocatable headers and static libraries. CMake/pkg-config
	// metadata embeds its temporary install directory and is not needed here.
	publication := root + '/publication'
	if os.exists(publication) { os.rmdir_all(publication)! }
	os.mkdir(publication)!
	os.cp_all(stage + '/include', publication + '/include', false)!
	os.mkdir(publication + '/lib')!
	for name in ['libfreetype.a', 'libharfbuzz.a', 'libharfbuzz-subset.a'] {
		os.cp(stage + '/lib/' + name, publication + '/lib/' + name)!
	}
	mut files := map[string]string{}
	hashes(publication, '', mut files)!
	mut records := map[string]json2.Any{}
	for path, digest in files { records[path] = json2.Any(digest) }
	os.write_file(publication + '/receipt.json', json2.encode(json2.Any({
		'recipe': json2.Any(1)
		'files':  json2.Any(records)
	}),
		prettify: true
	) + '\n')!
	previous := root + '/previous-sdk'
	if os.exists(previous) { os.rmdir_all(previous)! }
	if os.exists(prefix) && C.rename(prefix.str, previous.str) != 0 { return os.error_posix() }
	if C.rename(publication.str, prefix.str) != 0 {
		failure := os.error_posix()
		if os.exists(previous) { C.rename(previous.str, prefix.str) }
		return failure
	}
	if os.exists(previous) { os.rmdir_all(previous)! }
}

fn quote(value string) string { return "'" + value.replace("'", '\'"\'"\'') + "'" }

pub fn run(source string, argv []string) !int {
	compiler := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	arch := $if arm64 { 'arm64' } $else { 'x86_64' }
	root := (os.getenv_opt('VINIX_FONT_CACHE') or { os.home_dir() + '/.cache/vinix/fonts' }) + '/native-sdk-1-' + os.user_os() + '-' + arch
	os.mkdir_all(root)!
	fd := C.open((root + '/lock').str, C.O_CREAT | C.O_RDWR | C.O_CLOEXEC, 0o600)
	if fd < 0 { return os.error_posix() }
	defer { C.close(fd) }
	for C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		if C.errno !in [C.EWOULDBLOCK, C.EINTR] { return os.error_posix() }
		cachecli.checkpoint()!
		time.sleep(20 * time.millisecond)
	}
	defer { C.flock(fd, C.LOCK_UN) }
	prefix := os.getenv_opt('VINIX_FONT_SDK') or { root + '/sdk' }
	if os.getenv('VINIX_FONT_SDK') == '' && !ready(prefix) { build(root, prefix, arch)! }
	for file in ['include/freetype2/ft2build.h', 'include/harfbuzz/hb-subset-depend.h',
		'lib/libfreetype.a', 'lib/libharfbuzz.a', 'lib/libharfbuzz-subset.a'] {
		if !os.is_file(prefix + '/' + file) {
			return error('native font SDK is incomplete: ' + file)
		}
	}
	work := sourcecommand.temporary('vinix-font-tool')!
	defer { os.rmdir_all(work) or {} }
	cflags := '-I' + quote(prefix + '/include/freetype2') + ' -I' + quote(prefix + '/include/harfbuzz')
	mut ldflags := [prefix + '/lib/libharfbuzz-subset.a', prefix + '/lib/libharfbuzz.a',
		prefix + '/lib/libfreetype.a'].map(quote(it)).join(' ')
	$if macos {
		ldflags += ' -lc++ -framework CoreText -framework CoreGraphics -framework CoreFoundation'
	} $else {
		ldflags += ' -lstdc++ -lm -pthread'
	}
	mut target := []string{}
	$if macos {
		target = ['-arch', if arch == 'arm64' { 'arm64' } else { 'amd64' }, '-cflags',
			'--target=' + arch + '-apple-macos13', '-ldflags', '--target=' + arch + '-apple-macos13']
	}
	checked([compiler, '-nocache', '-cc', 'cc', ...target, '-d', 'font_sdk_custom', '-cflags',
		cflags, '-ldflags', ldflags, '-o', work + '/tool', source], work + '/build.log')!
	return sourcecommand.run_in([work + '/tool', ...argv], os.environ(), '', cachecli.cancelled, '')!.status
}
