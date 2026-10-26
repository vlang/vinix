// SPDX-License-Identifier: GPL-2.0-or-later
// Read back the complete original host build bundle; this is not an ART test.
module main

import crypto.sha256
import json2
import os

const packages = ['client', 'companion', 'blocked', 'disabled']
const operations = ['compile', 'link', 'assemble', 'zip', 'sign', 'verify', 'badging']
const pass_marker = 'SERVICE-ACCESS-PASS declared enabled application-enabled exported permission requested-permission same-package application-once classloader resources intent-copy bind start cached-invisible no-denied-callback'

struct FixtureBuild {
mut:
	argv               []string
	source_revision    string
	inputs_sha256      map[string]string
	artifacts_sha256   map[string]string
	java_version       string
	apks_sha256        map[string]string
	client_package     string
	companion_packages []string
	pass_marker        string
}

struct CommandReceipt {
mut:
	argv   []string
	status int
	output string
}

fn file_hash(path string) string {
	stat := os.stat(path) or { panic(err) }
	if stat.get_filetype() != .regular { panic('hash input must be a regular file: ' + path) }
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn require_hash(path string, expected string) {
	if expected.len != 64 || expected.bytes().any(it !in '0123456789abcdef'.bytes()) {
		panic('invalid SHA256 for ' + path)
	}
	if file_hash(path) != expected { panic('hash mismatch: ' + path) }
}

fn output_files(path string) []string {
	mut files := []string{}
	for name in os.ls(path) or { panic(err) } {
		item := os.join_path(path, name)
		stat := os.lstat(item) or { panic(err) }
		match stat.get_filetype() {
			.directory { files << output_files(item) }
			.regular { files << item }
			.symbolic_link { panic('unexpected bundle symlink: ' + item) }
			else { panic('unexpected bundle file type: ' + item) }
		}
	}
	return files
}

fn exact_set(label string, actual []string, expected []string) {
	mut a := actual.clone()
	mut e := expected.clone()
	a.sort()
	e.sort()
	if a != e { panic('${label} inventory mismatch:\nactual ${a}\nexpected ${e}') }
}

fn expected_artifacts() []string {
	mut names := ['fixture.p12', 'inputs/generator', 'inputs/service-access-fixture.v',
		'commands/keytool.json']
	for package_name in packages {
		for item in ['AndroidManifest.xml', 'classes.dex', 'probe.apk', 'probe.apk.idsig',
			'res/values/values.xml', 'resources.zip', 'unsigned.apk'] {
			names << package_name + '/' + item
		}
		mut classes := ['App', 'DeniedConnection']
		if package_name == 'client' {
			classes << ['Base', 'Main', 'Connection', 'Private', 'Protected', 'Exported']
		} else if package_name == 'companion' {
			classes << ['Base', 'Allowed']
		} else {
			classes << ['Missing', 'Disabled', 'Private', 'Protected', 'RequestedPermission', 'Target']
		}
		for class_name in classes {
			names << '${package_name}/smali/org/vinix/serviceaccess/${class_name}.smali'
		}
		for operation in operations { names << 'commands/${package_name}-${operation}.json' }
	}
	if names.len != 88 { panic('checker artifact inventory error') }
	return names
}

fn read_command(bundle string, name string) CommandReceipt {
	command := json2.decode[CommandReceipt](os.read_file(bundle + '/commands/' + name + '.json') or {
		panic(err)
	}) or { panic(err) }
	if command.status != 0 || command.argv.len == 0 { panic('failed/empty command: ' + name) }
	return command
}

fn input_path(repo string, path string) string {
	return os.abs_path(if os.is_abs_path(path) { path } else { os.join_path(repo, path) })
}

fn check_bundle(bundle string) {
	bundle_stat := os.lstat(bundle) or { panic(err) }
	if bundle_stat.get_filetype() != .directory { panic('bundle must be a regular directory') }
	build_path := bundle + '/build.json'
	build_stat := os.lstat(build_path) or { panic(err) }
	if build_stat.get_filetype() != .regular { panic('build.json must be a regular file') }
	build := json2.decode[FixtureBuild](os.read_file(build_path) or { panic(err) }) or {
		panic(err)
	}
	if build.argv.len != 7 || build.source_revision.len != 40
		|| build.source_revision.bytes().any(it !in '0123456789abcdef'.bytes())
		|| build.java_version == '' || build.client_package != 'org.vinix.serviceaccess.client'
		|| build.companion_packages != ['org.vinix.serviceaccess.companion',
			'org.vinix.serviceaccess.blocked', 'org.vinix.serviceaccess.disabled']
		|| build.pass_marker != pass_marker {
		panic('unexpected fixture build metadata')
	}
	expected := expected_artifacts()
	exact_set('artifact map', build.artifacts_sha256.keys(), expected)
	mut expected_files := expected.clone()
	expected_files << 'build.json'
	exact_set('bundle files', output_files(bundle).map(it.all_after(bundle + '/')),
		expected_files)
	for name, hash in build.artifacts_sha256 { require_hash(bundle + '/' + name, hash) }

	// The generator preserves its source, binary and key in the bundle. Require
	// those original copies, so a later working-tree edit cannot substitute for
	// historical evidence. Uncopied tool inputs must remain at their pinned paths.
	sources := build.inputs_sha256.keys().filter(it.ends_with('/tests/native-android-ws/service-access-fixture.v'))
	if sources.len != 1 { panic('fixture source input missing or ambiguous') }
	source := sources[0]
	repo := os.dir(os.dir(os.dir(source)))
	original_out := input_path(repo, build.argv[1])
	generator := input_path(repo, build.argv[0])
	aapt := input_path(repo, build.argv[2])
	resources := input_path(repo, build.argv[3])
	tools := input_path(repo, build.argv[4])
	java := input_path(repo, build.argv[5])
	signer := input_path(repo, build.argv[6])
	keytool := os.join_path(os.dir(os.real_path(java)), 'keytool')
	key_command := read_command(bundle, 'keytool')
	zip_command := read_command(bundle, 'client-zip')
	if key_command.argv[0] != keytool { panic('keytool provenance mismatch') }
	zip := zip_command.argv[0]
	mut expected_inputs := [source, generator, aapt, resources, java, signer, keytool, zip,
		original_out + '/fixture.p12']
	for name in os.ls(tools) or { panic(err) } {
		path := os.join_path(tools, name)
		if os.is_file(path) { expected_inputs << path }
	}
	exact_set('input map', build.inputs_sha256.keys(), expected_inputs)
	for name, hash in build.inputs_sha256 {
		preserved := if name == source {
			bundle + '/inputs/service-access-fixture.v'
		} else if name == generator {
			bundle + '/inputs/generator'
		} else if name == original_out + '/fixture.p12' {
			bundle + '/fixture.p12'
		} else {
			name
		}
		require_hash(preserved, hash)
	}
	mut apk_names := []string{}
	mut command_names := ['keytool.json']
	for package_name in packages {
		apk := '${original_out}/${package_name}/probe.apk'
		apk_names << apk
		if build.apks_sha256[apk] != build.artifacts_sha256['${package_name}/probe.apk'] {
			panic('APK map disagrees with artifact map: ' + package_name)
		}
		for operation in operations {
			name := '${package_name}-${operation}'
			command_names << name + '.json'
			command := read_command(bundle, name)
			if operation == 'assemble' {
				if command.argv != [java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble',
					'--jobs', '2', '${original_out}/${package_name}/smali', '-o',
					'${original_out}/${package_name}/classes.dex'] || command.output != '' {
					panic('unexpected assembly receipt: ' + package_name)
				}
			} else if operation == 'verify' {
				if command.argv != [java, '-jar', signer, 'verify', '--verbose', apk]
					|| !command.output.contains('\nVerifies\n')
					|| !command.output.contains('Verified using v3 scheme (APK Signature Scheme v3): true\n')
					|| !command.output.contains('Number of signers: 1\n') {
					panic('signature verification absent: ' + package_name)
				}
			} else if operation == 'badging' {
				if command.argv != [aapt, 'dump', 'badging', apk]
					|| !command.output.contains("package: name='org.vinix.serviceaccess.${package_name}'")
					|| (package_name == 'client'
						&& !command.output.contains("launchable-activity: name='org.vinix.serviceaccess.Main'")) {
					panic('unexpected package/launcher badging: ' + package_name)
				}
			}
		}
	}
	exact_set('APK map', build.apks_sha256.keys(), apk_names)
	exact_set('command files', os.ls(bundle + '/commands') or { panic(err) }, command_names)
	if command_names.len != 29 { panic('checker command inventory error') }
	println('SERVICE-ACCESS-FIXTURE-HASHES PASS inputs=${build.inputs_sha256.len} artifacts=88 commands=29 all-status=0 empty-assemblies=4 v3-verifications=4')
	println('revision ' + build.source_revision)
	println('build.json ' + file_hash(build_path))
	println('source ' + file_hash(bundle + '/inputs/service-access-fixture.v'))
	current_source := os.join_path(os.dir(@FILE), 'service-access-fixture.v')
	println('current-source ' + file_hash(current_source))
	for package_name in packages {
		println(package_name + '/probe.apk ' + file_hash('${bundle}/${package_name}/probe.apk'))
	}
	println(build.pass_marker)
}

fn main() {
	if os.args.len == 4 && os.args[1] == '--self-test' {
		self_test(os.abs_path(os.args[2]), os.abs_path(os.args[3]))
		return
	}
	if os.args.len != 2 {
		panic('usage: check-service-access-fixture BUNDLE\n       check-service-access-fixture --self-test BUNDLE FRESH_OUTPUT')
	}
	check_bundle(os.abs_path(os.args[1]))
}

fn self_test(bundle string, out string) {
	if os.exists(out) { panic('self-test output must be fresh: ' + out) }
	check_bundle(bundle)
	before := file_hash(bundle + '/build.json')
	os.mkdir_all(out) or { panic(err) }
	for probe in ['missing-file', 'extra-file', 'symlink-file', 'fifo-file', 'changed-artifact',
		'missing-artifact-map', 'missing-input-map', 'nonzero-command', 'noisy-assembly',
		'failed-signature'] {
		probe_dir := out + '/' + probe
		os.cp_all(bundle, probe_dir, false) or { panic(err) }
		mut receipt := json2.decode[FixtureBuild](os.read_file(probe_dir + '/build.json') or {
			panic(err)
		}) or { panic(err) }
		mut expected_failure := ''
		if probe == 'missing-file' {
			os.rm(probe_dir + '/client/classes.dex') or { panic(err) }
			expected_failure = 'bundle files inventory mismatch'
		} else if probe == 'extra-file' {
			os.write_file(probe_dir + '/unexpected.txt', 'extra') or { panic(err) }
			expected_failure = 'bundle files inventory mismatch'
		} else if probe == 'symlink-file' {
			os.symlink(probe_dir + '/build.json', probe_dir + '/unexpected-link') or { panic(err) }
			expected_failure = 'unexpected bundle symlink'
		} else if probe == 'fifo-file' {
			created := os.exec(['mkfifo', probe_dir + '/unexpected-fifo'])
			if created.exit_code != 0 {
				panic('cannot create FIFO rejection probe: ' + created.output)
			}
			expected_failure = 'unexpected bundle file type'
		} else if probe == 'changed-artifact' {
			os.write_file(probe_dir + '/client/classes.dex', 'changed') or { panic(err) }
			expected_failure = 'hash mismatch:'
		} else if probe == 'missing-artifact-map' {
			receipt.artifacts_sha256.delete('client/classes.dex')
			os.rm(probe_dir + '/client/classes.dex') or { panic(err) }
			expected_failure = 'artifact map inventory mismatch'
		} else if probe == 'missing-input-map' {
			sources := receipt.inputs_sha256.keys().filter(it.ends_with('/tests/native-android-ws/service-access-fixture.v'))
			receipt.inputs_sha256.delete(sources[0])
			expected_failure = 'fixture source input missing or ambiguous'
		} else {
			name := if probe == 'nonzero-command' {
				'commands/client-compile.json'
			} else if probe == 'noisy-assembly' {
				'commands/client-assemble.json'
			} else {
				'commands/client-verify.json'
			}
			mut command := json2.decode[CommandReceipt](os.read_file(probe_dir + '/' + name) or {
				panic(err)
			}) or { panic(err) }
			if probe == 'nonzero-command' {
				command.status = 1
				expected_failure = 'failed/empty command: client-compile'
			} else if probe == 'noisy-assembly' {
				command.output = 'unexpected assembler diagnostic'
				expected_failure = 'unexpected assembly receipt: client'
			} else {
				command.output = command.output.replace('APK Signature Scheme v3): true',
					'APK Signature Scheme v3): false')
				expected_failure = 'signature verification absent: client'
			}
			os.write_file(probe_dir + '/' + name, json2.encode(command, prettify: true)) or {
				panic(err)
			}
			// Update this checksum so the probe reaches semantic receipt validation.
			receipt.artifacts_sha256[name] = file_hash(probe_dir + '/' + name)
		}
		os.write_file(probe_dir + '/build.json', json2.encode(receipt, prettify: true)) or { panic(err) }
		args := [os.executable(), probe_dir]
		result := os.exec(args)
		os.write_file(out + '/' + probe + '.json', json2.encode(CommandReceipt{args, result.exit_code, result.output},
			prettify: true
		)) or { panic(err) }
		if result.exit_code == 0 || !result.output.contains(expected_failure) {
			panic('rejection probe failed: ' + probe + '\n' + result.output)
		}
		println('SERVICE-ACCESS-CHECKER-REJECT ' + probe)
	}
	if file_hash(bundle + '/build.json') != before { panic('self-test modified original receipt') }
	println('SERVICE-ACCESS-CHECKER-SELF-TEST PASS probes=10 original-build-sha256=' + before)
}
