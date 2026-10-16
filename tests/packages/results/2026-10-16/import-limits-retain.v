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
const import_markers = [
	'IMPORT LIMITS 129th directory refuses before materialization; source and ancestor state preserved PASS',
	'IMPORT LIMITS exact 128-level directory/file boundary and nested selector parents match final pack rules PASS',
	'IMPORT LIMITS shared 32768-entry budget counts selected roots, empty directories and repeated aliases; refusal precedes output and retry resets budget PASS',
	'IMPORT LIMITS remaining-budget enumeration refuses partial lists and preserves sorted exact-boundary names PASS',
	'IMPORT LIMITS 32 failed/successful public imports retire descriptors and private scratch, preserve source bytes and permit exact retry PASS',
]
fn pin(path string) !Pin { b := os.read_bytes(path)!; defer { unsafe { b.free() } }; return Pin{ path: path, bytes: u64(b.len), sha256: sha256.sum(b).hex() } }
fn assert_imports(output string) {
	assert output.count('IMPORT LIMITS ') == 5 && !output.contains('IMPORT LIMITS baseline:') && !output.contains('V panic:')
	for marker in import_markers { assert output.contains(marker), marker }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); host := work + '/h1'
	prefix := 'tests/packages/results/2026-10-16/import-limits-'
	mut artifacts := []Pin{}
	checks := json2.decode[HostReceipt](os.read_file(host + '/qualification.json')!)!
	assert checks.checks.len == 41 && checks.compiler_sha256 == pin('build/package-release-work/v-toolchain/v')!.sha256
	assert_imports(os.read_file(host + '/import_limits-run.txt')!)
	assert_imports(os.read_file(host + '/import_limits-sanitize-run.txt')!)
	baseline := json2.decode[[]Pin](os.read_file(work + '/baseline.json')!)!
	for item in baseline { actual := pin(item.path)!; assert actual.bytes == item.bytes && actual.sha256 == item.sha256; artifacts << actual }
	assert os.read_file(work + '/baseline.txt')!.contains('129 directory levels and payload materialized before the later pack walk PASS')
	for short, architecture in { 'arm': 'aarch64', 'x86': 'x86_64' } {
		guest := os.real_path('build/pil-' + short + '-1')
		receipt := json2.decode[Receipt](os.read_file(guest + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.scenario == 'packages-catalog-normalize' && receipt.artifacts.len == 12
		mut paths := {'kernel': guest + '/kernel', 'guest-init': guest + '/guest/init', 'serial-log': guest + '/packages-catalog-normalize/serial.log',
			'package-cli': guest + '/guest/root/usr/bin/vinix-package'}
		for name in ['catalog-normalize', 'catalog', 'composition', 'release', 'composition-ownership', 'catalog-plan', 'import-limits', 'import']! { paths[name] = guest + '/guest/root/usr/share/package-fixtures/' + name }
		for item in receipt.artifacts { actual := pin(paths[item.role])!; assert actual.bytes == item.bytes && actual.sha256 == item.sha256, item.role; artifacts << actual }
		prior := json2.decode[Receipt](os.read_file('tests/packages/results/2026-10-16/software-installed-' + architecture + '.json')!)!
		assert receipt.artifacts[0].sha256 == prior.artifacts.filter(it.role == 'kernel')[0].sha256
		serial := os.read_file(guest + '/packages-catalog-normalize/serial.log')!
		assert serial.contains('HWTEST PASS packages-catalog-normalize') && serial.count('CATALOG NORMALIZE PROCESS ') == 8
		assert serial.count('functional-cycles=16 PASS') == 16 && serial.count('functional-cycles=4 PASS') == 30
		assert_imports(serial)
		assert serial.contains('CATALOG PLAN legacy bytes, deduplicated workspace/largest-package budgets, disclosures and independent idempotently closeable results PASS')
		assert serial.contains('CATALOG WORKSPACE owned replies close independently without removing published manifests, objects or catalog PASS')
		assert serial.contains('COMPOSITION TARGET: explicit CLI/API equivalence, literal paths, unsupported host, argument counts and existing-output refusals PASS')
		assert !serial.contains('HWTEST FAIL')
		qmp := os.read_file(guest + '/packages-catalog-normalize/qmp.log')!; assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
		for suffix, source in { architecture + '.json': guest + '/qualification.json', architecture + '.serial.txt': guest + '/packages-catalog-normalize/serial.log', architecture + '.qmp.txt': guest + '/packages-catalog-normalize/qmp.log' } {
			os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
		}
		for path in ['guest/init.c', 'guest/build.log', 'guest/program-0/catalog-normalize.c', 'guest/program-1/catalog.c', 'guest/program-2/composition.c',
			'guest/program-3/release.c', 'guest/program-4/composition-ownership.c', 'guest/program-5/vinix-package.c', 'guest/program-6/catalog-plan.c',
			'guest/program-7/import-limits.c', 'guest/program-8/import.c'] { artifacts << pin(guest + '/' + path)! }
		println(architecture + ' target passed in ' + receipt.seconds.str() + ' seconds')
	}
	for suffix, source in {
		'host.json': host + '/qualification.json', 'core.txt': host + '/import_limits-run.txt',
		'asan.txt': host + '/import_limits-sanitize-run.txt', 'import-asan.txt': host + '/import-sanitize-run.txt', 'catalog-asan.txt': host + '/catalog-sanitize-run.txt',
		'cli.txt': host + '/distribution-cli-run.txt', 'baseline.txt': work + '/baseline.txt', 'baseline.json': work + '/baseline.json',
		'baseline-import.c.v.txt': work + '/baseline-import.c.v', 'baseline-fixture.v.txt': work + '/baseline-import_limits_test.v',
		'guest.v': work + '/guest.v', 'capture.v': work + '/capture.v', 'finish.v': work + '/finish.v', 'retain.v': work + '/retain.v' } {
		os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
	}
	for check in checks.checks { artifacts << pin(host + '/' + check.name + '.txt')! }
	for name in ['list-aarch64', 'list-x86_64', 'refuse-inputs', 'refuse-existing'] { artifacts << pin(work + '/' + name + '.txt')! }
	for name in ['vinix-package', 'import_limits', 'import', 'pack_source', 'prepared_root', 'root_recipe_decode', 'catalog', 'catalog_plan', 'composition', 'release',
		'native_profile', 'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'profile_inventory', 'publisher_schema', 'distribution-cli',
		'import_limits-sanitize', 'import-sanitize', 'catalog-sanitize'] { artifacts << pin(host + '/' + name)! }
	for path in [work + '/controller', work + '/host', work + '/guest', work + '/capture', work + '/finish', 'build/package-launch-transport-work/cross-cc',
		'/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc', '/opt/homebrew/bin/qemu-system-aarch64', '/opt/homebrew/bin/qemu-system-x86_64'] { artifacts << pin(path)! }
	prior_sources := json2.decode[Ledger](os.read_file('tests/packages/results/2026-10-16/catalog-plan-toolchain.json')!)!
	mut source_paths := prior_sources.sources.map(it.path)
	source_paths << ['tools/packages/pkgcore/import_limits_test.v', 'tests/packages/import-limits-check.v', 'tests/packages/import-limits-check.md',
		'tests/packages/prepared-root-check.md', 'roadmap.md']
	source_paths.sort(); mut sources := []Pin{}; for path in source_paths { sources << pin(path)! }
	changed := ['tools/packages/pkgcore/import.c.v', 'tools/packages/README.md', 'tools/packages/SDK.md', 'docs/application-distribution.md',
		'tests/packages/catalog-normalize-guest/main.v', 'tests/packages/catalog-normalize-runtime-check.v', 'tests/packages/catalog-normalize-check.md',
		'tests/packages/catalog-plan-check.md', 'tests/packages/composition-ownership-check.md']
	for source in prior_sources.sources { if source.path in changed { continue }; actual := pin(source.path)!; assert actual.sha256 == source.sha256 && actual.bytes == source.bytes, source.path }
	compiler := pin(os.real_path('build/package-release-work/v-toolchain/v'))!; assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{
		scope: 'Bounded prepared-root materialization: legacy 129-level traversal observation, forty-one host checks, real depth and selector-parent boundaries, seeded aggregate entry/alias limits, partial enumeration and repeated descriptor/private-workspace cleanup, exact public retry; direct pack, root admission, decoding, all five profiles, signed catalog/composition/release/CLI regressions and three sanitizer suites; four controller guards and fresh AArch64/x86-64 twelve-artifact guests with every required marker and guest poweroff. Kernels match installed-root qualification. No complete import/packer heap-retention or broader production/graphical/device acceptance claim.',
		compiler: compiler, sources: sources, artifacts: artifacts }) + '\n')!
	println('Verified baseline, forty-one host checks, two twelve-artifact guests, shutdown and ' + sources.len.str() + ' source pins')
}
