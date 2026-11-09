// SPDX-License-Identifier: GPL-2.0-or-later
// Uncompiled draft: install beside the unchanged historical admit.v to qualify.
module compactproof

import crypto.sha256
import json2
import launchproof
import os
import time

const current_state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const current_capture = current_state + '/native-consumer-tools-01/source-before-current-01'
const current_phase = current_state + '/compact-current-audit-01'
const current_owner = current_state + '/compact-current-audit-observer-01'
const current_bootstrap = current_state + '/compact-import-bootstrap-01'
const current_base_sha = '558e3d949d310b54d8550bb8d51bbabfab395655f58afdb6167bf1f42fc58f80'
const current_record_scope = 'Recorded original whole-root checks against the fixed current metadata inventories; historical refusals retained; static provenance, no new execution'
const current_import_method = 'verified compact compositor copy under the fixed current metadata profile with separate original hosted proof; no rebuild'

// The private wrapper cannot be supplied to the historical API accidentally.
// Its inner token uses the existing ready/30-minute/complete-pin mechanism.
pub struct CurrentAudits {
	audit Audits
}

struct CurrentCopy {
	source string
	capture string
	sha256 string
	mode u32
}

pub fn source_current() string { return $embed_file('current.v').to_string() }

fn current_manifests() map[string]string {
	return {
		'targets01': '9ab4265863021ce59410851dbeabe4de2cafb86ab07f335f6fe9959a47022753'
		'target-bootstrap01': 'ea4c3b1fb221baeacb97ad9a605841f5d7acf3a7385723fbd792c368c2d74591'
	}
}

