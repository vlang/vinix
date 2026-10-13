// SPDX-License-Identifier: GPL-2.0-or-later
module devcore

import json2
import crypto.sha256
import os
import time

pub struct BuildStep {
pub:
	name      string
	argv      []string
	directory string = '.'
	artifacts []string
}

pub struct BuildPlan {
pub:
	schema          int = 1
	source          Pin
	inputs          []Pin
	tools           map[string]Pin
	epoch           i64
	timeout_seconds int = 3600
	environment     map[string]string
	steps           []BuildStep
}

pub struct StepReceipt {
pub:
	name      string
	argv      []string
	exit_code int
	artifacts map[string]string
	detail    string
}

pub struct BuildReceipt {
pub:
	schema      int = 1
	plan_sha256 string
	source      Pin
	inputs      []Pin
	tools       map[string]Pin
	epoch       i64
	uid         int
	kernel      string
	started     string
pub mut:
	complete bool
	steps    []StepReceipt
}

fn expand(value string, work string, output string, tools map[string]Pin) !string {
	mut result := value.replace('{work}', work).replace('{output}', output)
	for name, pin in tools { result = result.replace('{' + name + '}', pin.path) }
	if result.contains('{') || result.contains('}') || result.contains('\x00') {
		return error('unknown build substitution: ${value}')
	}
	return result
}

pub fn validate_plan(plan BuildPlan) ! {
	if plan.schema != 1 || plan.steps.len == 0 || plan.epoch < 0
		|| plan.timeout_seconds < 1 || plan.timeout_seconds > 86400 {
		return error('invalid build plan')
	}
	if !os.is_dir(plan.source.path) { return error('source must be a prepared directory') }
	verify(plan.source)!
	for pin in plan.inputs { verify(pin)! }
	for name, pin in plan.tools {
		if name == '' || !name.bytes().all(it.is_alnum() || it == `_`) || name in [
			'work',
			'output',
		] {
			return error('invalid tool name: ${name}')
		}
		verify(pin)!
		if !os.is_executable(pin.path) { return error('tool is not executable: ${pin.path}') }
	}
	mut names := map[string]bool{}
	mut generated := map[string]bool{}
	for step in plan.steps {
		if step.name == '' || !step.name.bytes().all(it.is_alnum() || it in [`-`, `_`])
			|| step.name in names || step.argv.len == 0 {
			return error('build steps need unique names and argv')
		}
		names[step.name] = true
		relative_path(step.directory)!
		for artifact in step.artifacts { relative_path(artifact)! }
		for arg in step.argv { expand(arg, '/work', '/output', plan.tools)! }
		// Require the top-level executable to be pinned, including make/tar.
		if !plan.tools.keys().any(step.argv[0] == '{' + it + '}')
			&& !generated[step.argv[0]] {
			return error('step executable must name a pinned tool: ${step.name}')
		}
		for artifact in step.artifacts { generated['{work}/' + artifact] = true }
	}
}

fn save_receipt(output string, receipt BuildReceipt) ! {
	os.write_file(output + '/receipt.json', json2.encode(receipt, prettify: true) + '\n')!
}

pub fn build(plan_text string, output_path string) !BuildReceipt {
	check_interrupted()!
	plan := json2.decode[BuildPlan](plan_text, strict: true)!
	validate_plan(plan)!
	absolute_output := os.abs_path(output_path)
	output := os.real_path(os.dir(absolute_output)) + '/' + os.file_name(absolute_output)
	source := os.real_path(plan.source.path)
	if output == source || output.starts_with(source + '/') {
		return error('output must be outside the pinned source')
	}
	fresh_directory(output)!
	os.mkdir(output + '/home', mode: 0o700)!
	os.mkdir(output + '/tmp', mode: 0o700)!
	work := output + '/work'
	mut receipt := BuildReceipt{
		plan_sha256: sha256_text(plan_text)
		source:      plan.source
		inputs:      plan.inputs
		tools:       plan.tools
		epoch:       plan.epoch
		uid:         os.getuid()
		kernel:      os.uname().sysname
		started:     time.now().format_rfc3339()
	}
	save_receipt(output, receipt)!
	copy_tree(source, work)!
	// Catch source mutation during the copy before executing anything.
	if tree_hash(work)! != plan.source.sha256 { return error('source changed while copying') }
	mut env := environment(plan.epoch)
	env['HOME'] = output + '/home'
	env['TMPDIR'] = output + '/tmp'
	for name, value in plan.environment { env[name] = expand(value, work, output, plan.tools)! }
	mut generated := map[string]string{}
	for step in plan.steps {
		check_interrupted()!
		argv := step.argv.map(expand(it, work, output, plan.tools)!)
		if expected := generated[argv[0]] { verify(Pin{argv[0], expected})! }
		cwd := work + '/' + step.directory
		if !os.is_dir(cwd) || !os.real_path(cwd).starts_with(work + '/') && os.real_path(cwd) != work {
			return error('step directory escapes workspace: ${step.directory}')
		}
		println('Building ${step.name}')
		status := run(argv, cwd, env, plan.timeout_seconds, output + '/' + step.name + '.log') or {
			receipt.steps << StepReceipt{ name: step.name, argv: argv, exit_code: -1, detail: err.msg() }
			save_receipt(output, receipt)!
			return err
		}
		mut artifacts := map[string]string{}
		mut detail := ''
		if status == 0 {
			for path in step.artifacts {
				resolved := os.real_path(work + '/' + path)
				if !resolved.starts_with(work + '/') || !os.is_file(resolved) {
					detail = 'missing or escaped artifact: ${path}'
					break
				}
				artifacts[path] = file_hash(resolved)!
				generated[work + '/' + path] = artifacts[path]
			}
		}
		receipt.steps << StepReceipt{
			name:      step.name
			argv:      argv
			exit_code: status
			artifacts: artifacts
			detail:    detail
		}
		save_receipt(output, receipt)!
		if status != 0 || detail != '' {
			return error('${step.name} failed; see ${output}/receipt.json')
		}
	}
	// Inputs, including external SDK closures, must still match after the run.
	verify(plan.source)!
	for pin in plan.inputs { verify(pin)! }
	for _, pin in plan.tools { verify(pin)! }
	receipt.complete = true
	save_receipt(output, receipt)!
	return receipt
}

fn sha256_text(value string) string {
	return sha256.sum(value.bytes()).hex()
}
