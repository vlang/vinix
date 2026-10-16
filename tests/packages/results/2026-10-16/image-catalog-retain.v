module main
import crypto.sha256
import json2
import os
import time

struct Pin { path string bytes u64 sha256 string }
struct Check { name string code int seconds f64 }
struct CoreCheck { name string seconds f64 }
struct CoreHost { compiler_sha256 string checks []CoreCheck }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string seconds f64 artifacts []Artifact }
struct Ledger { format int = 1 baseline string = '984f537c2' completed_at i64 compiler Pin sources []Pin evidence []Pin scope string }
const work = 'build/package-image-catalog-work'
const prefix = 'tests/packages/results/2026-10-16/image-catalog-'
const owned = ['desktop/software_app.v', 'desktop/software_deployment.v', 'desktop/software_release.v',
	'tools/packages/pkgcore/image_catalog.v', 'tools/packages/pkgcore/image_check.v', 'tools/packages/pkgcore/image_applications_test.v',
	'tools/packages/pkgprotocol/image.v', 'tools/packages/stage.v', 'tests/packages/software_release_fixture.v',
	'tests/packages/software_fixture.v', 'tests/packages/software_image_fixture.v', 'tests/packages/distribution-check.v',
	'tests/packages/native-catalog-check.v', 'tests/packages/image-export-runtime-check.v', 'tools/packages/README.md',
	'tools/packages/SDK.md', 'docs/application-distribution.md', 'roadmap.md', 'examples/package-catalog/README.md', 'tests/packages/image-catalog-check.md']
const catalog_marker = 'SOFTWARE IMAGE staged-release-catalog discovered full-set review separate administrator approval exact offline install PASS'
const memory_marker = 'Software release catalog: 1000 full/compact form, discovery, missing-file refusal, navigation and retirement cycles retain zero tracked bytes PASS'

fn pin(path string) !Pin {
	data := os.read_bytes(path)!; defer { unsafe { data.free() } }
	return Pin{ path: path, bytes: u64(data.len), sha256: sha256.sum(data).hex() }
}
fn good(value string) {
	assert !value.contains('V panic:') && !value.contains('HWTEST FAIL') && !value.contains('ERROR: AddressSanitizer') && !value.contains('runtime error:')
}
fn matching(path string, artifact Artifact) !Pin {
	actual := pin(path)!
	assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256, path
	return actual
}

