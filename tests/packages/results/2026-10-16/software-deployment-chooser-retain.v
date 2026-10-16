module main

import crypto.sha256
import json2
import os
import time

struct Pin { path string bytes u64 sha256 string }
struct Result { name string code int seconds f64 }
struct Ledger { format int = 1 baseline string = '004399686' completed_at i64 compiler Pin sources []Pin evidence []Pin scope string }

const work = 'build/package-deployment-chooser-work'
const prefix = 'tests/packages/results/2026-10-16/software-deployment-chooser-'
const owned = ['desktop/software_app.v', 'desktop/software_deployment.v', 'desktop/software_deployment_chooser.v',
	'tests/packages/distribution-check.v', 'tests/packages/software_fixture.v', 'tests/packages/software_deployment_chooser_fixture.v',
	'tests/packages/launcher-check.v',
	'tools/packages/README.md', 'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md', 'tests/packages/software-deployment-chooser-check.md']
const chooser_marker = 'Software deployment chooser: real broker requests/pending/results/cancel/disconnect, literal paths, explicit review, duplicate suppression and late edit/navigation/review/audit/snapshot retirement PASS'
const memory_marker = 'Software deployment chooser: 1000 literal/empty/invalid/4096-byte/oversize/late-result/directory/full/compact lifecycle cycles retain zero tracked bytes PASS'

fn pin(path string) !Pin {
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	return Pin{ path: path, bytes: u64(data.len), sha256: sha256.sum(data).hex() }
}

fn good(value string) {
	assert !value.contains('V panic:') && !value.contains('runtime error:') && !value.contains('ERROR: AddressSanitizer')
}

