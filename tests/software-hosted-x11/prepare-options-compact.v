// SPDX-License-Identifier: GPL-2.0-or-later
// Adapt only the new mutable source copy; original native06 stays unchanged.
module main

import crypto.sha256
import json2
import nativeguard
import os

const repository = '/Users/alex/code/vinix'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const prior = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-01'
const suite = state + '/source/tests/software-hosted-x11'

fn need(ok bool, message string) ! { if !ok { return error(message) } }

fn sha(path string) !string { return sha256.hexhash(os.read_file(path)!) }

fn change(path string, before string, after string, count int) ! {
	text := os.read_file(path)!
	need(text.count(before) == count && os.lstat(path)!.nlink == 1,
		'fixed source count/independence differs: ' + before)!
	changed := text.replace(before, after)
	need(changed.replace(after, before) == text, 'source delta is not reversible: ' + before)!
	os.write_file(path, changed)!
}

fn capture_module(root string, name string, mut pins map[string]string) ! {
	for path in os.walk_ext(root + '/' + name, '.v') {
		need(!os.is_link(path) && os.lstat(path)!.mode & 0o170000 == 0o100000
			&& os.file_size(path) < 1024 * 1024, 'requires ordinary bounded module source')!
		pins[path[root.len + 1..]] = sha(path)!
	}
}

