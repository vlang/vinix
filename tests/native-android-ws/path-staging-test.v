// SPDX-License-Identifier: GPL-2.0-or-later
// Compare the maintained suite's APFS provider staging with V's cp_all merge.
module main

import os

fn function(source string, name string) string {
	marker := 'fn ' + name + '('
	assert source.count(marker) == 1, name
	tail := marker + source.all_after(marker)
	return tail.all_before('\nfn ') + '\n'
}

fn checked(argv []string) string {
	r := os.exec(argv)
	print(r.output)
	assert r.exit_code == 0, argv.str() + '\n' + r.output
	return r.output
}

const runtime_tests = r'
fn inventory(root string, relative string) ![]string {
	mut result := []string{}
	mut names := os.ls(root + relative)!
	names.sort()
	for name in names {
		path := relative + "/" + name
		if os.is_dir(root + path) {
			result << "D " + path
			result << inventory(root, path)!
		} else {
			assert !os.is_link(root + path), path
			result << "F " + path + " " + sha256.sum(os.read_bytes(root + path)!).hex()
		}
	}
	return result
}

fn original_stage(native string, runtime string) ! {
	for provider in ["egl-ws", "vulkan-ws"] {
		if os.is_dir(native + "/" + provider) {
			os.cp_all(native + "/" + provider, runtime + "/usr/lib/art/native-ws", false)!
		}
	}
}

fn compare(native string, root string) ! {
	for name in ["original", "generated"] {
		os.mkdir_all(root + "/" + name + "/usr/lib/art/native-ws")!
		os.write_file(root + "/" + name + "/usr/lib/art/native-ws/common.keep", "common bytes\n")!
	}
	original_stage(native, root + "/original")!
	generated_stage(native, root + "/generated")!
	original := inventory(root + "/original", "")!
	generated := inventory(root + "/generated", "")!
	assert original == generated, "provider inventory/bytes differ:\n" + original.join("\n") + "\n---\n" + generated.join("\n")
	assert os.read_file(root + "/generated/usr/lib/art/native-ws/common.keep")! == "common bytes\n"
	assert !os.exists(root + "/generated/usr/lib/art/native-ws/egl-ws")
	assert !os.exists(root + "/generated/usr/lib/art/native-ws/vulkan-ws")
	os.write_file(root + "/inventory.txt", generated.join("\n") + "\n")!
	println("PROVIDER-STAGING-PASS " + root + " entries=" + generated.len.str())
}

fn error_cases(root string) ! {
	missing := root + "/missing"
	mut failed := false
	suite_clone(missing, root + "/missing-copy") or { failed = true }
	assert failed && !os.exists(root + "/missing-copy")
	failed = false
	suite_clone_tree(missing, root + "/missing-tree") or { failed = true }
	assert failed
	os.write_file(root + "/not-directory", "keep")!
	failed = false
	os.cp_all(root + "/native/egl-ws", root + "/not-directory", false) or { failed = true }
	assert failed
	failed = false
	suite_clone_tree(root + "/native/egl-ws", root + "/not-directory") or { failed = true }
	assert failed && os.read_file(root + "/not-directory")! == "keep"
	os.mkdir_all(root + "/directory-target")!
	os.write_file(root + "/directory-target/keep", "directory bytes")!
	failed = false
	suite_clone(root + "/not-directory", root + "/directory-target") or { failed = true }
	assert failed && os.read_file(root + "/directory-target/keep")! == "directory bytes"
	println("PROVIDER-STAGING-ERRORS-PASS")
}

fn main() {
	root := os.args[1]
	os.mkdir_all(root + "/native/egl-ws/nested")!
	os.mkdir_all(root + "/native/vulkan-ws/other")!
	os.write_file(root + "/native/egl-ws/nested/driver.so", "nested driver\x00bytes\n")!
	os.write_file(root + "/native/egl-ws/library with space.so", "space bytes\n")!
	os.symlink("nested/driver.so", root + "/native/egl-ws/libEGL.so")!
	os.write_file(root + "/native/vulkan-ws/other/icd.json", "{ provider: vulkan }\n")!
	compare(root + "/native", root + "/synthetic")!
	error_cases(root)!
	if os.args.len == 3 { compare(os.args[2], root + "/actual")! }
	println("PATH-STAGING-PASS")
}
'

