// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed host controls and strict C objects; never runs the native controller.
module main

import crypto.sha256
import json2
import os
import time
import tools.packages.winejitstream

const base = '/Users/alex/Library/Caches/vinix-codex/section14'
const overlay = '/Users/alex/.cache/vinix-waitpid-width-20261026-02'
const compiler = overlay + '/toolchain/v'
const clang = '/opt/homebrew/opt/llvm/bin/clang'
const resource = '/opt/homebrew/opt/llvm/lib/clang/23'
const arm_sysroot = '/Users/alex/code/vinix/build/package-rollback-transaction-work/sysroot'
const arm_gcc = '/Users/alex/code/vinix/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0'
const amd_sysroot = base + '/wine-jit-stream-native-inputs-01/x86_64-linux-musl'
const amd_gcc = base + '/wine-jit-stream-native-inputs-01/lib/gcc/x86_64-linux-musl/14.2.0'
const reserve = u64(2 * 1024 * 1024)
const current_limit = u64(40 * 1024 * 1024)
const guard_limit = u64(16 * 1024 * 1024)
const cumulative_limit = u64(128 * 1024 * 1024)

struct Step {
	argv []string
	free_kib u64
	run winejitstream.NativeRun
	output_sha256 string
}

struct Binding {
	entries int
	digest string
}

struct OverlayPin {
	path string
	sha256 string
}

fn overlay_walk(relative string, started u64, mut entries []OverlayPin) ! {
	if entries.len >= 30000 || time.sys_mono_now() - started >= u64(120 * time.second) {
		return error('qualified overlay inventory bound exceeded')
	}
	path := overlay + '/toolchain/' + relative
	info := os.lstat(path)!
	if info.get_filetype() == .directory {
		entries << OverlayPin{relative, 'directory'}
		for name in os.ls(path)! { overlay_walk(relative + '/' + name, started, mut entries)! }
	} else if info.get_filetype() == .regular {
		entries << OverlayPin{relative, winejitstream.native_input_digest(path)!}
	} else { return error('qualified overlay contains a link or special entry: ' + path) }
}

fn qualified_overlay() ! {
	mut actual := []OverlayPin{}
	started := time.sys_mono_now()
	for relative in ['v', 'vlib', 'thirdparty', 'v.mod', 'snapshot.json'] {
		overlay_walk(relative, started, mut actual)!
	}
	mut expected := json2.decode[[]OverlayPin](os.read_file(overlay + '/overlay-before.json')!)!
	actual.sort(a.path < b.path)
	expected.sort(a.path < b.path)
	if actual != expected { return error('complete compiler root differs from qualified wait-width overlay') }
}

fn binding(pins map[string]winejitstream.NativePin) Binding {
	mut keys := pins.keys()
	keys.sort()
	mut hash := sha256.new()
	for key in keys { hash.write((json2.encode(key) + ':' + json2.encode(pins[key]) + '\n').bytes()) or { panic(err) } }
	mut sum := []u8{len: sha256.size}
	hash.checksum_into(mut sum)
	return Binding{entries: keys.len, digest: sum.hex()}
}

