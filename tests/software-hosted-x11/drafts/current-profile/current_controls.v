// SPDX-License-Identifier: GPL-2.0-or-later
// Uncompiled draft; this file is not part of the active qualified package.
module compactproof

import crypto.sha256
import json2
import os
import time

fn current_record_refused(path string) ! {
	current_recorded_inputs(path) or { return }
	return error('altered current record unexpectedly accepted')
}

// Parser fixtures only. Synthetic callback receipts never qualify execution.
pub fn run_current_controls(output string) ! {
	need(os.is_abs_path(output) && os.real_path(os.dir(output)) == os.dir(output)
		&& !os.exists(output) && !os.is_link(output), 'current controls require fresh canonical output')!
	current_output(os.dir(output))!
	os.mkdir(output, mode: 0o700)!
	run_controls(output + '/historical')!
	mut passed := 0
	mut paths := current_profile_inputs()!
	need(paths['complete/targets01'] == current_phase + '/targets01/inventory.json'
		&& paths['complete/target-bootstrap01'] == current_phase + '/target-bootstrap01/inventory.json'
		&& paths['historical/targets01'] == complete_root + '/targets01/inventory.json'
		&& paths['historical/target-bootstrap01'] == complete_root + '/target-bootstrap01/inventory.json',
		'explicit current/historical manifest identity differs')!
	passed++
	mut refused_empty := false
	CurrentAudits{}.inputs() or { refused_empty = true }
	mut refused_stale := false
	CurrentAudits{Audits{true, time.sys_mono_now() - i64(1800) * time.second,
		map[string]string{}, map[string]string{}}}.inputs() or { refused_stale = true }
	need(refused_empty && refused_stale, 'empty or expired current token accepted')!
	passed++
	for name in ['targets01', 'target-bootstrap01'] {
		root := if name == 'targets01' { target_root } else { bootstrap_root }
		for part, value in {
			'argv': json2.encode([original_checker, 'check', root, paths['complete/' + name]])
			'log': 'FRAME-PAGE COMPLETE STATE CHECK PASS\n'
			'exit': '{"exit_code":0}'
		} {
			path := output + '/' + name + '-' + part
			os.write_file(path, value)!
			paths['audit/' + name + '/' + part] = path
		}
	}
	mut hashes := map[string]string{}
	for name, path in paths { hashes[name] = digest(path, time.sys_mono_now())! }
	fixture := CurrentAudits{Audits{true, time.sys_mono_now(), paths, hashes}}
	path := output + '/record.json'
	producer_hash := fixture.write_record(path)!
	baseline := text(path, time.sys_mono_now())!
	record := json2.decode[AuditRecord](baseline, strict: true)!
	need(current_recorded_inputs(path)! == paths && baseline.len <= 65536
		&& record.scope == current_record_scope && producer_hash == sha256.hexhash(baseline),
		'current static record fixture differs')!
	passed++
	for changed in [AuditRecord{...record, format: 2}, AuditRecord{...record, scope: 'new execution'},
		AuditRecord{...record, source_sha256: sha256.hexhash(source())}] {
		os.write_file(path, json2.encode(changed) + '\n')!
		current_record_refused(path)!
	}
	passed++
	os.write_file(path, baseline)!
	mut refused_by_historical := false
	recorded_inputs(path) or { refused_by_historical = true }
	need(refused_by_historical, 'historical parser accepted current record scope')!
	os.write_file(path, json2.encode(AuditRecord{...record,
		scope: 'Recorded original complete compact checks; static provenance, no new execution',
		source_sha256: sha256.hexhash(source())}) + '\n')!
	current_record_refused(path)!
	passed++
	mut missing := paths.clone()
	missing.delete('audit/targets01/log')
	os.write_file(path, json2.encode(AuditRecord{...record, paths: missing}) + '\n')!
	current_record_refused(path)!
	mut substituted := paths.clone()
	mut substituted_hashes := hashes.clone()
	substituted['complete/targets01'] = complete_root + '/targets01/inventory.json'
	substituted_hashes['complete/targets01'] = manifest_paths()['targets01']
	os.write_file(path, json2.encode(AuditRecord{...record, paths: substituted, hashes: substituted_hashes}) + '\n')!
	current_record_refused(path)!
	argv_path := paths['audit/targets01/argv']
	argv_before := os.read_file(argv_path)!
	os.write_file(argv_path, json2.encode([original_checker, 'check', target_root,
		complete_root + '/targets01/inventory.json']))!
	mut changed_hashes := hashes.clone()
	changed_hashes['audit/targets01/argv'] = sha256.hexhash(os.read_file(argv_path)!)
	os.write_file(path, json2.encode(AuditRecord{...record, hashes: changed_hashes}) + '\n')!
	current_record_refused(path)!
	os.write_file(argv_path, argv_before)!
	os.write_file(path, baseline)!
	passed++
	for root in current_frozen_roots() {
		current_output(root) or { continue }
		return error('current audit output accepted inside frozen profile')
	}
	mut refused_reuse := false
	recorded_current_assembled('/unconsumed-desktop', '/unconsumed-stage', 'aarch64',
		'/unconsumed-compiler', path, producer_hash, path, producer_hash) or { refused_reuse = true }
	mut refused_hash := false
	recorded_current_assembled('/unconsumed-desktop', '/unconsumed-stage', 'aarch64',
		'/unconsumed-compiler', path, '0'.repeat(64), output + '/different-record', producer_hash) or { refused_hash = true }
	need(refused_reuse && refused_hash, 'current replay accepted repeated record or wrong producer hash')!
	passed++
	need(passed == 7, 'current control category count differs')!
	os.write_file(output + '/result.json', json2.encode({
		'outcome': 'PASS', 'historical_categories': '8', 'current_categories': passed.str(),
		'profile_inputs': (paths.len - 6).str(), 'encoded_current_record_bytes': baseline.len.str(),
		'scope': 'Historical controls and explicit current-profile provenance/record/token/refusal fixtures only. Synthetic callback receipts establish no audit, import or native execution.'
	}) + '\n')!
	println('COMPACTPROOF historical eight and current seven control categories PASS')
}
