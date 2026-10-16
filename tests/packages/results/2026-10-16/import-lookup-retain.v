module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string scenario string seconds f64 artifacts []Artifact }
struct Check { name string seconds f64 }
struct HostReceipt { compiler_sha256 string checks []Check }
struct Ledger { format int = 1 scope string compiler Pin sources []Pin artifacts []Pin }
const lookup_markers = [
	'IMPORT LOOKUP ordinary/guest-alias/parent/40-link/FIFO paths and late refusals retire scratch and descriptors PASS',
	'IMPORT LOOKUP independent descriptors survive retired source text, path scratch and host namespace replacement PASS',
	'IMPORT LOOKUP source rechecks retire complete and refused identity/size/execute/namespace scratch PASS',
	'IMPORT LOOKUP owned restart paths preserve parent/suffix order and exact 4096-byte boundary before allocation PASS',
]
const capture_markers = [
	'IMPORT CAPTURE retained root and guest-absolute aliases survive host namespace replacement with identical retry metadata PASS',
	'IMPORT CAPTURE 49 file identity/size/execute mutations refuse before publication; 32-descriptor cleanup and exact retry PASS',
	'IMPORT CAPTURE multi-block same-size rewrites during hashing and copying fail content comparison before publication PASS',
	'IMPORT CAPTURE directory replacement and added/removed/renamed entries refuse; guest targets survive and retries succeed PASS',
	'IMPORT CAPTURE pinned digest/execute admission, empty files, stripped special modes and canonical declarations survive exact retry PASS',
	'IMPORT CAPTURE nine injected checkpoint failures retire descriptors and private scratch before successful public retry PASS',
]
fn pin(path string) !Pin { b := os.read_bytes(path)!; defer { unsafe { b.free() } }; return Pin{ path: path, bytes: u64(b.len), sha256: sha256.sum(b).hex() } }
fn assert_lookup(output string, tracked bool) {
	assert !output.contains('V panic:') && !output.contains('IMPORT LIMITS baseline:') && !output.contains('HWTEST FAIL')
	for marker in lookup_markers { assert output.count(marker) == 1, marker }
	assert output.count('IMPORT LOOKUP case=') == 20 && output.count('IMPORT RECHECK fault=') == 8
	if tracked { assert output.count(' retained=0 allocations=0') == 28 && !output.contains('functional-cycles=') }
	else { assert output.count(' functional-cycles=8 PASS') == 28 }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); host := work + '/h1'
	prefix := 'tests/packages/results/2026-10-16/import-lookup-'
	mut artifacts := []Pin{}
	checks := json2.decode[HostReceipt](os.read_file(host + '/qualification.json')!)!
	assert checks.checks.len == 47 && checks.compiler_sha256 == pin('build/package-release-work/v-toolchain/v')!.sha256
	assert_lookup(os.read_file(host + '/import_lookup-run.txt')!, false)
	assert_lookup(os.read_file(host + '/import_lookup-sanitize-run.txt')!, false)
	assert_lookup(os.read_file(host + '/lookup-memory-run.txt')!, true)
	baseline := json2.decode[[]Pin](os.read_file(work + '/baseline.json')!)!
	for item in baseline { actual := pin(item.path)!; assert actual.bytes == item.bytes && actual.sha256 == item.sha256; artifacts << actual }
	before := os.read_file(work + '/baseline.txt')!
	assert before.count('IMPORT LOOKUP case=') == 20
	assert before.contains('IMPORT LOOKUP case=ordinary retained=503 allocations=10') && before.contains('IMPORT LOOKUP case=cycle retained=8574 allocations=365')
	mut summary := ''
	for check in checks.checks { artifacts << pin(host + '/' + check.name + '.txt')!; summary += check.name + ' PASS (' + check.seconds.str() + ' s)\n' }
	os.write_file(prefix + 'host.txt', summary)!; artifacts << pin(prefix + 'host.txt')!
	for short, architecture in { 'arm': 'aarch64', 'x86': 'x86_64' } {
		guest := os.real_path('build/plu-' + short + '-1')
		receipt := json2.decode[Receipt](os.read_file(guest + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.scenario == 'packages-import-lookup' && receipt.artifacts.len == 10
		mut paths := {'kernel': guest + '/kernel', 'guest-init': guest + '/guest/init', 'serial-log': guest + '/packages-import-lookup/serial.log'}
		for name in ['import-lookup', 'import-capture', 'import-limits', 'import', 'pack-source', 'catalog', 'release']! { paths[name] = guest + '/guest/root/usr/share/package-fixtures/' + name }
		for item in receipt.artifacts { actual := pin(paths[item.role])!; assert actual.bytes == item.bytes && actual.sha256 == item.sha256, item.role; artifacts << actual }
		prior := json2.decode[Receipt](os.read_file('tests/packages/results/2026-10-16/software-installed-' + architecture + '.json')!)!
		assert receipt.artifacts[0].sha256 == prior.artifacts.filter(it.role == 'kernel')[0].sha256
		serial := os.read_file(guest + '/packages-import-lookup/serial.log')!
		assert_lookup(serial, true)
		assert serial.contains('HWTEST PASS packages-import-lookup') && serial.count('IMPORT LOOKUP PROCESS ') == 7
		assert serial.count('IMPORT LIMITS ') == 5
		for marker in capture_markers { assert serial.count(marker) == 1, marker }
		qmp := os.read_file(guest + '/packages-import-lookup/qmp.log')!; assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
		for suffix, source in { architecture + '.json': guest + '/qualification.json', architecture + '.serial.txt': guest + '/packages-import-lookup/serial.log', architecture + '.qmp.txt': guest + '/packages-import-lookup/qmp.log' } {
			os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
		}
		artifacts << pin(guest + '/guest/init.c')!; artifacts << pin(guest + '/guest/build.log')!
		for index, name in ['import-lookup', 'import-capture', 'import-limits', 'import', 'pack-source', 'catalog', 'release']! {
			artifacts << pin(guest + '/guest/program-' + index.str() + '/' + name + '.c')!
		}
		println(architecture + ' target passed in ' + receipt.seconds.str() + ' seconds')
	}
	for suffix, source in {
		'host.json': host + '/qualification.json', 'core.txt': host + '/import_lookup-run.txt', 'memory.txt': host + '/lookup-memory-run.txt',
		'asan.txt': host + '/import_lookup-sanitize-run.txt', 'capture-asan.txt': host + '/import_capture-sanitize-run.txt', 'catalog-asan.txt': host + '/catalog-sanitize-run.txt',
		'cli.txt': host + '/distribution-cli-run.txt', 'baseline.txt': work + '/baseline.txt', 'baseline.json': work + '/baseline.json',
		'baseline-import.c.v.txt': work + '/baseline-import.c.v', 'baseline-fixture.v.txt': work + '/baseline-import_lookup_test.v',
		'guest.v': work + '/guest.v', 'guards.v': work + '/guards.v', 'capture.v': work + '/capture.v', 'retain.v': work + '/retain.v' } {
		os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
	}
	for name in ['list-aarch64', 'list-x86_64', 'refuse-inputs', 'refuse-existing'] { artifacts << pin(work + '/' + name + '.txt')! }
	for name in ['vinix-package', 'import_lookup', 'import_capture', 'import_limits', 'import', 'pack_source', 'prepared_root', 'root_recipe_decode', 'catalog', 'catalog_plan', 'composition', 'release',
		'native_profile', 'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'profile_inventory', 'publisher_schema', 'distribution-cli',
		'import_lookup-sanitize', 'import_capture-sanitize', 'catalog-sanitize', 'lookup-memory'] { artifacts << pin(host + '/' + name)! }
	for path in [work + '/controller', work + '/host', work + '/guest', 'build/package-launch-transport-work/cross-cc',
		'/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc', '/opt/homebrew/bin/qemu-system-aarch64', '/opt/homebrew/bin/qemu-system-x86_64'] { artifacts << pin(path)! }
	prior_sources := json2.decode[Ledger](os.read_file('tests/packages/results/2026-10-16/import-capture-toolchain.json')!)!
	assert baseline[0].sha256 == prior_sources.sources.filter(it.path == 'tools/packages/pkgcore/import.c.v')[0].sha256
	mut source_paths := prior_sources.sources.map(it.path)
	source_paths << ['tools/packages/pkgcore/import_lookup_test.v', 'tests/packages/import-lookup-check.v', 'tests/packages/import-lookup-check.md',
		'tests/packages/import-lookup-runtime-check.v', 'tests/packages/import-lookup-guest/main.v']
	source_paths.sort(); mut sources := []Pin{}; for path in source_paths { sources << pin(path)! }
	changed := ['tools/packages/pkgcore/import.c.v', 'tools/packages/README.md', 'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md']
	for source in prior_sources.sources { if source.path in changed { continue }; actual := pin(source.path)!; assert actual.sha256 == source.sha256 && actual.bytes == source.bytes, source.path }
	compiler := pin(os.real_path('build/package-release-work/v-toolchain/v'))!; assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{
		scope: 'Prepared-root lookup/recheck ownership: measured legacy 20-case retention; 3584 warmed path/recheck attempts with zero retained bytes/allocations on host and each architecture; independent descriptor and 4096-byte restart boundary assertions. Forty-seven host build/run checks, three sanitizer suites with leak detection disabled, four controller guards and fresh AArch64/x86-64 ten-artifact guests with all seven runners and guest poweroff. Includes source consistency mutations, bounded imports, direct pack, five host profiles and signed catalog/release/CLI maintenance. Kernels match installed-root qualification. No atomic source snapshot, complete import/packer heap retention or broader production catalog/graphical/device acceptance claim.',
		compiler: compiler, sources: sources, artifacts: artifacts }) + '\n')!
	println('Verified legacy baseline, forty-seven host checks, two ten-artifact guests, shutdown and ' + sources.len.str() + ' source pins')
}