fn account(state string, additional u64) !u64 {
	mut prior := u64(0)
	for name in ['wine-jit-stream-native-host-01', 'wine-jit-stream-native-host-02',
		'wine-jit-stream-native-host-03', 'wine-jit-stream-native-host-04', 'wine-jit-stream-native-host-05',
		'wine-jit-stream-native-arm-01.launch-refusal.json', 'wine-jit-stream-native-arm-01.launch-02.json',
		'wine-jit-stream-native-inputs-01', 'wine-jit-stream-native-host-06', 'wine-jit-stream-native-host-07'] {
		prior += winejitstream.static_state_bytes(base + '/' + name)!
	}
	prior += winejitstream.static_host_states_bytes(base)!
	if prior != 56318391 { return error('selected prior evidence changed') }
	mut current := u64(0)
	for name in ['wine-jit-stream-native-host-08', 'wine-jit-stream-native-host-09',
		'wine-jit-stream-native-host-10', 'wine-jit-stream-native-host-11',
		'wine-jit-stream-native-host-12', 'wine-jit-stream-native-host-13',
		'wine-jit-stream-native-host-14', 'wine-jit-stream-native-host-15',
		'wine-jit-stream-native-host-16', 'wine-jit-stream-native-host-17', 'wine-jit-stream-native-host-18',
		'wine-jit-stream-native-caller-seal-01', 'wine-jit-stream-native-width-seal-01',
		'wine-jit-stream-native-width-seal-01-complete'] {
		path := base + '/' + name
		if os.exists(path) || os.is_link(path) { current += winejitstream.static_state_bytes(path)! }
	}
	if current > current_limit || additional > current_limit - current {
		return error('width host state would exceed collective 40 MiB')
	}
	if prior + current + reserve > cumulative_limit
		|| additional > cumulative_limit - prior - current - reserve {
		return error('width host profile would exceed inclusive 128 MiB')
	}
	return prior + current + reserve + additional
}

fn inputs(root string) !map[string]winejitstream.NativePin {
	mut pins := map[string]winejitstream.NativePin{}
	for path in [compiler, overlay + '/toolchain/v.mod', overlay + '/bundle.json', '/usr/bin/true',
		overlay + '/overlay-before.json', overlay + '/changes.json', clang, os.executable(),
		root + '/tests/packages/wine-fork-jit-stream-width-host.v',
		root + '/tests/packages/wine-fork-jit-stream-native.v',
		root + '/tests/packages/wine-fork-jit-stream-native-host.v'] {
		winejitstream.native_input_add(path, mut pins)!
	}
	for path in [overlay + '/toolchain/vlib', overlay + '/toolchain/thirdparty',
		resource, arm_sysroot, arm_gcc, amd_sysroot, amd_gcc,
		root + '/tools/packages/winejitstream', root + '/tests/hardware-platform/hwhost',
		root + '/tests/packages/wine-fork-jit-stream-probe'] {
		winejitstream.native_input_tree(path, mut pins)!
	}
	return pins
}

fn modules(state string) ! {
	if os.getenv('VMODULES') != state + '/modules' { return error('private VMODULES selection changed') }
	winejitstream.native_require_empty_modules(state + '/modules')!
}

fn selected_environment(state string, scratch string) !map[string]string {
	mut environment := winejitstream.native_clear_compiler_environment()
	environment['inherited_VMODULES'] = os.getenv_opt('VMODULES') or { '<unset>' }
	for pair in ['V=' + compiler, 'VEXE=' + compiler, 'VINIX_V_COMPILER=' + compiler,
		'V_MACOS_V3_CALLER_VEXE=' + compiler, 'V_MACOS_V3_CALLER_VEXE_PRESENT=1',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT=0', 'V_MACOS_V3_CALLER_NO_FALLBACK=1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT=1',
		'V_MACOS_V3_NO_FALLBACK=1', 'V_C_ERROR_BUG_REPORT_DISABLED=1',
		'TMPDIR=' + scratch, 'VTMP=' + scratch, 'VMODULES=' + state + '/modules',
		'VINIX_WINE_WAIT_STATE=' + scratch, 'LANG=C', 'LC_ALL=C',
		'PATH=/opt/homebrew/bin:/usr/bin:/bin'] {
		at := pair.index('=') or { return error('invalid fixed environment') }
		os.setenv(pair[..at], pair[at + 1..], true)
		environment[pair[..at]] = pair[at + 1..]
	}
	for name in ['VCHILD', 'V_MACOS_V3_CALLER_VCHILD',
		'V_MACOS_V3_CHILD_VEXE_PRESENT', 'VINIX_WINE_WAIT_ASSERT_SENTINEL'] {
		os.unsetenv(name)
		environment[name] = '<unset>'
	}
	modules(state)!
	return environment
}

