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
fn pin(path string) !Pin { b := os.read_bytes(path)!; defer { unsafe { b.free() } }; return Pin{ path: path, bytes: u64(b.len), sha256: sha256.sum(b).hex() } }
fn main() {
	work := os.real_path(os.dir(@FILE)); host := work + '/h1'
	prefix := 'tests/packages/results/2026-10-16/catalog-plan-'
	mut artifacts := []Pin{}
	checks := json2.decode[HostReceipt](os.read_file(host + '/qualification.json')!)!
	assert checks.checks.len == 33 && checks.compiler_sha256 == pin('build/package-release-work/v-toolchain/v')!.sha256
	memory := os.read_file(host + '/tracked-run.txt')!
	assert memory.count('retained=0 allocations=0') == 14 && !memory.contains('functional-cycles') && memory.contains('independent idempotently closeable results PASS')
	for name in ['catalog_plan-run', 'catalog_plan-sanitize-run'] {
		functional := os.read_file(host + '/' + name + '.txt')!
		assert functional.count('functional-cycles=4 PASS') == 14 && !functional.contains('retained=')
	}
	assert os.read_file(host + '/catalog-sanitize-run.txt')!.contains('CATALOG WORKSPACE owned replies close independently')
	baseline := json2.decode[[]Pin](os.read_file(work + '/baseline.json')!)!
	for item in baseline { actual := pin(item.path)!; assert actual.bytes == item.bytes && actual.sha256 == item.sha256; artifacts << actual }
	assert os.read_file(work + '/baseline.txt')!.contains('imports=64 fault=none retained=1719209 allocations=1938')
	for short, architecture in { 'arm': 'aarch64', 'x86': 'x86_64' } {
		guest := os.real_path('build/pcp-' + short + '-1')
		receipt := json2.decode[Receipt](os.read_file(guest + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.scenario == 'packages-catalog-normalize' && receipt.artifacts.len == 10
		mut paths := {'kernel': guest + '/kernel', 'guest-init': guest + '/guest/init', 'serial-log': guest + '/packages-catalog-normalize/serial.log',
			'package-cli': guest + '/guest/root/usr/bin/vinix-package'}
		for name in ['catalog-normalize', 'catalog', 'composition', 'release', 'composition-ownership', 'catalog-plan']! { paths[name] = guest + '/guest/root/usr/share/package-fixtures/' + name }
		for item in receipt.artifacts { actual := pin(paths[item.role])!; assert actual.bytes == item.bytes && actual.sha256 == item.sha256, item.role; artifacts << actual }
		prior := json2.decode[Receipt](os.read_file('tests/packages/results/2026-10-16/software-installed-' + architecture + '.json')!)!
		assert receipt.artifacts[0].sha256 == prior.artifacts.filter(it.role == 'kernel')[0].sha256
		serial := os.read_file(guest + '/packages-catalog-normalize/serial.log')!
		assert serial.contains('HWTEST PASS packages-catalog-normalize') && serial.count('CATALOG NORMALIZE PROCESS ') == 6
		assert serial.count('functional-cycles=16 PASS') == 16 && serial.count('functional-cycles=4 PASS') == 30
		assert serial.contains('CATALOG PLAN owned metadata/budget planning and schema/architecture/depth/closure/object-length refusals PASS')
		assert serial.contains('CATALOG PLAN legacy bytes, deduplicated workspace/largest-package budgets, disclosures and independent idempotently closeable results PASS')
		assert serial.contains('CATALOG WORKSPACE owned replies close independently without removing published manifests, objects or catalog PASS')
		assert serial.contains('COMPOSITION OWNERSHIP independent plans and closeable replies survive retired inputs; canonical bytes, disclosures and idempotent close PASS')
		assert serial.contains('COMPOSITION TARGET: explicit CLI/API equivalence, literal paths, unsupported host, argument counts and existing-output refusals PASS')
		assert !serial.contains('HWTEST FAIL') && !serial.contains('V panic:') && !serial.contains('retained=')
		qmp := os.read_file(guest + '/packages-catalog-normalize/qmp.log')!; assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
		for suffix, source in { architecture + '.json': guest + '/qualification.json', architecture + '.serial.txt': guest + '/packages-catalog-normalize/serial.log', architecture + '.qmp.txt': guest + '/packages-catalog-normalize/qmp.log' } {
			os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
		}
		for path in ['guest/init.c', 'guest/build.log', 'guest/program-0/catalog-normalize.c', 'guest/program-1/catalog.c', 'guest/program-2/composition.c',
			'guest/program-3/release.c', 'guest/program-4/composition-ownership.c', 'guest/program-5/vinix-package.c', 'guest/program-6/catalog-plan.c'] { artifacts << pin(guest + '/' + path)! }
		println(architecture + ' target passed in ' + receipt.seconds.str() + ' seconds')
	}
	for suffix, source in {
		'host.json': host + '/qualification.json', 'memory.txt': host + '/tracked-run.txt', 'core.txt': host + '/catalog_plan-run.txt',
		'asan.txt': host + '/catalog_plan-sanitize-run.txt', 'catalog-asan.txt': host + '/catalog-sanitize-run.txt',
		'cli.txt': host + '/distribution-cli-run.txt', 'baseline.txt': work + '/baseline.txt', 'baseline.json': work + '/baseline.json',
		'baseline-catalog.v.txt': work + '/baseline-catalog.v', 'baseline-fixture.v.txt': work + '/baseline-catalog_plan_test.v',
		'guest.v': work + '/guest.v', 'capture.v': work + '/capture.v', 'finish.v': work + '/finish.v', 'retain.v': work + '/retain.v' } {
		os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
	}
	for check in checks.checks { artifacts << pin(host + '/' + check.name + '.txt')! }
	for name in ['list-aarch64', 'list-x86_64', 'refuse-inputs', 'refuse-existing'] { artifacts << pin(work + '/' + name + '.txt')! }
	for name in ['vinix-package', 'catalog_plan', 'catalog', 'catalog_decode', 'composition', 'composition_ownership', 'publisher_schema', 'native_profile',
		'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'release', 'tracked', 'distribution-cli', 'catalog_plan-sanitize', 'catalog-sanitize'] { artifacts << pin(host + '/' + name)! }
	for path in [work + '/controller', work + '/host', work + '/guest', work + '/capture', work + '/finish', 'build/package-launch-transport-work/cross-cc',
		'/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc', '/opt/homebrew/bin/qemu-system-aarch64', '/opt/homebrew/bin/qemu-system-x86_64'] { artifacts << pin(path)! }
	prior_sources := json2.decode[Ledger](os.read_file('tests/packages/results/2026-10-16/composition-ownership-toolchain.json')!)!
	mut source_paths := prior_sources.sources.map(it.path)
	source_paths << ['tools/packages/pkgcore/catalog_plan_test.v', 'tools/packages/pkgcore/publisher_encoding.v', 'tests/packages/catalog-plan-check.v',
		'tests/packages/catalog-plan-check.md', 'tests/packages/catalog-build-check.md']
	source_paths.sort(); mut sources := []Pin{}; for path in source_paths { sources << pin(path)! }
	changed := ['tools/packages/pkgcore/catalog.v', 'tools/packages/pkgcore/catalog_test.v', 'tools/packages/pkgcore/composition.v',
		'tools/packages/main.v', 'tools/packages/README.md', 'tools/packages/SDK.md', 'docs/application-distribution.md',
		'tests/packages/catalog-normalize-guest/main.v', 'tests/packages/catalog-normalize-runtime-check.v', 'tests/packages/catalog-normalize-check.md',
		'tests/packages/composition-ownership-check.md']
	for source in prior_sources.sources { if source.path in changed { continue }; actual := pin(source.path)!; assert actual.sha256 == source.sha256 && actual.bytes == source.bytes, source.path }
	compiler := pin(os.real_path('build/package-release-work/v-toolchain/v'))!; assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{
		scope: 'Catalog workspace metadata/budget plan ownership and independent public result cleanup: original measured planner, thirty-three host checks including 1792 warmed independently tracked success/refusal attempts, original canonical encoding/budget formula, five publisher profiles, signed CLI and two sanitizer suites; four controller guards and fresh AArch64/x86-64 ten-artifact functional guests with owned workspace/composition replies, literal CLI/API and signed offline maintenance. Existing kernels match installed-root qualification. Acquisition, complete pack/import and shared filesystem-helper lifetimes plus broader production/graphical/device acceptance remain separate.',
		compiler: compiler, sources: sources, artifacts: artifacts }) + '\n')!
	println('Verified baseline, thirty-three host checks, fourteen zero-retention cases, two ten-artifact guests, shutdown and ' + sources.len.str() + ' source pins')
}