// These are reviewed, completed receipts, not a caller-selectable trust map.
// The owner result contains every original sample's df text and cleanup.
// Raw per-sample df files remain retained; this profile does not rerun them.
fn current_fixed_pins() map[string]string {
	return {
		current_phase + '/result.json': '0dc92b3b97cd469a46caefd8f1f8e960d5f56cd3cf3cac4b27b41840115cbf4b'
		current_phase + '/modules-before.json': 'c3e81abb9453a2ff4e31645ef308053bbd6faf4fb8a9dae90da2978af14281a8'
		current_phase + '/modules-after.json': 'c3e81abb9453a2ff4e31645ef308053bbd6faf4fb8a9dae90da2978af14281a8'
		current_phase + '/original-inputs-before.json': '23d9d0d2b7fa5878e7ffc2cb6364fb9a5c2fe05122b37a5f066679df205e33ed'
		current_phase + '/original-inputs-after.json': '23d9d0d2b7fa5878e7ffc2cb6364fb9a5c2fe05122b37a5f066679df205e33ed'
		current_phase + '/targets01-differences.json': '37477cab9cb0c0885c49d478bbd07c7b4ee15d4811f7efb56816eb02a33a681d'
		current_phase + '/target-bootstrap01-differences.json': '9501c2c8c70345a3392bca095b742cc6c10e8ef7ee4f3ff781c572b80acac15a'
		current_owner + '/result.json': 'b9d0851a7d89f7f2682eac9ea79b5dee0be383067260bc410b7fcdb77a82fea7'
		current_owner + '/qualification.json': 'b73293eac98bf0cf2b2a1ffbb4316c07cdc102f15fc7d309d6dab1c0abee9a03'
		current_owner + '/modules-before.json': 'c3e81abb9453a2ff4e31645ef308053bbd6faf4fb8a9dae90da2978af14281a8'
		current_owner + '/modules-after.json': 'c3e81abb9453a2ff4e31645ef308053bbd6faf4fb8a9dae90da2978af14281a8'
		current_owner + '/argv.json': '3134a9479b4c2ccf2ba628e035237ac844ee9fa34d11159e81bce6f7d6109730'
		current_owner + '/environment.json': '5edcd88ac04cfa419fb88b71a5f8770d4f8fb29f518a88c661f37186991a0512'
		current_owner + '/output.log': '649e548ad5785d47a16e5d793bd974542f3caed43030bf6e133d837c980e737a'
		current_owner + '/output.log.barrier.json': '2c6db4e2f73f29afc050ce811f479b59644012dd8495f53cc609c0f5b145b072'
		current_owner + '/output.log.cleanup.json': 'bfff066729044d1ae4757b3c5f30ef8ddefbf626dad7ae165cfba6880bd03a57'
		current_owner + '/admission.json': 'c4347572c6f925bb975408febea8ca66b484db5e84eb1267a77e92527776ff02'
		current_owner + '/final-df': '2378b06d236c3ad8de5390f1ac5ab2bb8b81e0f80f226a65cd0466662b2ca8ab'
		current_owner + '/final-df.barrier.json': '56ffd1aa21226f9426cce85e77ca0ee313a7345ab11268ef2865977db5e4efd8'
		current_owner + '/final-df.cleanup.json': '9df7c6b9817c5c17edf0101166dfbcfa6bd9bbe9e29d2d0da80b06fcb7e296a9'
		current_state + '/compact-current-audit-admission-df': '01b42b16ef37ade954e5519ad4dcf231bcddf8c5f6331e6564e3bb761243b42d'
		current_state + '/compact-current-audit-admission-df.barrier.json': '5dcadd352bc323c92478edb7f201596cee9e08ce0d7f4e629c3012ff4152f6c3'
		current_state + '/compact-current-audit-admission-df.cleanup.json': '5db7ccaf1d4a52f0dcd0485763ebce71640773d0249762aa4039e0a58ee48929'
		current_state + '/compact-stage-projection-02.json': '67ae49eeb2f43ffdc16cbd093a43c3dd93e7a8c4933854913c0e7464ececb1e6'
		current_state + '/compact-frozen-tools-01.json': '14a1d04a2288ff548171b8428cabe92582a8ceefc7ea648e25f07f5ef00da579'
		current_bootstrap + '/compact-projection-02': 'd5b6902bd3b96051c15b805fbaf10d0c855ea9323e3b16a8fff26fd17d802b78'
		current_bootstrap + '/projection-source-02/compact-projection.v': '372bc38b3fd3dd52995bf0434840eed16d7e02341570f10ffa504ed3e607c857'
		current_bootstrap + '/source-04/compact-import.v': '919a40413995a882c494a6d8831750b0d64373cda057487d464214f08932e7a0'
		current_bootstrap + '/source-04/compactdiagnosis/compare.v': 'a4a3eac9206efd9d85887ba55529263acbd4b934ee405612be5a529fc44a0010'
		current_bootstrap + '/source-04/compactdiagnosis/controls.v': '61f80faf63c787dffd98fb4105c6c02d8e19a8e44f3a718ccb4819b37c5bf941'
		current_bootstrap + '/compact-import-04': 'e6c440ef7667b4a52939c8602490dd52c1de239f23131ae9b5d5e6c35df16717'
		current_bootstrap + '/compile-04.argv.json': 'f241ce1733ac360ddced66d956dd3a53f787a363dc90a5faa98cf26e3f365c7f'
		current_bootstrap + '/compile-04.environment.json': 'd9937798c01b6fb187b106ac419c74b97a0021b8571827e607c3dc7ded64dd3a'
		current_bootstrap + '/compile-04.observer-exit.json': '6d6714df08e3689cfc351244b1663373d6b61d25058ef8aff20deebe81a00d48'
		current_bootstrap + '/current-audit-run-01.argv.json': 'cfe67480ea8550748742a297a83f32c720ebbe165baac19d13381cac8c096839'
		current_bootstrap + '/current-audit-run-01.log': '61120586638139b23d0832cbb0c8d097732ca23c00e027fa98b83e76132746b9'
		current_bootstrap + '/current-audit-run-01.observer-exit.json': 'da1f8db21eb8bd6114e6e557de957b846e46a552b9450e259d08c2d463a9f2f7'
		current_bootstrap + '/current-audit-compiled-modules.json': '11848eb9980f4802ab121f1985778114e98e44b57b9c1d44a8d644a833aebcd1'
		current_bootstrap + '/modules-before.json': '7574aa941eeea3b7beb3dc58c14f6c23e57aea93bd5349a09f1aa8a51da9abce'
		current_bootstrap + '/current-audit-modules-after.json': '7574aa941eeea3b7beb3dc58c14f6c23e57aea93bd5349a09f1aa8a51da9abce'
		current_capture + '/mapping.json': '79a09c723f8bfb30a57b773576405bf9849544da6fb0882574e86e919b5297e6'
		current_capture + '/result.json': '01fd31eb692bf53b94e435df2ee20f05410312c5104444284db06f8b8bb5663b'
		current_capture + '/sources-before.json': '16fe3075ad4a6b39241a3f034848bb0622ec5b17aa42f96958788fddae407b9e'
		current_capture + '/sources-after.json': '16fe3075ad4a6b39241a3f034848bb0622ec5b17aa42f96958788fddae407b9e'
		current_capture + '/capture-tree.json': '7f1ab6f14fbf79e905b397b9b8b55c6f6e9b5c0591848ae292f228102104d464'
		current_state + '/native-consumer-tools-01/preserve-source-01/preserve-options-current.v': '9e4ee8e941235f528c6ab71cdb83606a64832409e826eb2e3a2d8b54ef9b4ab2'
		current_state + '/native-consumer-tools-01/preserve-options-current-01': '02e47bc109d5af25e84f74861f6809a3c4fa1401bcf953eada4cbd4e83fe2e5b'
		current_state + '/native-consumer-tools-01/preserve-bootstrap-01.argv.json': 'ed3ad310629cbbbbfd5e276b1a5fffe24e8f377e07b41349f1353b24f1cd09b0'
		current_state + '/native-consumer-tools-01/preserve-bootstrap-01.observer-exit.json': 'bb296f56804f95f992389a89b6f2a2a60c6a7fba0408b08595441b39b5ad805b'
		current_state + '/native-consumer-tools-01/preserve-run-01.argv.json': '76b22f4cea7f37725caa73c909646996ee2fd73e669a53bb7edf1fc38f67dbc2'
		current_state + '/native-consumer-tools-01/preserve-run-01.log': '521ec3aa188736419ca21f424dcb55d0fb8fdd25afc31a36b36f46fcc3e5d4b3'
		current_state + '/native-consumer-tools-01/preserve-run-01.observer-exit.json': 'c7d8445d5988cde19f11db25cf3cfcaace34ce29c2a91b53235676b1e20bab48'
		current_state + '/native-consumer-tools-01/preserve-frozen-comparisons-01.json': 'e505ed3d3aac814adb6b6dfb37fc4433f0e5cb0aadea90d1ea94604a7531da77'
		current_state + '/native-consumer-tools-01/frozen-before-preserve-01.log': 'f8919dbdede36b163eda833a7f8650b4bffc77f3a2cb01847185c3741c2d22d4'
		current_state + '/native-consumer-tools-01/frozen-after-preserve-01.log': 'f8919dbdede36b163eda833a7f8650b4bffc77f3a2cb01847185c3741c2d22d4'
		current_state + '/native-supervision-host-01/check-02.build.json': 'fbd39c8d161e8a0828131f53e6eb47be860f7362c39c0ae61d41f08889eefc58'
		current_state + '/native-consumer-tools-01/retain-01.build.json': '6d4eb66eeb057036a24c5f39edadb5e95e6d49c8fa4646bcd3b7aebf48302e75'
		'/Users/alex/.cache/vinix-waitpid-width-20261026-02/overlay-before.json': '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f'
		'/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v': 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		'/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23': '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'
	}
}

