// SPDX-License-Identifier: GPL-2.0-or-later
// Inspect one retained GMS class; no APK extraction or historical-cache writes.
module main

import androidhost
import crypto.sha256
import json2
import os

const state = '/Users/alex/.local/state/vinix/android'
const baseline = state + '/gms-cookie-method-audit-evidence-2026-10-26-r3'
const baseline_pin = 'bfdfc413af353e175b802672efa96475f5e7e07799016b9a19bc136b060954ee'
const apk = state + '/maps286-2026-10-25/prelaunch/inputs/build/android-maps/GooglePlayServices.apk'
const apk_pin = 'a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707'
const java = '/opt/homebrew/opt/openjdk@25/bin/java'
const java_pin = '236c86402d47923ebc974f8237175038eedfcb3b8a7594b2a2dd8113249b99ea'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buf := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buf) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buf[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn inspect(root string) ! {
	if !os.is_abs_path(root) || os.exists(root) || os.is_link(root)
		|| os.real_path(os.dir(root)) != os.dir(root) {
		return error('fresh canonical external output required')
	}
	if hash(baseline + '/sha256.json')! != baseline_pin || hash(apk)! != apk_pin
		|| hash(java)! != java_pin { return error('audited input identity differs') }
	pins := json2.decode[map[string]string](os.read_file(baseline + '/sha256.json')!)!
	mut inputs := map[string]string{}
	inputs[apk] = apk_pin
	inputs[java] = java_pin
	inputs[baseline + '/sha256.json'] = baseline_pin
	mut owner := ''
	for n in 1 .. 16 {
		name := 'dex/classes' + if n == 1 { '.dex' } else { n.str() + '.dex' }
		path := baseline + '/' + name
		expected := pins[name] or { return error('DEX absent from audited inventory') }
		if hash(path)! != expected { return error('DEX identity differs') }
		inputs[path] = expected
		data := os.read_bytes(path)!
		info := androidhost.dex_info(data)!
		if 'bpbx.class' in info.classes {
			if owner != '' { return error('ambiguous class owner') }
			owner = path
		}
		unsafe { data.free() }
	}
	if owner == '' { return error('class owner not found') }
	for name in os.ls(baseline + '/tools')! {
		if !name.ends_with('.jar') { continue }
		path := baseline + '/tools/' + name
		expected := pins['tools/' + name] or { return error('JAR absent from inventory') }
		if hash(path)! != expected { return error('JAR identity differs') }
		inputs[path] = expected
	}
	os.mkdir(root)!
	os.write_file(root + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	os.write_file(root + '/owner.txt', owner + '\n')!
	os.cp(@FILE, root + '/source.v')!
	os.cp(os.executable(), root + '/tool')!
	args := [java, '-Xmx192m', '-XX:ActiveProcessorCount=2', '-cp', baseline + '/tools/*',
		'org.jf.baksmali.Main', 'disassemble', '--jobs', '1', '--code-offsets',
		'--classes', 'Lbpbx;', '-o', root + '/selected', owner]
	os.write_file(root + '/argv.json', json2.encode(args, prettify: true) + '\n')!
	result := os.exec(args)
	os.write_file(root + '/command.log', result.output)!
	if result.exit_code != 0 || result.output.len > 1024 * 1024 {
		return error('targeted disassembly failed')
	}
	if os.ls(root + '/selected')! != ['bpbx.smali'] { return error('unexpected selected classes') }
	text := os.read_file(root + '/selected/bpbx.smali')!
	if !text.contains('.class public final Lbpbx;') || !text.contains('.method public static T(Landroid/content/Context;)Z') {
		return error('expected class or method absent')
	}
	for path, expected in inputs {
		if hash(path)! != expected { return error('input changed during audit') }
	}
	mut outputs := map[string]string{}
	for path in os.walk_ext(root, '') {
		if os.is_file(path) { outputs[path[root.len + 1..]] = hash(path)! }
	}
	os.write_file(root + '/sha256.json', json2.encode(outputs, prettify: true) + '\n')!
	println('GMS-0P-AUTH-CHECK PASS owner=' + owner + ' manifest=' + hash(root + '/sha256.json')!)
}

fn main() {
	if os.args.len != 2 { eprintln('usage: gms-0p-auth-check FRESH_EXTERNAL_OUTPUT'); exit(2) }
	inspect(os.args[1]) or { eprintln(err); exit(1) }
}
