// SPDX-License-Identifier: GPL-2.0-or-later
module m1parity

import crypto.sha256
import g13contract
import json2
import os

pub struct Inputs {
pub:
	vinix    string
	asahi    string
	packages string
	omarchy  string
	m1n1     string
}

pub struct Source {
pub:
	role   string
	path   string
	sha256 string
}

pub struct Gate {
pub:
	name   string
	checks []string
	error  string
}

pub struct Report {
pub:
	format_version int = 1
	verdict        string
	// There is deliberately no full-equivalence success state: these are
	// selected source contracts, not a proof over the entire two drivers.
	full_parity_certified bool
	native_gpu_executed   bool
	revisions             map[string]string
	comparisons           []Comparison
	protocol_gates        []Gate
	unverified_areas      []string
	sources               []Source
}

pub fn (report &Report) exit_code() int {
	if report.protocol_gates.any(it.error != '') { return 2 }
	return 1 // A full parity sign-off is unavailable, even if selected facts match.
}

pub fn (report &Report) markdown() string {
	mut lines := ['# M1 source parity audit', '',
		'Verdict: **${report.verdict}**. Full parity is not certified.',
		'No hardware access, boot, reboot or native GPU execution is performed.', '',
		'## Source revisions', '']
	for role in ['vinix', 'omarchy', 'packages', 'asahi', 'm1n1'] {
		lines << '- ${role}: `${report.revisions[role]}`'
	}
	lines << ['', '## Selected ABI facts', '',
		'DRM command numbers below include base 0x40, not the size/direction encoding of the complete ioctl.',
		'Layouts below describe scalar fields and offsets; matching them would still not prove matching semantics.',
		'', '| Fact | Vinix | Packaged reference | Result |', '| --- | --- | --- | --- |']
	for comparison in report.comparisons {
		lines << '| ${comparison.area} | ${comparison.vinix} | ${comparison.reference} | ${if comparison.matches {
			'same selected fact'
		} else {
			'**different**'
		}} |'
	}
	lines << ['', '## Selected protocol source gates', '']
	for gate in report.protocol_gates {
		lines << '- ${gate.name}: ${if gate.error == '' {
			'passed'
		} else {
			'FAILED: ' + gate.error
		}}'
		for check in gate.checks { lines << '  - ${check}' }
	}
	lines << ['', '## Unverified areas', '']
	for area in report.unverified_areas { lines << '- ${area}' }
	lines << ['', 'Passing a source gate or a host fixture is not complete driver equivalence.',
		'ABI changes require a coordinated kernel and Mesa migration; changing ioctl numbers alone is insufficient.',
		'']
	return lines.join('\n')
}

fn git(root string, args []string) !string {
	mut process := os.new_process('git')
	mut command_args := ['-C', root]
	command_args << args
	process.set_args(command_args)
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp()
	errors := process.stderr_slurp()
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('git ${root}: ${errors.trim_space()}') }
	return output.trim_space()
}

fn require_clean(root string, paths []string) ! {
	mut command_args := ['status', '--porcelain', '--untracked-files=no', '--']
	command_args << paths
	if git(root, command_args)! != '' {
		return error('reference checkout has modified inputs: ${root}')
	}
}

fn package_pin(source string) !string {
	mut found := ''
	for raw in source.split_into_lines() {
		line := raw.trim_space()
		if !line.starts_with('_commit=') { continue }
		if found != '' { return error('duplicate package kernel pin') }
		found = line.all_after('=').trim_space()
	}
	if found.len != 40 || !found.bytes().all(it.is_hex_digit()) {
		return error('package must contain one immutable 40-digit kernel pin')
	}
	return found
}

