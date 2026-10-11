// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

struct Package {
	architecture string
	name         string
	version      string
	url          string
	sha256       string
}

fn run(argv []string) ! {
	mut child := os.new_process(argv[0])
	child.set_args(argv[1..])
	child.run()
	child.wait()
	defer { child.close() }
	if child.code != 0 { return error('SDK command failed: ' + argv.str()) }
}

fn unpack_deb(archive string, output string) ! {
	mut child := os.new_process('ar')
	child.set_args(['x', os.real_path(archive)])
	child.set_work_folder(os.real_path(output))
	child.run()
	child.wait()
	defer { child.close() }
	if child.code != 0 { return error('Debian archive extraction failed') }
}

fn stage(architecture string, output string) ! {
	if os.exists(output) { return error('SDK output directory must be fresh') }
	root := os.real_path(os.dir(@FILE) + '/../../..')
	pin_file := root + '/tools/linux-compat/reference/glibc-packages.json'
	pin_bytes := os.read_bytes(pin_file)!
	pins := json2.decode[[]Package](pin_bytes.bytestr())!
	packages := pins.filter(it.architecture == architecture)
	if packages.len != 4 { return error('incomplete pinned SDK') }
	os.mkdir_all(output + '/downloads')!
	os.mkdir_all(output + '/sysroot')!
	for package in packages {
		if !package.url.starts_with('https://deb.debian.org/debian/pool/')
			|| !package.url.ends_with('.deb') || package.sha256.len != 64 {
			return error('invalid Debian package pin')
		}
		archive := output + '/downloads/' + package.url.all_after_last('/')
		run(['curl', '--fail', '--location', '--max-time', '90', '--output', archive,
			package.url])!
		bytes := os.read_bytes(archive)!
		if sha256.sum(bytes).hex() != package.sha256 {
			return error('SDK package hash mismatch: ' + package.name)
		}
		payload := output + '/payload-' + package.name
		os.mkdir_all(payload)!
		// Extract verified build inputs only. No dpkg or maintainer script runs.
		unpack_deb(archive, payload)!
		data := os.ls(payload)!.filter(it.starts_with('data.tar.'))
		if data.len != 1 { return error('ambiguous Debian payload') }
		run(['/usr/bin/tar', '-xf', payload + '/' + data[0], '-C', output + '/sysroot'])!
	}
	os.write_file(output + '/packages.json', json2.encode(packages, prettify: true) + '\n')!
	os.write_file(output + '/pins.sha256', sha256.sum(pin_bytes).hex() + '\n')!
	println(os.real_path(output + '/sysroot'))
}

fn main() {
	if os.args.len != 3 || os.args[1] !in ['arm64', 'amd64', 'i386'] {
		eprintln('Usage: sdk/main.v arm64|amd64|i386 FRESH-OUTPUT-DIR')
		exit(2)
	}
	stage(os.args[1], os.args[2]) or { eprintln(err.msg()); exit(1) }
}
