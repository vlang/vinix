// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed source binding only; never compile, start a process owner or boot a guest.
module main

import crypto.sha256
import json2
import nativeguard
import os
import proof
import strconv

#include <errno.h>

const repository = '/Users/alex/code/vinix'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const source_root = state + '/source'
const suite = source_root + '/tests/software-hosted-x11'
const host = state + '/native-supervision-host-01'
const consumer = state + '/native-consumer-tools-01'
const compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const old_compiler = repository + '/build/package-https-runtime-work/toolchain/v'
const old_state = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a'
const old_source = repository + '/build/package-hosted-launch-options-guest-worktree'
const supplement = '/Users/alex/Library/Caches/vinix-codex/section14/package-hosted-launch-options-native-20261026'
const binding_output = consumer + '/current-supervisor-binding-01'
const module_map_sha = '710351295e1be60a49b75f84348493ee85cf1f0777991a8b457ac3f4b83201d4'
const overlay_sha = '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f'
const original_supervisor_sha = 'cd879181f0de1d4fee74a21e091e254bec590f68fef5d6d31d5aea8e37ede1ac'
const guard_sha = '5aa9cea7b338b914f7548a9a63a86ae6874dabb373350a5605f068fa7f2858ce'
const recovery_sha = '924cf415fc8b73661700394f830dd56a421dac1f08fc3ca00421a561e520a154'

struct OverlayPin { path string sha256 string }

struct BuildReceipt {
	actual_df_after string
	actual_df_before string
	exit_code string
	namespace_allocated_bytes_before_final_receipt string
	pins string
	scope string
	scratch string
}

struct ExitCode { exit_code int }

struct Barrier {
	pid int
	observed_pgid int
	parent_uid int
	parent_euid int
}

struct CleanupLog { cleanup string error string }

fn need(ok bool, message string) ! { if !ok { return error(message) } }

fn same_stat(before os.Stat, after os.Stat) bool {
	return before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.size == after.size
		&& before.nlink == after.nlink && before.mtime == after.mtime && before.ctime == after.ctime
}

fn digest(path string) !string {
	before := os.lstat(path)!
	need(before.mode & 0o170000 == 0o100000 && before.size <= u64(64) << 20,
		'binder requires an ordinary input at most64MiB: ' + path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	mut size := u64(0)
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		size += u64(n)
		need(size <= before.size, 'binder input grew')!
		hash.write(buffer[..n])!
	}
	need(size == before.size && same_stat(before, os.lstat(path)!), 'binder input changed: ' + path)!
	return hash.sum([]u8{}).hex()
}

fn text(path string) !string {
	before := digest(path)!
	value := os.read_file(path)!
	need(sha256.hexhash(value) == before && digest(path)! == before, 'binder text input changed')!
	return value
}

fn pin(path string, hash string, mut pins map[string]string) ! {
	need(os.is_abs_path(path) && !path.bytes().any(it < 32 || it == 127)
		&& hash.len == 64 && hash.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		&& digest(path)! == hash, 'binder input pin differs: ' + path)!
	if path in pins { need(pins[path] == hash, 'contradictory binder input pin')! }
	pins[path] = hash
}

fn remember(path string, mut pins map[string]string) ! { pin(path, digest(path)!, mut pins)! }

fn fresh(path string) ! {
	need(!os.exists(path) && !os.is_link(path), 'binder output must be new: ' + path)!
}

fn replace_exact(input string, before string, after string, count int) !string {
	need(before != after && input.count(before) == count, 'binder fixed replacement count differs: ' + before)!
	changed := input.replace(before, after)
	need(changed.replace(after, before) == input, 'binder replacement inverse differs: ' + before)!
	return changed
}

fn literal(value string) string {
	return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"
}

// A complete one-hunk unified replacement retains every original/generated line.
fn full_diff(before string, after string, name string) string {
	old_lines := before.trim_right('\n').split('\n')
	new_lines := after.trim_right('\n').split('\n')
	return '--- original/' + name + '\n+++ generated/' + name + '\n@@ -1,' + old_lines.len.str()
		+ ' +1,' + new_lines.len.str() + ' @@\n' + old_lines.map('-' + it).join('\n')
		+ '\n' + new_lines.map('+' + it).join('\n') + '\n'
}

