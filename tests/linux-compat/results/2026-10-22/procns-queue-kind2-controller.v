import crypto.sha256
import envhelper
import guesthost
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	assert os.args.len == 2 && os.args[1] in ['before', 'after']
	phase := os.args[1]
	envhelper.configure()
	area := envhelper.area
	state := area + '/states/diagnostic-kind2b-' + phase + '-x86'
	assert !os.exists(state), 'Fresh state required'
	os.mkdir_all(state)!
	source := area + '/diagnostic-kind2b/procnsfixture/core.v'
	kernel := if phase == 'before' { '/Users/alex/.cache/vinix-linux-compat/procns-20261016/before-x86-track/kernel/bin/vinix' } else { area + '/x86-track/kernel/bin/vinix' }
	os.mkdir_all(state + '/kernel/bin')!
	os.cp(kernel, state + '/kernel/bin/vinix')!
	init := guesthost.compile_init(source, state, 'x86_64', false)!
	archive := guesthost.image(init, state)!
	launch := guesthost.launch(init, archive, state, state + '/kernel', 'x86_64', true)!
	os.write_file(state + '/inputs.json', json2.encode({'source_sha256': digest(source)!, 'init_sha256': digest(init)!, 'kernel_sha256': digest(kernel)!, 'runner_sha256': digest(os.executable())!, 'fixture': source, 'profile': 'diagnostic-only-kind2-warm200-measured200', 'qemu_command': launch.command.join(' ')}, prettify: true))!
	result := guesthost.boot_session(launch.command, launch.env, state, guesthost.SessionPolicy{pass: 'PROCNS DIAG: DONE', failures: ['LINUX PROCNS FAIL', 'KERNEL PANIC'], log: state + '/live.log'}, 7200, true)!
	os.write_file(state + '/receipt.json', json2.encode({'passed': json2.Any(result.passed), 'finished': json2.Any(result.finished), 'status': json2.Any(result.status), 'source_sha256': json2.Any(digest(source)!), 'init_sha256': json2.Any(digest(init)!), 'kernel_sha256': json2.Any(digest(kernel)!), 'serial_sha256': json2.Any(digest(state + '/serial.log')!), 'inputs_sha256': json2.Any(digest(state + '/inputs.json')!), 'purpose': json2.Any('Diagnostic attribution only; never replaces strict qualification')}, prettify: true))!
	if !result.finished || !result.passed { exit(1) }
}