fn invoke(argv []string, state string, name string, output string, expected int,
	mut steps map[string]Step) ! {
	modules(state)!
	free := winejitstream.native_require_free(state, winejitstream.native_free_floor(true))!
	account(state, 0)!
	run := winejitstream.native_guard(argv, state + '/guarded', name + '.log',
		winejitstream.NativeLimits{timeout_ms: if state == base + '/wine-jit-stream-native-host-18' {
			120000
		} else { 60000 }, file_bytes: guard_limit,
			total_bytes: guard_limit, log_bytes: 256 * 1024, serial_bytes: 256 * 1024,
			min_free_kib: winejitstream.native_free_floor(false)})!
	steps[name] = Step{argv: argv, free_kib: free, run: run}
	os.write_file(state + '/steps.json', json2.encode(steps))!
	account(state, 0)!
	modules(state)!
	if !run.stopped || run.wait_status != expected || run.timed_out || run.size_limited || run.reason != '' {
		return error('width step failed; raw result retained: ' + name)
	}
	if output != '' {
		if (os.lstat(output)!).get_filetype() != .regular { return error('width output is not ordinary') }
		steps[name] = Step{argv: argv, free_kib: free, run: run,
			output_sha256: winejitstream.native_input_digest(output)!}
		os.write_file(state + '/steps.json', json2.encode(steps))!
	}
}

fn v_arguments(root string, output string, source string, production bool, target string) []string {
	mut argv := [compiler, '-nocache', '-cc', clang]
	if production { argv << '-prod' }
	if target != '' { argv << ['-os', 'linux', '-arch', target, '-d', 'no_backtrace', '-d', 'no_segfault_handler'] }
	argv << ['-gc', 'none', '-manualfree', '-path', '@vlib|' + root + '|'
		+ root + '/tests/hardware-platform|@vmodules', '-o', output, source]
	return argv
}

fn strict_object(source string, output string, arm bool) []string {
	target := if arm { 'aarch64' } else { 'x86_64' }
	sysroot := if arm { arm_sysroot } else { amd_sysroot }
	gcc := if arm { arm_gcc } else { amd_gcc }
	return [clang, '--no-default-config', '--target=' + target + '-linux-musl',
		'--sysroot=' + sysroot, '--gcc-install-dir=' + gcc, '-resource-dir=' + resource,
		// V string literals use char* for u8*. Keep incompatible-pointer ABI
		// errors while avoiding their unrelated signed-char warning flood.
		'-O1', '-Wno-pointer-sign', '-Werror=incompatible-pointer-types',
		// The qualified compiler's rune table drops const. Retain that warning
		// without demoting incompatible-width wait status pointers.
		'-Wno-error=incompatible-pointer-types-discards-qualifiers',
		'-D_GNU_SOURCE', '-fno-stack-protector',
		'-c', source, '-o', output]
}

fn c_body(text string, name string, return_type string) !string {
	mut remaining := text
	// Calls may occur before a function's definition. Include its return type
	// so an if-body following a call cannot be mistaken for the definition.
	needle := return_type + ' ' + name + '('
	for {
		at := remaining.index(needle) or { return error('C function missing: ' + name) }
		remaining = remaining[at + needle.len - 1..]
		brace := remaining.index('{') or { return error('C function body missing: ' + name) }
		semi := remaining.index(';') or { return error('C function terminator missing: ' + name) }
		if semi < brace { remaining = remaining[semi + 1..]; continue }
		mut depth := 0
		for index in brace .. remaining.len {
			if remaining[index] == `{` { depth++ }
			if remaining[index] == `}` {
				depth--
				if depth == 0 { return remaining[..index + 1] }
			}
		}
		return error('unterminated C function: ' + name)
	}
	return error('unreachable C body search')
}

