// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import crypto.sha256
import json2
import os

fn command(args []string) ! {
	if os.system_args(args) != 0 { return error('boot library command failed') }
}

fn main() {
	tls := os.args.len == 4 && os.args[1] == '--tls-lifetime'
	args := if tls { os.args[2..] } else { os.args[1..] }
	if args.len != 2 { panic('usage: delegate-last-build [--tls-lifetime] BOOT_JAR FRESH_OUTPUT') }
	input, root := os.abs_path(args[0]), os.abs_path(args[1])
	if os.exists(root) { panic('fresh output required') }
	os.mkdir_all(root)!
	before := sha256.sum(os.read_bytes(input)!).hex()
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	cp := '/Users/alex/code/vinix/build/android-framework/tools/*'
	command([java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', input, '-o', root + '/smali'])!
	// Produce an unchanged assembly control: smali canonicalizes explicit
	// zero-valued static fields even when no adapter touches the class.
	command([java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/control.dex'])!
	command([java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', root + '/control.dex', '-o', root + '/control'])!
	if tls { androidtools.boot_tls_lifetime(root + '/smali')! }
	else { androidtools.boot_delegate_last(root + '/smali')! }
	command([java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'])!
	output := root + if tls { '/wolfssljni-hostdex.jar' } else { '/core-libart-hostdex.jar' }
	os.cp(input, output)!
	command(['/usr/bin/zip', '-q', '-j', output, root + '/classes.dex'])!
	command([java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', output, '-o', root + '/readback'])!
	mut names := []string{}
	for path in os.walk_ext(root + '/smali', '.smali') {
		name := path.all_after(root + '/smali/')
		original := os.read_file(root + '/control/' + name)!
		actual := os.read_file(root + '/readback/' + name)!
		// Compare every unrelated class with the unchanged assembly control.
		changed := if tls {
			name in ['com/wolfssl/provider/jsse/WolfSSLSocket.smali',
				'com/wolfssl/provider/jsse/WolfSSLSocket$WolfSSLInputStream.smali',
				'com/wolfssl/provider/jsse/WolfSSLSocket$WolfSSLOutputStream.smali']
		} else { name == 'dalvik/system/DelegateLastClassLoader.smali' }
		if !changed && original != actual {
			panic('unrelated boot class changed: ' + name)
		}
		names << name
	}
	if names.len != os.walk_ext(root + '/readback', '.smali').len { panic('boot class count changed') }
	if before != sha256.sum(os.read_bytes(input)!).hex() { panic('boot input changed') }
	os.write_file(root + '/receipt.json', json2.encode({
		'input': json2.Any(input), 'input_sha256': json2.Any(before),
		'output_sha256': json2.Any(sha256.sum(os.read_bytes(output)!).hex()),
		'classes': json2.Any(names.len), 'v_compiler': json2.Any(@VEXE),
		'v_revision': json2.Any(@VHASH)
	}, prettify: true))!
	println((if tls { 'TLS-LIFETIME' } else { 'DELEGATE-LAST' }) + '-BUILD-PASS classes=' + names.len.str())
}
