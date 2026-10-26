// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed selection; no target compiler, linker invocation, staging or VM.
module main

import json2
import os
import tools.packages.winejitstream

const base = '/Users/alex/Library/Caches/vinix-codex/section14'
const destination = base + '/wine-jit-stream-native-inputs-01'
const cross = '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec'
const clang = '/opt/homebrew/opt/llvm/bin/clang'
const linker = '/opt/homebrew/bin/ld.lld'
const resource = '/opt/homebrew/opt/llvm/lib/clang/23'
const historical_bytes = u64(7638328)
const receipt_reserve = u64(2 * 1024 * 1024)

struct Preflight {
	plan           winejitstream.StaticPlan
	old_bytes      u64
	new_bytes      u64
	reserved_bytes u64
	required_bytes u64
	available_kib  u64
	tools          map[string]winejitstream.NativePin
	driver_environment string
	envelope_bytes u64
	fixed_after_bytes u64
	final_receipt_bytes u64
}

struct Driver {
	argv []string
	run  winejitstream.NativeRun
	log  string
	pin  string
	candidates []string
}

fn retained_bytes() !u64 {
	mut total := u64(0)
	for name in ['wine-jit-stream-native-host-01', 'wine-jit-stream-native-host-02',
		'wine-jit-stream-native-host-03', 'wine-jit-stream-native-host-04', 'wine-jit-stream-native-host-05',
		'wine-jit-stream-native-arm-01.launch-refusal.json', 'wine-jit-stream-native-arm-01.launch-02.json'] {
		total += winejitstream.static_state_bytes(base + '/' + name)!
	}
	if total != historical_bytes { return error('historical selected state changed: ' + total.str()) }
	return total
}

fn save_absent(path string, value string) ! {
	winejitstream.static_require_absent(path)!
	os.write_file(path, value)!
}

fn save_bounded(path string, value string, bound u64) ! {
	winejitstream.static_receipt_check(value, bound)!
	save_absent(path, value)!
}

fn composition_receipt(bytes u64, plan winejitstream.StaticPlan, tools map[string]winejitstream.NativePin) string {
	return json2.encode({
		'logical_bytes_before_final_receipt': bytes.str()
		'destination_bytes': plan.bytes.str()
		'destination': destination
		'driver_tools': json2.encode(tools)
		'scope': 'Selected static C inputs copied and dry-run paths observed; no compile/link/target qualification. Host OS, SDK and transitive host-tool libraries are not frozen.'
	})
}

fn record_drivers(state string, drivers []Driver) ! {
	value := json2.encode(drivers)
	current := retained_bytes()! + winejitstream.static_host_states_bytes(base)!
		+ winejitstream.static_state_bytes(destination)!
	// Conservatively count the replacement in full while the old record exists.
	winejitstream.static_budget(current, 0, u64(value.len))!
	os.write_file(state + '/drivers.json', value)!
}

fn main() {
	run() or { eprintln(err); exit(1) }
}