fn c_anchors(path string, shared bool) ! {
	text := os.read_file(path)!
	if shared {
		raw := c_body(text, 'winejitstream__raw_waitpid', 'i32')!
		if !raw.starts_with('(i64 pid, i32* status, i64 options)')
			|| !raw.contains('return waitpid((i32)(pid), status, (i32)(options));')
			|| raw.contains('_cabi_out')
			|| !text.contains('struct winejitstream__WaitSlot {\n\tu32 before;\n\ti32 status;\n\tu32 after;') {
			return error('shared raw i32 C anchors missing')
		}
		for name in ['capture', 'native_guard'] {
			body := c_body(text, 'winejitstream__' + name,
				if name == 'capture' { '__v_result_winejitstream__Run' }
				else { '__v_result_winejitstream__NativeRun' })!
			if !body.contains('i32 status = (i32)(-1);') || !body.contains('i32 descendant_status = (i32)(0);')
				|| !body.contains('__raw_waitpid(pid, &status,')
				|| !body.contains('__raw_waitpid(-pid, &descendant_status,') {
				return error('supervisor i32 C storage/call missing: ' + name)
			}
		}
	} else {
		body := c_body(text, 'main', 'int')!
		if !body.starts_with('(int argc, char** argv)') { return error('probe actual C main signature missing') }
		if !body.contains('i32 status = (i32)(0);') || !body.contains('waitpid((i32)(pid), &status, 0)')
			|| body.contains('_cabi_out') { return error('probe raw i32 C anchors missing') }
	}
	encoded := overlay.replace('/', '_x2f_').replace('.', '_x2e_').replace('-', '_x2d_')
	if !text.contains(encoded + '_x2f_toolchain_x2f_vlib_x2f_os_x2f_os_x2e_v')
		|| text.contains('_x2f_v3_x2d_selfhost_x2d_performance_x2f_vlib') {
		return error('generated C selected overlay vlib prefix missing or baked prefix present')
	}
}

fn object_header(path string, arm bool) ! {
	mut file := os.open(path)!
	defer { file.close() }
	mut header := []u8{len: 20}
	machine := if arm { u8(183) } else { u8(62) }
	if file.read(mut header)! != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| header[16] != 1 || header[17] != 0 || header[18] != machine
		|| header[19] != 0 { return error('strict C output is not matching ELF64LE relocatable object') }
}

fn wrong_width_control(cfile string, state string, mut steps map[string]Step) ! {
	text := os.read_file(cfile)!
	body := c_body(text, 'winejitstream__capture', '__v_result_winejitstream__Run')!
	needle := 'i32 status = (i32)(-1);'
	if body.count(needle) != 1 { return error('wrong-width control needs exact actual capture storage') }
	wrong := body.replace_once(needle, 'i64 status = (i64)(-1);')
	source := state + '/guarded/shared-arm-width-refusal.c'
	output := state + '/guarded/shared-arm-width-refusal.o'
	winejitstream.static_require_absent(source)!
	winejitstream.static_require_absent(output)!
	os.write_file(source, text.replace_once(body, wrong))!
	invoke(strict_object(source, output, true), state, 'shared-arm-width-refusal.compile', '', 256, mut steps)!
	winejitstream.static_require_absent(output)!
	log := os.read_file(state + '/guarded/shared-arm-width-refusal.compile.log')!
	if !log.contains("error: incompatible pointer types passing 'i64 *'")
		|| !log.contains("to parameter of type 'i32 *'")
		|| !log.contains('[-Wincompatible-pointer-types]') {
		return error('actual capture wrong-width compiler refusal missing')
	}
}

