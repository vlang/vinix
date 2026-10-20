// Focused APK check against the preserved 3 October ARM64 runtime.
// The full runtime conformance failure is retained in the adjacent first run.
@[has_globals]
module main

import androidhost as ah
import androidrun
import cachecli
import crypto.sha256
import json2
import os

fn plan(args map[string]ah.Value, overlay ah.Value) !androidrun.Plan {
	mut context := androidrun.Context{root: os.getwd(), args: args}
	defer { context.close() }
	value := context.call('vm_plan', {'args': ah.Value(args), 'overlay': overlay})!.object()
	mut environment := map[string]string{}
	for key, item in ah.field(value, 'environment').object() { environment[key] = item.text() }
	mut command := ah.field(value, 'command').items().map(it.text())
	for index, argument in command {
		if argument.starts_with('--guest-init=') {
			command[index] = '--guest-init=' + os.getwd() + '/build/calculator-focused-init.sh'
		}
	}
	return androidrun.Plan{command, environment, os.getwd()}
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	root := os.getwd()
	state := root + '/build/android-calculator-20261020-focused'
	os.mkdir_all(state)!
	source := os.read_file(root + '/tests/android/guest-init.sh')!
	start := source.index('\nif [ "$TEST_RUNTIME_ARCH" = x86_64 ]; then') or { panic('missing preflight boundary') }
	launch := source.index('\nif [ "$TEST_MODE" = direct ]; then\n    mkfifo /tmp/android-events') or { panic('missing application boundary') }
	// Retain real stack/memory checks and the unmodified application/input/result
	// path. Fork/configuration/fortify/mallinfo/netdb conformance is not asserted.
	checks := '\necho ANDROID-FOCUSED-CHECK scope=calculator\n' +
		'runtime=/opt/vinix-android-aarch64\n' +
		'for probe in runtime-stack-probe runtime-memory-probe; do\n' +
		'  LD_PRELOAD="$runtime/usr/lib/libvinix-android-compat.so" VINIX_ALLOW_WX=1 "$runtime/lib/ld-musl-aarch64.so.1" --library-path "$runtime/lib:$runtime/usr/lib" "/opt/android-test/$probe" || fail "focused stack or memory check failed"\n' +
		'done\n'
	init := root + '/build/calculator-focused-init.sh'
	os.write_file(init, source[..start] + checks + source[launch..])!
	os.chmod(init, 0o755)!
	args := androidrun.parse_cli(root, [
		'--state-dir', state, '--memory', '12288', '--runtime-arch', 'aarch64',
		'--runtime', '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging',
		'--desktop', root + '/build/vinix-desktop', '--kernel-dir', root + '/kernel',
		'--initramfs', root + '/build/android-calculator-20261020/initramfs.tar',
		'--apk', '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/usr/share/vinix/android/Arity-1.1.apk',
		'--screenshot', state + '/calculator.png', '--input', 'qmp',
	])!
	mut context := androidrun.Context{root: root, args: args, plan_hook: plan}
	defer { context.close() }
	status := context.run_session(ah.Value(json2.Null{}))!
	mut result := json2.decode[ah.Value](os.read_file(state + '/result.json')!)!.object()
	result['check'] = ah.Value('calculator-focused')
	result['runtime_conformance'] = ah.Value('not passed: archived runtime lacks Android fork ABI exports; see ../android-calculator-20261020/result.json')
	result['guest_init_sha256'] = ah.Value(sha256.sum(os.read_bytes(init)!).hex())
	result['kernel_sha256'] = ah.Value(sha256.sum(os.read_bytes(state + '/kernel/bin/vinix')!).hex())
	result['desktop_sha256'] = ah.Value(sha256.sum(os.read_bytes(root + '/build/vinix-desktop')!).hex())
	os.write_file(state + '/result.json', ah.encode(ah.Value(result)) + '\n')!
	exit(status)
}