fn setup() ! {
	$if prod {} $else { return error('requires production source binding') }
	need(os.args == [os.executable(), '--prepare'] && !os.exists(state + '/compact-prepared.json'),
		'requires exact fresh --prepare')!
	need(sha(@FILE)! == sha256.hexhash($embed_file('prepare-options-compact.v').to_string()), 'preparer source changed')!
	need(sha(state + '/prepared.json')! == 'f10b77fb1592332e6c3f7c2fcc3bf14387710bbafc05998001acd2f150b2bbc9',
		'independent source preparation differs')!
	check := suite + '/check.v'
	need(sha(check)! == '7690dd77af1f8e9abd051d1cb79823a2a880bb2940f44dc1c1a3cea708d2b37d', 'native06 controller donor differs')!
	nativeguard.watch_interrupts()!
	df := nativeguard.actual_df(state, state + '/compact-admission-df')!
	need(df.available >= u64(2) << 30
		&& nativeguard.allocated([prior, state], os.lstat(state)!.dev)! <= u64(58) << 20,
		'compact setup admission or64MiB phase cap refused')!
	main_suite := repository + '/tests/software-hosted-x11'
	alias := state + '/source/tools/hosttest'
	need(!os.exists(alias) && !os.is_link(alias)
		&& os.readlink(repository + '/build/package-hosted-launch-options-guest-worktree/tools/hosttest')! == '../tests/linuxkpi/hosttest',
		'requires exact fresh hosttest module alias')!
	os.symlink('../tests/linuxkpi/hosttest', alias)!
	need(os.real_path(alias) == state + '/source/tests/linuxkpi/hosttest', 'hosttest alias escaped independent source')!
	process := state + '/source/tests/hardware-platform/hwhost/process.v'
	old_process := os.read_file(process)!
	qualified_process := os.read_file(repository + '/tests/hardware-platform/hwhost/process.v')!
	need(sha256.hexhash(old_process) == 'c6e025797a1770e9caa9166989f805acce98f227d7d8efcca4340dc6e1cd1f21'
		&& sha256.hexhash(qualified_process) == '1cefdf1ce196bbe4f05813969107144dd2c123662c56815124da56c92dc5e5d5'
		&& old_process.replace('mut status := 0', 'mut status := i32(0)').replace('c.status = status', 'c.status = int(status)') == qualified_process
		&& os.lstat(process)!.nlink == 1, 'requires exact qualified hwhost status-width correction')!
	os.write_file(state + '/compact-before-hwhost-process.v', old_process)!
	os.write_file(process, qualified_process)!
	mut modules := map[string]string{}
	for name in ['compactproof', 'compactui'] {
		need(!os.exists(suite + '/' + name), 'refuses existing compact module')!
		capture_module(main_suite, name, mut modules)!
	}
	need(modules.len >= 6 && modules.len < 30, 'compact module source selection differs')!
	for relative, expected in modules {
		target := suite + '/' + relative
		os.mkdir_all(os.dir(target), mode: 0o700)!
		os.cp(main_suite + '/' + relative, target)!
		need(os.lstat(target)!.nlink == 1 && sha(target)! == expected, 'compact module copy differs')!
	}
	for name in ['compactproof', 'compactui'] {
		os.cp(suite + '/' + name + '/check/main.v', suite + '/' + name + '-check.v')!
		os.cp(suite + '/' + name + '/check/main.v', suite + '/' + name + '-check-normal.v')!
	}
	for name in ['check.v', 'run-native06.v', 'build-supervision.v'] {
		os.cp(suite + '/' + name, state + '/compact-before-' + name)!
	}
	change(check, 'import launchproof\n', 'import launchproof\nimport compactproof\nimport compactui\n', 1)!
	change(check, 'struct TreeInput {', '__global (\n compact_audit_directory string\n)\n\nstruct TreeInput {', 1)!
	change(check, '\tos.write_file(log, output)!\n', '\tos.write_file(log, output)!\n\tos.write_file(log + \'.exit.json\', json2.encode({\'exit_code\': child.code}))!\n', 1)!
	change(check, "'--clipboard-root']", "'--clipboard-root', '--compact']", 1)!
	change(check, '\tlaunch_options := scenario == optionsfixture.scenario\n',
		'\tlaunch_options := scenario == optionsfixture.scenario\n' +
		"\tcompact_text := options['--compact'] or { '' }\n" +
		"\tif compact_text !in ['', 'true'] || (compact_text != '' && !launch_options) { return error('compact mode requires the literal launch-options scenario') }\n" +
		"\tcompact := compact_text == 'true'\n", 1)!
	change(check, '\tos.mkdir_all(work)!\n\thost :=',
		'\tos.mkdir_all(work)!\n\tmut compact_audits := compactproof.Audits{}\n\tif compact {\n' +
		"\t\tcompact_audit_directory = work + '/compact-audits-before'\n\t\tos.mkdir(compact_audit_directory)!\n" +
		"\t\tcompact_audits = compactproof.check_audits(compact_original_check)!\n\t\tcompact_audits.write_record(work + '/compact-audits-before.json')!\n\t}\n\thost :=", 1)!
	change(check, "'tests/software-hosted-x11/launchproof', 'tests/software-hosted-x11/optionsfixture']",
		"'tests/software-hosted-x11/launchproof', 'tests/software-hosted-x11/optionsfixture', 'tests/software-hosted-x11/compactproof', 'tests/software-hosted-x11/compactui']", 1)!
	change(check, '\tassembled := if launch_options { launchproof.assembled',
		'\tassembled := if compact { compactproof.assembled(os.dir(desktop), os.dir(stage), arch, host.v, compact_audits)! }\n\t\telse if launch_options { launchproof.assembled', 1)!
	change(check, '\tfor _, path in assembled { inputs[path] = digest(path)! }\n',
		'\tfor _, path in assembled { inputs[path] = digest(path)! }\n\tif compact {\n' +
		"\t\tinputs[work + '/compact-audits-before.json'] = digest(work + '/compact-audits-before.json')!\n" +
		'\t\tfor _, path in compact_audits.inputs()! { inputs[path] = digest(path)! }\n\t}\n', 1)!
	change(check, "for name in ['optionsfixture']", "for name in ['optionsfixture', 'compactproof', 'compactui']", 1)!
	change(check, 'graphical_boot(host.qemu, arguments, qmp, work, arch, launch_options)!',
		'graphical_boot(host.qemu, arguments, qmp, work, arch, launch_options, compact)!', 1)!
	change(check, '\tmut outputs := map[string]string{}\n',
		'\tif compact {\n' +
		"\t\tcompact_audit_directory = work + '/compact-audits-after'\n\t\tos.mkdir(compact_audit_directory)!\n" +
		"\t\tcompact_audits = compactproof.check_audits(compact_original_check)!\n\t\tcompact_audits.write_record(work + '/compact-audits-after.json')!\n" +
		'\t\tcompactproof.assembled(os.dir(desktop), os.dir(stage), arch, host.v, compact_audits)!\n\t\tcompactui.validate_frames(work)!\n\t\tverify(inputs)!\n\t\tverify_trees(trees)!\n\t\tqualified_compact_compiler(host.v, trees, mut inputs)!\n\t}\n' +
		'\tmut outputs := map[string]string{}\n\tif compact {\n' +
		"\t\toutputs['compact-audits-after.json'] = digest(work + '/compact-audits-after.json')!\n" +
		"\t\tfor path in os.walk_ext(work + '/compact-audits-after', '') { if os.is_file(path) { outputs[path[work.len + 1..]] = digest(path)! } }\n" +
		"\t\tfor frame in compactui.frames() { outputs[frame.name + '.png'] = digest(work + '/' + frame.name + '.png')! }\n" +
		"\t\toutputs['14-compact-painted.png'] = digest(work + '/14-compact-painted.png')!\n\t}\n", 1)!
	change(check, 'format: if launch_options { 2 } else { 1 }, scenario: scenario,',
		'format: if launch_options { 2 } else { 1 }, scenario: scenario, compact: compact,', 1)!
	change(check, 'struct Qualification {\n\tformat int = 1', 'struct Qualification {\n\tcompact bool\n\tformat int = 1', 1)!
	change(check, 'work string, arch string, launch_options bool) ! {',
		'work string, arch string, launch_options bool, compact bool) ! {', 1)!
	change(check, '\tif launch_options { drive_launch_options(mut monitor, work)! }',
		'\tif launch_options { if compact { compactui.drive(mut monitor, work)! } else { drive_launch_options(mut monitor, work)! } }', 1)!
	change(check, "\twait_paint(mut child, mut monitor, log, deadline, work, '02-painted', false)!",
		"\tif compact { wait_paint(mut child, mut monitor, log, deadline, work, '14-compact-painted', false)!; compactui.maximize_running(mut monitor)! }\n" +
		"\twait_paint(mut child, mut monitor, log, deadline, work, '02-painted', false)!", 1)!
	os.write_file(check, os.read_file(check)! + '\nfn compact_original_check(argv []string, label string) !compactproof.CheckRun {\n' +
		" base := compact_audit_directory + '/' + label\n" +
		" invoke(argv, base + '.log')!\n" +
		" return compactproof.CheckRun{0, base + '.log.argv.json', base + '.log', base + '.log.exit.json'}\n}\n")!
	os.write_file(check, compiler_admission(os.read_file(check)!)!)!
	// The wrapper's other kernel/rootfs/sysroot/stage inputs remain original.
	runner := suite + '/run-native06.v'
	change(runner, "'--scenario=launch-options', '--arch='", "'--scenario=launch-options', '--compact=true', '--arch='", 1)!
	change(runner, "'--desktop=/Users/alex/Library/Caches/vinix-codex/section14/package-hosted-launch-options-native-20261026/import-'",
		"'--desktop=' + state + '/import-'", 1)!
	builder := suite + '/build-supervision.v'
	change(builder, "'run-native06', 'run-evidence06']", "'run-native06', 'run-evidence06', 'compactproof-check', 'compactui-check', 'compactproof-check-normal', 'compactui-check-normal']", 1)!
	change(builder, '\targv := [compiler, \'-prod\'', '\tmut argv := [compiler, \'-prod\'', 1)!
	change(builder, "\tos.setenv('TMPDIR', output_root + '/scratch', true)",
		"\tif stem.ends_with('-normal') { argv.delete(1) }\n\tos.setenv('TMPDIR', output_root + '/scratch', true)", 1)!
	change(builder, '\tnativeguard.watch_interrupts()!\n\tif os.args.len',
		'\tnativeguard.watch_interrupts()!\n\tif compact_module_controls()! { return }\n\tif os.args.len', 1)!
	os.write_file(builder, module_pins(os.read_file(builder)! + control_support())!)!
	mut after := map[string]string{}
	for name in ['compactproof', 'compactui'] { capture_module(main_suite, name, mut after)! }
	need(modules == after, 'compact module sources changed during setup')!
	for relative, _ in modules { need(sha(suite + '/' + relative)! == modules[relative], 'copied compact source changed')! }
	final_df := nativeguard.actual_df(state, state + '/compact-completion-df')!
	bytes := nativeguard.allocated([prior, state], os.lstat(state)!.dev)!
	need(final_df.available >= u64(1) << 30 && bytes <= (u64(64) << 20) - (u64(2) << 20), 'compact setup final floor/cap refused')!
	os.write_file(state + '/compact-prepared.json', json2.encode({'outcome': 'PREPARED',
		'controller': sha(check)!, 'builder': sha(builder)!, 'runner': sha(runner)!,
		'modules': json2.encode(modules), 'allocated_bytes': bytes.str(),
		'scope': 'Mutable independent source setup only; no audits, import, target build or native guest.'}) + '\n')!
	println('PREPARED current compact controller and module source; original native06 unchanged; no guest')
}

