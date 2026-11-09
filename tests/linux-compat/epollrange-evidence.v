// SPDX-License-Identifier: GPL-2.0-or-later
// Audit the complete preserved bundle, including baseline and maintained runs.
module main

import crypto.sha256
import epollrangecheck
import epollmaxcheck
import epollnegativecheck
import epollfilecheck
import opathepollcheck
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn require(good bool, reason string) ! { if !good { return error(reason) } }

fn mapping(path string) !map[string]json2.Any {
	return (json2.decode[json2.Any](os.read_file(path)!)!).as_map()
}

fn preserved(path string, root string) string {
	if path.contains('/tests/linux-compat/epollrange') {
		return root + '/source/' + path.all_after('/tests/linux-compat/')
	}
	return path
}

fn pins(values map[string]json2.Any, root string, mut artifacts map[string]string) ! {
	require(values.len > 0, 'Empty input/output manifest')!
	for original, expected in values {
		path := preserved(original, root)
		require(digest(path)! == expected.str(), 'Changed preserved artifact: ' + path)!
		artifacts[path] = expected.str()
	}
}

fn remember(state string, names []string, mut artifacts map[string]string) ! {
	for name in names { artifacts[state + '/' + name] = digest(state + '/' + name)! }
}

fn native(state string, arch string, kernel string, probe string, root string, mut artifacts map[string]string) ! {
	receipt := mapping(state + '/receipt.json')!
	require(receipt['architecture']!.str() == arch && receipt['kernel']!.str() == kernel
		&& receipt['probe']!.str() == probe, 'Different native input')!
	require(receipt['finished']!.bool() && receipt['passed']!.bool() && receipt['status']!.int() == 0, 'Incomplete native guest')!
	require(receipt['serial']!.str() == digest(state + '/serial.log')!, 'Changed native log')!
	require(digest(state + '/rootfs/sbin/init')! == probe && digest(state + '/kernel/bin/vinix')! == kernel, 'Changed native snapshot')!
	pins(mapping(state + '/inputs.json')!, root, mut artifacts)!
	remember(state, ['receipt.json', 'inputs.json', 'serial.log', 'test.iso', 'initramfs.tar',
		'qemu.command.json', 'rootfs/sbin/init', 'kernel/bin/vinix'], mut artifacts)!
}

fn maskwait(text string) ! {
	mut wanted := map[string]int{}
	for ordinary in 0 .. 2 {
		for signal in [10, 12] {
			for kind in 0 .. 6 {
				for mode in 0 .. 4 {
					checks := 11 + (if mode == 1 { 3 } else { 0 }) + (if kind in [1, 2, 3, 4] {
						2
					} else {
						0
					})
					line := 'LINUX MASKWAIT CASE: uid=' + if ordinary == 0 {
						'0 gid=0'
					} else {
						'1000 gid=2000'
					} +
						' signal=' + signal.str() + ' wait=' + kind.str() + ' mode=' + mode.str() + ' checks=' + checks.str() + ' failures=0'
					wanted[line] = 1
				}
			}
		}
	}
	wanted['LINUX MASKWAIT SUMMARY: checks=1256 failures=0'] = 1
	wanted['LINUX MASKWAIT: PASS'] = 1
	mut actual := map[string]int{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('LINUX MASKWAIT') { actual[line]++ }
	}
	require(actual == wanted, 'Incomplete masked-wait regression')!
}