fn current_add(role string, path string, hash string, started i64, mut paths map[string]string) ! {
	need(role !in paths, 'duplicate current profile input role')!
	current_path_bound(role, path)!
	need(os.is_abs_path(path) && os.real_path(path) == path, 'current profile input path must be canonical')!
	pin(path, hash, started)!
	paths[role] = path
}

fn current_path_bound(role string, path string) ! {
	need(role.len <= 32 && path.len <= 300
		&& (role + path).bytes().all(it >= 32 && it <= 126 && it != `\\` && it != `"`),
		'current profile requires bounded literal ASCII receipt paths/roles')!
}

fn current_capture_name(path string) !string {
	fresh := current_state + '/source/'
	if path.starts_with(fresh) { return 'fresh/' + path[fresh.len..] }
	for name in ['bind-options-compact.v', 'preserve-options-current.v'] {
		if path == repository + '/tests/software-hosted-x11/' + name {
			return 'repository/tests/software-hosted-x11/' + name
		}
	}
	return error('unexpected historical source in current capture')
}

fn current_copies(started i64, mut paths map[string]string) !map[string]string {
	copies := json2.decode[[]CurrentCopy](text(current_capture + '/mapping.json', started)!, strict: true)!
	need(copies.len == 32, 'current source preservation count differs')!
	mut originals := map[string]string{}
	mut expected := map[string]string{}
	mut bytes := u64(0)
	for index, copy in copies {
		name := current_capture_name(copy.source)!
		need(copy.source !in originals && copy.capture == current_capture + '/files/' + name,
			'current captured source association differs')!
		stat := os.lstat(copy.capture)!
		need(os.real_path(copy.capture) == copy.capture && stat.mode == copy.mode
			&& stat.mode & 0o170000 == 0o100000 && stat.nlink == 1,
			'current captured source must remain an independent ordinary copy')!
		current_add('profile/source/' + index.str(), copy.capture, copy.sha256, started, mut paths)!
		originals[copy.source] = copy.capture
		expected[name] = copy.sha256
		bytes += stat.size
	}
	need(bytes == 334246 && inventory(current_capture + '/files')! == expected,
		'complete ordinary current source capture differs')!
	return originals
}

