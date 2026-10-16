module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string scenario string artifacts []Artifact }
struct Check { name string seconds f64 }
struct HostReceipt { compiler_sha256 string checks []Check }
struct Ledger { format int = 1 scope string compiler Pin sources []Pin artifacts []Pin }
fn pin(path string) !Pin { b := os.read_bytes(path)!; defer { unsafe { b.free() } }; return Pin{ path: path, bytes: u64(b.len), sha256: sha256.sum(b).hex() } }
fn main() {
	work := os.real_path(os.dir(@FILE)); host := work + '/h3'
	prefix := 'tests/packages/results/2026-10-16/catalog-normalize-'
	mut artifacts := []Pin{}
	checks := json2.decode[HostReceipt](os.read_file(host + '/qualification.json')!)!
	assert checks.checks.len == 35 && checks.compiler_sha256 == pin('build/package-release-work/v-toolchain/v')!.sha256
	memory := os.read_file(host + '/tracked-run.txt')!
	assert memory.count('retained=0 allocations=0') == 16 && !memory.contains('functional-cycles') && memory.contains('independent owned output')
	baseline := json2.decode[[]Pin](os.read_file(work + '/baseline.json')!)!
	for item in baseline { actual := pin(item.path)!; assert actual.bytes == item.bytes && actual.sha256 == item.sha256; artifacts << actual }
	assert os.read_file(work + '/baseline.txt')!.contains('imports=64 fault=none retained=905575 allocations=2584')
	for short, architecture in { 'arm': 'aarch64', 'x86': 'x86_64' } {
		guest := os.real_path('build/pcn-' + short + '-2')
		receipt := json2.decode[Receipt](os.read_file(guest + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.scenario == 'packages-catalog-normalize' && receipt.artifacts.len == 7
		mut paths := {'kernel': guest + '/kernel', 'guest-init': guest + '/guest/init', 'serial-log': guest + '/packages-catalog-normalize/serial.log'}
		for name in ['catalog-normalize', 'catalog', 'composition', 'release']! { paths[name] = guest + '/guest/root/usr/share/package-fixtures/' + name }
		for item in receipt.artifacts { actual := pin(paths[item.role])!; assert actual.bytes == item.bytes && actual.sha256 == item.sha256, item.role; artifacts << actual }
		prior := json2.decode[Receipt](os.read_file('tests/packages/results/2026-10-16/software-installed-' + architecture + '.json')!)!
		assert receipt.artifacts[0].sha256 == prior.artifacts.filter(it.role == 'kernel')[0].sha256
		serial := os.read_file(guest + '/packages-catalog-normalize/serial.log')!
		assert serial.contains('HWTEST PASS packages-catalog-normalize') && serial.count('CATALOG NORMALIZE PROCESS ') == 4
		assert serial.count('functional-cycles=16 PASS') == 16 && !serial.contains('HWTEST FAIL') && !serial.contains('V panic:')
		qmp := os.read_file(guest + '/packages-catalog-normalize/qmp.log')!; assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
		for suffix, source in { architecture + '.json': guest + '/qualification.json', architecture + '.serial.txt': guest + '/packages-catalog-normalize/serial.log', architecture + '.qmp.txt': guest + '/packages-catalog-normalize/qmp.log' } {
			os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
		}
		for path in ['guest/init.c', 'guest/build.log', 'guest/program-0/catalog-normalize.c', 'guest/program-1/catalog.c', 'guest/program-2/composition.c', 'guest/program-3/release.c'] { artifacts << pin(guest + '/' + path)! }
	}
	for suffix, source in {
		'host.json': host + '/qualification.json', 'memory.txt': host + '/tracked-run.txt', 'core.txt': host + '/catalog_normalize-run.txt',
		'asan.txt': host + '/catalog_normalize-sanitize-run.txt', 'release-asan.txt': host + '/release-sanitize-run.txt', 'composition-asan.txt': host + '/composition-sanitize-run.txt',
		'cli.txt': host + '/distribution-cli-run.txt', 'baseline.txt': work + '/baseline.txt', 'baseline.json': work + '/baseline.json',
		'baseline-catalog.v.txt': work + '/baseline-catalog.v', 'baseline-release.v.txt': work + '/baseline-release.v',
		'baseline-model.v.txt': work + '/baseline-model.v', 'baseline-search.v.txt': work + '/baseline-resolve_search.v', 'baseline-fixture.v.txt': work + '/baseline-catalog_normalize_test.v',
		'first-aarch64.txt': work + '/guest-aarch64.txt', 'first-x86_64.txt': work + '/guest-x86_64.txt',
		'guest.v': work + '/guest.v', 'capture.v': work + '/capture.v', 'finish.v': work + '/finish.v', 'retain.v': work + '/retain.v' } {
		os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
	}
	for check in checks.checks { artifacts << pin(host + '/' + check.name + '.txt')! }
	for name in ['list-aarch64', 'list-x86_64', 'refuse-inputs', 'refuse-existing'] { artifacts << pin(work + '/' + name + '.txt')! }
	for name in ['vinix-package', 'catalog_normalize', 'catalog', 'composition', 'release', 'publisher_schema', 'catalog_decode', 'native_profile', 'sqlite_profile', 'ffmpeg_profile', 'wine_profile', 'apple_profile', 'resolve_search', 'tracked', 'distribution-cli', 'catalog_normalize-sanitize', 'release-sanitize', 'composition-sanitize'] { artifacts << pin(host + '/' + name)! }
	for path in [work + '/controller', work + '/host', work + '/guest', work + '/capture', work + '/finish', 'build/package-launch-transport-work/cross-cc',
		'/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc', '/opt/homebrew/bin/qemu-system-aarch64', '/opt/homebrew/bin/qemu-system-x86_64'] { artifacts << pin(path)! }
	mut source_paths := []string{}
	for directory in ['tools/packages', 'tools/accounts', 'tools/keyring', 'tools/security-events', 'compat/ios', 'tests/packages/catalog-normalize-guest', 'tests/packages/applefixture', 'tests/packages/elffixture', 'tests/hardware-platform/hwhost'] { source_paths << os.walk_ext(directory, '.v') }
	for directory in ['compat/ios', 'tools/packages'] { for suffix in ['.h', '.S'] { source_paths << os.walk_ext(directory, suffix) } }
	source_paths << ['tests/packages/catalog-normalize-check.v', 'tests/packages/catalog-normalize-check.md', 'tests/packages/catalog-normalize-runtime-check.v',
		'tests/packages/distribution-cli.v', 'tests/packages/catalog-decode-check.md', 'desktop/tools/tests/heap_tracker.h',
		'tools/packages/README.md', 'docs/application-distribution.md']
	source_paths.sort(); mut sources := []Pin{}; for path in source_paths { sources << pin(path)! }
	prior_sources := json2.decode[Ledger](os.read_file('tests/packages/results/2026-10-16/composition-target-toolchain.json')!)!
	changed := ['tools/packages/pkgcore/catalog.v', 'tools/packages/pkgcore/release.v', 'tools/packages/pkgcore/composition_test.v', 'tools/packages/README.md', 'docs/application-distribution.md']
	for source in prior_sources.sources { if source.path in changed { continue }; actual := pin(source.path)!; assert actual.sha256 == source.sha256 && actual.bytes == source.bytes, source.path }
	compiler := pin(os.real_path('build/package-release-work/v-toolchain/v'))!; assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{
		scope: 'Catalog normalization and structural release-closure scratch: legacy measured probe, thirty-five final host checks including 16000 independently tracked validations and three sanitizer suites, four controller guards, fresh AArch64/x86-64 functional guests with signed composed maintenance; existing kernels pinned to installed-root qualification. Complete publisher result lifetimes and production/graphical/device acceptance remain open.',
		compiler: compiler, sources: sources, artifacts: artifacts }) + '\n')!
	println('Verified baseline, thirty-five final host checks, sixteen zero-retention cases, two seven-artifact guests, normal shutdown and ' + sources.len.str() + ' source pins')
}
