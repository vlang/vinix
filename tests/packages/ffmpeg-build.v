// SPDX-License-Identifier: GPL-2.0-or-later
// V orchestration of unmodified upstream FFmpeg and the static V SDK runner.
module main

import json2
import os
import tools.packages.pkgcore

struct SourceLock {
	format int @[required]
	version string @[required]
	url string @[required]
	bytes u64 @[required]
	sha256 string @[required]
}

struct Artifact { path string bytes u64 sha256 string }
struct BuildRecord {
	format int = 1
	version string
	source SourceLock
	commands [][]string
	artifacts []Artifact
}

fn run(argv []string, directory string, log string) !string {
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	if directory != '' { child.set_work_folder(directory) }
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	if log != '' { os.write_file(log, output)! }
	if child.code != 0 { return error('FFmpeg build command failed (${child.code}): ${argv}; ${log}\n' + output) }
	return output.trim_space()
}

fn build() ! {
	if os.args.len != 3 { return error('usage: ffmpeg-build PINNED_TAR_XZ NEW_OUTPUT_DIRECTORY') }
	repository := os.dir(os.dir(os.dir(@FILE)))
	archive := os.abs_path(os.args[1])
	output := os.abs_path(os.args[2])
	if os.is_link(archive) || !os.is_file(archive) || os.exists(output) || os.is_link(output) {
		return error('provide an ordinary pinned archive and a fresh output directory')
	}
	source := json2.decode[SourceLock](os.read_file(repository + '/tests/packages/ffmpeg-source.json')!)!
	assert source.format == 1 && source.version == '8.0.1'
	if os.file_size(archive) != source.bytes || pkgcore.hash_file(archive)! != source.sha256 {
		return error('FFmpeg source archive differs from the reviewed lock')
	}
	os.mkdir_all(output + '/source', mode: 0o700)!
	os.cp(archive, output + '/ffmpeg.tar.xz')!
	assert pkgcore.hash_file(output + '/ffmpeg.tar.xz')! == source.sha256
	os.chmod(output + '/ffmpeg.tar.xz', 0o444)!
	// The extractor only receives the pinned, retained archive. Check its
	// names first; never extract arbitrary publisher input as a host operation.
	list := run(['/usr/bin/tar', '-tJf', output + '/ffmpeg.tar.xz'], '', output + '/archive-list.txt')!
	for path in list.split_into_lines() {
		if !path.starts_with('ffmpeg-8.0.1/') || path.split('/').any(it == '..') || path.contains('\\') {
			return error('unexpected FFmpeg source archive path: ${path}')
		}
	}
	run(['/usr/bin/tar', '-xJf', output + '/ffmpeg.tar.xz', '--strip-components=1', '-C', output + '/source'], '', '')!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	make := os.find_abs_path_of_executable('make')!
	mut commands := [][]string{}
	mut artifacts := []Artifact{}
	for architecture in ['aarch64', 'x86_64'] {
		cc := os.find_abs_path_of_executable(os.getenv_opt('VINIX_MUSL_CC_' + architecture.to_upper()) or { architecture + '-linux-musl-gcc' })!
		root := output + '/roots/' + architecture
		work := output + '/build-' + architecture
		for directory in ['bin', 'lib', 'licenses', 'sources'] { os.mkdir_all(root + '/' + directory)! }
		os.mkdir_all(work)!
		configure := [output + '/source/configure', '--enable-cross-compile', '--target-os=linux',
			'--arch=' + architecture, '--cc=' + cc, '--cross-prefix=' + architecture + '-linux-musl-',
			'--prefix=/ffmpeg', '--disable-autodetect', '--disable-everything', '--disable-doc', '--disable-debug', '--disable-stripping',
			'--disable-x86asm', '--disable-asm', '--disable-network', '--disable-hwaccels', '--disable-gpl', '--disable-nonfree',
			'--disable-static', '--enable-shared', '--enable-pic', '--enable-ffmpeg', '--enable-ffprobe', '--disable-ffplay',
			'--enable-protocol=file,pipe', '--enable-indev=lavfi', '--enable-muxer=avi,wav,null', '--enable-demuxer=avi,wav',
			'--enable-encoder=mpeg4,rawvideo,pcm_s16le', '--enable-decoder=mpeg4,rawvideo,pcm_s16le,wrapped_avframe', '--enable-parser=mpeg4video',
			'--enable-filter=testsrc2,sine,scale,format,aresample,anull,null', '--extra-cflags=-O2 -fno-stack-protector',
			'--extra-ldexeflags=-pie']
		commands << configure
		run(configure, work, work + '/configure.log')!
		compile := [make, '-j4']
		commands << compile
		run(compile, work, work + '/make.log')!
		for name in ['ffmpeg', 'ffprobe'] { os.cp(work + '/' + name, root + '/bin/' + name)! }
		for library in ['avcodec', 'avdevice', 'avfilter', 'avformat', 'avutil', 'swresample', 'swscale'] {
			paths := os.ls(work + '/lib' + library)!.filter(it.starts_with('lib' + library + '.so.'))
			ordinary := paths.filter(!os.is_link(work + '/lib' + library + '/' + it))
			if ordinary.len != 1 { return error('expected one ordinary FFmpeg shared library: ${library}: ${paths}') }
			// SONAME's major alias is what the target loader resolves. Materialize
			// its bytes; package payloads never contain symlinks.
			parts := ordinary[0].split('.')
			name := parts[..3].join('.')
			os.cp(work + '/lib' + library + '/' + ordinary[0], root + '/lib/' + name)!
		}
		loader := run([cc, '-print-file-name=libc.so'], '', '')!
		os.cp(loader, root + '/lib/libc.so')!
		generated := work + '/runner.c'
		generate := [v, '-os', 'linux', '-arch', if architecture == 'aarch64' { 'arm64' } else { 'amd64' },
			'-gc', 'none', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', generated, repository + '/tools/packages/linux-runner.v']
		link := [cc, '-static', '-O2', '-std=gnu11', '-D_GNU_SOURCE', generated, '-o', root + '/bin/vinix-linux-runner', '-lm', '-lpthread']
		commands << generate
		run(generate, '', work + '/runner-generate.log')!
		commands << link
		run(link, '', work + '/runner-link.log')!
		for path in os.walk_ext(root + '/bin', '') { os.chmod(path, 0o755)! }
		for path in os.walk_ext(root + '/lib', '') { os.chmod(path, 0o755)! }
		for name in ['LICENSE.md', 'COPYING.LGPLv2.1'] { os.cp(output + '/source/' + name, root + '/licenses/ffmpeg-' + name)! }
		os.cp(repository + '/build-support/musl/COPYRIGHT', root + '/licenses/musl-COPYRIGHT')!
		os.cp(repository + '/LICENSE', root + '/licenses/vinix-COPYING')!
		os.cp(os.dir(v) + '/LICENSE', root + '/licenses/v-COPYRIGHT')!
		os.cp(output + '/ffmpeg.tar.xz', root + '/sources/ffmpeg.tar.xz')!
		os.cp(repository + '/tools/packages/linux-runner.v', root + '/sources/linux-runner.v')!
		os.cp(repository + '/tests/packages/ffmpeg-build.v', root + '/sources/ffmpeg-build.v')!
		os.cp(repository + '/tests/packages/ffmpeg-source.json', root + '/sources/ffmpeg-source.json')!
		os.write_file(root + '/sources/build.json', json2.encode(commands.filter(it.len > 0)) + '\n')!
		for path in os.walk_ext(root, '').filter(os.is_file(it)) {
			artifacts << Artifact{ path: path, bytes: os.file_size(path), sha256: pkgcore.hash_file(path)! }
		}
	}
	os.write_file(output + '/build.json', json2.encode(BuildRecord{ version: source.version, source: source, commands: commands, artifacts: artifacts }) + '\n')!
	println('FFmpeg inputs: pinned unmodified source, both target CLIs, shared libraries, notices and source archive built')
}

fn main() { build() or { eprintln(err); exit(1) } }