fn hash_file(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn snapshot(role string, root string, relative string, mut sources []Source) ! {
	path := os.join_path(root, relative)
	if os.is_link(path) { return error('source snapshot cannot follow links: ${path}') }
	if os.is_dir(path) {
		mut names := os.ls(path)!
		names.sort()
		for name in names { snapshot(role, root, os.join_path(relative, name), mut sources)! }
	} else if os.is_file(path) {
		if !path.ends_with('.v') && !path.ends_with('.rs') && !path.ends_with('.py') && !path.ends_with('.c')
			&& !path.ends_with('.h') && os.file_name(path) != 'PKGBUILD' {
			return
		}
		sources << Source{ role: role, path: relative, sha256: hash_file(path)! }
	} else {
		return error('missing source: ${path}')
	}
}

fn root_for(inputs Inputs, role string) !string {
	return match role {
		'vinix' { inputs.vinix }
		'asahi' { inputs.asahi }
		'packages' { inputs.packages }
		'm1n1' { inputs.m1n1 }
		else { return error('unknown source role: ${role}') }
	}
}

pub fn audit(inputs Inputs) !Report {
	package_path := 'pkgbuilds/linux-aurora/PKGBUILD'
	require_clean(inputs.packages, [package_path, 'pkgbuilds/mesa-aurora/PKGBUILD'])!
	require_clean(inputs.asahi, ['drivers/gpu/drm/asahi', 'include/uapi/drm/asahi_drm.h',
		'drivers/gpu/drm/scheduler/sched_entity.c', 'drivers/gpu/drm/scheduler/sched_main.c', 'rust/kernel/drm/sched.rs',
		'drivers/dma-buf/dma-fence.c', 'drivers/dma-buf/sync_file.c', 'drivers/gpu/drm/drm_syncobj.c', 'include/uapi/drm/drm.h'])!
	require_clean(inputs.m1n1, ['rust/src/gpu', 'proxyclient/m1n1/agx', 'proxyclient/m1n1/fw/agx'])!
	pin := package_pin(os.read_file(os.join_path(inputs.packages, package_path))!)!
	mut revisions := map[string]string{}
	for role, root in {
		'vinix':    inputs.vinix
		'omarchy':  inputs.omarchy
		'packages': inputs.packages
		'asahi':    inputs.asahi
		'm1n1':     inputs.m1n1
	} {
		revisions[role] = git(root, ['rev-parse', 'HEAD'])!
	}
	if pin != revisions['asahi'] {
		return error('Asahi checkout does not match package kernel pin ${pin}')
	}
	mut sources := []Source{}
	for role, paths in {
		'vinix':    ['kernel/gpu/agx', 'kernel/drm/syncobj', 'kernel/drm/ioctl/ioctl.v', 'kernel/drm/gem',
			'kernel/drm/drm.v', 'kernel/drm/syncobj_fd.v', 'kernel/drm/wait_storage.v', 'tools/agx-re/m1parity',
			'tools/agx-re/audit_m1_parity.v', 'tools/agx-re/g13contract', 'tools/agx-re/g13layout']
		'asahi':    ['drivers/gpu/drm/asahi', 'include/uapi/drm/asahi_drm.h',
			'drivers/gpu/drm/scheduler/sched_entity.c', 'drivers/gpu/drm/scheduler/sched_main.c', 'rust/kernel/drm/sched.rs',
			'drivers/dma-buf/dma-fence.c', 'drivers/dma-buf/sync_file.c', 'drivers/gpu/drm/drm_syncobj.c', 'include/uapi/drm/drm.h']
		'packages': [package_path, 'pkgbuilds/mesa-aurora/PKGBUILD']
		'm1n1':     ['rust/src/gpu', 'proxyclient/m1n1/agx', 'proxyclient/m1n1/fw/agx']
	} {
		for path in paths { snapshot(role, root_for(inputs, role)!, path, mut sources)! }
	}
	comparisons := compare_abi(os.read_file('${inputs.vinix}/kernel/drm/ioctl/ioctl.v')!,
		os.read_file('${inputs.asahi}/include/uapi/drm/asahi_drm.h')!,
		os.read_file('${inputs.vinix}/kernel/gpu/agx/submission/submission.v')!,
		os.read_file('${inputs.asahi}/drivers/gpu/drm/asahi/file.rs')!)!
	mut gates := []Gate{}
	for name, checks in {
		'm1n1 firmware contracts':                g13contract.check_m1n1_at(inputs.m1n1, inputs.vinix) or {
			gates << Gate{ name: 'm1n1 firmware contracts', error: err.msg() }
			[]string{}
		}
		'Asahi teardown and channel publication': g13contract.check_asahi(inputs.asahi) or {
			gates << Gate{ name: 'Asahi teardown and channel publication', error: err.msg() }
			[]string{}
		}
		'GPU TLBI':                               g13contract.check_tlb_reference(inputs.asahi, inputs.vinix) or {
			gates << Gate{ name: 'GPU TLBI', error: err.msg() }
			[]string{}
		}
		'retirement and recovery':                g13contract.check_queue_recovery_reference(inputs.asahi, inputs.vinix) or {
			gates << Gate{ name: 'retirement and recovery', error: err.msg() }
			[]string{}
		}
		'TVB feedback':                           g13contract.check_tvb_reference(inputs.asahi, inputs.vinix) or {
			gates << Gate{ name: 'TVB feedback', error: err.msg() }
			[]string{}
		}
	} {
		if checks.len > 0 { gates << Gate{ name: name, checks: checks } }
	}
	for source in sources {
		if hash_file(os.join_path(root_for(inputs, source.role)!, source.path))! != source.sha256 {
			return error('source changed during audit: ${source.role}/${source.path}')
		}
	}
	return Report{
		verdict:          if comparisons.any(!it.matches) { 'not_equivalent' } else { 'unverified' }
		revisions:        revisions
		comparisons:      comparisons
		protocol_gates:   gates
		sources:          sources
		unverified_areas: [
			'Complete ABI migration and matched Mesa integration',
			'Modern flat-command ABI integration and full cross-submission admission/backpressure',
			'Complete scheduler dependency/error policy beyond selected own-queue elision and input-errno handling',
			'VM replacement/splitting, reservation fences and object memory accounting',
			'Complete render object defaults and scheduler backpressure',
			'Every remaining firmware field, initialization default and error path',
			'M1 Pro/Max/Ultra topology and multi-die operation',
			'Power management, reset, suspend/resume and complete telemetry',
		]
	}
}

pub fn retain(inputs Inputs, report Report, directory string) ! {
	root := os.real_path(os.dir(directory)) + '/' + os.file_name(directory)
	if os.exists(root) || os.is_link(root) { return error('refusing to overwrite audit evidence') }
	for source_root in [inputs.vinix, inputs.asahi, inputs.packages, inputs.omarchy, inputs.m1n1] {
		canonical := os.real_path(source_root)
		if root == canonical || root.starts_with(canonical + '/') {
			return error('audit evidence must be outside source checkouts')
		}
	}
	os.mkdir_all(root)!
	for source in report.sources {
		path := os.join_path(root_for(inputs, source.role)!, source.path)
		data := os.read_bytes(path)!
		if sha256.sum(data).hex() != source.sha256 {
			return error('source changed before retention: ${path}')
		}
		target := os.join_path(root, 'source', source.role, source.path)
		os.mkdir_all(os.dir(target))!
		os.write_file_array(target, data)!
	}
	os.write_file(os.join_path(root, 'report.json'), json2.encode(report, prettify: true) + '\n')!
	os.write_file(os.join_path(root, 'report.md'), report.markdown())!
}