fn current_as_run(path string, originals map[string]string) string {
	if path in originals { return originals[path] }
	for name in ['compare.v', 'controls.v'] {
		if path == repository + '/tests/software-hosted-x11/compactdiagnosis/' + name {
			return current_bootstrap + '/source-04/compactdiagnosis/' + name
		}
	}
	return path
}

// Static fixed-profile provenance only. Actual consumption still requires
// check_current_audits() before/after the caller's admitted operation.
pub fn current_profile_inputs() !map[string]string {
	started := time.sys_mono_now()
	need(sha256.hexhash(source()) == current_base_sha, 'historical compact source must remain byte-exact')!
	need(os.real_path('/opt/homebrew/opt/llvm/bin/clang') == '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23',
		'recorded compiler driver alias no longer selects the pinned ordinary executable')!
	mut paths := checker_inputs()!
	for name in ['targets01', 'target-bootstrap01'] {
		paths['historical/' + name] = paths['complete/' + name]
		paths.delete('complete/' + name)
	}
	mut fixed := current_fixed_pins()
	fixed[current_bootstrap + '/compile-04.log'] = sha256.hexhash('')
	fixed[current_state + '/native-consumer-tools-01/preserve-bootstrap-01.log'] = sha256.hexhash('')
	for stem in [current_state + '/native-supervision-host-01/check-02',
		current_state + '/native-consumer-tools-01/retain-01'] {
		for name in ['modules-before.json', 'modules-after.json'] {
			fixed[stem + '.monitor/' + name] = '7574aa941eeea3b7beb3dc58c14f6c23e57aea93bd5349a09f1aa8a51da9abce'
		}
	}
	mut names := fixed.keys()
	names.sort()
	for index, path in names { current_add('profile/pin/' + index.str(), path, fixed[path], started, mut paths)! }
	originals := current_copies(started, mut paths)!
	for name, hash in read_map(current_phase + '/modules-before.json')! {
		resolved := current_as_run(name, originals)
		pin(resolved, hash, started)!
		need(resolved in paths.values(), 'as-run source/tool was not bound by current profile: ' + name)!
	}
	for map_path in [current_bootstrap + '/modules-before.json',
		current_bootstrap + '/current-audit-compiled-modules.json'] {
		for name, hash in read_map(map_path)! { pin(current_as_run(name, originals), hash, started)! }
	}
	for role_index, name in ['targets01', 'target-bootstrap01'] {
		hash := current_manifests()[name]
		root := if name == 'targets01' { target_root } else { bootstrap_root }
		fresh := current_phase + '/' + name + '/inventory.json'
		current_add('complete/' + name, fresh, hash, started, mut paths)!
		current_add('checksum/' + name, current_phase + '/' + name + '/inventory.sha256',
			sha256.hexhash(hash + '  inventory.json\n'), started, mut paths)!
		for action_index, action in ['original-refusal', 'current-seal', 'current-check'] {
			command := if action == 'current-seal' { 'seal' } else { 'check' }
			last := if action == 'original-refusal' { complete_root + '/' + name + '/inventory.json' }
				else if action == 'current-seal' { current_phase + '/' + name } else { fresh }
			base := current_phase + '/' + action + '-' + name
			code := if action == 'original-refusal' { 1 } else { 0 }
			marker := if action == 'original-refusal' { 'state inventory mismatch\n' }
				else if action == 'current-seal' { 'FRAME-PAGE COMPLETE STATE PASS ' + hash + '\n' }
				else { 'FRAME-PAGE COMPLETE STATE CHECK PASS\n' }
			for part_index, part in ['argv.json', 'exit.json', 'log'] {
				value := if part == 'argv.json' { json2.encode([original_checker, command, root, last]) }
					else if part == 'exit.json' { json2.encode({'exit_code': code}) } else { marker }
				role := 'profile/run/' + role_index.str() + '/' + action_index.str() + '/' + part_index.str()
				current_add(role, base + '.' + part, sha256.hexhash(value), started, mut paths)!
			}
		}
	}
	for index, name in ['before', 'after'] {
		base := current_phase + '/frozen-tools-' + name
		for part_index, part in ['argv.json', 'exit.json', 'log'] {
			value := if part == 'argv.json' { json2.encode([current_bootstrap + '/compact-projection-02', '--verify-frozen']) }
				else if part == 'exit.json' { json2.encode({'exit_code': 0}) }
				else { 'PASS complete frozen old tool root metadata, paths, contents and links unchanged\n' }
			current_add('profile/frozen/' + index.str() + '/' + part_index.str(), base + '.' + part,
				sha256.hexhash(value), started, mut paths)!
		}
	}
	current_add('profile/base-source', os.dir(@FILE) + '/admit.v', current_base_sha, started, mut paths)!
	current_add('profile/current-source', @FILE, sha256.hexhash(source_current()), started, mut paths)!
	need(paths.len <= 138, 'current profile exceeds138 fixed input roles')!
	for role, path in paths { current_path_bound(role, path)! }
	deadline(started)!
	return paths
}

