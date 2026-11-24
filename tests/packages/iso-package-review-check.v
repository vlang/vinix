// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os

const applications = 'VINIX_PACKAGE_IMAGE_APPLICATIONS'

struct Plan {
	architecture string
	applications []string
}

fn receipt(tool string, args []string, env map[string]string) os.Result {
	mut child := os.new_process(tool)
	defer { child.close() }
	child.set_args(args)
	child.set_environment(env)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	return os.Result{ exit_code: child.code, output: output }
}

fn expect_refusal(tool string, name string, reason string, env map[string]string, work string) ! {
	destination := work + '/' + name
	before := os.ls(work)!.sorted()
	result := receipt(tool, ['plan-pair', destination], env)
	if result.exit_code == 0 || !result.output.contains(reason) ||
		os.ls(work)!.sorted() != before || os.exists(destination) || os.is_link(destination) {
		return error('expected clean refusal for ' + name + ': ' + result.output)
	}
	println('PASS ' + name)
}

fn run() ! {
	if os.args.len != 3 {
		return error('usage: iso-package-review-check PACKAGE_RECEIPT NEW_WORK_DIRECTORY')
	}
	tool := os.real_path(os.args[1])
	work := os.args[2]
	os.mkdir(work, mode: 0o700)!
	env := os.environ()
	destination := work + '/reviewed plans'
	first := receipt(tool, ['plan-pair', destination], env)
	if first.exit_code != 0 {
		return error(first.output)
	}
	if os.ls(destination)!.sorted() != ['amd64.json', 'arm64.json'] ||
		os.stat(destination)!.mode & 0o777 != 0o700 {
		return error('expected exactly two plans in the private review directory')
	}
	mut originals := map[string]string{}
	for arch, filename in {'aarch64': 'arm64.json', 'x86_64': 'amd64.json'} {
		path := destination + '/' + filename
		exact := os.read_file(path)!
		single := receipt(tool, ['plan', arch], env)
		plan := json2.decode[Plan](exact)!
		if single.exit_code != 0 || exact != single.output || plan.architecture != arch ||
			plan.applications != ['org.ffmpeg.cli', 'org.ffmpeg.probe', 'org.neovim.editor',
				'org.sqlite.cli', 'org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello'] ||
			!exact.contains('"reviewed_origin":"https://') {
			return error('paired plan differs from the standalone hosted mixed plan for ' + arch)
		}
		originals[filename] = exact
	}
	println('PASS both hosted mixed plans match standalone output byte for byte')

	mut controls := env.clone()
	controls.delete(applications)
	controls.delete(applications + '_AARCH64')
	expect_refusal(tool, 'missing second declaration', 'aarch64 requires an advertised application set', controls, work)!
	controls[applications + '_AARCH64'] = env[applications + '_X86_64']
	expect_refusal(tool, 'wrong second architecture', 'aarch64 package preflight:', controls, work)!
	smaller := work + '/smaller.json'
	os.write_file(smaller, '{"format":1,"architecture":"aarch64","packages":["org.vinix.counter"]}\n')!
	controls[applications + '_AARCH64'] = os.real_path(smaller)
	expect_refusal(tool, 'different valid roots', 'requires the same advertised application IDs', controls, work)!
	controls[applications + '_AARCH64'] = env[applications + '_AARCH64']
	controls['VINIX_PACKAGE_IMAGE_INDEXES_AARCH64'] = os.real_path(smaller)
	expect_refusal(tool, 'invalid second pin', 'aarch64 package preflight:', controls, work)!

	before := os.ls(work)!.sorted()
	second := receipt(tool, ['plan-pair', destination], env)
	if second.exit_code == 0 || !second.output.contains('destination must be new') ||
		os.ls(work)!.sorted() != before {
		return error('existing review directory must be preserved: ' + second.output)
	}
	for filename, exact in originals {
		if os.read_file(destination + '/' + filename)! != exact {
			return error('existing plan bytes changed: ' + filename)
		}
	}
	println('PASS existing review directory and its plans are preserved')
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