fn retain() ! {
	mut results := json2.decode[[]Result](os.read_file(work + '/ui-results.json')!)!
	results << json2.decode[[]Result](os.read_file(work + '/asan-results.json')!)!
	results << json2.decode[[]Result](os.read_file(work + '/launcher-results.json')!)!
	assert results.len == 14 && results.all(it.code == 0)
	mut summary := '14 focused compile/run checks passed:\n'
	for result in results { good(os.read_file(work + '/' + result.name + '.txt')!); summary += 'PASS ' + result.name + '\n' }
	driver := os.read_file(work + '/driver-current.txt')!
	good(driver)
	assert driver.contains(chooser_marker) && driver.contains(memory_marker) && !driver.contains(': fn test_')
	assert driver.contains('Software verification navigation: 1000') && driver.contains('/launcher-check failed with status 1')
	assert driver.count('error:') == 2 && driver.contains('cannot import module "authclient"') && driver.contains('cannot import module "authproto"')
	launcher := os.read_file(work + '/launcher-run.txt')!
	good(launcher); assert !launcher.contains('error:') && launcher.contains('Package launcher assertions passed')
	summary += 'PASS maintained Software functional suite, all 26 allocation modes and both full Linux desktop architecture typechecks\nPASS independently rebuilt launcher check after fixing its nested account-module lookup; full driver raw output retains that final helper failure before correction\n'
	ui := os.read_file(work + '/ui-functional.txt')! + '\n' + os.read_file(work + '/ui-chooser.txt')!
	assert ui.contains(chooser_marker)
	memory := os.read_file(work + '/ui-memory.txt')! + os.read_file(work + '/ui-navigation-memory.txt')!
	assert memory.contains(memory_marker)
	asan := 'ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1\nController instrumented with address/undefined sanitizers; actual session broker compiled normally.\n\n' + os.read_file(work + '/asan-functional.txt')! + '\n' + os.read_file(work + '/asan-chooser.txt')! + os.read_file(work + '/asan-memory.txt')! + os.read_file(work + '/asan-navigation-memory.txt')!
	assert asan.contains(chooser_marker) && asan.contains(memory_marker)
	os.write_file(prefix + 'host.json', json2.encode(results) + '\n')!
	os.write_file(prefix + 'host.txt', summary)!
	os.write_file(prefix + 'ui.txt', ui)!
	os.write_file(prefix + 'memory.txt', memory)!
	os.write_file(prefix + 'asan.txt', asan)!
	os.write_file(prefix + 'driver.txt', driver + '\nIndependent launcher retry after account-module lookup correction:\n' + launcher)!
	initial := os.read_file(work + '/driver-final.txt')!
	start := initial.index('desktop/quick_launch_search.v:161:17: error:') or { return error('missing initial overlay diagnostic') }
	os.write_file(prefix + 'attempts.txt', 'The initial full desktop typecheck selected an older desktop.workflowcore from the ui2 test overlay and could not find the current launcher_query interface. The maintained driver now resolves repository modules and account interfaces before that overlay. Fresh controller/broker, allocation and sanitizer runs use that source lookup order. The maintained rerun passed all 26 allocation modes and both target typechecks before its final launcher helper failed because its nested compiler omitted tools/accounts. That helper now uses the same repository/account-first lookup; its independent fresh compile/run passed. Raw combined driver/retry output is retained. Unrelated desktop implementation was left unchanged.\n\nInitial architecture typecheck diagnostic:\n' + initial[start..])!
	os.cp(work + '/checks.v', prefix + 'checks.v')!
	os.cp(work + '/retain.v', prefix + 'retain.v')!
	mut commit_paths := owned.clone()
	for suffix in ['host.json', 'host.txt', 'ui.txt', 'memory.txt', 'asan.txt', 'driver.txt', 'attempts.txt', 'checks.v', 'retain.v', 'toolchain.json'] { commit_paths << prefix + suffix }
	os.write_file(work + '/owned-paths.json', json2.encode(commit_paths) + '\n')!
	mut paths := owned.clone()
	for directory in ['tools/packages', 'tools/accounts', 'tools/security-events', 'tools/keyring', 'desktop/workflowcore', 'desktop/packagecore', 'desktop/sessioncore', 'desktop/sessionipc', 'desktop/sessiondaemon', 'desktop/serviceprocess', 'desktop/services/session'] {
		paths << os.walk_ext(directory, '.v').filter(!it.contains('.v3cc.') && !it.ends_with('_test.v'))
	}
	for name in os.ls('desktop')! { if name.ends_with('.v') || name.ends_with('.h') || name.ends_with('.vml') { paths << 'desktop/' + name } }
	for name in os.ls('tests/packages')! { if name.starts_with('software_') && name.ends_with('_fixture.v') { paths << 'tests/packages/' + name } }
	paths << os.walk_ext('build/package-view-reader-work/desktop/modules', '.v')
	paths << ['desktop/tools/tests/heap_tracker.h', work + '/checks.v', work + '/retain.v', 'build/package-release-work/v-toolchain/vlib/os/os.v']
	mut evidence := []Pin{}
	for stage in ['ui-sources-current', 'asan-sources-current'] {
		for name in os.ls(work + '/' + stage)! {
			actual := work + '/' + stage + '/' + name
			original := if name == 'main.v' { 'tests/packages/software_fixture.v' } else if name.ends_with('_fixture.v') { 'tests/packages/' + name } else { 'desktop/' + name }
			assert pin(actual)!.sha256 == pin(original)!.sha256
			evidence << pin(actual)!
		}
	}
	for name in ['ui', 'asan', 'session-broker-ui', 'session-broker-asan', 'distribution', 'checks', 'launcher', 'launcher-results.json', 'ui-results.json', 'asan-results.json'] { evidence << pin(work + '/' + name)! }
	for result in results { evidence << pin(work + '/' + result.name + '.txt')! }
	for path in commit_paths { if path.starts_with(prefix) && !path.ends_with('toolchain.json') { evidence << pin(path)! } }
	paths.sort(); mut seen := map[string]bool{}; mut sources := []Pin{}
	for path in paths { if path !in seen { seen[path] = true; sources << pin(path)! } }
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ completed_at: time.now().unix(), compiler: compiler, sources: sources, evidence: evidence,
		scope: 'Software deployment file chooser through the existing real authenticated session broker: literal bounded UTF-8 admission, explicit separate review/confirmation, duplicate suppression, cancellation/disconnect diagnostics/manual fallback, late input/navigation/review/audit/snapshot retirement. Complete Software functional fixture, all 26 maintained allocation modes, focused 1000-cycle zero-retention selection/form and existing deployment lifecycle checks; controller ASan/UBSan (broker normal, leak detection disabled). Both full desktop Linux target typechecks and launcher checks. No new guest/compositor-presentation qualification, whole-session IPC allocation freedom, production publisher/catalog/runtime or complete roadmap14 acceptance claim.' }) + '\n')!
	println('Retained ' + sources.len.str() + ' source pins and ' + evidence.len.str() + ' evidence pins; ' + commit_paths.len.str() + ' owned paths')
}

fn main() { retain() or { eprintln(err); exit(1) } }