fn identity(path string) !string {
	info := os.lstat(path)!
	return info.dev.str() + ':' + info.inode.str() + ':' + info.mode.str() + ':' + info.uid.str()
		+ ':' + info.gid.str() + ':' + info.nlink.str() + ':' + info.size.str() + ':'
		+ info.mtime.str() + ':' + info.ctime.str()
}

fn tool_versions() map[string]string {
	return {
		'check': 'check-03'
		'retain': 'retain-02'
		'evidence-check': 'evidence-check-01'
		'supervision-check': 'supervision-check-01'
	}
}

fn tool_root(stem string) string {
	return if stem == 'supervision-check' { host } else { consumer }
}

fn expected_evidence_wrapper() !string {
	old := text(state + '/original-run-evidence06.v')!
	need(sha256.hexhash(old) == 'e6a4b84faccddf673a79a89905b80ca0c837af9cf6058bb23f1a775bd6d8c5d9',
		'original evidence wrapper snapshot differs')!
	mut current := replace_exact(old, old_state, state, 1)!
	current = replace_exact(current, old_source, source_root, 1)!
	current = replace_exact(current, old_compiler, compiler, 1)!
	current = replace_exact(current, "state + '/tools-06/retain'", "state + '/native-supervision-host-01/retain-01'", 1)!
	return replace_exact(current, "state + '/tools-06/evidence-check'", "state + '/native-supervision-host-01/evidence-check-01'", 1)
}

fn final_evidence_wrapper() !string {
	mut value := expected_evidence_wrapper()!
	value = replace_exact(value, "state + '/native-supervision-host-01/retain-01'",
		"state + '/native-consumer-tools-01/retain-02'", 1)!
	value = replace_exact(value, "state + '/native-supervision-host-01/evidence-check-01'",
		"state + '/native-consumer-tools-01/evidence-check-01'", 1)!
	return value
}

fn wrapper_inputs(mut inputs map[string]string) !(string, string) {
	prepared_path := state + '/compact-prepared.json'
	prepared := json2.decode[map[string]string](text(prepared_path)!, strict: true)!
	native_path := suite + '/run-native06.v'
	evidence_path := suite + '/run-evidence06.v'
	native_before := text(native_path)!
	evidence_before := text(evidence_path)!
	need(prepared['outcome'] == 'PREPARED' && sha256.hexhash(native_before) == prepared['runner']
		&& prepared['runner'] == '694154cce9dd8cb216a79109154cafc81fdeea8726053ae39aa9b5f67f2889a0',
		'compact prepared native wrapper differs')!
	need(evidence_before == expected_evidence_wrapper()!, 'prepared evidence wrapper differs')!
	need(os.lstat(native_path)!.nlink == 1 && os.lstat(evidence_path)!.nlink == 1,
		'wrapper sources must be independent ordinary copies')!
	for path in [prepared_path, state + '/original-run-evidence06.v', native_path, evidence_path] {
		remember(path, mut inputs)!
	}
	return native_before, evidence_before
}

fn qualified_modules(path string, mut pins map[string]string) ! {
	pin(path + '/modules-before.json', module_map_sha, mut pins)!
	pin(path + '/modules-after.json', module_map_sha, mut pins)!
	expected := json2.decode[map[string]string](text(path + '/modules-before.json')!, strict: true)!
	mut actual := map[string]string{}
	for name in ['proof', 'launchproof', 'optionsfixture', 'compactproof', 'compactui'] {
		root := suite + '/' + name
		need(os.real_path(root) == root && os.lstat(root)!.mode & 0o170000 == 0o040000,
			'qualified module requires an ordinary canonical root')!
		// Reuse the historical complete tree reader; do not add an inventory owner.
		for relative, hash in proof.tree(root, true)! {
			need(relative.ends_with('.v') && hash.len == 64, 'unexpected module source or alias')!
			actual[root + '/' + relative] = hash
		}
	}
	need(actual == expected, 'qualified complete fixture module map differs')!
	for input, hash in actual { pin(input, hash, mut pins)! }
}