fn control_support() string {
	return '\nfn compact_module_controls() !bool {\n' +
		" if os.args.len < 2 || os.args[1] != '--module-controls' { return false }\n" +
		control_names() +
		" output := output_root + '/' + os.args[2] + '-controls'\n" +
		" for suffix in ['', '.argv.json', '.log', '.exit.json', '.run.json'] { if os.exists(output + suffix) || os.is_link(output + suffix) { return error('compact control output already exists') } }\n" +
		' available, before := df()!\n' +
		" if available < u64(550) * 1024 || allocation(output_root)! > u64(36) << 20 { return error('compact controls need550MiB free and4MiB namespace headroom') }\n" +
		" executable := output_root + '/' + os.args[2]\n" +
		' mut pins := map[string]string{}\n' +
		' for path in [@FILE, os.executable(), executable, suite + \'/nativeguard/guard.v\', suite + \'/diagnostics/recoveryguard/recoveryguard.v\'] { pins[path] = sha(path)! }\n' +
		" argv := [executable, '--controls', output]\n" +
		" os.write_file(output + '.argv.json', json2.encode(argv))!\n" +
		' code := monitored(argv, output, 120000)!\n' +
		" os.write_file(output + '.exit.json', json2.encode({'exit_code': code}))!\n" +
		' after_kib, after := df()!\n' +
		' for path, expected in pins { if sha(path)! != expected { return error(\'compact control source/tool changed\') } }\n' +
		' bytes := allocation(output_root)!\n' +
		" os.write_file(output + '.run.json', json2.encode({'actual_exit': code.str(), 'pins': json2.encode(pins), 'df_before': before, 'df_after': after, 'allocated_bytes': bytes.str()}))!\n" +
		" if code != 0 || after_kib < u64(550) * 1024 || allocation(output_root)! > u64(40) << 20 { return error('compact controls or final resource checks failed') }\n" +
		" println('PASS fixed compact module controls: ' + os.args[2])\n return true\n}\n"
}

