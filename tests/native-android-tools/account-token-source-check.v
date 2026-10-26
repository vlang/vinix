// SPDX-License-Identifier: GPL-2.0-or-later
// Compile the actual token/Future generators in an isolated source closure.
module main

import crypto.sha256
import json2
import os

fn between(text string, first string, next string) !string {
	start := text.index(first) or { return error('missing source start') }
	end := text[start..].index(next) or { return error('missing source end') }
	return text[start..start + end]
}

fn main() {
	assert os.args.len == 7, 'V ROOT OUTPUT ACCOUNT_MANAGER_SMALI TOOLS JAVA'
	compiler, root, work := os.real_path(os.args[1]), os.real_path(os.args[2]), os.abs_path(os.args[3])
	assert !os.exists(work)
	os.mkdir_all(work + '/androidtools')!
	base := root + '/tests/native-android-tools'
	accounts := os.read_file(base + '/androidtools/framework_accounts.v')!
	os.write_file(work + '/androidtools/accounts.v', accounts.all_before('\nfn framework_account_listeners(').replace('\nimport os\n', '\n'))!
	for name in ['framework_account_client', 'framework_account_token'] {
		os.cp(base + '/androidtools/' + name + '.v', work + '/androidtools/' + name + '.v')!
	}
	classes := os.read_file(base + '/androidtools/framework_classes.v')!
	framework := os.read_file(base + '/androidtools/framework.v')!
	helpers := between(classes, 'fn interface_class(', '\npub fn framework_extra_classes(')! +
		between(framework, 'pub fn framework_replace_method(', '\n// Missing packages')!
	assembly := 'pub fn framework_assemble(smali string, dex string, tools string, java string) ! {\n' +
		'if os.exists(dex) { os.rm(dex)! }\n' +
		'result := os.exec([java, "-cp", tools + "/*", "org.jf.smali.Main", "assemble", "--jobs", "2", smali, "-o", dex])\n' +
		'if result.exit_code != 0 || !os.is_file(dex) { return error(result.output) }\n}\n'
	os.write_file(work + '/androidtools/helpers.v', 'module androidtools\nimport os\n' + helpers + assembly)!
	os.cp(base + '/check-account-token.v', work + '/check.v')!
	mut receipts := map[string]json2.Any{}
	compile := [compiler, '-w', '-o', work + '/check', work + '/check.v']
	built := os.exec(compile)
	os.write_file(work + '/compile.log', built.output)!
	assert built.exit_code == 0, built.output
	receipts['compile'] = json2.Any({'argv': json2.Any(compile), 'exit_code': json2.Any(built.exit_code)})
	argv := [work + '/check', os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6]), work + '/assembled']
	result := os.exec(argv)
	os.write_file(work + '/check.log', result.output)!
	assert result.exit_code == 0, result.output
	receipts['check'] = json2.Any({'argv': json2.Any(argv), 'exit_code': json2.Any(result.exit_code)})
	mut pins := map[string]json2.Any{}
	for path in [os.args[4], base + '/androidtools/framework_account_token.v', base + '/androidtools/framework_account_client.v', base + '/androidtools/framework_accounts.v', base + '/check-account-token.v', base + '/account-token-source-check.v'] {
		pins[os.real_path(path)] = json2.Any(sha256.sum(os.read_bytes(path)!).hex())
	}
	os.write_file(work + '/receipt.json', json2.encode({'commands': json2.Any(receipts), 'inputs_sha256': json2.Any(pins)}, prettify: true))!
	print(result.output)
}