fn check() ! {
	if os.args.len != 2 { return error('Usage: epollrange-evidence BUNDLE') }
	root := os.real_path(os.args[1])
	mut artifacts := map[string]string{}
	remember(root + '/source', ['epollrangefixture/core.v', 'epollrangereferenceinit/core.v',
		'epollrangecheck/core.v', 'epollrange-reference.v', 'epollrange-evidence.v', 'run-epollrange.v'], mut artifacts)!
	epollrangecheck.self_test()!
	for arch in ['aarch64', 'x86_64'] {
		suffix := if arch == 'aarch64' { 'arm' } else { 'x86' }
		compile := root + '/compile-' + suffix + '-r1'
		compiled := mapping(compile + '/receipt.json')!
		require(compiled['architecture']!.str() == arch, 'Wrong compile architecture')!
		pins(compiled['inputs']!.as_map(), root, mut artifacts)!
		pins(compiled['outputs']!.as_map(), root, mut artifacts)!
		remember(compile, ['receipt.json', 'fixture.c', 'serial.c', 'reference.c', 'probe',
			'reference-init'], mut artifacts)!
		probe := digest(compile + '/probe')!
		launcher := digest(compile + '/reference-init')!
		build := root + '/build-' + suffix
		pins(mapping(build + '/inputs.json')!, root, mut artifacts)!
		pins(mapping(build + '/outputs.json')!, root, mut artifacts)!
		remember(build, ['inputs.json', 'outputs.json', 'build.log', 'build.log.command.json',
			'build.log.status', 'kernel/bin/vinix', 'blob.c'], mut artifacts)!
		require(os.read_file(build + '/build.log.status')!.trim_space() == '0', 'Kernel build failed')!
		kernel := digest(build + '/kernel/bin/vinix')!
		state := root + '/native-' + suffix + '-r1'
		native(state, arch, kernel, probe, root, mut artifacts)!
		epollrangecheck.verify(os.read_file(state + '/serial.log')!, arch, false, false)!
		if arch == 'aarch64' {
			smoke := root + '/standalone-arm-r1'
			receipt := mapping(smoke + '/receipt.json')!
			require(receipt['architecture']!.str() == arch && receipt['finished']!.bool() && receipt['passed']!.bool() && receipt['status']!.int() == 0, 'Incomplete standalone run')!
			require(receipt['probe']!.str() == probe && receipt['kernel']!.str() == kernel && receipt['serial']!.str() == digest(smoke + '/serial.log')!, 'Different standalone input/output')!
			require(digest(smoke + '/init')! == probe && digest(smoke + '/kernel/bin/vinix')! == kernel && receipt['source']!.str() == digest(root + '/source/epollrangefixture/core.v')!, 'Changed standalone snapshot')!
			epollrangecheck.verify(os.read_file(smoke + '/serial.log')!, arch, false, false)!
			remember(smoke, ['receipt.json', 'inputs.json', 'serial.log', 'initramfs.tar', 'test.iso',
				'command.json', 'init', 'kernel/bin/vinix'], mut artifacts)!
		}
		reference := root + '/reference-' + suffix + '-r1'
		ref := mapping(reference + '/receipt.json')!
		require(ref['architecture']!.str() == arch && ref['finished']!.bool() && ref['passed']!.bool() && ref['status']!.int() == 0, 'Incomplete Linux reference')!
		ref_artifacts := ref['artifacts']!.as_map()
		require(ref_artifacts['probe']!.str() == probe && ref_artifacts['wrapper_elf']!.str() == launcher, 'Different Linux probe/launcher')!
		for label, name in {
			'kernel':      'linux'
			'probe':       'probe'
			'wrapper_elf': 'init'
			'initramfs':   'initramfs.cpio'
			'serial':      'serial.log'
		} {
			require(ref_artifacts[label]!.str() == digest(reference + '/' + name)!, 'Changed Linux artifact')!
		}
		pins(mapping(reference + '/inputs.json')!, root, mut artifacts)!
		remember(reference, ['receipt.json', 'inputs.json', 'serial.log', 'initramfs.cpio', 'linux',
			'probe', 'init', 'command.json'], mut artifacts)!
		epollrangecheck.verify(os.read_file(reference + '/serial.log')!, arch, false, true)!
		baseline := root + '/baseline-' + suffix + '-r1'
		baseline_kernel := digest(os.dir(root) + '/epollmax-20261109/build-' + suffix + '/kernel/bin/vinix')!
		native(baseline, arch, baseline_kernel, probe, root, mut artifacts)!
		epollrangecheck.verify(os.read_file(baseline + '/serial.log')!, arch, true, false)!
		for label in ['max', 'negative', 'opathepoll', 'epollfile', 'async', 'maskwait'] {
			regression := root + '/regression-' + label + '-' + suffix
			text := os.read_file(regression + '/serial.log')!
			native(regression, arch, kernel, digest(regression + '/rootfs/sbin/init')!, root, mut artifacts)!
			for bad in ['FAIL', 'MISMATCH', 'KERNEL PANIC', 'FATAL EXCEPTION'] {
				require(!text.contains(bad), 'Regression failure: ' + bad)!
			}
			if label == 'max' {
				epollmaxcheck.verify(text, arch, false, false)!
			} else if label == 'negative' {
				epollnegativecheck.verify(text, arch, false, false)!
			} else if label == 'opathepoll' {
				opathepollcheck.verify(text, arch, false, false)!
			} else if label == 'epollfile' {
				epollfilecheck.verify(text, arch, false, false)!
			} else if label == 'maskwait' {
				maskwait(text)!
			} else {
				actual := text.split_into_lines().map(it.trim_space()).filter(it.starts_with('LINUX POLLASYNC'))
				require(actual == ['LINUX POLLASYNC CASE: vmpressure PASS',
					'LINUX POLLASYNC CASE: cgroup PASS', 'LINUX POLLASYNC CASE: virtual-files PASS',
					'LINUX POLLASYNC CASE: pidfd PASS', 'LINUX POLLASYNC SUMMARY: cases=4 failures=0',
					'LINUX POLLASYNC: PASS'], 'Incomplete asynchronous regression')!
			}
		}
		println('Epoll output-range evidence: PASS ' + arch)
	}
	os.write_file(root + '/epollrange-artifacts.json', json2.encode(artifacts, prettify: true) + '\n')!
}

fn main() {
	check() or {
		eprintln(err.msg())
		exit(1)
	}
}