fn control_names() string {
	return " if os.args.len != 3 { return error('requires a fixed compiled compact control tool') }\n" +
		" tool := os.args[2].all_before_last('-')\n attempt := os.args[2].all_after_last('-')\n" +
		" if tool !in ['compactproof-check', 'compactproof-check-normal', 'compactui-check', 'compactui-check-normal'] || attempt.len < 1 || attempt.len > 2 || !attempt.bytes().all(it >= `0` && it <= `9`) || attempt.int() < 1 { return error('requires a fixed compiled compact control tool') }\n"
}

fn replacing(text string, before string, after string) !string {
	need(text.count(before) == 1, 'module pin transformation count differs')!
	result := text.replace(before, after)
	need(result.replace(after, before) == text, 'module pin transformation is not reversible')!
	return result
}

fn module_pins(text string) !string {
	first := replacing(text, '\tos.mkdir(monitor)!\n\tresult :=',
		"\tos.mkdir(monitor)!\n\tmodules_before := compact_module_map()!\n\tos.write_file(monitor + '/modules-before.json', json2.encode(modules_before))!\n\tresult :=")!
	second := replacing(first, "\tos.write_file(monitor + '/result.json', json2.encode(result))!\n",
		"\tos.write_file(monitor + '/result.json', json2.encode(result))!\n\tmodules_after := compact_module_map()!\n\tos.write_file(monitor + '/modules-after.json', json2.encode(modules_after))!\n\tif modules_before != modules_after { return error('imported fixture module changed during command') }\n")!
	return second + r"

fn compact_module_map() !map[string]string {
 mut result := map[string]string{}
 started := time.sys_mono_now()
 for name in ['proof', 'launchproof', 'optionsfixture', 'compactproof', 'compactui'] {
  for path in os.walk_ext(suite + '/' + name, '.v') {
   if result.len >= 64 || time.sys_mono_now() - started >= 30000000000 { return error('fixture module inventory bound') }
   info := os.lstat(path)!
   if info.mode & 0o170000 != 0o100000 || info.size > 1048576 { return error('fixture module requires small ordinary source') }
   result[path] = sha(path)!
  }
 }
 if result.len < 5 || json2.encode(result).len > 16384 { return error('fixture module map is incomplete or exceeds16KiB') }
 return result
}
"
}

