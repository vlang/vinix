module main

import crypto.sha256
import json2
import os
import time

struct Pin { path string bytes u64 sha256 string }
struct Check { name string code int seconds f64 }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { format int architecture string seconds f64 platform string boots int artifacts []Artifact }
struct Proof { format int image string files []Artifact }
struct Ledger { format int = 1 baseline string = '5aeffd936' completed_at i64 compiler Pin sources []Pin evidence []Pin scope string }
const work = 'build/package-release-audit-work'
const prefix = 'tests/packages/results/2026-10-16/release-audit-'
const owned = ['desktop/software_deployment.v', 'desktop/software_release.v',
	'tests/accounts/guest/package_installed_image.v', 'tests/accounts/guest/package_software_persistence.v',
	'tests/packages/native-catalog-check.v', 'tests/packages/software_image_fixture.v', 'tests/packages/software_release_fixture.v',
	'tools/packages/SDK.md', 'tools/packages/README.md', 'docs/application-distribution.md', 'roadmap.md',
	'tests/packages/image-catalog-check.md', 'tests/packages/software-installed-check.md', 'tests/packages/release-audit-check.md']
const release = '/usr/share/vinix-packages/applications.json'
const catalog_marker = 'SOFTWARE IMAGE staged-release-catalog discovered full-set review separate administrator approval exact offline install PASS'
const disk_marker = 'PACKAGE INSTALLED RELEASE exact declaration disk identity mode digest PASS'
const audits = ['initial-empty installed=absent', 'initial-installed installed=1.0.0', 'standard-account installed=1.0.0',
	'cold-upgrade installed=1.0.0', 'cold-upgraded installed=1.1.0', 'cold-maintain installed=1.1.0',
	'cold-rollback installed=1.0.0', 'cold-removed installed=absent', 'cold-reinstalled installed=1.1.0', 'cold-reopen installed=1.1.0']

