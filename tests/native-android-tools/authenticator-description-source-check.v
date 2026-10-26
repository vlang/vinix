// SPDX-License-Identifier: GPL-2.0-or-later
// Retain an isolated provider/checker source closure and host DEX validation.
module main

import crypto.sha256
import json2
import os

struct SourceReceipt {
	context string = 'host provider guards and smali DEX assembly; no ART or account login claim'
	compile_argv []string
	compile_exit int
	check_argv []string
	check_exit int
	inputs_sha256 map[string]string
	tool_jars_sha256 map[string]string
	checker_sha256 string
	dex_sha256 string
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn tool_inputs(tools string) !map[string]string {
	mut pins := map[string]string{}
	for name in os.ls(tools)! {
		if name.ends_with('.jar') { pins[name] = digest(tools + '/' + name)! }
	}
	if pins.len == 0 { return error('missing smali tool jars') }
	return pins
}

fn main() {
	assert os.args.len == 6, 'usage: source-check V ROOT FRESH-OUTPUT TOOLS JAVA'
	compiler := os.real_path(os.args[1])
	root := os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	tools := os.real_path(os.args[4])
	java := os.real_path(os.args[5])
	assert !os.exists(work), 'output must be fresh'
	base := root + '/tests/native-android-tools'
	provider := base + '/androidtools/framework_authenticator_descriptions.v'
	checker := base + '/check-authenticator-descriptions.v'
	framework := base + '/androidtools/framework.v'
	mut pins := map[string]string{}
	for path in [compiler, java, provider, checker, framework,
		base + '/authenticator-description-source-check.v'] { pins[path] = digest(path)! }
	tool_pins := tool_inputs(tools)!
	os.mkdir_all(work + '/androidtools')!
	os.cp(provider, work + '/androidtools/framework_authenticator_descriptions.v')!
	os.cp(checker, work + '/check.v')!
	source := os.read_file(framework)!
	start := source.index('pub fn framework_replace_method(') or { panic('missing replace helper') }
	end := start + (source[start..].index('\n// Missing packages') or { panic('missing replace helper end') })
	assembly := '\npub fn framework_assemble(smali string, dex string, tools string, java string) ! {\n' +
		'if os.exists(dex) { os.rm(dex)! }\n' +
		'result := os.exec([java, "-cp", tools + "/*", "org.jf.smali.Main", "assemble", "--jobs", "2", smali, "-o", dex])\n' +
		'if result.exit_code != 0 || !os.is_file(dex) { return error(result.output) }\n}\n'
	os.write_file(work + '/androidtools/helpers.v', 'module androidtools\nimport os\n' + source[start..end] + assembly)!
	compile := [compiler, '-w', '-o', work + '/check', work + '/check.v']
	built := os.exec(compile)
	os.write_file(work + '/compile.log', built.output)!
	assert built.exit_code == 0, built.output
	command := [work + '/check', tools, java, work + '/assembled']
	checked := os.exec(command)
	os.write_file(work + '/check.log', checked.output)!
	assert checked.exit_code == 0, checked.output
	for path, pin in pins { assert digest(path)! == pin, 'input changed: ' + path }
	assert tool_inputs(tools)! == tool_pins, 'smali tools changed during validation'
	os.write_file(work + '/receipt.json', json2.encode(SourceReceipt{
		compile_argv: compile
		compile_exit: built.exit_code
		check_argv: command
		check_exit: checked.exit_code
		inputs_sha256: pins
		tool_jars_sha256: tool_pins
		checker_sha256: digest(work + '/check')!
		dex_sha256: digest(work + '/assembled/classes.dex')!
	}, prettify: true) + '\n')!
	print(checked.output)
}