fn qualify(root string, state string) ! {
	for name in ['guarded', 'scratch', 'steps.json', 'environment.json', 'width-receipt.json',
		'binding-before.json', 'binding-after.json', 'modules.json'] {
		winejitstream.static_require_absent(state + '/' + name)!
	}
	os.mkdir(state + '/guarded')!
	os.mkdir(state + '/scratch')!
	environment := selected_environment(state, state + '/scratch')!
	os.write_file(state + '/environment.json', json2.encode(environment))!
	os.write_file(state + '/modules.json', json2.encode({'path': state + '/modules',
		'kind': 'canonical ordinary empty directory', 'entry_count': '0',
		'rechecks': 'immediately before and after each guarded child and final receipt'}))!
	before := inputs(root)!
	os.write_file(state + '/binding-before.json', json2.encode(binding(before)))!
	mut steps := map[string]Step{}
	for name in ['controller', 'wait', 'wait-prod'] {
		output := state + '/guarded/' + name
		source := root + if name == 'controller' { '/tests/packages/wine-fork-jit-stream-native.v' }
			else { '/tools/packages/winejitstream/native_wait_test.v' }
		invoke(v_arguments(root, output, source, name != 'wait', ''), state, name + '.build', output, 0, mut steps)!
	}
	for name in ['wait', 'wait-prod', 'sentinel', 'sentinel-prod'] {
		sentinel := name.starts_with('sentinel')
		if sentinel { os.setenv('VINIX_WINE_WAIT_ASSERT_SENTINEL', '1', true) }
		else { os.unsetenv('VINIX_WINE_WAIT_ASSERT_SENTINEL') }
		argv := [state + '/guarded/' + if name.ends_with('-prod') { 'wait-prod' } else { 'wait' }]
		invoke(argv, state, name + '.run', '', if sentinel { 256 } else { 0 }, mut steps)!
		if sentinel && !os.read_file(state + '/guarded/' + name + '.run.log')!.contains('wine-native-wait intentional assertion sentinel') {
			return error('width assertion sentinel missing')
		}
	}
	os.unsetenv('VINIX_WINE_WAIT_ASSERT_SENTINEL')
	for name in ['shared-arm', 'probe-amd'] {
		shared := name == 'shared-arm'
		source := root + if shared { '/tools/packages/winejitstream/native_wait_test.v' }
			else { '/tests/packages/wine-fork-jit-stream-probe/main.v' }
		cfile := state + '/guarded/' + name + '.c'
		object := state + '/guarded/' + name + '.o'
		invoke(v_arguments(root, cfile, source, true, if shared { 'arm64' } else { 'x64' }),
			state, name + '.emit', cfile, 0, mut steps)!
		c_anchors(cfile, shared)!
		invoke(strict_object(cfile, object, shared), state, name + '.compile', object, 0, mut steps)!
		object_header(object, shared)!
		if shared { wrong_width_control(cfile, state, mut steps)! }
	}
	qualified_overlay()!
	after := inputs(root)!
	if before != after { return error('selected width sources/tools changed') }
	os.write_file(state + '/binding-after.json', json2.encode(binding(after)))!
	modules(state)!
	measured := account(state, 0)!
	receipt := json2.encode({'argv': json2.encode(os.args), 'environment': json2.encode(environment),
		'selected_binding': json2.encode(binding(after)), 'steps': json2.encode(steps),
		'inclusive_state_plus_2MiB_reserve_before_receipt': measured.str(),
		'scope': 'Host normal/production explicit controls and sentinel failures; host controller build; strict incompatible-pointer C object compilation of actual ARM shared unit/helper and AMD supplemental probe. Generated string signed-char pointer warnings are disabled; the known qualified-overlay rune const-pointer diagnostic remains a warning; incompatible-width pointer errors stay enabled and an actual capture i64 status mutation must fail under identical flags. No target diagnostic executable, staging, image or VM. Full selected overlay libraries, source and static C input trees re-enumerated/hashed before/after. Empty canonical VMODULES rechecked around every child. Bootstrap observed outside its own guard. Guarded subtree sampled at 16MiB/512 entries/256KiB logs, per-file hard 16MiB; all08/09/10/11/12/13/14/15/16 states together limited to32MiB with separate scratch counted without following links before/after every child. Only vanished child entries/subdirectories (ENOENT) are skipped during live scans; a missing selected scan root and other errors remain fatal. Trusted tools must not detach or write outside selected state. Host SDK/dynamic dependencies are not frozen; this does not claim a hermetic build or native workload qualification.'})
	account(state, u64(receipt.len))!
	os.write_file(state + '/width-receipt.json', receipt)!
	account(state, 0)!
	winejitstream.native_require_free(state, winejitstream.native_free_floor(false))!
	println('PASS host-only native wait-width and module controls')
}