fn retry_tools() ! {
	$if prod {} $else { return error('requires production source binding') }
	need(sha(@FILE)! == sha256.hexhash($embed_file('prepare-options-compact.v').to_string()), 'preparer source changed')!
	output := state + '/compact-tool-retry-01'
	need(!os.exists(output) && !os.is_link(output), 'tool correction output already exists')!
	old_builder := os.read_file(suite + '/build-supervision.v')!
	need(sha256.hexhash(old_builder) == 'dafa1b08dc9d63bdb5d43daa26cc04b67cc9fcd0e6c2fadb13e90e4c326c0d88', 'builder02 source differs')!
	old_module := os.read_file(suite + '/compactproof/admit.v')!
	new_module := os.read_file(repository + '/tests/software-hosted-x11/compactproof/admit.v')!
	need(sha256.hexhash(old_module) == 'fac6363b877320e49ea2964f8eda142d0d81cba605446271e5e05ab7afb78c10'
		&& sha256.hexhash(new_module) == '558e3d949d310b54d8550bb8d51bbabfab395655f58afdb6167bf1f42fc58f80'
		&& old_module.replace('same_stat(before os.FileInfo, after os.FileInfo)',
			'same_stat(before os.Stat, after os.Stat)') == new_module, 'requires exact pinnedvlib type correction')!
	old_names := " if os.args.len != 3 || os.args[2] !in ['compactproof-check-01', 'compactproof-check-normal-01', 'compactui-check-01', 'compactui-check-normal-01'] { return error('requires a fixed compiled compact control tool') }\n"
	updated := replacing(old_builder, old_names, control_names())!
	new_builder := module_pins(updated)!
	old_check := os.read_file(suite + '/check.v')!
	prepared := json2.decode[map[string]string](os.read_file(state + '/compact-prepared.json')!, strict: true)!
	need(sha256.hexhash(old_check) == prepared['controller'], 'prepared compact controller differs')!
	new_check := compiler_admission(old_check)!
	need(!os.exists(suite + '/build-supervision-03.v')
		&& os.lstat(suite + '/compactproof/admit.v')!.nlink == 1, 'requires new builder and independent module')!
	nativeguard.watch_interrupts()!
	df := nativeguard.actual_df(state, state + '/tool-retry-admission-df')!
	need(df.available >= u64(2) << 30 && nativeguard.allocated([prior, state], os.lstat(state)!.dev)! <= u64(58) << 20,
		'tool correction admission refused')!
	os.mkdir(output, mode: 0o700)!
	os.write_file(output + '/before-admit.v', old_module)!
	os.write_file(output + '/before-builder.v', old_builder)!
	os.write_file(output + '/before-check.v', old_check)!
	os.write_file(suite + '/compactproof/admit.v', new_module)!
	os.write_file(suite + '/build-supervision-03.v', new_builder)!
	os.write_file(suite + '/check.v', new_check)!
	os.write_file(output + '/after-admit.v', new_module)!
	os.write_file(output + '/after-builder.v', new_builder)!
	os.write_file(output + '/after-check.v', new_check)!
	final_df := nativeguard.actual_df(state, state + '/tool-retry-completion-df')!
	bytes := nativeguard.allocated([prior, state], os.lstat(state)!.dev)!
	need(final_df.available >= u64(1) << 30 && bytes <= (u64(64) << 20) - (u64(2) << 20),
		'tool correction completion floor/cap refused')!
	os.write_file(output + '/result.json', json2.encode({'outcome': 'PREPARED',
		'builder_before': sha256.hexhash(old_builder), 'builder_after': sha256.hexhash(new_builder),
		'module_before': sha256.hexhash(old_module), 'module_after': sha256.hexhash(new_module),
		'controller_before': sha256.hexhash(old_check), 'controller_after': sha256.hexhash(new_check),
		'allocated_bytes': bytes.str(), 'available_bytes': final_df.available.str(),
		'scope': 'One exact os.Stat compatibility correction; same owner/caps/deadlines; bounded importedmodule maps and fixedtool retry suffixes. No compile/control/guest.'}) + '\n')!
	println('PREPARED bounded source-bound compact tool retry; prior source and failed attempt preserved')
}

