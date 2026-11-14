// SPDX-License-Identifier: GPL-2.0-or-later
// Retain/check this continuation's source and validation evidence. This does
// not certify full driver parity or substitute for native GPU acceptance.
import crypto.sha256
import json2
import os

const source_paths = [
	'kernel/gpu/agx/tlb/tlb.v',
	'kernel/gpu/agx/tlb/plan.v',
	'kernel/gpu/agx/pgtable/pgtable.v',
	'kernel/gpu/agx/mmu/mmu.v',
	'kernel/gpu/agx/gpu/g13.v',
	'kernel/gpu/agx/gpu/gpu.v',
	'kernel/gpu/agx/gpu/g13_recovery.v',
	'kernel/gpu/agx/fw/channels.v',
	'kernel/gpu/agx/fw/g13_initdata_layout.v',
	'kernel/gpu/agx/fw/initdata_g13_globals.v',
	'kernel/gpu/agx/file/file.v',
	'tools/agx-re/g13layout/core.v',
	'tools/agx-re/g13contract/core.v',
	'tools/agx-re/check_g13_reference_contract.v',
	'tools/agx-re/check_m1_parity_evidence.v',
	'tests/agx-g13-failure/run.v',
	'tests/agx-g13-failure/fixture/gpu/fixture.v',
	'tests/agx-g13-failure/fixture/gpu/agx/event/event.v',
	'tests/agx-g13-failure/fixture/aarch64/timer/timer.v',
	'tests/agx-tlb/run.v',
	'tests/agx-tlb/test.v',
	'tests/agx-tlb/fixture/gpu/agx/tlb/tlb.v',
]

const artifact_paths = [
	'build-aarch64.log',
	'build-x86_64.log',
	'recovery-sanitize.log',
	'tlb-sanitize.log',
	'reference.log',
	'reference-unit.log',
	'abi.log',
	'layouts.log',
	'opp.log',
	'hardware.log',
	'protocol-disassembly.txt',
	'kernel-arm64/kernel/bin/vinix',
	'kernel-x86/kernel/bin/vinix',
]

struct FileDigest {
	path   string
	sha256 string
}

struct Receipt {
	format_version int = 1
	full_parity    bool
	vinix_base     string
	upstream       string = 'bed544bdf93a496ebf70ba180923bab12b6e01cf'
	sources        []FileDigest
	artifacts      []FileDigest
}

fn hash_file(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn git_base(path string) !string {
	mut git := os.new_process('git')
	git.set_args(['-C', path, 'rev-parse', 'HEAD'])
	git.set_redirect_stdio()
	git.run()
	output := git.stdout_slurp()
	git.wait()
	code := git.code
	git.close()
	if code != 0 { return error('cannot identify worktree: ${path}') }
	return output.trim_space()
}

fn record(state string, repo string) ! {
	path := '${state}/parity-evidence.json'
	if os.exists(path) || os.exists('${state}/source') {
		return error('refusing to overwrite retained evidence')
	}
	base := git_base('${state}/kernel-arm64')!
	if base != git_base('${state}/kernel-x86')! { return error('worktree revisions differ') }
	mut sources := []FileDigest{}
	for relative in source_paths {
		hash := hash_file('${repo}/${relative}')!
		if relative.starts_with('kernel/') {
			for build in ['kernel-arm64', 'kernel-x86'] {
				if hash_file('${state}/${build}/${relative}')! != hash {
					return error('${build}: source changed after build: ${relative}')
				}
			}
		}
		sources << FileDigest{ path: relative, sha256: hash }
	}
	mut artifacts := []FileDigest{}
	for relative in artifact_paths {
		artifacts << FileDigest{ path: relative, sha256: hash_file('${state}/${relative}')! }
	}
	for log, marker in {
		'recovery-sanitize.log': 'G13 failure handling: PASS'
		'tlb-sanitize.log':      'context reuse passed'
		'reference.log':         'TVB growth ACK halt counter'
		'reference-unit.log':    '2 passed, 2 total'
		'abi.log':               'G13 firmware ABI translation tests passed'
		'layouts.log':           'G13 work-command layout tests passed'
		'opp.log':               't8103 operating-point table tests passed'
	} {
		if !os.read_file('${state}/${log}')!.contains(marker) {
			return error('missing successful check: ${log}')
		}
	}
	for source in sources {
		destination := '${state}/source/${source.path}'
		os.mkdir_all(os.dir(destination))!
		os.cp('${repo}/${source.path}', destination)!
	}
	receipt := Receipt{ vinix_base: base, sources: sources, artifacts: artifacts }
	os.write_file(path, json2.encode(receipt, prettify: true) + '\n')!
	println('receipt SHA-256: ' + hash_file(path)!)
}

fn check(state string) ! {
	receipt := json2.decode[Receipt](os.read_file('${state}/parity-evidence.json')!)!
	if receipt.format_version != 1 || receipt.full_parity || receipt.sources.len != source_paths.len
		|| receipt.artifacts.len != artifact_paths.len {
		return error('incomplete or unsupported evidence receipt')
	}
	for index, source in receipt.sources {
		if source.path != source_paths[index] || hash_file('${state}/source/${source.path}')! != source.sha256 {
			return error('source snapshot mismatch: ${source.path}')
		}
	}
	for index, artifact in receipt.artifacts {
		if artifact.path != artifact_paths[index] || hash_file('${state}/${artifact.path}')! != artifact.sha256 {
			return error('artifact mismatch: ${artifact.path}')
		}
	}
	println('M1 parity continuation evidence: integrity verified; full parity remains incomplete')
}

fn main() {
	if os.args.len == 4 && os.args[1] == 'record' {
		record(os.real_path(os.args[2]), os.real_path(os.args[3])) or {
			eprintln(err)
			exit(1)
		}
	} else if os.args.len == 3 && os.args[1] == 'check' {
		check(os.real_path(os.args[2])) or {
			eprintln(err)
			exit(1)
		}
	} else {
		eprintln('usage: check_m1_parity_evidence.v record STATE_DIR REPO | check STATE_DIR')
		exit(2)
	}
}