fn main() {
	$if prod { eprintln('path-staging-test requires assertions; compile without -prod'); exit(2) }
	repo := os.real_path(os.dir(@FILE) + '/../..')
	mut compiler := os.getenv_opt('VINIX_V_COMPILER') or { '/Users/alex/code/v/v_old' }
	mut out := repo + '/build/android-path-staging-test'
	mut native := ''
	for arg in os.args[1..] {
		if arg.starts_with('out=') {
			out = os.abs_path(arg.all_after('out='))
		} else if arg.starts_with('compiler=') {
			compiler = os.abs_path(arg.all_after('compiler='))
		} else if arg.starts_with('native=') {
			native = os.abs_path(arg.all_after('native='))
		} else { panic('usage: path-staging-test [out=FRESH_DIR] [compiler=V] [native=PROVIDER_PARENT]') }
	}
	if native != '' {
		assert os.is_dir(native + '/egl-ws') && os.is_dir(native + '/vulkan-ws'), native
	}
	assert !os.exists(out), 'use a fresh output directory: ' + out
	os.mkdir_all(out)!
	runner := os.read_file(repo + '/tests/native-android-ws/compound-button-run.v')!
	// The transformer embeds function declarations in a string: bound it by its
	// maintained next function rather than treating those declarations as V code.
	assert runner.count('\nfn apfs_suite_staging(') == 1 && runner.count('\nfn prepare_runs(') == 1
	transformer := 'fn apfs_suite_staging(' + runner.all_after('\nfn apfs_suite_staging(').all_before('\nfn prepare_runs(')
	transform := 'module main\nimport os\n' + function(runner, 'section') + function(runner, 'checked') + transformer + r'
fn main() {
	suite := apfs_suite_staging(os.read_file(os.args[1])!)
	helpers := "fn suite_clone(" + suite.all_after("fn suite_clone(").all_before("fn prepare_module(")
	start := "\tfor provider in [\x27egl-ws\x27, \x27vulkan-ws\x27] {"
	end := "\n\tif os.is_file(native + \x27/vinix-session\x27)"
	assert suite.count(start) == 1 && suite.count(end) == 1
	provider := start + suite.all_after(start).all_before(end)
	os.write_file(os.args[2], "module main\nimport os\nimport crypto.sha256\n" + os.read_file(os.args[3])! + helpers + "\nfn generated_stage(native string, runtime string) ! {\n" + provider + "\n}\n" + os.read_file(os.args[4])!)!
}
'
	os.write_file(out + '/transform.v', transform)!
	os.write_file(out + '/checked.v.txt', function(runner, 'checked'))!
	os.write_file(out + '/cases.v.txt', runtime_tests)!
	os.write_file(out + '/transform.log', checked([compiler, 'run', out + '/transform.v', repo + '/build/android-maps/suite239-stream.v', out + '/runtime.v', out + '/checked.v.txt', out + '/cases.v.txt']))!
	os.write_file(out + '/compile.log', checked([compiler, '-o', out + '/runtime', out + '/runtime.v']))!
	mut argv := [out + '/runtime', out + '/cases']
	if native != '' { argv << native }
	os.write_file(out + '/run.log', checked(argv))!
	// Prove the same inventory assertion catches the original provider nesting.
	runtime := os.read_file(out + '/runtime.v')!
	good := "suite_clone_tree(native + '/' + provider, runtime + '/usr/lib/art/native-ws')!"
	bad := "suite_clone_tree(native + '/' + provider, runtime + '/usr/lib/art/native-ws/' + provider)!"
	assert runtime.count(good) == 1
	os.write_file(out + '/negative.v', runtime.replace(good, bad))!
	os.write_file(out + '/negative-compile.log', checked([compiler, '-o', out + '/negative', out + '/negative.v']))!
	negative := os.exec([out + '/negative', out + '/negative-cases'])
	os.write_file(out + '/negative.log', negative.output)!
	assert negative.exit_code != 0 && negative.output.contains('provider inventory/bytes differ'), negative.output
	println('PATH-STAGING-NESTING-NEGATIVE-PASS')
}
