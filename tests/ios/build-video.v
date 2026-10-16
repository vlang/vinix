// SPDX-License-Identifier: GPL-2.0-or-later
// Build the optional ARM64 software VideoToolbox backend from reviewed sources.
module main

import os
import crypto.sha256
import json2

struct VideoSource {
	version string
	bytes u64
	sha256 string
}

fn video_command(args []string, directory string, log string) {
	mut child := os.new_process(args[0])
	child.set_args(args[1..])
	child.set_work_folder(directory)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	status := child.code
	child.close()
	os.write_file(log, output) or { panic(err) }
	assert status == 0, output
}

fn main() {
	if os.args.len !in [3, 4]! { panic('usage: build-video FFMPEG_ARCHIVE NEW_SDK_DIRECTORY [AARCH64_MUSL_CC]') }
	root := os.real_path(os.getwd())
	archive := os.real_path(os.args[1])
	out := os.abs_path(os.args[2])
	compiler := os.find_abs_path_of_executable(if os.args.len == 4 { os.args[3] } else { 'aarch64-linux-musl-gcc' }) or { panic(err) }
	manifest := json2.decode[VideoSource](os.read_file(root + '/tests/packages/ffmpeg-source.json') or { panic(err) }) or { panic(err) }
	bytes := os.read_bytes(archive) or { panic(err) }
	assert u64(bytes.len) == manifest.bytes && sha256.sum(bytes).hex() == manifest.sha256, 'FFmpeg archive differs from reviewed package source'
	assert !os.exists(out), 'use a fresh SDK directory; existing build evidence is preserved'
	os.mkdir_all(out + '/source') or { panic(err) }
	os.mkdir(out + '/arm64') or { panic(err) }
	video_command(['tar', '-xJf', archive, '--strip-components=1', '-C', out + '/source'], root, out + '/extract.log')
	args := [out + '/source/configure', '--enable-cross-compile', '--target-os=linux', '--arch=aarch64', '--cc=' + compiler,
		'--disable-autodetect', '--disable-everything', '--disable-programs', '--disable-doc', '--disable-debug', '--disable-network',
		'--disable-asm', '--disable-inline-asm', '--disable-hwaccels', '--disable-avdevice', '--disable-avfilter', '--disable-avformat', '--disable-swresample',
		'--disable-gpl', '--disable-nonfree', '--enable-avcodec', '--enable-avutil', '--enable-swscale', '--enable-decoder=h264,hevc,rawvideo',
		'--enable-parser=h264,hevc', '--enable-static', '--disable-shared', '--enable-pic', '--extra-cflags=-O2 -fno-stack-protector -ffixed-x18']
	os.write_file(out + '/configure-args.txt', args.join('\n') + '\n') or { panic(err) }
	video_command(args, out + '/arm64', out + '/configure.log')
	video_command(['make', '-j4'], out + '/arm64', out + '/make.log')
	for name in ['avcodec', 'swscale', 'avutil']! {
		path := out + '/arm64/lib' + name + '/lib' + name + '.a'
		os.write_file(path + '.sha256', sha256.sum(os.read_bytes(path) or { panic(err) }).hex()) or { panic(err) }
	}
	os.write_file(out + '/source.sha256', manifest.sha256) or { panic(err) }
	os.write_file(out + '/build.status.txt', '0\n') or { panic(err) }
	println('Built FFmpeg ' + manifest.version + ' ARM64 software VideoToolbox backend: ' + out)
}