fn qualified_compiler(mut pins map[string]string) ! {
	manifest := os.dir(os.dir(compiler)) + '/overlay-before.json'
	pin(manifest, overlay_sha, mut pins)!
	mut expected := map[string]string{}
	for item in json2.decode[[]OverlayPin](text(manifest)!, strict: true)! {
		need(item.path !in expected, 'duplicate qualified overlay entry')!
		expected[item.path] = item.sha256
	}
	need(os.real_path(os.dir(compiler)) == os.dir(compiler)
		&& os.lstat(os.dir(compiler))!.mode & 0o170000 == 0o040000
		&& proof.tree(os.dir(compiler), false)! == expected, 'complete qualified compiler overlay differs')!
	pin(compiler, 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5', mut pins)!
}

fn frozen_inputs(mut pins map[string]string) ! {
	for path, hash in {
		state + '/compact-stage-projection-02.json': '67ae49eeb2f43ffdc16cbd093a43c3dd93e7a8c4933854913c0e7464ececb1e6'
		state + '/compact-frozen-tools-01.json': '14a1d04a2288ff548171b8428cabe92582a8ceefc7ea648e25f07f5ef00da579'
		state + '/compact-import-bootstrap-01/compact-projection-02': 'd5b6902bd3b96051c15b805fbaf10d0c855ea9323e3b16a8fff26fd17d802b78'
		state + '/compact-import-bootstrap-01/projection-source-02/compact-projection.v': '372bc38b3fd3dd52995bf0434840eed16d7e02341570f10ffa504ed3e607c857'
	} { pin(path, hash, mut pins)! }
	// These production controls qualified guard/provenance logic only. Their
	// synthetic callbacks do not establish an import, full audit or native run.
	for path, hash in {
		consumer + '/compactproof-check-02-controls.run.json': '656880024d84c5a496a12293351c56676e20d6698c7c3e4c09b1f5fc33c9ac6e'
		consumer + '/compactproof-check-02-controls/result.json': '985d5a811ded63a22ea45a6dccb60ff748e31b460fac0f6db349dcaa47c20449'
		consumer + '/compactproof-check-02-controls.monitor/result.json': '45110b70f4ed10f2d6de1a83697eb90b710b042c55c0d337add56df6031dd0e2'
		consumer + '/compactproof-check-02-controls.monitor/modules-before.json': module_map_sha
		consumer + '/compactproof-check-02-controls.monitor/modules-after.json': module_map_sha
	} { pin(path, hash, mut pins)! }
}

// Explicitly reviewed current host bytes; never accept an arbitrary current
// digest. All other original global tool pins remain unchanged.
fn rebound_tools() map[string]string {
	return {
		'/bin/df': '84b985a1e447eb674bd1e8b2209dac5ca2a6803cad6cd0a9543bbd9e6b4e28bd'
		'/bin/cp': 'a589d802b1c0dcafb205223774d7652a1d0a08b835a2dfbcf72692bfbe412880'
		'/usr/bin/tar': '640f174362e1c0bd27450d0cbf77583d1811f8011a6de54de81c3118b7be0863'
	}
}

fn rebind_tool_pins(original string) !string {
	old := {
		'/bin/df': 'f57b43da7cc2f701db5ebad1b78ae9a30f10f9a102b2a83b0707031e69367e8a'
		'/bin/cp': '07cdcfe6a6474d9abac66f0b1959e2e9e4877bf4629e2e400249a3e7641b09f9'
		'/usr/bin/tar': '9ab7f0793033dc9dc4809d83d695118801bd687cbacda59a0cbbf151ba25dc2b'
	}
	mut result := original
	for path, wanted in rebound_tools() {
		result = replace_exact(result, '\t\t' + literal(path) + ': ' + literal(old[path]),
			'\t\t' + literal(path) + ': ' + literal(wanted), 1)!
	}
	return result
}

fn expected_build_argv(stem string, version string) []string {
	return [compiler, '-prod', '-enable-globals', '-nocache', '-keepc', '-cc',
		'/opt/homebrew/opt/llvm/bin/clang', '-cflags',
		'-Werror=incompatible-pointer-types -Wno-error=incompatible-pointer-types-discards-qualifiers',
		'-path', '@vlib|' + source_root + '|' + source_root + '/tools|' + source_root + '/build-support|'
		+ suite + '|' + suite + '/diagnostics|' + source_root + '/tests/hardware-platform|'
		+ source_root + '/tools/accounts|@vmodules', '-o', tool_root(stem) + '/' + version, suite + '/' + stem + '.v']
}

fn qualified_build(stem string, version string, mut pins map[string]string) ! {
	root := tool_root(stem) + '/' + version
	receipt_path := root + '.build.json'
	receipt := json2.decode[BuildReceipt](text(receipt_path)!, strict: true)!
	need(receipt.exit_code == '0' && receipt.scratch == tool_root(stem) + '/scratch', 'fresh tool build failed or scratch differs')!
	need(nativeguard.parse_df(receipt.actual_df_before)! >= u64(550) << 20
		&& nativeguard.parse_df(receipt.actual_df_after)! >= u64(550) << 20
		&& strconv.parse_uint(receipt.namespace_allocated_bytes_before_final_receipt, 10, 64)! <= u64(40) << 20,
		'actual fresh build budget receipt differs')!
	need(json2.decode[ExitCode](text(root + '.exit.json')!, strict: true)!.exit_code == 0,
		'fresh tool actual exit differs')!
	need(json2.decode[[]string](text(root + '.argv.json')!, strict: true)! == expected_build_argv(stem, version),
		'fresh tool literal build argv differs')!
	result := json2.decode[nativeguard.Result](text(root + '.monitor/result.json')!, strict: true)!
	need(result.reason == '' && result.group_observed && result.cleanup.exit_code == 0
		&& result.cleanup.reaped && result.cleanup.group_empty && result.cleanup.final_wait == -1
		&& result.cleanup.final_errno == C.ECHILD, 'fresh tool build cleanup differs')!
	barrier := json2.decode[Barrier](text(root + '.log.barrier.json')!, strict: true)!
	cleanup := json2.decode[CleanupLog](text(root + '.log.cleanup.json')!, strict: true)!
	need(barrier.pid > 1 && barrier.pid == barrier.observed_pgid && barrier.pid == result.cleanup.pid
		&& cleanup.error == '' && json2.decode[nativeguard.Cleanup](cleanup.cleanup, strict: true)! == result.cleanup,
		'fresh build barrier/cleanup receipts disagree')!
	build_pins := json2.decode[map[string]string](receipt.pins, strict: true)!
	for path in [compiler, suite + '/' + stem + '.v', root, root + '.argv.json', root + '.exit.json',
		root + '.log', suite + '/nativeguard/guard.v', suite + '/diagnostics/recoveryguard/recoveryguard.v'] {
		need(path in build_pins, 'required fresh build pin missing: ' + path)!
	}
	for path, hash in build_pins {
		if stem == 'supervision-check' && path == suite + '/build-supervision.v' {
			// The qualified runner predates the mutable builder adaptation. Its
			// original receipt and exact independently retained as-run bytes remain.
			need(hash == '219445d01032857858f5675d7221539955b5e506e08f5f4309cdaab9620f9d91',
				'original supervision runner builder source differs')!
			pin(state + '/compact-before-build-supervision.v', hash, mut pins)!
		} else { pin(path, hash, mut pins)! }
	}
	for path in [receipt_path, root + '.monitor/result.json', root + '.log.barrier.json', root + '.log.cleanup.json'] {
		remember(path, mut pins)!
	}
	if stem == 'supervision-check' {
		pin(suite + '/supervision-check.v', '12918b84ac3c095615379f28bb73f808c696e541b00d334368a02ef8a48fa6e8', mut pins)!
		pin(root, '50f096c4a5bc6ab5be9a9cb8ebcec074c66ea1621db71f047ea7f34d7a3db36e', mut pins)!
	} else { qualified_modules(root + '.monitor', mut pins)! }
	mut c_names := os.ls(tool_root(stem) + '/scratch')!
	c_names = c_names.filter(it.starts_with(version + '.') && it.ends_with('.tmp.c'))
	need(c_names.len == 1, 'fresh tool requires its one retained generated C file')!
	remember(tool_root(stem) + '/scratch/' + c_names[0], mut pins)!
}

fn wrapper_branch(original string, name string) !string {
	header := 'module main\n\nimport os\nimport json2\nimport crypto.sha256\n\n'
	tail := '\nfn main() { run() or { eprintln(err); exit(1) } }\n'
	need(original.starts_with(header) && original.ends_with(tail)
		&& original.count(header) == 1 && original.count(tail) == 1,
		'original wrapper header/main differs')!
	body := original[header.len..original.len - tail.len]
	return replace_exact(body, 'fn run() ! {\n', 'fn ' + name + '() ! {\n', 1)
}

// The three existing argv counts are disjoint. Invalid arities never choose a
// branch; the original supervisor mode guard and native architecture guard stay.
fn dispatch_branch(arity int) string {
	return match arity { 2 { 'supervisor_run' } 3 { 'evidence_run' } 4 { 'native_run' } else { '' } }
}

// BEGIN fixed combined wrapper preflight
fn wrapper_mode(arguments []string) string {
	for arch in ['x86_64', 'aarch64'] {
		native := state + '/native-' + arch + '-compact-01'
		if arguments == [arch, supplement + '/restored-stage-' + arch + '/root', native] {
			return 'native_run'
		}
		if arguments == [native, state + '/controls-' + arch + '-compact-01'] {
			return 'evidence_run'
		}
	}
	return ''
}
// END fixed combined wrapper preflight

fn wrapper_preflight_source() !string {
	// Execute the same function body that is copied into the combined source.
	for arch in ['x86_64', 'aarch64'] {
		stage := supplement + '/restored-stage-' + arch + '/root'
		native := state + '/native-' + arch + '-compact-01'
		controls := state + '/controls-' + arch + '-compact-01'
		other := if arch == 'x86_64' { 'aarch64' } else { 'x86_64' }
		need(wrapper_mode([arch, stage, native]) == 'native_run'
			&& wrapper_mode([native, controls]) == 'evidence_run', 'fixed wrapper vector refused')!
		for bad in [
			[]string{}, ['--native-' + arch], [arch, stage], [arch, stage, native, 'extra'],
			['other', stage, native], [other, stage, native], [arch, stage + '/else', native],
			[arch, 'relative', native], [arch, stage, native + '/else'], [arch, stage, 'relative'],
			[native, controls, 'extra'], [native + '/else', controls], [native, controls + '/else'],
			['relative', controls], [native, 'relative'],
			[native, state + '/controls-' + other + '-compact-01'],
		] {
			need(wrapper_mode(bad) == '', 'nonfixed wrapper vector accepted')!
		}
	}
	value := $embed_file('bind-current-options.v').to_string()
	begin := '// BEGIN ' + 'fixed combined wrapper preflight\n'
	end := '// END ' + 'fixed combined wrapper preflight\n'
	need(value.count(begin) == 1 && value.count(end) == 1, 'preflight source markers differ')!
	first := value.index(begin) or { return error('missing preflight source start') }
	last := value.index(end) or { return error('missing preflight source end') }
	need(first < last, 'preflight source marker order differs')!
	return value[first + begin.len..last]
}

fn dispatch_source() !string {
	for arity in -1 .. 8 {
		expected := if arity == 2 { 'supervisor_run' } else if arity == 3 { 'evidence_run' }
			else if arity == 4 { 'native_run' } else { '' }
		need(dispatch_branch(arity) == expected, 'ambiguous argc dispatch')!
	}
	mut source := '\n' + wrapper_preflight_source()! + '\nfn dispatch() ! {\n\tmatch os.args.len {\n'
	for arity in [2, 3, 4] {
		// Wrapper invocations inherit the frozen supervisor bindings, including
		// the current self executable. The fixed two-argument refusal still runs
		// before binding, just as the original supervisor did.
		action := if arity == 2 { dispatch_branch(arity) + '()!' }
			else { "if wrapper_mode(os.args[1..]) != '" + dispatch_branch(arity)
				+ "' { return error('requires exact fixed wrapper vector; arbitrary commands refused') }; "
				+ '_ := bindings()!; ' + dispatch_branch(arity) + '()!' }
		source += '\t\t' + arity.str() + ' { ' + action + ' }\n'
	}
	source += "\t\telse { return error('requires exact supervisor/native/evidence argc; arbitrary commands refused') }\n"
		+ '\t}\n}\n\nfn main() { dispatch() or { eprintln(recoveryguard.bounded_message(err.msg())); exit(1) } }\n'
	return source
}

fn coherent_environment() string {
	return "\t\t'V': compiler\n\t\t'VEXE': compiler\n\t\t'V_MACOS_V3_CALLER_VEXE': compiler\n"
		+ "\t\t'V_MACOS_V3_CALLER_VEXE_PRESENT': '1'\n\t\t'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'\n"
		+ "\t\t'V_MACOS_V3_NO_FALLBACK': '1'\n\t\t'V_MACOS_V3_CALLER_NO_FALLBACK': '1'\n"
		+ "\t\t'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1'\n\t\t'V_C_ERROR_BUG_REPORT_DISABLED': '1'\n"
		+ "\t\t'V_SKIP_VVMRC': '1'\n\t\t'VMODULES': guard + '/modules'\n\t\t'VTMP': guard + '/scratch'\n"
		+ "\t\t'V3CACHE': guard + '/cache'\n\t\t'XDG_CACHE_HOME': guard + '/cache'\n"
		+ "\t\t'SDKROOT': '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk'\n"
		+ "\t\t'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'\n"
}

fn generate(original string, native string, evidence string, inputs map[string]string) !string {
	need(sha256.hexhash(original) == original_supervisor_sha, 'fresh supervisor template differs')!
	mut result := replace_exact(original, "const state = '" + old_state + "'", "const state = '" + state + "'", 1)!
	result = replace_exact(result, "const source_root = '" + old_source + "'", "const source_root = '" + source_root + "'", 1)!
	result = replace_exact(result, "const compiler = '" + old_compiler + "'", "const compiler = '" + compiler + "'", 1)!
	result = rebind_tool_pins(result)!
	for name in ['process_nix.c.v', 'execute_capture_nix.h'] {
		result = replace_exact(result, old_compiler.all_before_last('/') + '/vlib/os/' + name,
			os.dir(compiler) + '/vlib/os/' + name, 1)!
	}
	start := result.index('\tmut expected := {\n') or { return error('missing original bindings map') }
	end_relative := result[start..].index('\n\t}\n\tfor path, data in {') or { return error('missing original bindings map end') }
	end := start + end_relative + '\n\t}'.len
	old_map := result[start..end]
	mut kept := []string{}
	mut removed := 0
	for line in old_map.split('\n') {
		if line.trim_space().starts_with("state + '/") || line.trim_space().starts_with("suite + '/") {
			removed++
		} else { kept << line }
	}
	need(removed == 11 && kept.last() == '\t}', 'original local binding selection differs')!
	kept.delete_last()
	mut paths := inputs.keys()
	paths.sort()
	rebound := rebound_tools()
	for path in paths {
		if path in rebound {
			// The original global map entry has already been replaced exactly.
			// Inputs pin the same reviewed bytes without emitting a duplicate key.
			need(inputs[path] == rebound[path], 'reviewed host tool pin differs')!
			continue
		}
		if path == compiler {
			need(inputs[path] == 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5',
				'original global compiler pin differs')!
			continue
		}
		kept << '\t\t' + literal(path) + ': ' + literal(inputs[path])
	}
	kept << '\t}'
	new_map := kept.join('\n')
	result = replace_exact(result, old_map, new_map, 1)!
	result = replace_exact(result, "state + '/run-evidence06'", 'os.executable()', 1)!
	result = replace_exact(result, "state + '/run-native06'", 'os.executable()', 1)!
	result = replace_exact(result, "'-06'", "'-compact-01'", 2)!
	result = replace_exact(result, 'native06-supervision-', 'compact01-supervision-', 6)!
	result = replace_exact(result, '} { expected[path] = sha256.hexhash(data) }',
		"} {\n\t\tembedded := sha256.hexhash(data)\n\t\tif path in expected && expected[path] != embedded { return error('compiled source differs from qualified binding: ' + path) }\n\t\texpected[path] = embedded\n\t}", 1)!
	result = replace_exact(result, "\t\t'TMPDIR': guard + '/scratch'\n",
		"\t\t'TMPDIR': guard + '/scratch'\n" + coherent_environment(), 1)!
	result = replace_exact(result, "\tos.mkdir(guard + '/scratch')!\n",
		"\tos.mkdir(guard + '/scratch')!\n\tos.mkdir(guard + '/modules')!\n\tos.mkdir(guard + '/cache')!\n", 1)!
	result = replace_exact(result, 'requires one exact native06 architecture/mode; arbitrary commands refused',
		'requires one exact compact01 architecture/mode; arbitrary commands refused', 1)!
	result = replace_exact(result, 'native06 supervised attempt refused;', 'compact01 supervised attempt refused;', 1)!
	result = replace_exact(result, 'PASS bounded native06 host supervisor:', 'PASS bounded compact01 host supervisor:', 1)!
	result = replace_exact(result, 'fn run() ! {\n', 'fn supervisor_run() ! {\n', 1)!
	result = replace_exact(result,
		"\nfn main() { run() or { eprintln(recoveryguard.bounded_message(err.msg())); exit(1) } }\n", '', 1)!
	result = replace_exact(result, 'fn bindings() !map[string]string {\n',
		'fn bindings() !map[string]string {\n'
		+ "\tif os.executable() != '" + consumer + "/supervise-01' { return error('combined executable path differs') }\n", 1)!
	native_current := replace_exact(native, "state + '/native-supervision-host-01/check-01'",
		"state + '/native-consumer-tools-01/check-03'", 1)!
	need(evidence == expected_evidence_wrapper()!, 'unchanged evidence input differs')!
	owner_source := result
	result += '\n' + wrapper_branch(native_current, 'native_run')! + '\n'
		+ wrapper_branch(final_evidence_wrapper()!, 'evidence_run')! + dispatch_source()!
	// Literal semantic guards preserve the original resource/owner protocol.
	for required in ["namespace_cap := u64(1) << 30", "receipt_reserve := u64(8) << 20",
		"start_bytes: u64(2202010) * 1024", "floor_bytes: u64(1) << 30",
		"wall_ms: if controls { 20 * 60 * 1000 } else { 30 * 60 * 1000 }",
		"nativeguard.supervise(args, source_root, state, paths", "supplement + '/restored-stage-' + arch + '/root'"] {
		need(owner_source.count(required) == original.count(required) && original.count(required) > 0,
			'original supervisor behavior guard differs: ' + required)!
	}
	for required in ["expected[os.executable()] = sha(os.executable())!",
		"suite + '/supervise.v': \$embed_file('supervise.v').to_string()",
		"args := if controls { [os.executable(), native, output] }",
		"else { [os.executable(), arch, supplement + '/restored-stage-' + arch + '/root', output] }"] {
		need(result.count(required) == 1, 'combined source/self/argv binding differs: ' + required)!
	}
	need(result.count('fn main()') == 1 && result.count('fn dispatch()') == 1
		&& !result.contains("state + '/run-native06'") && !result.contains("state + '/run-evidence06'")
		&& !result.contains("state + '/native-supervision-host-01/check-")
		&& !result.contains("state + '/native-supervision-host-01/retain-")
		&& !result.contains("state + '/native-supervision-host-01/evidence-check-"),
		'combined dispatch or stale consumer executable differs')!
	return result
}

fn bind_supervisor() ! {
	fresh(binding_output)!
	for arch in ['x86_64', 'aarch64'] {
		for stem in ['native-' + arch + '-compact-01', 'controls-' + arch + '-compact-01',
			'compact01-supervision-' + arch + '-native', 'compact01-supervision-' + arch + '-controls'] {
			for suffix in ['', '.argv.json', '.environment.json', '.runner.json', '.controller.log',
				'.controller-exit.json', '.log', '.exit.json', '.admission-df.log',
				'.admission-df.log.barrier.json', '.admission-df.log.cleanup.json', '.admission-df.log.barrier-cleanup.json'] {
				fresh(state + '/' + stem + suffix)!
			}
		}
	}
	for suffix in ['', '.argv.json', '.exit.json', '.log', '.build.json', '.monitor'] { fresh(consumer + '/supervise-01' + suffix)! }
	supervisor_path := suite + '/supervise.v'
	original := text(supervisor_path)!
	need(sha256.hexhash(original) == original_supervisor_sha && os.lstat(supervisor_path)!.nlink == 1,
		'fresh independent original supervisor source required')!
	mut pins := map[string]string{}
	for path in [@FILE, os.executable()] { remember(path, mut pins)! }
	native, evidence := wrapper_inputs(mut pins)!
	frozen_inputs(mut pins)!
	for path, wanted in rebound_tools() { pin(path, wanted, mut pins)! }
	qualified_compiler(mut pins)!
	pin(suite + '/nativeguard/guard.v', guard_sha, mut pins)!
	pin(suite + '/diagnostics/recoveryguard/recoveryguard.v', recovery_sha, mut pins)!
	for path in [source_root + '/tests/hardware-platform/hwhost/process.v',
		source_root + '/tests/hardware-platform/hwhost/host.v',
		source_root + '/tests/hardware-platform/hwhost/boot.v',
		source_root + '/tests/hardware-platform/plainiso/iso.v',
		os.dir(compiler) + '/vlib/os/process_nix.c.v',
		os.dir(compiler) + '/vlib/os/execute_capture_nix.h'] { remember(path, mut pins)! }
	for stem, version in tool_versions() { qualified_build(stem, version, mut pins)! }
	// The unchanged consumer --check builder looks up both executables in its
	// own root. This copy is admitted through the complete original runner build
	// above; it needs no invented second build receipt and never writes old_tools.
	pin(consumer + '/supervision-check-01',
		'50f096c4a5bc6ab5be9a9cb8ebcec074c66ea1621db71f047ea7f34d7a3db36e', mut pins)!
	// No final13-control result is needed here: it can only exist after the
	// generated supervisor is compiled. That independent gate precedes guest use.
	need(json2.encode(pins).len <= 24000, 'actual supervisor input pins exceed24KiB')!
	os.mkdir(binding_output, mode: 0o700)!
	os.write_file(binding_output + '/original-run-native06.v', native)!
	os.write_file(binding_output + '/original-run-evidence06.v', evidence)!
	os.write_file(binding_output + '/original-supervise.v', original)!
	for leaf in ['original-run-native06.v', 'original-run-evidence06.v', 'original-supervise.v'] {
		remember(binding_output + '/' + leaf, mut pins)!
	}
	os.write_file(binding_output + '/identities-before.json', json2.encode({
		suite + '/run-native06.v': identity(suite + '/run-native06.v')!,
		suite + '/run-evidence06.v': identity(suite + '/run-evidence06.v')!,
		supervisor_path: identity(supervisor_path)!
	}) + '\n')!
	os.write_file(binding_output + '/actual-inputs.json', json2.encode(pins) + '\n')!
	remember(binding_output + '/actual-inputs.json', mut pins)!
	generated := generate(original, native, evidence, pins)!
	os.write_file(binding_output + '/generated-supervise.v', generated)!
	os.write_file(binding_output + '/supervisor.diff', full_diff(original, generated, 'supervise.v'))!
	for path, hash in pins { need(digest(path)! == hash, 'binding input changed during generation')! }
	os.write_file(supervisor_path, generated)!
	need(text(supervisor_path)! == generated, 'written supervisor source differs')!
	need(text(suite + '/run-native06.v')! == native && text(suite + '/run-evidence06.v')! == evidence,
		'original wrapper source changed')!
	os.write_file(binding_output + '/identities-after.json', json2.encode({
		suite + '/run-native06.v': identity(suite + '/run-native06.v')!,
		suite + '/run-evidence06.v': identity(suite + '/run-evidence06.v')!,
		supervisor_path: identity(supervisor_path)!
	}) + '\n')!
	os.write_file(binding_output + '/result.json', json2.encode({
		'outcome': 'BOUND_SOURCE', 'source': supervisor_path,
		'original_sha256': sha256.hexhash(original), 'generated_sha256': sha256.hexhash(generated),
		'inputs_sha256': digest(binding_output + '/actual-inputs.json')!,
		'generator_sha256': digest(@FILE)!, 'versions': json2.encode(tool_versions()),
		'supervision_runner_copy': consumer + '/supervision-check-01',
		'scope': 'Actual completed tool/build/module/cleanup pins; exact original supervisor and wrapper branch derivation into one source. Self executable hash is captured by the original runtime binding, not a circular preknown hash. No compile, final13 controls, target or guest.'
	}) + '\n')!
	println('BOUND current compact supervisor source; final compile and13 controls still required')
}

fn main() {
	$if prod {} $else { eprintln('binder requires production embedded source binding'); exit(2) }
	need(os.args.len == 2 && os.args[1] == '--bind', 'requires exact --bind') or { eprintln(err); exit(2) }
	need(digest(@FILE)! == sha256.hexhash($embed_file('bind-current-options.v').to_string()), 'binder source changed') or { eprintln(err); exit(1) }
	for path in [consumer, suite] {
		need(os.real_path(path) == path && os.lstat(path)!.mode & 0o170000 == 0o040000,
			'binder requires an existing ordinary canonical output/source root') or { eprintln(err); exit(1) }
	}
	bind_supervisor() or { eprintln(err); exit(1) }
}
