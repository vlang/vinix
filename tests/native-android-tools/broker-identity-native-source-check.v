// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the exact JNI generator without compiling unrelated Android tools.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn helper(source string, signature string) !string {
	marker := '\n' + signature
	if source.count(marker) != 1 { return error('unique helper required: ' + signature) }
	start := (source.index(marker) or { return error('missing helper') }) + 1
	tail := source[start..]
	end := tail.index('\n}') or { return error('unterminated helper') }
	return tail[..end + 2] + '\n'
}

fn run(work string, label string, argv []string) ! {
	result := os.exec(argv)
	os.write_file(work + '/' + label + '.json', json2.encode({
		'argv': json2.Any(argv), 'exit_code': json2.Any(result.exit_code), 'output': json2.Any(result.output)
	}, prettify: true) + '\n')!
	if result.exit_code != 0 { return error(label + ': ' + result.output) }
	print(result.output)
}

fn main() {
	assert os.args.len == 4, 'usage: broker-identity-native-source-check V ROOT FRESH_OUTPUT'
	compiler, repo := os.real_path(os.args[1]), os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	assert !os.exists(work) && !os.is_link(work) && work != repo && !work.starts_with(repo + '/')
	os.mkdir_all(work + '/androidtools')!
	os.mkdir(work + '/helper-inputs')!
	base := repo + '/tests/native-android-tools/androidtools'
	mut pins := map[string]string{}
	for path in [compiler, @FILE] { pins[path] = digest(path)! }
	provider := base + '/framework_account_broker_context.v'
	native := base + '/native_ws.v'
	broadcast := base + '/framework_broadcast_result.v'
	spec := repo + '/build-support/android/nativews/bindings.txt'
	for path in [provider, native, broadcast, spec] {
		pins[path] = digest(path)!
		target := work + '/helper-inputs/' + os.base(path)
		os.cp(path, target)!
		assert digest(target)! == pins[path]!
	}
	os.cp(work + '/helper-inputs/framework_account_broker_context.v', work + '/androidtools/broker.v')!
	mut helpers := 'module androidtools\nimport os\n'
	source := os.read_file(work + '/helper-inputs/native_ws.v')!
	for signature in ['fn native_ws_hex4(', 'pub fn native_ws_jni_escape(', 'pub fn native_ws_abi(',
		'fn native_ws_broadcast_bridge(', 'pub fn native_ws_bindings('] {
		helpers += helper(source, signature)!
	}
	for signature in ['fn broadcast_method(', 'pub fn framework_broadcast_run_method('] {
		helpers += helper(os.read_file(work + '/helper-inputs/framework_broadcast_result.v')!, signature)!
	}
	os.write_file(work + '/androidtools/native.v', helpers)!
	mut rows := []string{}
	for line in os.read_file(work + '/helper-inputs/bindings.txt')!.split_into_lines() {
		if line.starts_with('android/atl/VinixAccountBrokerContext|clearCallingIdentity|')
			|| line.starts_with('android/atl/VinixAccountBrokerContext|restoreCallingIdentity|') { rows << line }
	}
	assert rows.len == 2 && rows[0].contains('|clearCallingIdentity|') && rows[1].contains('|restoreCallingIdentity|')
	os.write_file(work + '/identity-bindings.txt', rows.join('\n') + '\n')!
	os.write_file(work + '/check.v', check_source)!
	run(work, 'compile', [compiler, '-nocache', '-cc', 'cc', '-o', work + '/check', work + '/check.v'])!
	run(work, 'generate', [work + '/check', work])!
	run(work, 'compile-wrappers', [compiler, '-nocache', '-cc', 'cc', '-o', work + '/wrappers', work + '/wrappers.v'])!
	run(work, 'wrappers', [work + '/wrappers'])!
	for path, pin in pins { assert digest(path)! == pin, 'input changed: ' + path }
	for name in ['androidtools/broker.v', 'androidtools/native.v', 'identity-bindings.txt', 'check.v',
		'check', 'generated.v', 'wrappers.v', 'wrappers'] { pins[work + '/' + name] = digest(work + '/' + name)! }
	os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
	println('BROKER-IDENTITY-NATIVE-PASS exact production JNI generator current bindings 64-bit token boolean return mutations=3')
}

const check_source = '
module main
import androidtools
import os
fn validate(source string) ! {
 for expected in ["@[export: \'Java_android_atl_VinixAccountBrokerContext_clearCallingIdentity__\']",
  "@[export: \'Java_android_atl_VinixAccountBrokerContext_restoreCallingIdentity__J\']",
  "fn ws_binding_0(e voidptr, this voidptr) i64", "fn ws_binding_1(e voidptr, this voidptr, p0 i64) u8",
  "return ws_auth_clear_identity()", "return u8(ws_auth_restore_identity(p0))"] {
  if source.count(expected) != 1 { return error("JNI ABI changed: " + expected) }
 }
 if source.count("\\n@[export:") != 2 { return error("unexpected JNI exports") }
}
fn main() {
 assert os.args.len == 2
 work := os.args[1]
 name := "android/atl/VinixAccountBrokerContext"
 baseline := androidtools.framework_account_broker_context_classes()[name]
 context := androidtools.framework_account_broker_identity_context(baseline)!
 os.mkdir_all(work + "/smali/android/atl")!
 path := work + "/smali/" + name + ".smali"
 os.write_file(path,context)!
 spec := os.read_file(work + "/identity-bindings.txt")!
 generated := androidtools.native_ws_bindings(spec,work + "/smali")!
 validate(generated)!
 os.write_file(work + "/generated.v",generated)!
 mut rejected := 0
 for invalid in [context.replace("clearCallingIdentity()J","clearCallingIdentity()I"),
  context.replace("restoreCallingIdentity(J)Z","restoreCallingIdentity(I)Z"),
  context.replace("restoreCallingIdentity(J)Z","restoreCallingIdentity(J)V")] {
  os.write_file(path,invalid)!
  candidate := androidtools.native_ws_bindings(spec,work + "/smali")!
  validate(candidate) or { rejected++; continue }
  panic("JNI width drift accepted")
 }
 assert rejected == 3
 os.write_file(path,context)!
 probe := "\\nfn ws_auth_clear_identity() i64 { return i64(0x1234567890123456) }\\n" +
  "fn ws_auth_restore_identity(token i64) bool { return token == i64(0x1234567890123456) }\\n" +
  "fn main() { assert ws_binding_0(unsafe {nil},unsafe {nil}) == i64(0x1234567890123456); " +
  "assert ws_binding_1(unsafe {nil},unsafe {nil},i64(0x1234567890123456)) == 1; " +
  "assert ws_binding_1(unsafe {nil},unsafe {nil},i64(0x1234567890123457)) == 0 }\\n"
 os.write_file(work + "/wrappers.v",generated.replace("module atlframework","module main") + probe)!
 println("BROKER-IDENTITY-JNI-GENERATION-PASS wide-token boolean result exact exports mutations=3")
}
'
