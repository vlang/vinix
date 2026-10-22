// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import strings

fn digest(path string) !string {
	return sha256.hexhash(os.read_file(path)!)
}

fn command(program string, args []string, accepted bool, marker string, mut report strings.Builder) ! {
	report.writeln('COMMAND ' + json2.encode([program, ...args]))
	mut child := os.new_process(program)
	child.set_args(args)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	code := child.code
	child.close()
	report.write_string(output)
	if (code == 0) != accepted {
		return error(program + ': unexpected exit ' + code.str() + '\n' + output)
	}
	if accepted && marker != '' && !output.contains(marker) {
		return error(program + ': missing completion ' + marker)
	}
	if !accepted && output.contains('controls PASS') {
		return error(program + ': refused command printed success')
	}
	report.writeln('EXPECTED ' + if accepted { 'acceptance PASS' } else { 'refusal PASS' })
}

fn run() ! {
	if os.args.len != 5 {
		return error('usage: https-runtime-control-modes COMPILER CC NEW_WORK REPORT')
	}
	root := os.getwd()
	compiler := os.abs_path(os.args[1])
	cc := os.abs_path(os.args[2])
	work := os.abs_path(os.args[3])
	if os.exists(work) || os.is_link(work) {
		return error('work directory must be new: ' + work)
	}
	os.mkdir(work, mode: 0o700)!
	mut report := strings.new_builder(32768)
	mut pins := map[string]string{}
	for path in [compiler, cc, @FILE, os.executable(),
		root + '/tests/packages/https-runtime-retain.v',
		root + '/tests/packages/https-runtime-input-check.v',
		root + '/tests/packages/https-runtime-evidence-check.v',
		root + '/tests/packages/tlsruntime/fixture.v'] {
		pins[path] = digest(path)!
		report.writeln('INPUT ' + path + ' SHA256 ' + pins[path])
	}
	common := ['-cc', cc, '-nocache', '-gc', 'none', '-manualfree', '-path',
		'@vlib|@vmodules|' + root + '/tests/packages']
	for mode in ['normal', 'prod'] {
		flags := if mode == 'normal' { []string{} } else { ['-prod'] }
		for kind in ['retain', 'input-check', 'evidence-check'] {
			program := work + '/' + kind + '-' + mode
			command(compiler, [...flags, ...common, '-o', program,
				root + '/tests/packages/https-runtime-' + kind + '.v'], true, '', mut report)!
			report.writeln('BINARY ' + program + ' SHA256 ' + digest(program)!)
		}
	}
	for name in ['admit', 'reject', 'missing-marker'] {
		path := work + '/fixture-' + name
		os.cp(os.executable(), path)!
		os.chmod(path, 0o700)!
		report.writeln('BINARY ' + path + ' SHA256 ' + digest(path)!)
	}
	mut controls := 0
	for mode in ['normal', 'prod'] {
		for kind in ['input', 'evidence'] {
			program := work + '/' + kind + '-check-' + mode
			marker := if kind == 'input' {
				'GUEST TLS historical input controls PASS'
			} else { 'GUEST TLS evidence controls PASS' }
			for retainer in ['normal', 'prod'] {
				command(program, [work + '/retain-' + retainer], true, marker, mut report)!
				controls += if kind == 'input' { 10 } else { 34 }
			}
			for name in ['admit', 'reject', 'missing-marker'] {
				refused_report := work + '/' + kind + '-' + mode + '-' + name + '.txt'
				command(program, [work + '/fixture-' + name, refused_report], false, '', mut report)!
				if os.exists(refused_report) || os.is_link(refused_report) {
					return error('refused controls published a report: ' + refused_report)
				}
				controls++
			}
			command(program, [], false, '', mut report)!
			command(program, ['unused', 'unused', 'unused'], false, '', mut report)!
			controls += 2
		}
	}
	if controls != 196 { return error('incomplete control matrix') }
	for path, hash in pins {
		if digest(path)! != hash { return error('input changed during qualification: ' + path) }
	}
	report.writeln('GUEST TLS normal/prod drivers and retainers: 176 real controls and 20 refusal controls PASS')
	os.write_file(os.args[4], report.str())!
	println('GUEST TLS normal/prod drivers and retainers: 176 real controls and 20 refusal controls PASS')
}

fn main() {
	match os.base(os.executable()) {
		'fixture-admit' {
			println('GUEST TLS historical input evidence PASS\nGUEST TLS native evidence PASS\nGUEST TLS request evidence PASS')
			return
		}
		'fixture-reject' { exit(1) }
		'fixture-missing-marker' { return }
		else {}
	}
	run() or { eprintln(err); exit(1) }
}
