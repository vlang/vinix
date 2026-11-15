// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2

fn check() ! {
	if os.args.len !in [5, 6] { return error('usage: CHECK CONTROLLER PRODUCER RETAINER FRESH_OUTPUT [PREPARED]') }
	out := os.abs_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('fresh host startup control output required') }
	os.mkdir_all(out)!
	mut passed := []string{}
	for index, role in ['controller', 'producer', 'retainer'] {
		original := os.real_path(os.args[index + 1])
		for kind in ['missing', 'linked', 'moved', 'role', 'format'] {
			dir := out + '/' + role + '-' + kind
			os.mkdir_all(dir)!
			os.cp(original, dir + '/program')!; os.chmod(dir + '/program', 0o755)!
			mut expected := 'host build receipt required beside executable'
			if kind == 'linked' { os.symlink(os.dir(original) + '/host-build.json', dir + '/host-build.json')! }
			else if kind != 'missing' {
				mut proof := json2.decode[map[string]json2.Any](os.read_file(os.dir(original) + '/host-build.json')!)!
				if kind != 'moved' { proof['directory'] = json2.Any(dir) }
				if kind == 'role' { proof['role'] = json2.Any('fixture') }
				if kind == 'format' { proof['format'] = json2.Any(0) }
				os.write_file(dir + '/host-build.json', json2.encode(proof))!
				expected = if kind == 'format' { 'host build declaration differs' } else { 'host executable binding differs' }
			}
			output := dir + '/must-not-exist'
			args := match role {
				'controller' { ['x86_64', output, '/missing', '/missing', '/missing', '/missing', '/missing', '/missing', '--owned-manager'] }
				'producer' { ['x86_64', '/missing', output, '/missing', '/missing', '/missing', '/missing', '/missing', '--local-qualification-only', '--owned-manager'] }
				else { ['/missing', '/missing', 'x86_64', output, '--owned-holder-death'] }
			}
			os.write_file(dir + '/argv.json', json2.encode(args))!
			mut child := os.new_process(dir + '/program')
			child.set_args(args); child.set_redirect_stdio_merged(); child.run()
			C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
			text := child.stdout_slurp(); child.wait()
			status := child.code; child.close()
			os.write_file(dir + '/run.log', text)!
			if status == 0 || !text.contains(expected) || os.exists(output) { return error('host startup gate did not refuse before output: ' + role + '-' + kind) }
			passed << role + '-' + kind
		}
	}
	if os.args.len == 6 {
		prepared := os.real_path(os.args[5])
		for kind in ['linked', 'hash', 'input'] {
			dir := out + '/prepared-' + kind
			for file in ['owned-manager.json', 'outputs.json', 'logs/v.log.argv.json', 'prepared/x86_64/runtime/bin/wine-runner', 'host-producer.json', 'build-producer.json', 'inputs-before-build.json'] {
				os.mkdir_all(os.dir(dir + '/' + file))!; os.cp(prepared + '/' + file, dir + '/' + file)!
			}
			mut binding := json2.decode[map[string]string](os.read_file(dir + '/host-producer.json')!)!
			mut expected := 'host build binding record differs'
			if kind == 'linked' {
				os.rm(dir + '/host-producer.json')!; os.symlink(prepared + '/host-producer.json', dir + '/host-producer.json')!
				expected = 'host build evidence must be bounded and ordinary'
			} else if kind == 'hash' {
				binding['proof_sha256'] = 'bad'; os.write_file(dir + '/host-producer.json', json2.encode(binding))!
			} else {
				mut inputs := json2.decode[map[string]string](os.read_file(dir + '/inputs-before-build.json')!)!
				inputs.delete(binding['directory'] + '/host-build.json')
				os.write_file(dir + '/inputs-before-build.json', json2.encode(inputs))!
				expected = 'host build artifact input absent or changed'
			}
			output := dir + '/native-must-stay-empty'
			mut child := os.new_process(os.real_path(os.args[1]))
			child.set_args(['x86_64', output, dir, '/missing', '/missing', '/missing', '/missing', '/missing', '--owned-manager'])
			child.set_redirect_stdio_merged(); child.run()
			C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
			text := child.stdout_slurp(); child.wait()
			status := child.code; child.close()
			os.write_file(dir + '/run.log', text)!
			if status == 0 || !text.contains(expected) || (os.exists(output) && os.ls(output)!.len != 0) {
				return error('prepared host binding did not refuse before signing/build output: ' + kind)
			}
			passed << 'prepared-' + kind
		}
	}
	os.write_file(out + '/result.json', json2.encode(passed))!
	println('WINE HOST RECEIPT STARTUP PASS ' + passed.len.str() + ' exact refusals before qualification output')
}

fn main() { check() or { eprintln(err); exit(1) } }
