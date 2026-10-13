// SPDX-License-Identifier: GPL-2.0-or-later
// Build a minimal native BusyBox HTTP/CGI server from a caller-pinned archive.
module main

import devcore
import json2
import os
import sourcecommand

struct SourcePatch {
	path string
	before_sha256 string
	after_sha256 string
}

struct Receipt {
	schema int = 1
	architecture string
	source devcore.Pin
	make devcore.Pin
	cc devcore.Pin
	host_cc devcore.Pin
	tar devcore.Pin
	epoch i64 = 1700000000
mut:
	source_tree_sha256 string
	patches []SourcePatch
	patched_source_tree_sha256 string
	configuration_sha256 string
	binary_sha256 string
	complete bool
}

fn build() ! {
	if os.args.len == 2 && os.args[1] == '--help' {
		println('Usage: v run build-http.v aarch64|x86_64 BUSYBOX-1.36.1-ARCHIVE EXPECTED-SHA256 FRESH-BUILD')
		return
	}
	if os.args.len != 5 || os.args[1] !in ['aarch64', 'x86_64'] { return error('invalid arguments; use --help') }
	arch := os.args[1]
	archive := os.real_path(os.args[2])
	if os.lstat(os.args[2])!.get_filetype() != .regular { return error('source archive must be an ordinary file') }
	pin := devcore.Pin{archive, os.args[3]}
	devcore.verify(pin)!
	cc := os.find_abs_path_of_executable(arch + '-linux-musl-gcc')!
	host_cc := os.find_abs_path_of_executable('cc')!
	make := os.find_abs_path_of_executable('make')!
	tar := os.find_abs_path_of_executable('tar')!
	mut env := devcore.environment(1700000000)
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	listing := sourcecommand.capture([tar, '-tf', archive], env, 30, 2 * 1024 * 1024, unsafe { nil })!
	if listing.status != 0 { return error('cannot inspect source archive') }
	for line in listing.stdout.split_into_lines() {
		path := line.trim_right('/')
		if path != 'busybox-1.36.1' && !path.starts_with('busybox-1.36.1/') { return error('unexpected archive root') }
		if path.split('/').any(it in ['..', '.']) || path.contains('\x00') { return error('invalid source archive path') }
	}
	devcore.fresh_directory(os.args[4])!
	out := os.real_path(os.args[4])
	mut receipt := Receipt{architecture: arch, source: pin, make: devcore.Pin{make, devcore.file_hash(make)!},
		cc: devcore.Pin{cc, devcore.file_hash(cc)!}, host_cc: devcore.Pin{host_cc, devcore.file_hash(host_cc)!},
		tar: devcore.Pin{tar, devcore.file_hash(tar)!}}
	manifest := out + '/http-server.json'
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	if devcore.run([tar, '-xf', archive, '-C', out, '--exclude=*.py', '--exclude=*.pyc', '--exclude=*.pyo'],
		os.getwd(), env, 120, out + '/extract.log')! != 0 { return error('source export failed') }
	source := out + '/busybox-1.36.1'
	receipt.source_tree_sha256 = devcore.tree_hash(source)!
	// BusyBox 1.36.1 reaches the body loop even when HEAD requested headers
	// alone. Preserve its headers and exit before sending file bytes.
	httpd := source + '/networking/httpd.c'
	before := devcore.file_hash(httpd)!
	text := os.read_file(httpd)!
	anchor := '\tif (what & SEND_HEADERS)\n\t\tsend_headers(HTTP_OK);\n#if ENABLE_FEATURE_USE_SENDFILE\n'
	if text.count(anchor) != 1 { return error('unrecognized BusyBox HEAD source; adaptation refused') }
	os.write_file(httpd, text.replace(anchor, '\tif (what & SEND_HEADERS)\n\t\tsend_headers(HTTP_OK);\n\tif (!(what & SEND_BODY))\n\t\tlog_and_exit();\n#if ENABLE_FEATURE_USE_SENDFILE\n'))!
	receipt.patches << SourcePatch{'networking/httpd.c', before, devcore.file_hash(httpd)!}
	receipt.patched_source_tree_sha256 = devcore.tree_hash(source)!
	if devcore.run([make, 'allnoconfig', 'HOSTCC=' + host_cc], source, env, 120, out + '/config.log')! != 0 {
		return error('HTTP configuration failed')
	}
	// This BusyBox Kconfig resets bools during allnoconfig, including values
	// in KCONFIG_ALLCONFIG. Start with its complete disabled configuration,
	// then apply explicit selections through the noninteractive defconfig mode.
	selections := ['BUSYBOX', 'STATIC', 'HTTPD', 'FEATURE_HTTPD_BASIC_AUTH',
		'FEATURE_HTTPD_CGI', 'SHOW_USAGE', 'FEATURE_VERBOSE_USAGE']
	mut configuration := os.read_file(source + '/.config')!
	for name in selections {
		configuration = configuration.replace('# CONFIG_' + name + ' is not set', 'CONFIG_' + name + '=y')
	}
	configuration += '\nCONFIG_FEATURE_HTTPD_PORT_DEFAULT=8080\n'
	os.write_file(source + '/http.config', configuration)!
	if devcore.run([make, 'defconfig', 'KBUILD_DEFCONFIG=http.config', 'HOSTCC=' + host_cc],
		source, env, 120, out + '/select.log')! != 0 { return error('HTTP selections failed') }
	resolved := os.read_file(source + '/.config')!.split_into_lines()
	for name in selections {
		if 'CONFIG_' + name + '=y' !in resolved { return error('required HTTP configuration is disabled: ' + name) }
	}
	receipt.configuration_sha256 = devcore.file_hash(source + '/.config')!
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	if devcore.run([make, '-j4', 'HOSTCC=' + host_cc, 'CROSS_COMPILE=' + cc.trim_string_right('gcc')],
		source, env, 300, out + '/build.log')! != 0 { return error('HTTP server compilation failed; see ' + out + '/build.log') }
	devcore.verify(pin)!
	devcore.verify(receipt.make)!
	devcore.verify(receipt.cc)!
	devcore.verify(receipt.host_cc)!
	devcore.verify(receipt.tar)!
	devcore.verify(devcore.Pin{source + '/.config', receipt.configuration_sha256})!
	binary := source + '/busybox'
	mut file := os.open(binary)!
	mut header := []u8{len: 20}
	count := file.read(mut header)!
	file.close()
	if count != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| (u16(header[18]) | (u16(header[19]) << 8)) != if arch == 'aarch64' { u16(183) } else { u16(62) } {
		return error('HTTP build has the wrong native ELF architecture')
	}
	receipt.binary_sha256 = devcore.file_hash(binary)!
	receipt.complete = true
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	println('Built native HTTP server: ' + source + '/busybox')
}
fn main() { build() or { eprintln(err); exit(1) } }
