// Isolated application checks using the preserved ARM64 runtime. Full runtime
// conformance is separately recorded as failing its newer fork ABI preflight.
@[has_globals]
module main

import androidhost as ah
import androidrun
import cachecli
import crypto.sha256
import json2
import os

fn plan(args map[string]ah.Value, overlay ah.Value) !androidrun.Plan {
 if os.getenv('VINIX_ANDROID_REUSE_BOOT') == '1' {
  // Reuse this investigation's stopped boot disk, replacing its base module.
  // The existing final qemu-runtime module retains the identical guest init.
  state := args['state_dir']!.text()
  disk := state + '/boot.img'
  if !os.is_file(disk) || !os.is_file(state + '/kernel/bin/vinix') { return error('reuse requires an existing stopped investigation boot') }
  copied := os.exec(['mcopy', '-o', '-i', disk, args['initramfs']!.text(), '::/boot/initramfs.tar'])
  if copied.exit_code != 0 { return error(copied.output) }
  return androidrun.Plan{command: [os.getwd() + '/build/qemu-horizontal/bin/qemu-system-aarch64',
   '-qmp', 'unix:' + state + '/qmp.sock,server=on,wait=off', '-machine', 'virt,gic-version=3',
   '-accel', 'hvf', '-cpu', 'host', '-m', '12288', '-smp', '4',
   '-object', 'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device',
   '-drive', 'if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
   '-drive', 'if=pflash,format=raw,file=' + state + '/efivars.fd', '-drive', 'format=raw,file=' + disk,
   '-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device',
   '-netdev', 'user,id=net0', '-device', 'virtio-net-device,netdev=net0,mac=52:54:00:12:34:56',
   '-device', 'ramfb', '-display', 'none', '-serial', 'mon:stdio'], environment: os.environ(), directory: os.getwd()}
 }
	mut context := androidrun.Context{root: os.getwd(), args: args}
	defer { context.close() }
	value := context.call('vm_plan', {'args': ah.Value(args), 'overlay': overlay})!.object()
	mut environment := map[string]string{}
	for key, item in ah.field(value, 'environment').object() { environment[key] = item.text() }
	mut command := ah.field(value, 'command').items().map(it.text())
	for index, argument in command {
		if argument.starts_with('--guest-init=') {
			command[index] = '--guest-init=' + args['state_dir']!.text() + '/guest-init.sh'
		}
	}
	return androidrun.Plan{command, environment, os.getwd()}
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	root := os.getwd()
	mut args := androidrun.parse_cli(root, os.args[1..])!
	for key, value in {
		'runtime': '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging'
		'runtime_arch': 'aarch64'
		'desktop': root + '/build/vinix-desktop'
		'kernel_dir': root + '/kernel'
		'input': 'qmp'
	} {
		if args[key]! is json2.Null { args[key] = ah.Value(value) }
	}
	state := os.abs_path(args['state_dir']!.text())
	args['state_dir'] = ah.Value(state)
	if args['screenshot']! is json2.Null {
		args['screenshot'] = ah.Value(state + '/application.png')
	}
	os.mkdir_all(state)!
	source := os.read_file(root + '/tests/android/guest-init.sh')!
	start := source.index('\nif [ "$TEST_RUNTIME_ARCH" = x86_64 ]; then') or { panic('missing preflight boundary') }
	launch := source.index('\nif [ "$TEST_MODE" = direct ]; then\n    mkfifo /tmp/android-events') or { panic('missing application boundary') }
	checks := '\necho ANDROID-FOCUSED-CHECK scope=application\nTEST_TIMEOUT=60\n' +
		'runtime=/opt/vinix-android-aarch64\n' +
		'for probe in runtime-stack-probe runtime-memory-probe; do\n' +
		'  LD_PRELOAD="$runtime/usr/lib/libvinix-android-compat.so" VINIX_ALLOW_WX=1 "$runtime/lib/ld-musl-aarch64.so.1" --library-path "$runtime/lib:$runtime/usr/lib" "/opt/android-test/$probe" || fail "focused stack or memory check failed"\n' +
		'done\n'
	init := state + '/guest-init.sh'
	observation := source[launch..].replace('while [ "$i" -lt "$TEST_OBSERVATION_SECONDS" ]; do', 'while [ "$i" -lt "$TEST_OBSERVATION_SECONDS" ]; do\n        if [ $((i % 5)) -eq 0 ]; then application_logs full; fi')
	os.write_file(init, source[..start] + checks + observation)!
	os.chmod(init, 0o755)!
	mut context := androidrun.Context{root: root, args: args, plan_hook: plan}
	defer { context.close() }
	status := context.run_session(ah.Value(json2.Null{}))!
	mut result := json2.decode[ah.Value](os.read_file(state + '/result.json')!)!.object()
	result['scope'] = ah.Value('application only; full legacy-runtime conformance failed the fork ABI preflight')
	result['guest_init_sha256'] = ah.Value(sha256.sum(os.read_bytes(init)!).hex())
	result['kernel_sha256'] = ah.Value(sha256.sum(os.read_bytes(state + '/kernel/bin/vinix')!).hex())
	result['desktop_sha256'] = ah.Value(sha256.sum(os.read_bytes(root + '/build/vinix-desktop')!).hex())
	os.write_file(state + '/result.json', ah.encode(ah.Value(result)) + '\n')!
	exit(status)
}