fn current_frozen_roots() []string {
	return [current_phase, current_owner, current_bootstrap, current_capture,
		current_state + '/native-supervision-host-01',
		current_state + '/native-consumer-tools-01/preserve-source-01',
		'/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain']
}

fn current_output(path string) ! {
	current_path_bound('', path)!
	mutable_output(path)!
	for root in current_frozen_roots() {
		need(path != root && !path.starts_with(root + '/'), 'current audit output cannot change its frozen provenance')!
	}
	for input in current_fixed_pins().keys() { need(path != input, 'current output cannot replace a fixed proof input')! }
}

pub fn check_current_audits(check OriginalCheck) !CurrentAudits {
	started := time.sys_mono_now()
	checker_paths := current_profile_inputs()!
	mut paths := checker_paths.clone()
	for name in ['targets01', 'target-bootstrap01'] {
		root := if name == 'targets01' { target_root } else { bootstrap_root }
		argv := [original_checker, 'check', root, paths['complete/' + name]]
		run := check(argv, 'compact-current-' + name)!
		for path in [run.argv_path, run.log_path, run.exit_path] { current_output(path)! }
		verify_run(run, argv)!
		paths['audit/' + name + '/argv'] = run.argv_path
		paths['audit/' + name + '/log'] = run.log_path
		paths['audit/' + name + '/exit'] = run.exit_path
	}
	need(current_profile_inputs()! == checker_paths, 'current metadata profile changed during whole-root checks')!
	mut hashes := map[string]string{}
	for name, path in paths { hashes[name] = digest(path, time.sys_mono_now())! }
	return CurrentAudits{Audits{true, started, paths, hashes}}
}

