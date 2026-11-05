// SPDX-License-Identifier: GPL-2.0-or-later
module compactproof

import crypto.sha256
import json2
import os
import time

fn test_root(name string) !string {
	base := os.getenv('COMPACTPROOF_TEST_ROOT')
	need(os.is_abs_path(base) && os.real_path(base) == base
		&& os.lstat(base)!.mode & 0o170000 == 0o040000,
		'COMPACTPROOF_TEST_ROOT must be an existing canonical external directory')!
	root := base + '/' + name
	need(!os.exists(root) && !os.is_link(root), 'control output must be fresh')!
	os.mkdir(root, mode: 0o700)!
	return root
}

fn check_literal_relative_names() {
	for value in ['.hidden', 'space λ/名前.v', 'a/b', '$literal;name'] {
		relative(value) or { panic(err) }
	}
	for value in ['', '/absolute', 'a//b', '.', '..', 'a/../b', 'a/./b', 'a\\b',
		'a\x00b', 'a\nb', 'a\rb', 'a\tb', 'a\x7fb'] {
		relative(value) or { continue }
		panic('unsafe compact path accepted: ' + value)
	}
}

fn manifest_controls() ! {
	root := test_root('manifest')!
	os.mkdir(root + '/source')!
	os.write_file(root + '/source/.hidden', 'hidden bytes')!
	os.write_file(root + '/source/ordinary', 'ordinary bytes')!
	expected := inventory(root)!
	mut names := expected.keys()
	names.sort()
	mut manifest := ''
	for name in names { manifest += expected[name] + '\t' + name + '\n' }
	os.write_file(root + '/bundle.sha256', manifest)!
	wanted := sha256.hexhash(manifest)
	need(sealed_manifest(root, wanted)! == expected, 'complete fixture manifest refused')!
	// Resealed manifests still must account for every hidden regular input.
	os.write_file(root + '/source/.added', 'added hidden bytes')!
	sealed_manifest(root, wanted) or {
		os.rm(root + '/source/.added')!
		need(sealed_manifest(root, wanted)! == expected, 'baseline failed after hidden-add refusal')!
		return manifest_path_controls(root, manifest)
	}
	return error('hidden unlisted file accepted')
}

fn manifest_path_controls(root string, original string) ! {
	for changed in [original + original.split_into_lines()[0] + '\n',
		sha256.hexhash('outside') + '\t../outside\n',
		sha256.hexhash('outside') + '\t/absolute\n',
		'bad\tsource/ordinary\n', ''] {
		os.write_file(root + '/bundle.sha256', changed)!
		sealed_manifest(root, sha256.hexhash(changed)) or { continue }
		return error('invalid or incomplete resealed compact manifest accepted')
	}
	os.write_file(root + '/bundle.sha256', original)!
	os.symlink(root + '/source/ordinary', root + '/source/alias')!
	sealed_manifest(root, sha256.hexhash(original)) or { return }
	return error('bundle alias accepted')
}

fn check_complete_fixture_manifest_and_alias_refusals() {
	manifest_controls() or { panic(err) }
}

fn reader_controls() ! {
	root := test_root('reader')!
	path := root + '/value'
	os.write_file(path, 'four')!
	need(digest(path, time.sys_mono_now())! == sha256.hexhash('four'), 'ordinary reader differs')!
	digest(path, time.sys_mono_now() - scan_ns) or {
		mut scan := Scan{bytes: tree_limit - 3}
		mut paths := map[string]string{}
		walk(root, '', 0, mut scan, mut paths) or {
			os.symlink(path, root + '/alias')!
			digest(root + '/alias', time.sys_mono_now()) or { return }
			return error('literal digest followed an alias')
		}
		return error('cumulative inventory byte limit accepted')
	}
	return error('expired scan deadline accepted')
}

fn check_reader_deadline_byte_and_alias_refusals() {
	reader_controls() or { panic(err) }
}