fn retain() ! {
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	host := json2.decode[CoreHost](os.read_file(work + '/host-qualified/qualification.json')!)!
	assert host.checks.len == 32 && host.compiler_sha256 == compiler.sha256
	mut checks := json2.decode[[]Check](os.read_file(work + '/ui-results.json')!)!
	checks << json2.decode[[]Check](os.read_file(work + '/asan-results.json')!)!
	assert checks.len == 14 && checks.all(it.code == 0)
	for check in checks { good(os.read_file(work + '/' + check.name + '.txt')!) }
	for check in host.checks { good(os.read_file(work + '/host-qualified/' + check.name + '.txt')!) }
	driver := os.read_file(work + '/distribution.txt')!; good(driver)
	assert driver.contains('Software distribution checks passed') && driver.contains(memory_marker) && !driver.contains('error:')
	ui := os.read_file(work + '/ui-functional.txt')!
	assert ui.contains('Software release catalog: optional ordinary-file discovery')
	memory := os.read_file(work + '/ui-release-memory.txt')! + os.read_file(work + '/ui-memory.txt')! + os.read_file(work + '/ui-navigation-memory.txt')!
	assert memory.contains(memory_marker)
	asan := 'ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1\nUI controller and core image fixture instrumented; session broker compiled normally.\n\n' + os.read_file(work + '/asan-functional.txt')! + '\n' + os.read_file(work + '/asan-release-memory.txt')! + os.read_file(work + '/asan-memory.txt')! + os.read_file(work + '/asan-navigation-memory.txt')! + '\nImage/catalog/publishing checks:\n' + os.read_file(work + '/host-qualified/image_applications-sanitize-run.txt')!
	assert asan.contains(memory_marker)
	os.cp(work + '/host-qualified/qualification.json', prefix + 'core-host.json')!
	os.write_file(prefix + 'ui-host.json', json2.encode(checks) + '\n')!
	os.write_file(prefix + 'ui.txt', ui)!
	os.write_file(prefix + 'memory.txt', memory)!
	os.write_file(prefix + 'asan.txt', asan)!
	os.write_file(prefix + 'driver.txt', driver)!
	os.cp(work + '/host-qualified/image_applications-run.txt', prefix + 'core.txt')!
	mut summary := '32 host package/cache/CLI compile-run checks and 14 focused Software compile-run checks passed. Maintained Software functional suite, all 27 allocation modes, both full desktop Linux target typechecks and launcher checks passed.\n'
	mut evidence := []Pin{}
	mut artifact_count := 0
	for kind in ['core', 'software']! {
		for architecture in ['aarch64', 'x86_64']! {
			short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
			base := 'build/picat-' + kind + '-' + short + '-' + if kind == 'core' { '1' } else { '2' }
			root := base + '/guest/root'
			receipt := json2.decode[Receipt](os.read_file(base + '/qualification.json')!)!
			assert receipt.architecture == architecture
			if kind == 'core' { assert receipt.artifacts.len == 13 }
			else {
				assert receipt.artifacts.len > 40
				assert receipt.artifacts.any(it.role == 'image/usr/share/vinix-packages/applications.json')
			}
			for artifact in receipt.artifacts {
				path := match artifact.role {
					'kernel' { base + '/kernel' }
					'guest-init' { base + '/guest/init' }
					'input-build-record' { 'build/package-native-catalog-work/inputs/build.json' }
					'serial-log' { base + '/' + if kind == 'core' { 'packages-image-export/serial.log' } else { 'native/serial.log' } }
					'qmp-log' { base + '/native/qmp.log' }
					else {
						if kind == 'core' { root + '/usr/share/package-fixtures/' + artifact.role }
						else if artifact.role.starts_with('input/') { base + '/verified-inputs/usr/share/native-catalog/' + artifact.role[6..] }
						else if artifact.role.starts_with('image/') { root + '/' + artifact.role[6..] }
						else { root + '/' + artifact.role }
					}
				}
				evidence << matching(path, artifact)!; artifact_count++
			}
			kernel := receipt.artifacts.filter(it.role == 'kernel')[0]
			assert kernel.sha256 == if short == 'arm' { 'cfa3788c594b308c6009bee49d9e08a92feb5c23fe3b710ab5142427fc1f2d7e' }
				else { 'a989a9b1aff3db4260fe435336d3fba6120450992a96ab0fccbab27c38dce5b1' }
			scenario := if kind == 'core' { 'packages-image-export' } else { 'native' }
			serial := os.read_file(base + '/' + scenario + '/serial.log')!; good(serial)
			assert serial.contains(if kind == 'core' { 'HWTEST PASS packages-image-export' } else { catalog_marker })
			for secret in ['alex has a password', 'sam has another', 'incorrect fixture password']! { assert !serial.contains(secret) }
			qmp := os.read_file(base + '/' + scenario + '/qmp.log')!
			assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
			name := prefix + kind + '-' + architecture
			for suffix, input in {'.json': base + '/qualification.json', '.serial.txt': base + '/' + scenario + '/serial.log', '.qmp.txt': base + '/' + scenario + '/qmp.log'} { os.cp(input, name + suffix)! }
			if kind == 'software' {
				os.cp(base + '/stage.log', name + '.stage.txt')!
				assert os.read_file(base + '/publisher/image-config.json')! == os.read_file(root + '/etc/vinix-packages/config.json')!
				for item in ['publisher/image-config.json', 'publisher/image-applications.json', 'package-stage', 'software-build/software-image.c']! { evidence << pin(base + '/' + item)! }
				for file in os.ls(base + '/software-source')! {
					original := if file == 'main.v' { 'tests/packages/software_image_fixture.v' } else if file == 'terminal_fixture.v' { 'tests/packages/software_terminal_fixture.v' } else { 'desktop/' + file }
					assert pin(base + '/software-source/' + file)!.sha256 == pin(original)!.sha256
				}
			}
			summary += kind + ' ' + architecture + ' PASS ' + receipt.seconds.str() + 's, ' + receipt.artifacts.len.str() + ' receipt artifacts\n'
		}
	}
	os.write_file(prefix + 'host.txt', summary)!
	os.write_file(prefix + 'attempts.txt', 'The first warmed UI check retained 1408000 bytes in 1000 chooser lifecycle iterations after adding release discovery. The standard is_file/is_link helpers retained status scratch. Discovery now uses one non-following lstat call with stack scratch. Fresh UI/core sanitizers, all 27 maintained allocation modes and both target typechecks passed after correction.\n\nInitial allocation output:\n' + os.read_file(work + '/ui-checks.txt')! + '\nThe first native image builders emitted a format-1 requirement with an unwanted locked field by using the format-2 lock type. Strict staging refused before publication or guest boot on both hosts. A dedicated format-1 input record now supplies the three reviewed roots. Fresh builds and guests passed.\n\nInitial native build refusals:\n' + os.read_file(work + '/guest-software-aarch64-1.txt')! + os.read_file(work + '/guest-software-x86_64-1.txt')!)!
	for item in ['guest.v', 'checks.v', 'retain.v']! { os.cp(work + '/' + item, prefix + item)! }
	mut paths := owned.clone()
	for directory in ['tools/packages', 'tools/accounts', 'tools/security-events', 'tools/keyring', 'desktop/workflowcore', 'desktop/packagecore', 'desktop/sessioncore', 'desktop/sessionipc', 'desktop/sessiondaemon', 'desktop/serviceprocess', 'tests/accounts/guest', 'tests/hardware-platform/hwhost'] {
		for extension in ['.v', '.h', '.c']! {
			paths << os.walk_ext(directory, extension).filter(!it.contains('.v3cc.') && !it.contains('/.cache/'))
		}
	}
	for name in os.ls('desktop')! { if name.ends_with('.v') || name.ends_with('.h') || name.ends_with('.vml') { paths << 'desktop/' + name } }
	for name in os.ls('tests/packages')! { if name.starts_with('software_') && name.ends_with('_fixture.v') { paths << 'tests/packages/' + name } }
	paths << os.walk_ext('build/package-view-reader-work/desktop/modules', '.v')
	paths << ['tests/packages/image-export-check.v', 'desktop/tools/tests/heap_tracker.h', 'build-support/cachekey/desktop.v', 'build-support/cachekey/desktop_test.v', work + '/guest.v', work + '/checks.v', work + '/retain.v']
	for stage in ['ui-sources-qualified', 'asan-sources-qualified']! {
		for file in os.ls(work + '/' + stage)! {
			actual := work + '/' + stage + '/' + file
			original := if file == 'main.v' { 'tests/packages/software_fixture.v' } else if file.ends_with('_fixture.v') { 'tests/packages/' + file } else { 'desktop/' + file }
			assert pin(actual)!.sha256 == pin(original)!.sha256
			evidence << pin(actual)!
		}
	}
	for name in ['host', 'guest', 'checks', 'distribution', 'core-controller', 'software-controller', 'ui', 'asan', 'ui-results.json', 'asan-results.json']! { evidence << pin(work + '/' + name)! }
	for check in checks { evidence << pin(work + '/' + check.name + '.txt')! }
	for check in host.checks { evidence << pin(work + '/host-qualified/' + check.name + '.txt')! }
	mut commit_paths := owned.clone()
	for file in os.ls(os.dir(prefix))! {
		if file.starts_with('image-catalog-') && !file.ends_with('toolchain.json') {
			path := os.dir(prefix) + '/' + file; commit_paths << path; evidence << pin(path)!
		}
	}
	commit_paths << prefix + 'toolchain.json'
	os.write_file(work + '/owned-paths.json', json2.encode(commit_paths) + '\n')!
	paths.sort(); mut sources := []Pin{}; mut seen := map[string]bool{}
	for path in paths { if path !in seen { seen[path] = true; sources << pin(path)! } }
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ completed_at: time.now().unix(), compiler: compiler, sources: sources, evidence: evidence,
		scope: 'Release image application declarations: captured exact format-2 locks, reproducible digest/bytes/action reports, publication after matching signed bundle/configuration, preservation and failure/race cleanup. Real ordinary Software full-set review, separate administrator approval and native SDK launch/maintenance on both guests. Thirty-two host core/cache/CLI checks, fourteen focused UI checks, ASan/UBSan with leak detection disabled, all 27 maintained allocation modes including 1000 zero-retention release discovery/full/compact cycles, both full Linux desktop target typechecks and launcher checks. Four fresh TCG guests use unchanged qualified kernels. Headless UI trees; no full compositor presentation, persistent/installed-root requalification, production publisher/catalog migration, whole-service allocation freedom or full section14 acceptance claim.' }) + '\n')!
	println('Retained ' + sources.len.str() + ' source pins, ' + evidence.len.str() + ' evidence pins and ' + artifact_count.str() + ' guest receipt artifacts; ' + commit_paths.len.str() + ' owned paths')
}
fn main() { retain() or { eprintln(err); exit(1) } }