// Rebuild only, without invoking the native target controller or changing
// host-16's sealed evidence. Caller marker selection has separate source review.
fn qualify_caller(root string, state string) ! {
	for name in ['guarded', 'scratch', 'steps.json', 'environment.json', 'caller-receipt.json',
		'binding-before.json', 'binding-after.json'] {
		winejitstream.static_require_absent(state + '/' + name)!
	}
	os.mkdir(state + '/guarded')!
	os.mkdir(state + '/scratch')!
	environment := selected_environment(state, state + '/scratch')!
	os.write_file(state + '/environment.json', json2.encode(environment))!
	before := inputs(root)!
	os.write_file(state + '/binding-before.json', json2.encode(binding(before)))!
	mut steps := map[string]Step{}
	output := state + '/guarded/controller'
	invoke(v_arguments(root, output, root + '/tests/packages/wine-fork-jit-stream-native.v', true, ''),
		state, 'controller.build', output, 0, mut steps)!
	qualified_overlay()!
	after := inputs(root)!
	if before != after { return error('caller followup selected sources/tools changed') }
	os.write_file(state + '/binding-after.json', json2.encode(binding(after)))!
	modules(state)!
	receipt := json2.encode({'selected_binding': json2.encode(binding(after)), 'steps': json2.encode(steps),
		'controller_source_sha256': winejitstream.native_input_digest(root + '/tests/packages/wine-fork-jit-stream-native.v')!,
		'inclusive_state_plus_2MiB_reserve_before_receipt': account(state, 0)!.str(),
		'scope': 'One guarded120-second host production controller rebuild after independent caller environment source review. No controller execution, target compilation, staging or VM. Qualified overlay and selected static inputs hashed before/after; private empty modules checked around child. Other width-host limits and non-hermetic host SDK/dynamic dependency scope unchanged. Historical host08-17 unchanged; host18 and caller seal join collective40MiB current state and inclusive128MiB profile.'})
	account(state, u64(receipt.len))!
	os.write_file(state + '/caller-receipt.json', receipt)!
	account(state, 0)!
	winejitstream.native_require_free(state, winejitstream.native_free_floor(false))!
	println('PASS host-only native caller environment rebuild')
}