pub fn (audits CurrentAudits) inputs() !map[string]string { return audits.audit.inputs() }

pub fn (audits CurrentAudits) write_record(path string) !string {
	paths := audits.inputs()!
	need(os.is_abs_path(path) && os.real_path(os.dir(path)) == os.dir(path)
		&& !os.exists(path) && !os.is_link(path), 'current audit record requires fresh canonical output')!
	current_output(os.dir(path))!
	record := AuditRecord{scope: current_record_scope, source_sha256: sha256.hexhash(source_current()),
		paths: paths, hashes: audits.audit.hashes.clone()}
	value := json2.encode(record) + '\n'
	need(value.len <= 65536, 'current audit record exceeds unchanged64KiB bound')!
	os.write_file(path, value)!
	pin(path, sha256.hexhash(value), time.sys_mono_now())!
	return sha256.hexhash(value)
}

fn current_recorded_inputs(path string) !map[string]string {
	value := text(path, time.sys_mono_now())!
	need(value.len <= 65536, 'current recorded audit exceeds unchanged64KiB bound')!
	record := json2.decode[AuditRecord](value, strict: true)!
	need(value == json2.encode(record) + '\n' && record.format == 1
		&& record.scope == current_record_scope && record.source_sha256 == sha256.hexhash(source_current()),
		'current recorded audit header differs')!
	checker_paths := current_profile_inputs()!
	mut wanted := checker_paths.keys()
	for name in ['targets01', 'target-bootstrap01'] {
		for part in ['argv', 'log', 'exit'] { wanted << 'audit/' + name + '/' + part }
	}
	wanted.sort()
	mut actual := record.paths.keys()
	actual.sort()
	mut hashed := record.hashes.keys()
	hashed.sort()
	need(actual == wanted && hashed == wanted, 'current recorded audit roles differ')!
	for name, expected in checker_paths { need(record.paths[name] == expected, 'current recorded fixed path differs')! }
	for name, input in record.paths { pin(input, record.hashes[name], time.sys_mono_now())! }
	for name in ['targets01', 'target-bootstrap01'] {
		root := if name == 'targets01' { target_root } else { bootstrap_root }
		run := CheckRun{0, record.paths['audit/' + name + '/argv'], record.paths['audit/' + name + '/log'],
			record.paths['audit/' + name + '/exit']}
		for output in [run.argv_path, run.log_path, run.exit_path] { current_output(output)! }
		verify_run(run, [original_checker, 'check', root, checker_paths['complete/' + name]])!
	}
	return record.paths
}

fn current_import_receipt(arch string, build_sha string) ImportReceipt {
	return ImportReceipt{method: current_import_method, architecture: arch, bundle: bundle_root,
		sealed_manifest_sha256: bundle_sha256, complete_manifest_sha256: current_manifests()['targets01'],
		source_sha256: sha256.hexhash(source_current()), desktop_build_sha256: build_sha}
}