fn compiler_admission(text string) !string {
	changed := replacing(text, '\tassembled := if compact {',
		'\tif compact { qualified_compact_compiler(host.v, trees, mut inputs)! }\n\tassembled := if compact {')!
	return changed + r"

struct CompactCompilerPin { path string sha256 string }

fn qualified_compact_compiler(v string, trees map[string]TreeInput, mut inputs map[string]string) ! {
 if v != '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v' { return error('compact controller requires qualified compiler path') }
 root := os.dir(v)
 if os.real_path(root) != root || os.lstat(root)!.mode & 0o170000 != 0o040000 { return error('compact compiler root must be ordinary and canonical') }
 mut root_names := os.ls(root)!
 root_names.sort()
 if root_names != ['snapshot.json', 'thirdparty', 'v', 'v.mod', 'vlib'] { return error('complete compact compiler root entries differ') }
 manifest := os.dir(root) + '/overlay-before.json'
 if digest(manifest)! != '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f' { return error('compact qualified compiler manifest differs') }
 mut expected := map[string]string{}
 for item in json2.decode[[]CompactCompilerPin](os.read_file(manifest)!, strict: true)! {
  if item.path in expected { return error('duplicate compact compiler entry') }
  expected[item.path] = item.sha256
 }
 mut actual := map[string]string{}
 for name in ['v', 'v.mod', 'snapshot.json'] {
  path := root + '/' + name
  if os.lstat(path)!.mode & 0o170000 != 0o100000 { return error('compact compiler requires ordinary root files') }
  actual[name] = digest(path)!
  inputs[path] = actual[name]
 }
 for name, role in {'vlib': 'compiler-vlib', 'thirdparty': 'compiler-thirdparty'} {
  if os.lstat(root + '/' + name)!.mode & 0o170000 != 0o040000 { return error('compact compiler tree must be an ordinary directory') }
  tree := trees[role] or { return error('complete compact compiler tree missing') }
  if tree.root != root + '/' + name || tree.selected_sources { return error('compact compiler tree root or selection differs') }
  actual[name] = 'directory'
  for relative, value in tree.entries { actual[name + '/' + relative] = value }
 }
 if actual != expected { return error('complete compact compiler differs from qualified overlay') }
 inputs[manifest] = digest(manifest)!
}
"
}

fn main() {
	if os.args == [os.executable(), '--prepare-tools-retry'] {
		retry_tools() or { eprintln(err); exit(1) }
	} else { setup() or { eprintln(err); exit(1) } }
}
