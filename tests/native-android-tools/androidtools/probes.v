// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import cachecli
import hosttest
import os
import sourcecommand

fn probe_command(arguments []string, capture bool, host_arch string) !string {
	result := if capture {
		sourcecommand.capture_stdout_preferred(arguments, os.environ(), -1, 0x7ffffffe, cachecli.cancelled, host_arch) or {
			if err.msg().starts_with('cannot start ') { return ah.command_spawn_error(arguments[0], err.code()) }
			return err
		}
	} else {
		sourcecommand.run_preferred(arguments, os.environ(), cachecli.cancelled, host_arch) or {
			if err.msg().starts_with('cannot start ') { return ah.command_spawn_error(arguments[0], err.code()) }
			return err
		}
	}
	if result.stderr != '' { eprint(result.stderr); flush_stderr() }
	if capture { hosttest.module_decode_utf8(result.stdout)! }
	output := if capture { result.stdout.replace('\r\n', '\n').replace('\r', '\n') } else { '' }
	if result.status != 0 { return ah.command_failure(arguments, result.status, capture, output) }
	return output
}

pub fn probe_cli(kind string, origin string, argv []string) !int {
	previous := ah.set_command_runner(probe_command)
	defer { ah.set_command_runner(previous) }
	if kind !in ['lifecycle', 'cookie', 'autofill', 'location', 'layout-focus', 'pointer-capture', 'egl-queue', 'split'] { return error('unknown Android probe kind') }
	simple := kind in ['layout-focus', 'pointer-capture']
	advanced := kind in ['egl-queue', 'split']
	mut scalar := ['--framework-classes', '--core-classes', '--r8', '--output', '--javac', '--java']
	mut required := ['--framework-classes', '--r8', '--output']
	if simple { scalar << '--stub-classes'; required << '--stub-classes' }
	else {
		scalar << ['--framework-res', '--aapt2']
		if !advanced { scalar << ['--manifest', '--source'] }
		required << ['--framework-res', '--core-classes']
	}
	if advanced { scalar << ['--jni-include', '--cc']; required << '--jni-include' }
	args := parse_arguments(argv, scalar, []string{}, []string{}, 0, 0, 'usage: native Android ' + kind + ' probe [compiler and framework options]')!
	for flag in required { required_value(args, flag)! }
	here := os.dir(origin)
	stem := match kind {
		'lifecycle' { 'AndroidActivityLifecycleProbe' }
		'cookie' { 'AndroidCookieProbe' }
		'autofill' { 'AndroidAutofillProbe' }
		'location' { 'AndroidLocationProbe' }
		'egl-queue' { 'AndroidEglQueueProbe' }
		'split' { 'AndroidSplitApkProbe' }
		else { '' }
	}
	mut row := map[string]ah.Value{
		'operation': ah.Value(if simple { 'build_simple_probe' } else { 'build_probe' })
		'kind': ah.Value(kind)
		'helper': ah.Value(origin)
		'javac': ah.Value(args.value('--javac', 'javac'))
		'java': ah.Value(args.value('--java', 'java'))
	}
	for name in ['framework-classes', 'framework-res', 'stub-classes', 'r8', 'output', 'jni-include'] {
		if '--' + name in args.options { row[name.replace('-', '_')] = args.value('--' + name, '') }
	}
	row['core_classes'] = args.value('--core-classes', '/usr/lib/java/core-all_classes.jar')
	if !simple {
		row['manifest'] = args.value('--manifest', here + '/' + stem + 'Manifest.xml')
		row['source'] = args.value('--source', here + '/' + stem + '.java')
		row['aapt2'] = args.value('--aapt2', 'aapt2')
	}
	if advanced {
		row['cc'] = args.value('--cc', if kind == 'split' { 'cc' } else { 'gcc' })
		row['tool_arch'] = os.uname().machine
		row['native_source'] = here + '/' + if kind == 'split' { 'android-split-probe.c' } else { 'android-egl-queue-probe.c' }
		if kind == 'split' { row['split_manifest'] = here + '/AndroidSplitApkProbeConfigManifest.xml' }
		row.delete('operation')
		mut fields := map[string]ah.Value{}
		for key, value in row { fields[key] = value.text().bytes().hex() }
		ah.query(ah.encode(ah.Value({'operation': ah.Value('build_advanced_probe'), 'fields': ah.Value(fields)})))!
		return 0
	}
	result := ah.query(ah.encode(ah.Value(row)))!
	if simple {
		if result != '""' { return InputError{'pinned compiler input checksum mismatch: ' + result} }
	}
	return 0
}