// This is a new import, not a rewrite of a historical import/build receipt.
pub fn current_import_build(arch string, destination string, audits CurrentAudits) !string {
	bundle := admitted(audits.inputs()!)!
	expected := build_manifest(bundle, arch)!
	need(os.is_abs_path(destination) && os.real_path(os.dir(destination)) == os.dir(destination)
		&& !os.exists(destination) && !os.is_link(destination), 'current import requires fresh canonical output')!
	current_output(os.dir(destination))!
	for root in [compact_root, hosted_root, hosted_bundle, os.dir(original_checker)] {
		need(destination != root && !destination.starts_with(root + '/'), 'current import cannot modify frozen evidence')!
	}
	for root in current_frozen_roots() {
		need(destination != root && !destination.starts_with(root + '/'), 'current import cannot modify frozen evidence')!
	}
	os.mkdir(destination, mode: 0o700)!
	os.cp_all(bundle_root + '/source', destination + '/source', false)!
	need(inventory(destination + '/source')! == bundle.sources, 'current imported sources differ')!
	os.mkdir(destination + '/app')!
	for name in ['app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
		os.cp(bundle_root + '/' + arch + '/' + name, destination + '/' + name)!
		pin(destination + '/' + name, expected[name], time.sys_mono_now())!
	}
	os.write_file(destination + '/desktop-build.json', json2.encode(expected) + '\n')!
	os.write_file(destination + '/import.json', json2.encode(current_import_receipt(arch,
		digest(destination + '/desktop-build.json', time.sys_mono_now())!)) + '\n')!
	pin(bundle_root + '/bundle.sha256', bundle_sha256, time.sys_mono_now())!
	return bundle_sha256
}

pub fn current_assembled(desktop string, stage string, arch string, compiler string, audits CurrentAudits) !map[string]string {
	return current_assembled_inputs(admitted(audits.inputs()!)!, desktop, stage, arch, compiler)
}

fn current_assembled_inputs(bundle Bundle, desktop string, stage string, arch string, compiler string) !map[string]string {
	expected := build_manifest(bundle, arch)!
	value := text(desktop + '/import.json', time.sys_mono_now())!
	receipt := json2.decode[ImportReceipt](value, strict: true)!
	need(value == json2.encode(receipt) + '\n' && receipt == current_import_receipt(arch,
		digest(desktop + '/desktop-build.json', time.sys_mono_now())!), 'current imported receipt identity differs')!
	need(read_map(desktop + '/desktop-build.json')! == expected
		&& inventory(desktop + '/source')! == bundle.sources, 'current imported build/source inventory differs')!
	mut result := launchproof.assembled(hosted_root + '/import-' + arch, stage, arch, compiler)!
	for name, path in bundle.inputs { result[name] = path }
	result['compact/import.json'] = desktop + '/import.json'
	result['compact/desktop-build.json'] = desktop + '/desktop-build.json'
	for name in bundle.sources.keys() { result['compact/desktop/source/' + name] = desktop + '/source/' + name }
	for name in ['app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
		pin(desktop + '/' + name, expected[name], time.sys_mono_now())!
		result['compact/desktop/' + name] = desktop + '/' + name
	}
	return result
}

// Static replay of a source-bound producer's exact expected pre/post record
// hashes. This preserves the existing protocol and launches no checker.
pub fn recorded_current_assembled(desktop string, stage string, arch string, compiler string,
	before_record string, before_sha256 string, after_record string, after_sha256 string) !map[string]string {
	need(before_record != after_record, 'distinct current producer pre/post records required')!
	pin(before_record, before_sha256, time.sys_mono_now())!
	pin(after_record, after_sha256, time.sys_mono_now())!
	before := current_recorded_inputs(before_record)!
	after := current_recorded_inputs(after_record)!
	for name, path in before {
		if name.starts_with('audit/') { need(path != after[name], 'current producer reused an audit output path')! }
	}
	mut result := current_assembled_inputs(admitted(before)!, desktop, stage, arch, compiler)!
	result['compact/audit-record/before'] = before_record
	result['compact/audit-record/after'] = after_record
	for name, path in after { result['compact/post/' + name] = path }
	return result
}
