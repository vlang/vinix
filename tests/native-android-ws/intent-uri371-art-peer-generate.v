// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the exact qualified369 semantic oracle in the successor peer reader.
module main

import os

fn once(source string, before string, after string) string {
	assert source.count(before) == 1, before
	return source.replace_once(before, after)
}

fn main() {
	assert os.args.len == 1
	dir := os.dir(@FILE)
	output := dir + '/intent-uri371-art-peer-readback.v'
	assert !os.is_link(output)
	mut source := os.read_file(dir + '/intent-uri369-art-peer-readback.v')!
	source = once(source, "const root = state + '/intent-uri369-fixture-2026-10-26'", "const root = state + '/intent-uri371-fixture-2026-10-26'\nconst origin = state + '/intent-uri369-fixture-2026-10-26'\nconst snapshot = state + '/intent-uri369-failure-readback-b-2026-10-26'\nconst original_inventory = '6e2288faa9a4eb14f3a5495a751b1298d1e179e181eba247627880748181da4b'\nconst original_receipt = '0f91fd7499563acb0cb863b04e078d2390210986d53e8888f9c1f7558a706e96'\nconst source_pin = 'PENDING_SOURCE'\nconst shared_pin = 'PENDING_SHARED'\nconst build_pin = 'PENDING_BUILD'\nconst framework_pin = 'PENDING_FRAMEWORK'\nconst bootstrap_pin = 'PENDING_BOOTSTRAP'\nconst action_source_pin = 'PENDING_ACTION_SOURCE'\nconst action_binary_pin = 'PENDING_ACTION_BINARY'")
	source = once(source, "const output = state + '/intent-uri369-art-peer-readback-2026-10-26'", "const output = state + '/intent-uri371-art-peer-readback-2026-10-26'")
	source = once(source, "const runner_pin = '3229369e8b908233b6d6dcd0a8b7aa2d45697c734de3e11ebe38c84082e10d33'", "const runner_pin = 'PENDING_RUNNER'\nconst original_runner = '3229369e8b908233b6d6dcd0a8b7aa2d45697c734de3e11ebe38c84082e10d33'")
	source = once(source, "const new_jar = '74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b'", "const new_jar = 'PENDING_JAR'\nconst failed_jar = '74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b'")
	body := os.read_file(dir + '/intent-uri371-art-peer-body.v')!.all_after('\nmodule main\n')
	start := source.index('\nfn inputs(') or { panic('missing inputs') }
	end := source.index('\nfn require(') or { panic('missing require') }
	source = source[..start] + '\n' + body + source[end..]
	start_runtime := source.last_index('\nfn runtime(') or { panic('missing runtime') }
	end_runtime := source.index('\nfn main(') or { panic('missing main') }
	source = source[..start_runtime] + source[end_runtime..]
	source = source.replace("root + '/source/intent-uri369-run.v'", "root + '/source/intent-uri371-run.v'")
	source = once(source, "assert hash(root + '/source/intent-uri371-run.v')! == '09b717df537cb6d320224b53e74405c5ba62b994114443bdfe64d93d4218fd1b'", "assert hash(root + '/source/intent-uri371-run.v')! == source_pin")
	source = source.replace('INTENT369-ART-', 'INTENT371-ART-')
	source = source.replace('PENDING_SOURCE', 'e6de49d024b706ffc34f6169b3a1a31f725708d3bbfd7425657513d9c6d2e707')
	source = source.replace('PENDING_FRAMEWORK', '71e311764ece295185656854294a514a9c641419c567d5f96ac66f52f4b89750')
	source = source.replace('PENDING_BOOTSTRAP', '4c192b967eb30a27caa5fa08d5d5c0ff15e4136e89134390d91c7704ef4488b6')
	source = source.replace('PENDING_ACTION_SOURCE', 'cb0dafd546e714bbeb3157a49f420b758e5d98221e9de1b3891396e722c46819')
	source = source.replace('PENDING_ACTION_BINARY', 'b2d0fdd9791b7f25b509b3ac7145759ce2f69076387c7b1f5b2f9d1945a64997')
	source = source.replace('PENDING_JAR', '3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21')
	source = source.replace('PENDING_RUNNER', '00c60580fbd151f9760dbf9b83604d469ebcf29093822aa38a73b518932c966b')
	source = source.replace('PENDING_SHARED', '81c6c4915ce15be52471fed4ba3972f04d913ad88c7a77a59ccd79bb6e0b0dad')
	source = source.replace('PENDING_BUILD', '73e13c76dfb0e74245a3010723badc66549a2da68bcf3c1f665364b1f4b0847b')
	source = once(source, "  'stdout_sha256': json2.Any(hash(output + '/stdout.log')!), 'frozen_closure_inputs': json2.Any(closure_count)", "  'stdout_sha256': json2.Any(hash(output + '/stdout.log')!), 'frozen_closure_inputs': json2.Any(closure_count),\n  'fresh_runner_frozen_closure_inputs': json2.Any(270),\n  'historical_control_scope': json2.Any('Pinned complete 52112-file historical snapshot; full original file presence required; every selected retained control byte rehashed at origin and in the canonical371 bundle.'),\n  'original_historical_inventory_sha256': json2.Any(original_inventory)")
	source = once(source, " assert receipt['manifest_sha256']!.str() == manifest_pin && receipt['files_checked']!.int() == manifest.len", " assert receipt['manifest_sha256']!.str() == manifest_pin && receipt['files_checked']!.int() == manifest.len\n assert receipt['root']!.str() == root && receipt['checker_sha256']!.str() == checker_pin\n assert receipt['argv']!.as_array().map(it.str()) == argv\n assert receipt['started_utc']!.str() >= started && receipt['started_utc']!.str() <= receipt['completed_utc']!.str()")
	if os.exists(output) {
		assert os.read_file(output)! == source, 'existing generated reader must match exact generator output'
		println('INTENT371-ART-PEER-GENERATOR-CHECK-PASS')
		return
	}
	os.write_file(output, source)!
	println(output)
}
