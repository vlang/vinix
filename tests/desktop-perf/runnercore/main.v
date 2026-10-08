// SPDX-License-Identifier: GPL-2.0-or-later
module runnercore

import androidhost as ah
import json2
import encoding.hex

fn main_plan() !ah.Value {
	scenario_option := option('scenarios')!.text()
	scenarios := scenario_option.split(',').filter(it != '')
	mut seen := map[string]bool{}
	for name in scenarios { seen[name] = true }
	if scenarios.len == 0 || seen.len != scenarios.len {
		parser_error('choose at least one scenario without duplicates')!
	}
	rounds := option('rounds')!
	seconds := option('seconds')!
	settle := option('settle')!
	timeout_option := option('timeout')!
	if compare('lt', rounds, ah.Value(1))! || compare('lt', seconds, ah.Value(1))! || compare('lt', settle, ah.Value(0))! || compare('lt', timeout_option, ah.Value(0))! {
		parser_error('rounds and seconds must be positive; settle and timeout must be nonnegative')!
	}
	allowed := constant('SCENARIOS')!.items().map(it.text())
	for name in scenarios {
		if name !in allowed {
			parser_error('unknown scenario ' + name + '; choose from ' + allowed.join(', '))!
		}
	}
	mut builds := [][]string{}
	for item in option('builds')!.items() {
		text := item.text()
		at := text.index('=') or { -1 }
		name := if at >= 0 { text[..at] } else { text }
		binary := if at >= 0 { text[at + 1..] } else { '' }
		valid_name := name.len > 0 && name.bytes().all((it >= `A` && it <= `Z`) || (it >= `a` && it <= `z`) || (it >= `0` && it <= `9`) || it == `_` || it == `-`)
		if !valid_name || binary == '' { parser_error('expected NAME=BINARY, got ' + text)! }
		if !boolean(path(binary, 'is_file', []ah.Value{}, map[string]ah.Value{})!) {
			parser_error('no such binary: ' + binary)!
		}
		builds << [name, binary]
	}
	mut labels := []string{}
	mut label_set := map[string]bool{}
	for build in builds {
		labels << build[0]
		label_set[build[0]] = true
	}
	if labels.len != label_set.len { parser_error('build labels must be unique')! }
	dictionary := option('dictionary_data')!
	if 'workflows' in scenarios && dictionary is json2.Null {
		parser_error('workflows requires --dictionary-data=DIR with prepared local data and license')!
	}
	mut assets := null()
	if dictionary !is json2.Null {
		assets = public('dictionary_assets', [path_arg(dictionary.text())]) or {
			if err is BindingError && boolean(ah.field(err.value, 'dictionary_error')) {
				callback('parser_error', {
					'message': ah.field(err.value, 'message')
					'error':   ah.Value(err.value)
				})!
			}
			return err
		}
	}
	work := invoke('tempfile', 'mkdtemp', []ah.Value{}, {
		'prefix': ah.Value('vinix-desktop-perf.')
	})!.text()
	owner := callback('enter', {
		'name':      ah.Value('temporary_vm')
		'arguments': ah.Value([path_arg(work)])
	})!.object()
	id := ah.field(owner, 'id').text()
	runtime := ah.field(owner, 'value').text()
	mut result := null()
	mut cause := ?IError(none)
	result = main_runtime(work, runtime, assets, builds, labels, scenarios, rounds, settle, seconds, timeout_option) or {
		cause = err
		null()
	}
	suppressed := exit_owner(id, cause)!
	if failure := cause {
		if !suppressed { return failure }
		return null()
	}
	return result
}

