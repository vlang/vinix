// SPDX-License-Identifier: GPL-2.0-or-later
// Verify a source-only diagnostic rebuild preserves every dependency receipt.
module main

import crypto.sha256
import json2
import os

struct Inputs {
	base_runtime string
	base_lock_sha256 string
	runtime_manifest_sha256 string
	addon_lock_sha256 string
	archive_bytes u64
	archive_references map[string]string
	runtime_references map[string]string
	guest_helper_references map[string]string
	compiler_sha256 string
	cross_compiler_sha256 string
	fault_probe_build_sha256 string
	fault_probe_shim_sha256 string
	fault_probe_fixture_sha256 string
	fault_probe_files_sha256 map[string]string
}

struct Outputs {
	source_files_sha256 map[string]string
	probe_sha256 string
	session_sha256 string
	guest_sha256 string
}

fn digest(path string) !string { return sha256.sum256(os.read_bytes(path)!).hex() }

fn outputs(root string, body string) !Outputs {
	result := json2.decode[Outputs](body)!
	if result.source_files_sha256.len != 8 { return error('complete preparation sources required') }
	for name, pin in result.source_files_sha256 {
		if os.base(name) != name || digest(root + '/sources/' + name)! != pin {
			return error('source pin mismatch: ' + name)
		}
	}
	for name, pin in {'probe': result.probe_sha256, 'session': result.session_sha256,
		'guest': result.guest_sha256} {
		if digest(root + '/bin/browser-' + name)! != pin { return error('executable pin mismatch') }
	}
	return result
}

fn compare(before string, before_pin string, after string, changed string, changed_pin string) ! {
	if digest(before + '/build.json')! != before_pin { return error('original receipt pin mismatch') }
	old_body := os.read_file(before + '/build.json')!
	new_body := os.read_file(after + '/build.json')!
	old_inputs := json2.decode[Inputs](old_body)!
	new_inputs := json2.decode[Inputs](new_body)!
	if old_inputs != new_inputs { return error('dependency inputs changed') }
	if old_inputs.archive_references.len == 0 || old_inputs.runtime_references.len == 0
		|| old_inputs.compiler_sha256.len != 64 || old_inputs.fault_probe_files_sha256.len == 0 {
		return error('complete frozen dependency receipts required')
	}
	old := outputs(before, old_body)!
	new := outputs(after, new_body)!
	if changed !in old.source_files_sha256 || changed !in new.source_files_sha256
		|| new.source_files_sha256[changed] != changed_pin || old.source_files_sha256[changed] == changed_pin {
		return error('expected source delta missing')
	}
	for name, pin in old.source_files_sha256 {
		if name != changed && new.source_files_sha256[name] != pin {
			return error('unexpected source delta: ' + name)
		}
	}
	println('BROWSER-PREPARATION COMPARE PASS frozen-dependencies source-delta=' + changed
		+ ' build-sha256=' + digest(after + '/build.json')!)
}

fn main() {
	if os.args.len != 6 {
		eprintln('usage: compare-preparation OLD OLD_BUILD_SHA256 NEW CHANGED_SOURCE NEW_SOURCE_SHA256')
		exit(2)
	}
	compare(os.args[1], os.args[2], os.args[3], os.args[4], os.args[5]) or {
		eprintln(err)
		exit(1)
	}
}