fn audit_receipt_controls() ! {
	root := test_root('audit-receipts')!
	argv := [original_checker, 'check', target_root, complete_root + '/targets01/inventory.json']
	run := CheckRun{0, root + '/argv.json', root + '/log', root + '/exit.json'}
	os.write_file(run.argv_path, json2.encode(argv))!
	os.write_file(run.log_path, 'FRAME-PAGE COMPLETE STATE CHECK PASS\n')!
	os.write_file(run.exit_path, '{"exit_code":0}')!
	// Parser fixture only: this does not construct Audits or run/qualify a checker.
	verify_run(run, argv)!
	verify_run(CheckRun{1, run.argv_path, run.log_path, run.exit_path}, argv) or {
		for changed in ['{"exit_code":1}', '{"exit_code":0,"extra":0}', '{}'] {
			os.write_file(run.exit_path, changed)!
			verify_run(run, argv) or { continue }
			return error('bad actual-exit receipt accepted')
		}
		os.write_file(run.exit_path, '{"exit_code":0}')!
		for changed in ['', 'FRAME-PAGE COMPLETE STATE CHECK PASS',
			'FRAME-PAGE COMPLETE STATE CHECK PASS\nFRAME-PAGE COMPLETE STATE CHECK PASS\n'] {
			os.write_file(run.log_path, changed)!
			verify_run(run, argv) or { continue }
			return error('bad original-check marker accepted')
		}
		os.write_file(run.log_path, 'FRAME-PAGE COMPLETE STATE CHECK PASS\n')!
		os.write_file(run.argv_path, json2.encode([original_checker, 'seal', target_root, argv[3]]))!
		verify_run(run, argv) or { return }
		return error('different original-check argv accepted')
	}
	return error('nonzero actual callback result accepted')
}

fn check_original_audit_receipt_refusals() {
	audit_receipt_controls() or { panic(err) }
}

fn token_controls() ! {
	Audits{}.inputs() or {
		root := test_root('audit-token')!
		path := root + '/receipt'
		os.write_file(path, 'observed receipt')!
		paths := {'receipt': path}
		hashes := {'receipt': sha256.hexhash('observed receipt')}
		Audits{true, time.sys_mono_now() - i64(1800) * time.second, paths, hashes}.inputs() or {
			ready := Audits{true, time.sys_mono_now(), paths, hashes}
			need(ready.inputs()! == paths, 'fixture token changed inputs')!
			os.write_file(path, 'modified receipt')!
			ready.inputs() or { return }
			return error('changed original audit receipt accepted')
		}
		return error('stale original audit token accepted')
	}
	return error('unready original audit token accepted')
}

fn check_unready_stale_and_changed_audit_tokens() {
	token_controls() or { panic(err) }
}

fn record_controls() ! {
	root := test_root('recorded-audits')!
	mut paths := checker_inputs()!
	for name in ['targets01', 'target-bootstrap01'] {
		original_root := if name == 'targets01' { target_root } else { bootstrap_root }
		argv := [original_checker, 'check', original_root, paths['complete/' + name]]
		for part, value in {
			'argv': json2.encode(argv)
			'log': 'FRAME-PAGE COMPLETE STATE CHECK PASS\n'
			'exit': '{"exit_code":0}'
		} {
			path := root + '/' + name + '-' + part
			os.write_file(path, value)!
			paths['audit/' + name + '/' + part] = path
		}
	}
	mut hashes := map[string]string{}
	for name, path in paths { hashes[name] = digest(path, time.sys_mono_now())! }
	// Static parser fixture only: it creates no live token or actual audit claim.
	record := AuditRecord{source_sha256: sha256.hexhash(source()), paths: paths, hashes: hashes}
	path := root + '/record.json'
	baseline := json2.encode(record) + '\n'
	os.write_file(path, baseline)!
	need(recorded_inputs(path)! == paths, 'static recorded parser baseline refused')!
	for changed in [AuditRecord{...record, format: 2}, AuditRecord{...record, scope: 'new execution'},
		AuditRecord{...record, source_sha256: '0'.repeat(64)}] {
		os.write_file(path, json2.encode(changed) + '\n')!
		recorded_inputs(path) or { continue }
		return error('altered recorded audit header accepted')
	}
	mut missing := paths.clone()
	missing.delete('audit/targets01/log')
	os.write_file(path, json2.encode(AuditRecord{...record, paths: missing}) + '\n')!
	recorded_inputs(path) or {
		mut changed_hashes := hashes.clone()
		changed_hashes['audit/targets01/log'] = '0'.repeat(64)
		os.write_file(path, json2.encode(AuditRecord{...record, hashes: changed_hashes}) + '\n')!
		recorded_inputs(path) or {
			os.write_file(path, baseline)!
			pin(path, '0'.repeat(64), time.sys_mono_now()) or {
				os.write_file(paths['audit/targets01/log'], 'changed callback log\n')!
				recorded_inputs(path) or { return }
				return error('changed callback bytes accepted by static replay')
			}
			return error('wrong producer record hash accepted')
		}
		return error('changed recorded digest accepted')
	}
	return error('missing recorded audit role accepted')
}