fn main_runtime(work string, runtime string, assets ah.Value, builds [][]string, labels []string, scenarios []string, rounds ah.Value, settle ah.Value, seconds ah.Value, timeout_option ah.Value) !ah.Value {
	overlay := join(runtime, 'overlay/opt/vinix-perf')!
	mkdir(overlay, true, false)!
	if assets !is json2.Null {
		directory := join(runtime, 'overlay/usr/share/vinix/dictionary')!
		mkdir(directory, true, false)!
		for asset in assets.items() {
			name := path(asset.text(), 'name', []ah.Value{}, map[string]ah.Value{})!.text()
			library('shutil', 'copyfile', [path_arg(asset.text()), path_arg(join(directory, name)!)])!
		}
	}
	for build in builds {
		library('shutil', 'copyfile', [path_arg(build[1]),
			path_arg(join(overlay, 'vinix-desktop-' + build[0])!)])!
	}
	source := path(constant('__file__')!.text(), 'with_name', [value_arg(ah.Value('measure.c'))], map[string]ah.Value{})!.text()
	public('compile_measure', [path_arg(source), path_arg(join(overlay, 'measure')!)])!
	configuration := "VARIANTS='" + labels.join(' ') + "'\nSCENARIOS='" + scenarios.join(' ') + "'\nROUNDS=" + string_value(rounds)! + '\nSETTLE=' + string_value(settle)! + '\nMEASURE=' + string_value(seconds)! + "\nDESKTOP_ARGS='" + option('desktop_args')!.text() + "'\n"
	path(join(overlay, 'config')!, 'write_text', [value_arg(ah.Value(configuration))], map[string]ah.Value{})!
	socket := join(work, 'qmp.sock')!
	initramfs := path(option('initramfs')!.text(), 'resolve', []ah.Value{}, map[string]ah.Value{})!.text()
	tag := callback('hash', {
		'value': ah.Value(initramfs)
	})!.text()[..12]
	stem := path(initramfs, 'stem', []ah.Value{}, map[string]ah.Value{})!.text()
	root := constant('ROOT')!.text()
	module_iso := join(root, 'build/desktop-perf/' + stem + '-' + tag + '.iso')!
	python := callback('sys_executable', map[string]ah.Value{})!.text()
	invoke('', 'run_guest_command', [value_arg(strings([python,
		join(root, 'tools/prune-build-artifacts.py')!, '--root', root, '--automatic', '--keep',
		initramfs, '--keep', module_iso]))], {
		'check': ah.Value(true)
	})!
	invoke('', 'run_guest_command', [value_arg(strings([python,
		join(root, 'tools/build-qemu-module-iso.py')!, initramfs, module_iso]))], {
		'check': ah.Value(true)
	})!
	mut environment := callback('environ', map[string]ah.Value{})!.object()
	old_extra := ah.field(environment, 'VINIX_QEMU_EXTRA')
	mut extra := if old_extra is json2.Null { '' } else { old_extra.text() }
	extra += ' -qmp unix:' + socket + ',server,nowait'
	updates := {
		'VINIX_INITRAMFS':            initramfs
		'VINIX_INITRAMFS_COMPRESSED': '0'
		'VINIX_QEMU_MODULE_ISO':      module_iso
		'VINIX_QEMU_BASE_ARCHIVE':    ''
		'VINIX_QEMU_MODULE_MANIFEST': ''
		'VINIX_QEMU_EXTRA_MODULES':   ''
		'VINIX_QEMU_ROOT_DISK':       '0'
		'VINIX_BOOT_DISK':            join(runtime, 'boot.img')!
		'VINIX_EFIVARS':              join(runtime, 'efivars.fd')!
		'VINIX_QEMU_PACKAGE_STORE':   join(runtime, 'packages.tar')!
		'VINIX_QEMU_PACKAGE_PERSIST': '0'
		'VINIX_QEMU_PERSIST_DISK':    join(runtime, 'root.ext2')!
		'VINIX_QEMU_PERSIST_SIZE_MB': '256'
		'VINIX_KEEP_TEMP_BOOT_DISK':  '1'
		'VINIX_QEMU_OVERLAY':         join(runtime, 'overlay')!
		'VINIX_QEMU_RESOLUTION':      '2048x1536x32'
		'VINIX_OVMF_CODE':            join(root, 'boot-image/edk2-aarch64-code-2048x1536.fd')!
		'VINIX_QEMU_EXTRA':           callback('strip', {
			'value': ah.Value(extra)
		})!.text()
		'VINIX_QEMU_HOST_SOURCE':     '0'
		'VINIX_QEMU_AUDIO':           'off'
	}
	for key, value in updates { environment[key] = ah.Value(value) }
	environment.delete('VINIX_QEMU_PERSIST')
	guest_init := path(constant('__file__')!.text(), 'with_name', [value_arg(ah.Value('perf-init.sh'))], map[string]ah.Value{})!.text()
	command := [join(root, 'scripts/run-aarch64.sh')!, '--no-build', '--serial',
		'--mem=' + string_value(option('mem')!)!, '--guest-init=' + guest_init]
	per_run := arithmetic('add', arithmetic('add', settle, seconds)!, ah.Value(60))!
	mut timeout := timeout_option
	if compare('eq', timeout, ah.Value(0))! {
		timeout = arithmetic('add', ah.Value(900), arithmetic('mul', arithmetic('mul', arithmetic('mul', per_run, ah.Value(builds.len))!, ah.Value(scenarios.len))!, rounds)!)!
	}
	print_message('==> Measuring ' + labels.join(', ') + ' over ' + scenarios.join(', ') + ' x' + string_value(rounds)! + ' (up to ' + string_value(timeout)! + 's)', true)!
	callback('pointer', {
		'path': ah.Value(socket)
	})!
	fork := callback('fork', {
		'root':        ah.Value(root)
		'command':     strings(command)
		'environment': ah.Value(environment)
	})!.items()
	pid, master := fork[0], fork[1]
	deadline := arithmetic('add', library('time', 'monotonic', []ah.Value{})!, timeout)!
	mut timed_out := false
	mut cause := ?IError(none)
	timed_out = supervise(deadline) or {
		cause = err
		false
	}
	exit_code := callback('stop', {
		'pid': pid
	})!
	callback('join_console', {
		'timeout': ah.Value(2)
	})!
	public('close_guest_fd', [value_arg(master)])!
	callback('join_console', {
		'timeout': ah.Value(1)
	})!
	transcript := callback('transcript', map[string]ah.Value{})!.object()
	log := join(work, 'serial.log')!
	callback('write_bytes', {
		'path': ah.Value(log)
		'data': ah.field(transcript, 'data')
	})!
	print_message('\n==> Serial log: ' + log, false)!
	if failure := cause { return failure }
	output := option('json')!
	result := public('finish_run', [arg('bytes', ah.field(transcript, 'data')),
		value_arg(strings(labels)), value_arg(strings(scenarios)), value_arg(rounds),
		if output is json2.Null { value_arg(output) } else { path_arg(output.text()) },
		value_arg(ah.Value(timed_out)), value_arg(exit_code)])!
	if !boolean(ah.field(transcript, 'closed')) {
		callback('print', {
			'message': ah.Value('ERROR: serial console did not finish draining after guest shutdown')
			'stderr':  ah.Value(true)
		})!
		return ah.Value(1)
	}
	return result
}

