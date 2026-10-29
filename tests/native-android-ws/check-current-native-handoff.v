// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the producer's real exec helper with its retained compiler/library.
module main

import crypto.sha256
import json2
import os

const previous = '/Users/alex/.local/state/vinix/android/current-native-build-2026-10-28-account-pump-r1'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const framework_argument = '/retained framework/with spaces'

struct State {
	pid int
	argv []string
	executable string
	sentinel string
}

struct Before {
	pid int
}

fn hash(path string) !string {
	if os.lstat(path)!.get_filetype() != .regular { return error('regular input required') }
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn function(source string, name string) string {
	start := source.index('fn ' + name + '(') or { panic('missing production helper') }
	end := source[start..].index('\n}') or { panic('unclosed production helper') }
	return source[start..start + end + 2]
}

fn command(root string, label string, argv []string) os.Result {
	r := os.exec(argv)
	os.write_file(root + '/' + label + '.json', json2.encode({
		'argv': json2.Any(argv), 'exit_code': json2.Any(r.exit_code), 'output': json2.Any(r.output)
	}, prettify: true)) or { panic(err) }
	return r
}

fn compile(root string, label string, source string, output string, mut inputs map[string]string) ! {
	v := previous + '/compiler-root/v'
	listing := command(root, label + '-listing', [v, '-gc', 'none', '-nocache', '-print-v-files', source])
	assert listing.exit_code == 0, listing.output
	mut found := false
	for path in listing.output.split_into_lines().filter(it.ends_with('.v')) {
		assert path.starts_with(previous + '/compiler-root/vlib/') || path == source, 'unexpected compiler source: ' + path
		inputs[path] = hash(path)!
		if path == source { found = true }
	}
	assert found, 'generated source absent from compiler discovery'
	r := command(root, label + '-build', [v, '-gc', 'none', '-nocache', '-cc', 'cc', '-o', output, source])
	assert r.exit_code == 0, r.output
	for path, pin in inputs { assert hash(path)! == pin, 'source changed while compiling: ' + path }
}

fn main() {
	assert os.args.len == 2, 'usage: check-current-native-handoff FRESH_EXTERNAL_OUTPUT'
	repo := os.real_path(os.getwd())
	root := os.abs_path(os.args[1])
	assert !os.exists(root) && !os.is_link(root) && root != repo && !root.starts_with(repo + '/')
	assert os.real_path(os.dir(root)) == os.dir(root), 'canonical external parent required'
	os.mkdir_all(root + '/tools')!
	source := os.read_file(repo + '/tests/native-android-ws/build-current-native.v')!
	checker := os.read_file(@FILE)!
	old_os := previous + '/compiler-root/vlib/os/os.c.v'
	old_text := os.read_file(old_os)!
	assert old_text.contains('pub fn execvp(cmdpath string, cmdargs []string) ! {')
	assert old_text.contains('cargs << &char(cmdpath.str)')
	assert old_text.contains('cargs << &char(cmdargs[i].str)')
	helper := function(source, 'replace_frozen_builder')
	assert helper.contains('os.execvp(argv[0], argv[1..])!')
	assert !helper.contains('os.exec(')
	bootstrap := function(source, 'bootstrap')
	assert bootstrap.contains('replace_frozen_builder(argv, executable_pin)!')
	assert bootstrap.contains("write_json(root + '/frozen-launch.json'")
	assert !bootstrap.contains('result := os.exec(argv)')
	os.write_file(root + '/builder-source.v.input', source)!
	os.write_file(root + '/checker-source.v.input', checker)!
	os.write_file(root + '/old-os.c.v.input', old_text)!
	os.write_file(root + '/callee.v', callee)!
	os.write_file(root + '/caller.v', caller_prefix + helper + caller_main)!
	v := previous + '/compiler-root/v'
	assert hash(v)! == compiler_pin, 'retained compiler identity differs'
	mut inputs := {v: compiler_pin, old_os: hash(old_os)!}
	os.chdir(previous + '/compiler-root')!
	for name in ['VEXE', 'V', 'VINIX_V_COMPILER'] { os.setenv(name, v, true) }
	os.setenv('VROOT', previous + '/compiler-root', true)
	compile(root, 'callee', root + '/callee.v', root + '/tools/frozen-builder', mut inputs)!
	compile(root, 'caller', root + '/caller.v', root + '/tools/caller', mut inputs)!
	r := command(root, 'replacement', [root + '/tools/caller', root, 'good'])
	assert r.exit_code == 37, r.output
	assert r.output.count('FROZEN-HANDOFF-STDOUT\n') == 1
	assert r.output.count('FROZEN-HANDOFF-STDERR\n') == 1
	assert !r.output.contains('UNREACHABLE')
	before := json2.decode[Before](os.read_file(root + '/before-good.json')!)!
	after_text := os.read_file(root + '/after.json')!
	after := json2.decode[State](after_text)!
	assert before.pid > 0 && before.pid == after.pid, 'exec changed PID'
	assert after.argv == [root + '/tools/frozen-builder', '--frozen-build', framework_argument, root]
	assert after.executable == root + '/tools/frozen-builder'
	assert after.sentinel == 'environment value with spaces'
	for mode in ['bad-pin', 'wrong-flag', 'wrong-path', 'short-argv'] {
		bad := command(root, mode, [root + '/tools/caller', root, mode])
		assert bad.exit_code == 23 && bad.output.count('HANDOFF-REFUSED\n') == 1, bad.output
		assert os.read_file(root + '/after.json')! == after_text, 'rejected call executed callee'
	}
	os.chmod(root + '/tools/frozen-builder', 0o644)!
	bad_exec := command(root, 'nonexecutable', [root + '/tools/caller', root, 'nonexecutable'])
	assert bad_exec.exit_code == 23 && bad_exec.output.count('HANDOFF-REFUSED\n') == 1, bad_exec.output
	assert os.read_file(root + '/after.json')! == after_text
	os.chmod(root + '/tools/frozen-builder', 0o755)!
	for path, pin in inputs { assert hash(path)! == pin, 'compiler input changed: ' + path }
	os.write_file(root + '/inputs.json', json2.encode(inputs, prettify: true))!
	os.write_file(root + '/evidence.json', json2.encode({
		'builder_sha256': json2.Any(sha256.hexhash(source)),
		'checker_sha256': json2.Any(sha256.hexhash(checker)),
		'old_os_sha256': json2.Any(hash(old_os)!),
		'compiler_sha256': json2.Any(compiler_pin),
		'callee_sha256': json2.Any(hash(root + '/tools/frozen-builder')!),
		'caller_sha256': json2.Any(hash(root + '/tools/caller')!),
		'pid': json2.Any(after.pid),
		'scope': json2.Any('Production helper with pinned old compiler/vlib: exact argv, same PID, environment/stdout/stderr/exit propagation and five refusals; no native provider or ART execution claim.')
	}, prettify: true))!
	println('NATIVE-PRODUCER-HANDOFF-PASS same-pid exact-argv environment stdout stderr exit37 bad-pin wrong-flag wrong-path short-argv exec-failure')
}

const caller_prefix = 'module main
import crypto.sha256
import json2
import os
fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
'

const caller_main = '
fn main() {
 assert os.args.len == 3
 root, mode := os.args[1], os.args[2]
 mut argv := [root + "/tools/frozen-builder", "--frozen-build", "/retained framework/with spaces", root]
 mut pin := hash(argv[0]) or { panic(err) }
 match mode {
  "bad-pin" { pin = "0".repeat(64) }
  "wrong-flag" { argv[1] = "--other" }
  "wrong-path" { argv[0] = root + "/tools/caller" }
  "short-argv" { argv = argv[..3].clone() }
  "good" {}
  "nonexecutable" {}
  else { panic("unknown probe mode") }
 }
 os.write_file(root + "/before-" + mode + ".json", json2.encode({"pid":json2.Any(os.getpid())})) or { panic(err) }
 os.setenv("VINIX_NATIVE_HANDOFF_SENTINEL", "environment value with spaces", true)
 replace_frozen_builder(argv,pin) or { eprintln("HANDOFF-REFUSED"); exit(23) }
 println("UNREACHABLE")
 exit(99)
}
'

const callee = 'module main
import json2
import os
fn main() {
 assert os.args.len == 4 && os.args[1] == "--frozen-build"
 os.write_file(os.args[3] + "/after.json", json2.encode({
  "pid":json2.Any(os.getpid()),
  "argv":json2.decode[json2.Any](json2.encode(os.args)) or { panic(err) },
  "executable":json2.Any(os.executable()),
  "sentinel":json2.Any(os.getenv("VINIX_NATIVE_HANDOFF_SENTINEL"))
 })) or { panic(err) }
 println("FROZEN-HANDOFF-STDOUT")
 eprintln("FROZEN-HANDOFF-STDERR")
 exit(37)
}
'