fn pin(path string) !Pin {
	mut file := os.open(path)!; defer { file.close() }
	mut hash := sha256.new(); mut buffer := []u8{len: 1024 * 1024}; mut digest := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); buffer.free(); digest.free() } }
	mut size := u64(0)
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		hash.write(unsafe { buffer[..n] })!; size += u64(n)
	}
	hash.checksum_into(mut digest)
	return Pin{ path: path, bytes: size, sha256: digest.hex() }
}
fn good(text string) {
	for marker in ['V panic:', 'HWTEST FAIL', 'ERROR: AddressSanitizer', 'runtime error:']! { assert !text.contains(marker), marker }
}
fn matches(path string, artifact Artifact) !Pin {
	actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256, path
	return actual
}
fn retain() ! {
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	mut checks := json2.decode[[]Check](os.read_file(work + '/ui-results.json')!)!
	checks << json2.decode[[]Check](os.read_file(work + '/asan-results.json')!)!
	assert checks.len == 14 && checks.all(it.code == 0)
	mut evidence := []Pin{}
	for check in checks { good(os.read_file(work + '/' + check.name + '.txt')!); evidence << pin(work + '/' + check.name + '.txt')! }
	ui := os.read_file(work + '/ui-functional.txt')!; assert ui.contains('Software release audit: visible ordinary read')
	memory := os.read_file(work + '/ui-release-memory.txt')!; assert memory.contains('zero tracked bytes PASS')
	driver := os.read_file(work + '/distribution.txt')!; good(driver)
	assert driver.contains('Software distribution checks passed') && driver.contains('Software release audit: visible ordinary read')
	os.write_file(prefix + 'host.json', json2.encode(checks) + '\n')!
	os.write_file(prefix + 'ui.txt', ui)!
	os.write_file(prefix + 'memory.txt', memory + os.read_file(work + '/ui-navigation-memory.txt')! + os.read_file(work + '/ui-memory.txt')!)!
	os.write_file(prefix + 'asan.txt', 'ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1\nSoftware controller instrumented; session broker compiled normally.\n\n'
		+ os.read_file(work + '/asan-functional.txt')! + os.read_file(work + '/asan-release-memory.txt')! + os.read_file(work + '/asan-memory.txt')! + os.read_file(work + '/asan-navigation-memory.txt')!)!
	os.write_file(prefix + 'driver.txt', driver)!
	mut summary := 'Fourteen focused Software compile/run checks passed, including ASan/UBSan with leak detection disabled. Maintained Software functional suite, 27 allocation modes, both full Linux desktop target typechecks and launcher checks passed.\n'
	mut artifact_count := 0
	for kind in ['installed', 'persistent']! {
		for architecture in ['aarch64', 'x86_64']! {
			short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
			base := 'build/praudit-' + kind + '-' + short + '-3'; root := base + '/guest/root'
			receipt := json2.decode[Receipt](os.read_file(base + '/qualification.json')!)!
			assert receipt.format == 1 && receipt.architecture == architecture && receipt.boots == 4
			assert receipt.platform == if kind == 'installed' { 'qemu-vjfs-installed-root' } else { 'qemu-ext2-retained-subtrees' }
			assert receipt.artifacts.any(it.role == 'image' + release)
			for artifact in receipt.artifacts {
				path := match artifact.role {
					'kernel' { base + '/kernel' }
					'guest-init' { base + '/guest/init' }
					'input-build-record' { 'build/package-native-catalog-work/inputs/build.json' }
					'initial-blank-system-disk' { base + '/initial.raw' }
					'initial-ext2' { base + '/initial.ext2' }
					'final-installed-system-disk' { base + '/native/system.vjfs' }
					'final-ext2' { base + '/native/packages.ext2' }
					'serial-log' { base + '/native/serial.log' }
					'qmp-log' { base + '/native/qmp.log' }
					'serial-log-2', 'serial-log-3', 'serial-log-4' { base + '/native/serial-' + artifact.role.all_after_last('-') + '.log' }
					else {
						if artifact.role.starts_with('input/') { base + '/verified-inputs/usr/share/native-catalog/' + artifact.role[6..] }
						else if artifact.role.starts_with('image/') { root + '/' + artifact.role[6..] }
						else { root + '/' + artifact.role }
					}
				}
				evidence << matches(path, artifact)!; artifact_count++
			}
			kernel := receipt.artifacts.filter(it.role == 'kernel')[0]
			assert kernel.sha256 == if short == 'arm' { 'cfa3788c594b308c6009bee49d9e08a92feb5c23fe3b710ab5142427fc1f2d7e' }
				else { 'a989a9b1aff3db4260fe435336d3fba6120450992a96ab0fccbab27c38dce5b1' }
			mut serial := ''
			name := prefix + kind + '-' + architecture
			os.cp(base + '/qualification.json', name + '.json')!; os.cp(base + '/stage.log', name + '.stage.txt')!
			for boot in 1 .. 5 {
				path := base + '/native/' + if boot == 1 { 'serial.log' } else { 'serial-' + boot.str() + '.log' }
				text := os.read_file(path)!; good(text)
				assert text.contains('HWTEST PASS packages-software-' + (if kind == 'installed' { 'installed' } else { 'persistence' }))
				assert text.contains('PACKAGE ' + (if kind == 'installed' { 'INSTALLED' } else { 'COLD' }) + ' BOOT ' + boot.str() + ' ')
				if kind == 'installed' { assert text.contains(disk_marker) && !text.contains('sysdisk: running from memory') && !text.contains('sysdisk: updating the system on') }
				for secret in ['alex has a password', 'sam has another', 'incorrect fixture password']! { assert !text.contains(secret) }
				serial += text; os.cp(path, name + '.boot-' + boot.str() + '.serial.txt')!
			}
			assert serial.contains(catalog_marker)
			for audit in audits { assert serial.contains('SOFTWARE RELEASE audit ' + audit + ' exact-baseline unchanged-state ordinary-read PASS'), audit }
			qmp := os.read_file(base + '/native/qmp.log')!
			assert qmp.count('"SHUTDOWN"') == 4 && qmp.count('"guest": true') == 4
			os.cp(base + '/native/qmp.log', name + '.qmp.txt')!
			assert os.read_file(base + '/publisher/image-config.json')! == os.read_file(root + '/etc/vinix-packages/config.json')!
			if kind == 'installed' {
				proof_path := root + '/usr/share/package-fixtures/installed-image.json'
				proof := json2.decode[Proof](os.read_file(proof_path)!)!
				assert proof.format == 1 && proof.image == 'vinix-packages-installed-sdk-1' && proof.files.len == 10
				assert proof.files.any(it.role == release)
				for file in proof.files { evidence << matches(if file.role == '/sbin/init' { base + '/guest/init' } else { root + file.role }, file)! }
				os.cp(proof_path, name + '.proof.json')!
			}
			for file in os.ls(base + '/software-source')! {
				original := if file == 'main.v' { 'tests/packages/software_image_fixture.v' } else if file == 'terminal_fixture.v' { 'tests/packages/software_terminal_fixture.v' } else { 'desktop/' + file }
				assert pin(base + '/software-source/' + file)!.sha256 == pin(original)!.sha256
			}
			for path in ['publisher/image-config.json', 'publisher/image-applications.json', 'package-stage', 'software-build/software-image.c', 'guest/init.c']! { evidence << pin(base + '/' + path)! }
			summary += kind + ' ' + architecture + ' PASS ' + receipt.seconds.str() + 's; four boots, ten release audits, ' + receipt.artifacts.len.str() + ' artifacts\n'
		}
	}
	os.write_file(prefix + 'summary.txt', summary)!
	os.write_file(prefix + 'attempts.txt', 'An initial controller build hit the pinned V compiler constant-array spread lowering bug (const string[10] has no .data). Returning the marker array from a helper fixed the host build; no target behavior changed.\n\nThe first four guest attempts failed in initial-empty audit qualification because the fixture required an empty diagnostics panel after its intentional bad-password attempt. Software correctly retains that diagnostic. The corrected fixture requires unchanged diagnostic count, exact audit match/drift results, and unchanged state bytes.\n\nAttempt 2 passed both four-boot ext2 workflows and installed AArch64. Installed x86 completed all four workflows but the host refused because the added root-proof marker used stdout (the display console on that target) rather than the harness serial writer. The marker now uses Test.say on both targets. Attempt 3 reruns all four workflows on fresh disks with unchanged final product and fixture sources.\n')!
	for kind in ['installed', 'persistent']! {
		for architecture in ['aarch64', 'x86_64']! {
			os.cp(work + '/guest-' + kind + '-' + architecture + '-1.txt', prefix + 'attempt-' + kind + '-' + architecture + '.txt')!
			os.cp(work + '/guest-' + kind + '-' + architecture + '-2.txt', prefix + 'attempt-' + kind + '-' + architecture + '-2.txt')!
		}
	}
	for name in ['guest.v', 'checks.v', 'retain.v']! { os.cp(work + '/' + name, prefix + name)! }
	mut paths := owned.clone()
	for directory in ['tools/packages', 'tools/accounts', 'tools/security-events', 'tools/keyring', 'desktop/workflowcore', 'desktop/packagecore', 'desktop/sessioncore', 'desktop/sessionipc', 'desktop/sessiondaemon', 'desktop/serviceprocess', 'tests/accounts/guest', 'tests/hardware-platform/hwhost']! {
		for extension in ['.v', '.h', '.c']! { paths << os.walk_ext(directory, extension).filter(!it.contains('.v3cc.') && !it.contains('/.cache/')) }
	}
	for name in os.ls('desktop')! { if name.ends_with('.v') || name.ends_with('.h') || name.ends_with('.vml') { paths << 'desktop/' + name } }
	for name in os.ls('tests/packages')! { if name.starts_with('software_') && name.ends_with('_fixture.v') { paths << 'tests/packages/' + name } }
	paths << os.walk_ext('build/package-view-reader-work/desktop/modules', '.v')
	paths << ['tests/packages/distribution-check.v', 'desktop/tools/tests/heap_tracker.h', work + '/checks.v', work + '/guest.v', work + '/retain.v']
	for stage in ['ui-sources-qualified', 'asan-sources-qualified']! {
		for file in os.ls(work + '/' + stage)! {
			original := if file == 'main.v' { 'tests/packages/software_fixture.v' } else if file.ends_with('_fixture.v') { 'tests/packages/' + file } else { 'desktop/' + file }
			actual := work + '/' + stage + '/' + file
			assert pin(actual)!.sha256 == pin(original)!.sha256; evidence << pin(actual)!
		}
	}
	for name in ['checks', 'guest', 'controller', 'ui', 'asan', 'ui-results.json', 'asan-results.json', 'distribution.txt']! { evidence << pin(work + '/' + name)! }
	evidence << pin('build/package-image-catalog-work/distribution')!
	paths.sort(); mut sources := []Pin{}; mut seen := map[string]bool{}
	for path in paths { if path !in seen { seen[path] = true; sources << pin(path)! } }
	mut commit_paths := owned.clone()
	for file in os.ls(os.dir(prefix))! {
		if file.starts_with('release-audit-') && !file.ends_with('toolchain.json') { path := os.dir(prefix) + '/' + file; commit_paths << path; evidence << pin(path)! }
	}
	commit_paths << prefix + 'toolchain.json'
	os.write_file(work + '/owned-paths.json', json2.encode(commit_paths) + '\n')!
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ completed_at: time.now().unix(), compiler: compiler, sources: sources, evidence: evidence,
		scope: 'Ordinary read-only release catalog audit; fixed baseline, literal path, late picker, missing/alias refusal and zero retained warmed UI buffers. Four fresh TCG workflows, sixteen boots: both installed VJFS roots and ext2 retained subtrees. Exact declaration bytes/disk identity/mode and ten release audit transitions per workflow, one approved release deployment, real native apps and private data, reviewed upgrade/rollback/removal/cached reinstall with payload media absent. Fourteen focused host checks, Software functional/all 27 allocation modes, both full Linux desktop typechecks/launcher checks, UI ASan/UBSan with leak detection disabled. Existing unchanged qualified kernels. Headless UI trees; no full compositor/firmware/production-catalog/foreign-runtime/device/crash acceptance or whole-service allocation claim.' }) + '\n')!
	println(summary + 'Verified ' + artifact_count.str() + ' receipt artifacts; ' + sources.len.str() + ' source pins and ' + evidence.len.str() + ' evidence pins')
}
fn main() { retain() or { eprintln(err); exit(1) } }
