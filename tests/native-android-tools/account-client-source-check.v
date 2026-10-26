// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the real account generators in an isolated module. This bounds the
// check independently of unrelated Android build and tar tooling imports.
module main

import os

fn between(text string, first string, next string) !string {
	start := text.index(first) or { return error('missing source start: ' + first) }
	end := text[start..].index(next) or { return error('missing source end: ' + next) }
	return text[start..start + end]
}

fn command(work string, label string, args []string) ! {
	result := os.exec(args)
	os.write_file(work + '/' + label + '.log', result.output)!
	if result.exit_code != 0 { return error(label + ': ' + result.output) }
	print(result.output)
}

fn main() {
	assert os.args.len in [4, 6], 'usage: account-client-source-check V ROOT OUTPUT [TOOLS JAVA]'
	compiler := os.real_path(os.args[1])
	root := os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	assert !os.exists(work), 'output directory already exists'
	os.mkdir_all(work + '/androidtools')!
	base := root + '/tests/native-android-tools'
	accounts := os.read_file(base + '/androidtools/framework_accounts.v')!
	assert accounts.contains('\nfn framework_account_listeners(')
	assert accounts.all_after('\nfn framework_account_listeners(').contains('framework_account_client_classes()')
	assert accounts.all_after('\nfn framework_account_listeners(').contains('framework_account_client_addition(')
	os.write_file(work + '/androidtools/accounts.v', accounts.all_before('\nfn framework_account_listeners(').replace('\nimport os\n', '\n'))!
	os.cp(base + '/androidtools/framework_account_client.v', work + '/androidtools/client.v')!
	classes := os.read_file(base + '/androidtools/framework_classes.v')!
	framework := os.read_file(base + '/androidtools/framework.v')!
	interface_helper := between(classes, 'fn interface_class(', '\npub fn framework_extra_classes(')!
	replace_helper := between(framework, 'pub fn framework_replace_method(', '\n// Missing packages')!
	// Assembly is a test dependency, not the behavior under test. Require fresh
	// DEX output because smali can exit zero while reporting a syntax error.
	assembly := 'pub fn framework_assemble(smali string, dex string, tools string, java string) ! {\n' +
		'if os.exists(dex) { os.rm(dex)! }\n' +
		'result := os.exec([java, "-cp", tools + "/*", "org.jf.smali.Main", "assemble", "--jobs", "2", smali, "-o", dex])\n' +
		'if result.exit_code != 0 || !os.is_file(dex) { return error(result.output) }\n}\n'
	os.write_file(work + '/androidtools/helpers.v', 'module androidtools\nimport os\n' + interface_helper + replace_helper + assembly)!
	for name in ['client', 'async', 'addition'] {
		os.cp(base + '/check-account-' + name + '.v', work + '/check-' + name + '.v')!
		command(work, 'compile-' + name, [compiler, '-w', '-o', work + '/check-' + name, work + '/check-' + name + '.v'])!
		mut args := [work + '/check-' + name]
		if os.args.len == 6 { args << [os.real_path(os.args[4]), os.real_path(os.args[5])] }
		command(work, 'check-' + name, args)!
	}
}