fn supervise(deadline ah.Value) !bool {
	for {
		remaining := arithmetic('sub', deadline, library('time', 'monotonic', []ah.Value{})!)!
		if compare('le', remaining, ah.Value(0))! { return true }
		interval := if compare('lt', remaining, ah.Value(ah.Number{'0.5'}))! {
			remaining
		} else {
			ah.Value(ah.Number{'0.5'})
		}
		row := callback('line', {
			'timeout': interval
		})!.object()
		if 'empty' in row {
			if boolean(ah.field(row, 'closed')) { return false }
			continue
		}
		line := ah.field(row, 'line').text()
		drive := callback('match', {
			'name': ah.Value('DRIVE')
			'data': ah.Value(line)
		})!
		if drive !is json2.Null {
			values := drive.items()
			callback('drive', {
				'scenario': values[0]
				'seconds':  values[1]
			})!
		}
		shot := callback('match', {
			'name': ah.Value('SHOT')
			'data': ah.Value(line)
		})!
		if shot !is json2.Null {
			shots := option('shots')!
			if shots !is json2.Null {
				mkdir(shots.text(), true, true)!
				name := shot.items().map(it.text()).join('-')
				resolved := path(shots.text(), 'resolve', []ah.Value{}, map[string]ah.Value{})!.text()
				callback('screendump', {
					'path': ah.Value(join(resolved, name + '.ppm')!)
				})!
			}
		}
		raw := hex.decode(line)!.bytestr()
		if callback('bytes_strip', {
			'data': ah.Value(line)
		})!.text() == '56494e4958204445534b544f5020504552463a20444f4e45' || raw.contains('KERNEL PANIC') || raw.contains('FATAL EXCEPTION') || raw.contains('PERF-ERROR') {
			return false
		}
	}
	return false
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	inputs := ah.field(row, 'arguments').items()
	return match ah.field(row, 'operation').text() {
		'dictionary_assets' { dictionary_assets(inputs[0].text())! }
		'compile_measure' { compile_measure(inputs[0].text(), inputs[1].text())! }
		'main' { main_plan()! }
		else { return failed('RuntimeError', 'unknown desktop operation') }
	}
}
