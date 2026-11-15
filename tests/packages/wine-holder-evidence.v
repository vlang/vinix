// SPDX-License-Identifier: GPL-2.0-or-later
// Focused native holder-death outcome check; not runtime producer admission.
module main

import os
import json2
import tests.packages.winesource

struct Outcome {
	scenario string
	passed bool
	interrupted bool
	seconds f64
	reason string
}

const milestones = [
	'HWTEST START packaged-Wine',
	'HWTEST INFO Wine ordinary-caller-SIGKILL outer-status137 holder-alive PASS',
	'HWTEST INFO Wine signed competing-prefix refusal126 after caller death original-workload-live lease-busy PASS',
	'HWTEST INFO Wine holder-SIGKILL reaped9 manager-adopted kernel-lease-busy PASS',
	'HWTEST INFO Wine initial-client-gone server-live obsolete-generation collection-retained PASS',
	'HWTEST INFO Wine holder-death manager-status37 all-runtime-retired lease-free PASS',
	'HWTEST INFO Wine signed holder-SIGKILL kernel-lease collection-retained natural-retirement PASS',
	'HWTEST PASS packaged-Wine',
]
const unavailable = 'HWTEST FAIL packaged-Wine: holder-death qualification requires kernel workload leases and an unenrolled observer'

fn trace(serial string, baseline bool) ! {
	lines := serial.replace('\r', '').split_into_lines()
	if baseline {
		if lines.filter(it == unavailable).len != 1 || serial.contains('VINIX COLLECTION')
			|| serial.contains('HWTEST PASS') || serial.contains('holder-SIGKILL reaped9') {
			return error('baseline did not refuse before Wine execution at the capability gate')
		}
	} else {
		mut previous := -1
		for marker in milestones {
			if lines.filter(it == marker).len != 1 { return error('missing or duplicate exact milestone: ' + marker) }
			position := lines.index(marker)
			if position <= previous { return error('holder-death milestone order differs') }
			previous = position
		}
		if serial.contains('HWTEST FAIL') { return error('failed guest output') }
	}
	for forbidden in ['Kernel panic', 'KERNEL PANIC', 'FATAL EXCEPTION'] {
		if serial.contains(forbidden) { return error('forbidden guest output') }
	}
}
fn flags(args []string, guest bool) ! {
	mut required := ['wine_owned_manager', 'wine_kernel_lease', 'wine_holder_death_probe']
	if guest { required << ['wine_collection_probe', 'wine_caller_death_probe'] }
	for flag in required {
		mut count := 0
		for index in 0 .. args.len {
			if args[index] == flag && index > 0 && args[index - 1] == '-d' { count++ }
		}
		if count != 1 { return error('missing or duplicate exact compiler flag: ' + flag) }
	}
}
fn controls() ! {
	good := milestones.join('\n') + '\n'
	trace(good, false)!
	trace(unavailable + '\n', true)!
	for bad in [good.replace(milestones[3] + '\n', ''), good + milestones[3] + '\n',
		good.replace(milestones[3], 'quoted "' + milestones[3] + '"'),
		good.replace(milestones[3], milestones[4]).replace(milestones[4] + '\n' + milestones[4], milestones[4] + '\n' + milestones[3]),
		good + 'HWTEST FAIL late failure\n', good + 'Kernel panic\n'] {
		mut refused := false
		trace(bad, false) or { refused = true; unsafe { err.free() } }
		if !refused { return error('counterfeit positive trace accepted') }
	}
	for bad in [good, 'quoted ' + unavailable, unavailable + '\nHWTEST PASS packaged-Wine\n'] {
		mut refused := false
		trace(bad, true) or { refused = true; unsafe { err.free() } }
		if !refused { return error('wrong baseline gate accepted') }
	}
	valid := ['v', '-d', 'wine_owned_manager', '-d', 'wine_kernel_lease', '-d', 'wine_holder_death_probe']
	flags(valid, false)!
	for bad in [valid.filter(it != 'wine_kernel_lease'), [...valid, '-d', 'wine_kernel_lease'], ['v', '-d wine_kernel_lease']] {
		mut refused := false
		flags(bad, false) or { refused = true; unsafe { err.free() } }
		if !refused { return error('counterfeit compiler flags accepted') }
	}
	println('WINE HOLDER EVIDENCE CONTROLS PASS missing duplicate quoted reordered forbidden wrong-gate compiler-flags')
}
fn check(run string, baseline bool) ! {
	declaration := json2.decode[map[string]string](os.read_file(run + '/declaration.json')!)!
	if declaration['architecture'] != 'x86_64' || declaration['run'] != run { return error('native holder run identity differs') }
	inputs := json2.decode[map[string]string](os.read_file(run + '/inputs.json')!)!
	if inputs.len == 0 || inputs != json2.decode[map[string]string](os.read_file(run + '/inputs-before-build.json')!)!
		|| inputs != json2.decode[map[string]string](os.read_file(run + '/inputs-verified.json')!)! { return error('input verification inventory differs') }
	for name in ['kernel', 'compiler', 'qemu', 'controller'] {
		if declaration[name] == '' || declaration[name] !in inputs { return error('missing selected input: ' + name) }
	}
	for path, expected in inputs {
		if winesource.file_digest(path)! != expected { return error('native input changed: ' + path) }
	}
	generated := json2.decode[map[string]string](os.read_file(run + '/generated-before-boot.json')!)!
	if generated.len == 0 || generated['extras/usr/bin/vinix-package'] == ''
		|| generated['build-guest/guest'] == '' || generated['extras/usr/bin/vinix-package'] != generated['build-package/package'] { return error('staged package binary differs') }
	for path, expected in generated {
		if path.starts_with('/') || '..' in path.split('/') || path.contains('\x00') { return error('unsafe artifact path') }
		if winesource.file_digest(run + '/' + path)! != expected { return error('generated artifact changed: ' + path) }
	}
	for name in ['guest', 'package'] {
		args := json2.decode[[]string](os.read_file(run + '/build-' + name + '/v.log.argv.json')!)!
		if args.len == 0 || args[0] != declaration['compiler'] { return error('compiler identity differs') }
		flags(args, name == 'guest')!
	}
	vm := json2.decode[[]string](os.read_file(run + '/boot/qemu-0.argv.json')!)!
	at := vm.index('-m')
	if vm.len == 0 || vm[0] != declaration['qemu'] || vm.filter(it == '-m').len != 1
		|| at < 0 || at + 1 >= vm.len || vm[at + 1] != '3072' { return error('holder VM identity or memory differs') }
	outcome := json2.decode[Outcome](os.read_file(run + '/guest-outcome.json')!)!
	if outcome.scenario != 'packaged-Wine' || outcome.interrupted || outcome.seconds <= 0 || outcome.seconds >= 600 { return error('invalid native outcome or deadline') }
	if baseline {
		if outcome.passed || !outcome.reason.contains(unavailable) || os.exists(run + '/result.json') || os.is_link(run + '/result.json') {
			return error('baseline published acceptance or failed at another gate')
		}
	} else if !outcome.passed || outcome.reason != '' || outcome != json2.decode[Outcome](os.read_file(run + '/result.json')!)! {
		return error('requires matching verified passing native outcome')
	}
	trace(os.read_file(run + '/boot/serial.log')!, baseline)!
	println('WINE HOLDER EVIDENCE PASS expectation=' + if baseline { 'baseline' } else { 'positive' })
}
fn main() {
	if os.args == [os.args[0], 'controls'] { controls() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[2] !in ['positive', 'baseline'] { eprintln('usage: CHECK controls | RUN positive|baseline'); exit(1) }
	check(os.real_path(os.args[1]), os.args[2] == 'baseline') or { eprintln(err); exit(1) }
}