fn run() ! {
	if os.args.len != 3 || os.args[1] !in ['plan', 'compose'] {
		return error('usage: inputs plan|compose ABSOLUTE_HOST_STATE')
	}
	state := os.args[2]
	if !state.starts_with(base + '/wine-jit-stream-static-inputs-host-') || os.real_path(state) != state
		|| (os.lstat(state)!).get_filetype() != .directory { return error('invalid fixed host state') }
	available := winejitstream.native_require_free(state, 2 * 1024 * 1024)!
	plan := winejitstream.static_input_plan(cross + '/x86_64-linux-musl/include',
		cross + '/x86_64-linux-musl/lib', cross + '/lib/gcc/x86_64-linux-musl/14.2.0')!
	plan_json := json2.encode(plan)
	mut tool_pins := map[string]winejitstream.NativePin{}
	for path in [clang, linker] { winejitstream.native_input_add(path, mut tool_pins)! }
	winejitstream.native_input_tree(resource, mut tool_pins)!
	mut driver_environment := map[string]string{}
	for name in ['CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH',
		'OBJCPLUS_INCLUDE_PATH', 'LIBRARY_PATH', 'COMPILER_PATH', 'GCC_EXEC_PREFIX',
		'CCC_OVERRIDE_OPTIONS', 'CLANG_CONFIG_FILE_SYSTEM_DIR', 'CLANG_CONFIG_FILE_USER_DIR',
		'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET'] {
		driver_environment[name] = os.getenv_opt(name) or { '<unset>' }
		os.unsetenv(name)
	}
	environment_json := json2.encode({
		'inherited_then_unset': json2.encode(driver_environment)
		'selected': 'Listed variables unset; --no-default-config in both fixed argv; other host environment inherited.'
	})
	old := retained_bytes()!
	new := winejitstream.static_host_states_bytes(base)!
	prototype := Preflight{plan: plan, old_bytes: old, new_bytes: new,
		reserved_bytes: receipt_reserve, available_kib: available, tools: tool_pins,
		driver_environment: environment_json}
	// The inventory envelope includes these projection fields. Their decimal
	// values fit far below 4096 additional bytes; check actual encoding at write.
	envelope_bound := u64(json2.encode(prototype).len) + 4096
	final_bound := u64(composition_receipt(~u64(0), plan, tool_pins).len)
	fixed_after := 2 * u64(plan_json.len) + u64(environment_json.len) + final_bound
	before := envelope_bound * u64(if os.args[1] == 'plan' { 2 } else { 1 })
	required := old + new + plan.bytes + before + fixed_after + receipt_reserve
	preflight := Preflight{plan: plan, old_bytes: old, new_bytes: new,
		reserved_bytes: receipt_reserve, required_bytes: required, available_kib: available,
		tools: tool_pins, driver_environment: environment_json, envelope_bytes: envelope_bound,
		fixed_after_bytes: fixed_after, final_receipt_bytes: final_bound}
	winejitstream.static_receipt_projection(old + new, plan.bytes, before, fixed_after, receipt_reserve) or {
		winejitstream.static_budget(old + new, 0, 4096)!
		save_absent(state + '/preflight-refused.json', json2.encode({
			'selected_bytes': plan.bytes.str()
			'selected_files': plan.entries.len.str()
			'existing_bytes': (old + new).str()
			'reserved_bytes': receipt_reserve.str()
			'projected_before_bytes': before.str()
			'projected_fixed_after_bytes': fixed_after.str()
			'required_bytes': required.str()
			'reason': err.msg()
		}))!
		return error('preflight required ' + required.str() + ' bytes; destination was not created')
	}
	if os.args[1] == 'plan' {
		winejitstream.static_require_absent(destination)!
		save_bounded(state + '/preflight.json', json2.encode(preflight), envelope_bound)!
		println('selected=' + plan.bytes.str() + ' files=' + plan.entries.len.str()
			+ ' existing=' + (old + new).str() + ' reserved=' + receipt_reserve.str()
			+ ' projected_before=' + before.str() + ' projected_fixed_after=' + fixed_after.str()
			+ ' required=' + required.str())
		return
	}
	expected := json2.decode[Preflight](os.read_file(state + '/preflight.json')!)!
	if expected.plan != plan || expected.old_bytes != old || expected.tools != tool_pins
		|| expected.driver_environment != environment_json { return error('reviewed preflight inputs changed') }
	save_bounded(state + '/compose-before.json', json2.encode(preflight), envelope_bound)!
	// Recount the written envelope, retaining all future fixed receipts plus the
	// separate 2 MiB dynamic log/record reserve before any destination creation.
	winejitstream.static_receipt_projection(old + winejitstream.static_host_states_bytes(base)!,
		plan.bytes, 0, fixed_after, receipt_reserve)!
	winejitstream.static_input_copy(plan, destination,
		old + winejitstream.static_host_states_bytes(base)!, fixed_after + receipt_reserve, 1024 * 1024)!
	// Copy has just read back and matched the complete destination entry set,
	// ordinary types, sizes and hashes. Retain that full matched inventory.
	save_bounded(state + '/output-readback.json', plan_json, u64(plan_json.len))!
	save_bounded(state + '/source-after.json', json2.encode(
		winejitstream.static_input_plan(plan.headers, plan.library, plan.gcc)!), u64(plan_json.len))!
	save_bounded(state + '/driver-environment.json', environment_json, u64(environment_json.len))!
	// Resource dir itself is an expected Homebrew directory alias; its ordinary
	// canonical tree is inventoried. Executable literal links are bound above.
	mut drivers := []Driver{}
	for mode in ['-###', '-print-search-dirs'] {
		argv := [clang, '--no-default-config', '--target=x86_64-linux-musl', '--sysroot=' + destination + '/x86_64-linux-musl',
			'--gcc-install-dir=' + destination + '/lib/gcc/x86_64-linux-musl/14.2.0',
			'-resource-dir=' + resource, '-fuse-ld=' + linker, '-static', '-O2', '-w', '-D_GNU_SOURCE',
			'-fno-stack-protector', '-x', 'c', '/dev/null', '-lm', '-lpthread', '-o', state + '/unused', mode]
		name := if mode == '-###' { 'driver.recipe.log' } else { 'driver.search.log' }
		winejitstream.native_require_free(state, 2 * 1024 * 1024)!
		winejitstream.static_receipt_projection(old + winejitstream.static_host_states_bytes(base)!,
			winejitstream.static_state_bytes(destination)!, 0, final_bound, receipt_reserve)!
		result := winejitstream.native_guard(argv, state + '/guarded', name, winejitstream.NativeLimits{
			timeout_ms: 30000, file_bytes: 1024 * 1024, total_bytes: 20 * 1024 * 1024,
			log_bytes: 256 * 1024, serial_bytes: 256 * 1024, min_free_kib: 1024 * 1024
		})!
		log := state + '/guarded/' + name
		drivers << Driver{argv: argv, run: result, log: log,
			pin: winejitstream.native_input_digest(log)!}
		record_drivers(state, drivers)!
		if !result.stopped || result.wait_status != 0 || result.timed_out || result.size_limited || result.reason != '' {
			return error('guarded Clang driver failed; raw result retained')
		}
		text := os.read_file(log)!
		if text.contains(cross + '/') { return error('Clang recipe includes original cross installation') }
		if !text.contains(destination + '/lib/gcc/x86_64-linux-musl/14.2.0') {
			return error('Clang did not select relocated GCC')
		}
		if mode == '-###' {
			candidates := winejitstream.static_driver_recipe_check(text, destination, resource, cross)!
			drivers[drivers.len - 1] = Driver{argv: argv, run: result, log: log,
				pin: winejitstream.native_input_digest(log)!, candidates: candidates}
			record_drivers(state, drivers)!
		}
	}
	winejitstream.native_input_verify(tool_pins)!
	winejitstream.static_input_recheck(plan)!
	winejitstream.static_output_verify(plan, destination)!
	final_bytes := old + winejitstream.static_host_states_bytes(base)! + winejitstream.static_state_bytes(destination)!
	receipt := composition_receipt(final_bytes, plan, tool_pins)
	winejitstream.static_budget(final_bytes, 0, u64(receipt.len))!
	save_bounded(state + '/composition.json', receipt, final_bound)!
	winejitstream.static_budget(old + winejitstream.static_host_states_bytes(base)!,
		winejitstream.static_state_bytes(destination)!, 0)!
	winejitstream.native_require_free(state, 1024 * 1024)!
	println('static composition and guarded driver observations complete')
}