fn observe() ! {
	bootstrap := os.args.len == 6 && os.args[1] == '--record-bootstrap'
	caller := os.args.len == 4 && os.args[1] == '--caller'
	if !bootstrap && !caller && (os.args.len != 4 || os.args[1] != '--run') {
		return error('usage: width-host --run ROOT FIXED_HOST_08_TO_16_STATE | --caller ROOT FIXED_HOST_18_STATE')
	}
	root := os.real_path(os.args[2])
	state := os.args[3]
	if state !in [base + '/wine-jit-stream-native-host-08', base + '/wine-jit-stream-native-host-09',
		base + '/wine-jit-stream-native-host-10', base + '/wine-jit-stream-native-host-11',
		base + '/wine-jit-stream-native-host-12', base + '/wine-jit-stream-native-host-13',
		base + '/wine-jit-stream-native-host-14', base + '/wine-jit-stream-native-host-15',
		base + '/wine-jit-stream-native-host-16', base + '/wine-jit-stream-native-host-18'] || os.real_path(state) != state
		|| (os.lstat(state)!).get_filetype() != .directory {
		return error('requires fixed ordinary width host state')
	}
	if !bootstrap && caller != (state == base + '/wine-jit-stream-native-host-18') {
		return error('caller followup requires its own fresh fixed namespace')
	}
	for path, digest in {
		compiler: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		overlay + '/bundle.json': '32d8bc5f46c953aeb5e9ad1ad63e182f10752fe270983943a22c040016617976'
		overlay + '/overlay-before.json': '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f'
		overlay + '/changes.json': '4941c055c018c321d7a4cc94c054b26ba6494bc6be7fa508d99a1bb10b7b2b21'
	} {
		if winejitstream.native_input_digest(path)! != digest { return error('selected overlay pin differs: ' + path) }
	}
	for path, text in {
		'tests/packages/wine-fork-jit-stream-width-host.v': $embed_file('wine-fork-jit-stream-width-host.v').to_string()
		'tools/packages/winejitstream/supervisor.v': $embed_file('../../tools/packages/winejitstream/supervisor.v').to_string()
		'tools/packages/winejitstream/native_guard.v': $embed_file('../../tools/packages/winejitstream/native_guard.v').to_string()
		'tools/packages/winejitstream/native_policy.v': $embed_file('../../tools/packages/winejitstream/native_policy.v').to_string()
	} {
		if os.read_file(root + '/' + path)! != text { return error('compiled width source differs: ' + path) }
	}
	qualified_overlay()!
	winejitstream.native_require_free(state, winejitstream.native_free_floor(true))!
	account(state, 0)!
	modules(state)!
	if bootstrap {
		winejitstream.static_require_absent(state + '/bootstrap.json')!
		if os.executable() != state + '/host' { return error('bootstrap executable differs') }
		mut environment := map[string]string{}
		for name in ['V', 'VEXE', 'VINIX_V_COMPILER', 'V_MACOS_V3_CALLER_VEXE',
			'V_MACOS_V3_CALLER_VEXE_PRESENT', 'V_MACOS_V3_CALLER_VCHILD_PRESENT',
			'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT', 'V_MACOS_V3_NO_FALLBACK',
			'V_C_ERROR_BUG_REPORT_DISABLED', 'TMPDIR', 'VTMP', 'VMODULES', 'LC_ALL', 'LANG', 'PATH',
			'VCHILD', 'V_MACOS_V3_CALLER_VCHILD', 'V_MACOS_V3_CALLER_NO_FALLBACK',
			'V_MACOS_V3_CHILD_VEXE_PRESENT', 'VFLAGS', 'CFLAGS', 'LDFLAGS', 'VTEST_ONLY_FN', 'V3CACHE',
			'CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH',
			'OBJCPLUS_INCLUDE_PATH', 'LIBRARY_PATH', 'COMPILER_PATH', 'GCC_EXEC_PREFIX',
			'CCC_OVERRIDE_OPTIONS', 'CLANG_CONFIG_FILE_SYSTEM_DIR', 'CLANG_CONFIG_FILE_USER_DIR',
			'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET'] {
			environment[name] = os.getenv_opt(name) or { '<unset>' }
		}
		for name in ['V', 'VEXE', 'VINIX_V_COMPILER', 'V_MACOS_V3_CALLER_VEXE'] {
			if os.getenv(name) != compiler { return error('bootstrap compiler selection differs') }
		}
		if os.getenv('V_MACOS_V3_CALLER_VEXE_PRESENT') != '1'
			|| os.getenv('V_MACOS_V3_CALLER_VCHILD_PRESENT') != '0'
			|| os.getenv('V_MACOS_V3_CALLER_NO_FALLBACK') != '1'
			|| os.getenv('V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT') != '1'
			|| os.getenv('V_MACOS_V3_NO_FALLBACK') != '1' { return error('bootstrap compiler markers differ') }
		os.write_file(state + '/bootstrap.json', json2.encode({
			'kind': 'Posthoc external completed bootstrap observation; bootstrap outside its own guard, 300-second observed stop policy.'
			'exit_code': os.args[4], 'observed_elapsed_ms': os.args[5],
			'argv': json2.encode(v_arguments(root, state + '/host', root + '/tests/packages/wine-fork-jit-stream-width-host.v', true, '')),
			'environment': json2.encode(environment),
			'compiler_sha256': winejitstream.native_input_digest(compiler)!,
			'observer_sha256': winejitstream.native_input_digest(os.executable())!,
			'log_sha256': winejitstream.native_input_digest(state + '/bootstrap.log')!,
			'selected_binding_after': json2.encode(binding(inputs(root)!))
		}))!
		account(state, 0)!
		return
	}
	if caller { qualify_caller(root, state)! } else { qualify(root, state)! }
}

fn main() { observe() or { eprintln(err); exit(1) } }
