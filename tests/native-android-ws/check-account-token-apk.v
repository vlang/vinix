// SPDX-License-Identifier: GPL-2.0-or-later
// Validate a complete signed fixture bundle. This does not execute it on ART.
module main

import crypto.sha256
import json2
import os

const certificate_pin = '12520d3c4783e80927f029e8d0108b9808e3c17fbb9d69647f10527ffe1308f7'
const commands = ['assemble', 'compile-resources', 'link-resources', 'zip', 'sign', 'verify', 'manifest',
	'authenticator-xml']

struct Build {
	apk_sha256           string
	argv                 []string
	authenticator_action string
	authenticator_marker string
	cache_manifest       bool
	cache_markers        []string
	inputs_sha256        map[string]string
}

struct Command {
	argv      []string
	exit_code int
	output    string
}

fn require(value bool, message string) ! {
	if !value { return error(message) }
}

fn pin(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn canonical(path string) bool {
	return path.starts_with('/') && !path.contains('\x00') && !path.contains('\n')
		&& os.abs_path(path) == path && os.real_path(path) == path && !os.is_link(path)
}

fn identity(info os.Stat) string {
	return '${info.dev}:${info.inode}:${info.mode}:${info.size}:${info.mtime}:${info.ctime}'
}

fn digest(path string) !string {
	require(canonical(path), 'noncanonical input: ' + path)!
	before := os.lstat(path)!
	require(before.get_filetype() == .regular && before.size <= 256 * 1024 * 1024, 'regular bounded input: ' + path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	mut count := u64(0)
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		count += u64(n)
		require(count <= before.size, 'input grew: ' + path)!
		hash.write(buffer[..n])!
	}
	require(count == before.size && identity(before) == identity(os.lstat(path)!), 'input changed: ' + path)!
	return hash.sum([]u8{}).hex()
}

fn text(path string) !string {
	require(os.file_size(path) <= 1024 * 1024, 'bounded JSON input')!
	digest(path)!
	return os.read_file(path)!
}

fn relative(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains('\x00') && !path.contains('\n')
		&& path.split('/').all(it != '' && it != '.' && it != '..')
}

fn inventory(root string, prefix string, depth int, mut files map[string]string) ! {
	require(depth <= 16 && files.len <= 512, 'inventory bounds')!
	directory := if prefix == '' { root } else { root + '/' + prefix }
	require(canonical(directory) && os.lstat(directory)!.get_filetype() == .directory, 'canonical directory required')!
	names := os.ls(directory)!
	require(names.len <= 512, 'directory entry bounds')!
	for name in names {
		key := if prefix == '' { name } else { prefix + '/' + name }
		require(relative(key), 'unsafe inventory path')!
		path := root + '/' + key
		require(canonical(path), 'symlink or noncanonical inventory path')!
		info := os.lstat(path)!
		if info.get_filetype() == .directory {
			inventory(root, key, depth + 1, mut files)!
		} else {
			require(info.get_filetype() == .regular, 'nonregular inventory entry')!
			if key != 'sha256.json' {
				require(files.len < 512, 'inventory file bounds')!
				files[key] = digest(path)!
			}
		}
	}
}

fn complete(root string, expected_pin string) !map[string]string {
	require(digest(root + '/sha256.json')! == expected_pin, 'inventory pin mismatch')!
	expected := json2.decode[map[string]string](text(root + '/sha256.json')!)!
	require(expected.len > 0 && expected.len <= 512 && 'sha256.json' !in expected, 'inventory shape')!
	for key, value in expected { require(relative(key) && pin(value), 'inventory key/hash')! }
	mut actual := map[string]string{}
	inventory(root, '', 0, mut actual)!
	require(actual == expected, 'complete inventory mismatch')!
	return actual
}

fn inputs(pins map[string]string) ! {
	require(pins.len > 0 && pins.len <= 512, 'input pin bounds')!
	for path, value in pins {
		require(pin(value) && digest(path)! == value, 'input pin mismatch: ' + path)!
	}
}

fn run() ! {
	require(os.args.len == 4, 'usage: check-account-token-apk BUNDLE SHA256_JSON_PIN FRESH_EXTERNAL_RECEIPT_DIRECTORY')!
	root, expected, output := os.args[1], os.args[2], os.args[3]
	require(canonical(root) && pin(expected), 'canonical bundle and lowercase SHA-256 required')!
	repo := os.real_path(os.dir(@FILE) + '/../..')
	require(output.starts_with('/') && os.abs_path(output) == output && canonical(os.dir(output))
		&& !os.exists(output) && !os.is_link(output) && output != repo && !output.starts_with(repo + '/')
		&& output != root && !output.starts_with(root + '/'), 'fresh external receipt directory required')!
	files := complete(root, expected)!
	build := json2.decode[Build](text(root + '/build.json')!)!
	require(build.apk_sha256 == files['probe.apk'] && pin(build.apk_sha256), 'APK pin')!
	require(build.authenticator_action == 'android.accounts.AccountAuthenticator'
		&& build.authenticator_marker == 'ACCOUNT-AUTHENTICATORS-PASS' && build.cache_manifest
		&& build.cache_markers.filter(it == 'ACCOUNT-AUTHENTICATORS-PASS').len == 1
		&& build.cache_markers.filter(it == 'ACCOUNT-TOKEN-CACHE-PASS broker-invalidation exact-multiaccount preserved-other-value').len == 1, 'metadata/cache fixture contract')!
	require(build.argv.len == 8 && build.argv[1] == root, 'fixture build argv')!
	require(files.keys().filter(it.starts_with('commands/')).len == commands.len, 'exact command record inventory')!
	for name in commands {
		command := json2.decode[Command](text(root + '/commands/' + name + '.json')!)!
		require(command.exit_code == 0 && command.argv.len > 0, 'recorded command failure: ' + name)!
		if name == 'verify' {
			require(command.output.contains('Verified using v3 scheme (APK Signature Scheme v3): true'), 'recorded APK v3 verification')!
		}
	}
	mut checked_inputs := build.inputs_sha256.clone()
	for path in [os.real_path(@FILE), os.real_path(os.executable())] {
		checked_inputs[path] = digest(path)!
	}
	for path in [build.argv[0], build.argv[4], build.argv[5]] {
		require(path in checked_inputs, 'missing executable/build input pin')!
	}
	require(files['builder'] == checked_inputs[build.argv[0]]
		&& files['builder.v'] == checked_inputs[repo + '/tests/native-android-ws/account-token-fixture.v'], 'retained builder source/executable pins')!
	inputs(checked_inputs)!
	argv := [build.argv[4], '-jar', build.argv[5], 'verify', '--verbose', '--print-certs',
		root + '/probe.apk']
	result := os.exec(argv)
	require(result.exit_code == 0 && result.output.len <= 1024 * 1024
		&& result.output.contains('Verified using v3 scheme (APK Signature Scheme v3): true'), 'independent APK v3 verification')!
	cert_line := 'Signer #1 certificate SHA-256 digest: ' + certificate_pin
	require(result.output.split_into_lines().filter(it == cert_line).len == 1
		&& result.output.split_into_lines().filter(it == 'Number of signers: 1').len == 1, 'fixture signer certificate')!
	inputs(checked_inputs)!
	require(complete(root, expected)! == files, 'bundle changed during verification')!
	os.mkdir(output)!
	os.cp(@FILE, output + '/checker.v')!
	os.cp(os.executable(), output + '/checker')!
	require(digest(output + '/checker.v')! == checked_inputs[os.real_path(@FILE)]
		&& digest(output + '/checker')! == checked_inputs[os.real_path(os.executable())], 'preserved checker source/executable pins')!
	os.write_file(output + '/certificate-command.json', json2.encode(Command{argv, result.exit_code, result.output},
		escape_unicode: true
		time_as_unix:   true
	) + '\n')!
	os.write_file(output + '/receipt.json', json2.encode({
		'bundle':             root
		'inventory_sha256':   expected
		'apk_sha256':         build.apk_sha256
		'certificate_sha256': certificate_pin
		'checks':             'complete-inventory source-executable-input-pins exact-metadata-markers recorded-command-success independent-v3-single-signer recheck'
		'scope':              'Signed fixture validation only; ART and Google login not executed.'
	},
		escape_unicode: true
		time_as_unix:   true
	) + '\n')!
	os.write_file(output + '/inputs.json', json2.encode(checked_inputs,
		escape_unicode: true
		time_as_unix:   true
	) + '\n')!
	mut evidence := map[string]string{}
	inventory(output, '', 0, mut evidence)!
	os.write_file(output + '/sha256.json', json2.encode(evidence,
		escape_unicode: true
		time_as_unix:   true
	) + '\n')!
	println('ACCOUNT-TOKEN-APK-CHECK-PASS ' + expected + ' receipt=' + digest(output + '/sha256.json')!)
}

fn main() {
	run() or {
		eprintln('ACCOUNT-TOKEN-APK-CHECK-FAIL ' + err.msg())
		exit(1)
	}
}
