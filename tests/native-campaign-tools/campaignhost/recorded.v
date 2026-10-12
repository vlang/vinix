// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import hosttest
import json2
import os
import sourcecommand

// Frozen run manifests remain data. Known retired core harnesses are executed
// by a separately compiled native supervisor, including four-level
// CPU policy. Unknown interpreter commands never fall through to execution.
pub fn native_command(command []string) ![]string {
	if command.len == 0 { return error('empty recorded command') }
	name := os.base(command[0])
	if name in ['python', 'python3'] || name.starts_with('python3.') {
		if command.len < 2 || os.base(command[1]) !in ['run_vm.py', 'run-vm'] {
			return error('recorded command needs a native replacement: ' + command.str())
		}
		root := os.dir(os.dir(os.dir(command[1])))
		cpu := if command[1].contains('four-level') { 'max,-la57' } else { 'max' }
		return ['__native_core_harness__', root, cpu, ...command[2..]]
	}
	if command[0].ends_with('.py') {
		return error('recorded command needs a native replacement: ' + command.str())
	}
	return command
}

pub fn compile_core_harness(temporary string, with_package_server bool) !string {
	compiler := captured(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', hosttest.root()])!
	arch := $if amd64 { 'amd64' } $else { 'arm64' }
	captured([compiler, '-nocache', '-cc', 'cc', '-arch', arch, '-o', temporary + '/core', hosttest.root() + '/tests/native-campaign-tools/core-main.v'])!
	if with_package_server {
		captured([compiler, '-nocache', '-cc', 'cc', '-arch', arch, '-o', temporary + '/packages', hosttest.root() + '/tools/qemu-package-store.v'])!
	}
	return temporary + '/core'
}

pub fn recorded_core(context Context, supplement bool, final_arm bool) !int {
	state := if final_arm {
		context.root + '/build/useralloc-arm-core-final-v5'
	} else {
		context.state
	}
	mut manifest := read_json(state + '/run.json')!
	if final_arm {
		if !os.is_executable(state + '/init') { return error('core init is not executable') }
		manifest['started_utc'] = now()
		manifest.delete('exit_code')
		manifest.delete('finished_utc')
		write_json(state + '/run.json', manifest)!
	}
	mut environment := env_merge(manifest['run_environment']!.as_map())!
	mut command := native_command(strings(manifest['run_command']!)!)!
	mut temporary := ''
	defer { if temporary != '' { hosttest.remove_work_dir(temporary) or {} } }
	// Record the native executable actually invoked, retaining captured argv
	// separately when this manifest originally named the retired interpreter.
	if command[0] == '__native_core_harness__' {
		temporary = sourcecommand.temporary('vinix-campaign-core')!
		legacy_boot := os.is_file(command[1] + '/run-aarch64.sh') && !os.is_file(command[1] + '/scripts/run-aarch64.sh')
		command[0] = compile_core_harness(temporary, legacy_boot)!
		if legacy_boot { environment['VINIX_CAMPAIGN_PACKAGE_SERVER'] = temporary + '/packages' }
		manifest['native_run_command'] = command.map(json2.Any(it))
		manifest['native_harness'] = true
	}
	// ARM's inner supervisor permits five seconds for QEMU escape and two
	// for SIGTERM. Let that owner finish before the outer private group reap.
	mut status := logged_grace(command, state + '/serial.log', environment, '', '', if temporary != '' {
		10
	} else {
		0
	})!
	if supplement {
		passed := os.read_bytes(state + '/serial.log')!.bytestr().count('PAGETABLE CHECK: PASS') == 1
		manifest['boundary_supplement_pass'] = passed
		if status == 0 && !passed { status = 1 }
	}
	manifest['exit_code'] = status
	manifest['finished_utc'] = now()
	manifest['serial_sha256'] = digest(state + '/serial.log')!
	write_json(state + '/run.json', manifest)!
	println(if final_arm { 'core ' } else { 'full core ' } + status.str())
	flush_stdout()
	return status
}

pub fn command_with_origin(command string, origin string, args []string) []string {
	return [os.executable(), command, origin, ...args]
}

pub fn resolve(path string) !string { return hosttest.module_resolve(path)! }