fn fixture_elf(arch string) []u8 {
	mut data := []u8{len: 120}
	for index, byte in [u8(0x7f), `E`, `L`, `F`, 2, 1] { data[index] = byte }
	data[16] = 2
	machine := if arch == 'aarch64' { u16(183) } else { u16(62) }
	data[18] = u8(machine)
	data[19] = u8(machine >> 8)
	data[32] = 64
	data[54] = 56
	data[56] = 1
	data[64] = 1
	data[96] = 120
	data[104] = 120
	return data
}

fn elf_controls() ! {
	for arch in ['aarch64', 'x86_64'] {
		good := fixture_elf(arch)
		elf_bytes(good, arch)!
		for index, replacement in {0: u8(0), 4: 1, 5: 2, 16: 3, 18: 0,
			32: 255, 54: 55, 56: 0, 64: 3, 96: 121, 104: 119} {
			mut changed := good.clone()
			changed[index] = replacement
			elf_bytes(changed, arch) or { continue }
			return error('malformed compact ELF accepted at byte' + index.str())
		}
		elf_bytes(good[..63], arch) or { continue }
		return error('short compact ELF accepted')
	}
	elf_bytes(fixture_elf('aarch64'), 'unknown') or { return }
	return error('unknown compact ELF architecture accepted')
}

fn check_static_elf_type_interpreter_and_segment_refusals() {
	elf_controls() or { panic(err) }
}

// The caller owns this small command under the existing supervisor. The output
// path must be new, outside frozen evidence, with an ordinary canonical parent.
pub fn run_controls(output string) ! {
	need(os.is_abs_path(output) && os.real_path(os.dir(output)) == os.dir(output)
		&& os.lstat(os.dir(output))!.mode & 0o170000 == 0o040000
		&& !os.exists(output) && !os.is_link(output), 'compact controls require fresh external output')!
	mutable_output(os.dir(output))!
	os.mkdir(output, mode: 0o700)!
	old_root := os.getenv_opt('COMPACTPROOF_TEST_ROOT')
	os.setenv('COMPACTPROOF_TEST_ROOT', output, true)
	defer {
		if value := old_root { os.setenv('COMPACTPROOF_TEST_ROOT', value, true) }
		else { os.unsetenv('COMPACTPROOF_TEST_ROOT') }
	}
	check_literal_relative_names()
	check_complete_fixture_manifest_and_alias_refusals()
	check_reader_deadline_byte_and_alias_refusals()
	check_original_audit_receipt_refusals()
	check_unready_stale_and_changed_audit_tokens()
	record_controls()!
	check_static_elf_type_interpreter_and_segment_refusals()
	for path in [compact_root + '/targets01/receipt', hosted_root + '/receipt',
		hosted_bundle + '/receipt', os.dir(original_checker) + '/receipt'] {
		mutable_output(path) or { continue }
		return error('audit output inside frozen evidence accepted')
	}
	os.write_file(output + '/result.json', json2.encode({
		'outcome': 'PASS', 'categories': '8',
		'scope': 'Small parser/inventory/ELF/audit-receipt/token/output controls; no original audit, import or guest.'
	}) + '\n')!
	println('COMPACTPROOF eight explicit control categories PASS')
}
