// SPDX-License-Identifier: GPL-2.0-or-later
// Run independent admission controls without changing the native baseline.
module main

import crypto.sha256
import json2
import os

struct WineControls {
	format          int = 1
	architecture    string
	baseline        bool
	copied_baseline bool
	refused         []string
	inputs          map[string]string
}

fn digest(path string) !string {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	return sha256.hexhash(text)
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

// Every mutation detaches a control's symlink first. Original evidence never
// becomes writable through a copied control.
fn replace(path string, text string) ! {
	if os.exists(path) || os.is_link(path) { os.rm(path)! }
	os.write_file(path, text)!
}

fn clone_tree(source string, destination string) ! {
	os.mkdir_all(destination)!
	for path in os.walk_ext(source, '') {
		if !os.is_file(path) { continue }
		target := destination + path[source.len..]
		os.mkdir_all(os.dir(target))!
		// Source-offer admission deliberately rejects links. Preserve that
		// independent check; all other large immutable files can be shared.
		if path.contains('/publisher-notices/') {
			os.cp(path, target)!
		} else {
			os.symlink(path, target)!
		}
	}
}

fn input_update(run string, removed string, changed string, expected string) ! {
	for name in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json']! {
		mut inputs := read_map(run + '/' + name)!
		if removed != '' { inputs.delete(removed) }
		if changed != '' { inputs[changed] = expected }
		replace(run + '/' + name, json2.encode(inputs) + '\n')!
	}
}

fn prepared_copy(run string, prepared string, destination string) ! {
	clone_tree(prepared, destination)!
	mut declaration := read_map(run + '/declaration.json')!
	declaration['prepared'] = destination
	replace(run + '/declaration.json', json2.encode(declaration) + '\n')!
	for name in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json']! {
		original := read_map(run + '/' + name)!
		mut copied := map[string]string{}
		for path, expected in original {
			copied[if path.starts_with(prepared + '/') {
				destination + path[prepared.len..]
			} else {
				path
			}] = expected
		}
		replace(run + '/' + name, json2.encode(copied) + '\n')!
	}
}

fn reseal_producer(run string, prepared string, name string) ! {
	mut outputs := read_map(prepared + '/outputs.json')!
	outputs[name] = digest(prepared + '/' + name)!
	replace(prepared + '/outputs.json', json2.encode(outputs) + '\n')!
	input_update(run, '', prepared + '/' + name, outputs[name])!
	input_update(run, '', prepared + '/outputs.json', digest(prepared + '/outputs.json')!)!
}

fn admit(retainer string, run string, prepared string, architecture string, output string, log string) !int {
	mut child := os.new_process(retainer)
	defer { child.close() }
	child.set_args([run, prepared, architecture, output])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	defer { unsafe { text.free() } }
	child.wait()
	os.write_file(log, text)!
	return child.code
}

fn checks() ! {
	$if prod {
	} $else {
		return error('compile Wine evidence controls with -prod')
	}
	if os.args.len != 6 {
		return error('usage: wine-evidence-check RETAINER RUN PREPARED ARCH NEW_OUTPUT')
	}
	retainer := os.real_path(os.args[1])
	run := os.real_path(os.args[2])
	prepared := os.real_path(os.args[3])
	architecture := os.args[4]
	proof := os.abs_path(os.args[5])
	if architecture !in ['aarch64', 'x86_64'] || os.exists(proof) {
		return error('unsupported architecture or existing proof directory')
	}
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-evidence-check.v').to_string()) {
		return error('Wine controls source changed')
	}
	os.mkdir_all(proof)!
	inputs := {
		retainer:                   digest(retainer)!
		@FILE:                      digest(@FILE)!
		os.executable():            digest(os.executable())!
		run + '/result.json':       digest(run + '/result.json')!
		run + '/inputs.json':       digest(run + '/inputs.json')!
		prepared + '/outputs.json': digest(prepared + '/outputs.json')!
	}
	if admit(retainer, run, prepared, architecture, proof + '/baseline', proof + '/baseline.log')! != 0 {
		return error('real Wine native evidence baseline was refused')
	}
	baseline_copy := proof + '/copied-baseline'
	clone_tree(run, baseline_copy)!
	prepared_copy(baseline_copy, prepared, baseline_copy + '/prepared')!
	if admit(retainer, baseline_copy, baseline_copy + '/prepared', architecture, baseline_copy + '/retained', proof + '/copied-baseline.log')! != 0 {
		return error('unchanged copied Wine evidence baseline was refused')
	}
	mut names := ['failed', 'interrupted', 'reason', 'missing-ready', 'duplicate-ready', 'missing-pass',
		'marker-order', 'forbidden', 'input-mismatch', 'missing-fixture-input', 'missing-library-input',
		'missing-generated-c', 'missing-generated-log', 'missing-generated-argv', 'changed-generated-c',
		'missing-package-c', 'missing-package-log', 'missing-package-argv', 'changed-package',
		'package-v-argv', 'package-cc-argv', 'changed-account', 'changed-sandbox',
		'producer-c-output-only', 'producer-missing-c', 'producer-missing-log', 'producer-missing-argv',
		'producer-v-argv', 'producer-cc-argv', 'producer-missing-locale', 'producer-missing-intl',
		'producer-changed-locale', 'producer-changed-intl', 'producer-missing-inf',
		'producer-changed-inf', 'pe-executable-binding', 'resealed-prepared-pe', 'source-offer-closure',
		'wine-server-resealed-patch', 'wine-client-resealed-patch']
	if architecture == 'aarch64' {
		names << ['translator-declaration', 'translator-resealed-patch', 'translator-resealed-smoke',
			'missing-smoke-marker', 'missing-arm-loader-input', 'missing-firmware-vars-input',
			'missing-arm-loader-declaration', 'missing-firmware-vars-declaration']
	}
	if architecture == 'x86_64' {
		names << ['missing-iso-input', 'changed-iso-argv', 'x86-firmware-vars']
	}
	mut refused := []string{}
	for name in names {
		directory := proof + '/' + name
		clone_tree(run, directory)!
		mut selected_prepared := prepared
		mut expected := ''
		if name.starts_with('producer-') || name in ['pe-executable-binding', 'resealed-prepared-pe',
			'source-offer-closure', 'translator-declaration', 'translator-resealed-patch',
			'wine-server-resealed-patch', 'wine-client-resealed-patch'] {
			selected_prepared = directory + '/prepared'
			prepared_copy(directory, prepared, selected_prepared)!
		}
		if name in ['missing-arm-loader-input', 'missing-firmware-vars-input'] {
			declaration := read_map(directory + '/declaration.json')!
			key := if name == 'missing-arm-loader-input' { 'arm_loader' } else { 'firmware_vars' }
			input_update(directory, declaration[key], '', '')!
			expected = 'missing required input:'
		} else if name in ['missing-arm-loader-declaration', 'missing-firmware-vars-declaration',
			'x86-firmware-vars'] {
			mut declaration := read_map(directory + '/declaration.json')!
			key := if name == 'missing-arm-loader-declaration' {
				'arm_loader'
			} else {
				'firmware_vars'
			}
			if name == 'x86-firmware-vars' {
				declaration[key] = declaration['firmware']
				expected = 'x86 ARM loader/variable-store declaration must be empty'
			} else {
				declaration.delete(key)
				expected = 'missing ARM boot input declaration:'
			}
			replace(directory + '/declaration.json', json2.encode(declaration))!
		} else if name in ['wine-server-resealed-patch', 'wine-client-resealed-patch'] {
			part := if name == 'wine-server-resealed-patch' {
				'/usr/bin/wineserver'
			} else {
				'/usr/lib/wine/x86_64-unix/ntdll.so'
			}
			file := 'prepared/' + architecture + '/runtime/root' + part
			original := os.read_file(selected_prepared + '/' + file)!
			changed := original.clone()
			unsafe { changed.str[0] ^= 1 }
			replace(selected_prepared + '/' + file, changed)!
			reseal_producer(directory, selected_prepared, file)!
			expected = 'Wine binary differs from the exact private-server patch: '
		} else if name == 'missing-iso-input' {
			declaration := read_map(directory + '/declaration.json')!
			input_update(directory, declaration['iso_bootx64'], '', '')!
			expected = 'missing required input'
		} else if name == 'changed-iso-argv' {
			mut command := json2.decode[[]string](os.read_file(directory + '/boot/image-commands.json')!)!
			command[0] = '/control/unadmitted-image-producer'
			replace(directory + '/boot/image-commands.json', json2.encode(command))!
			expected = 'Wine ISO producer argv differs'
		} else if name in ['failed', 'interrupted', 'reason'] {
			mut outcome := json2.decode[map[string]json2.Any](os.read_file(directory + '/result.json')!)!
			if name == 'failed' {
				outcome['passed'] = false
			} else if name == 'interrupted' {
				outcome['interrupted'] = true
			} else {
				outcome['reason'] = 'control failure'
			}
			replace(directory + '/result.json', json2.encode(outcome))!
			expected = 'requires uninterrupted passing native Wine outcome'
		} else if name in ['missing-ready', 'duplicate-ready', 'missing-pass', 'marker-order',
			'forbidden', 'missing-smoke-marker'] {
			serial := os.read_file(directory + '/boot/serial.log')!
			ready := 'VINIX SIGNED REAL WIN64 READY'
			pass := 'HWTEST PASS packaged-Wine'
			mut changed := serial
			if name == 'missing-ready' {
				changed = serial.replace(ready, 'removed READY')
			} else if name == 'duplicate-ready' {
				changed = serial + '\n' + ready + '\n'
			} else if name == 'missing-pass' {
				changed = serial.replace(pass, 'removed PASS')
			} else if name == 'missing-smoke-marker' {
				changed = serial.replace('HWTEST INFO Wine translated BusyBox true ordinary split-WX control PASS', 'removed smoke')
			} else if name == 'marker-order' {
				changed = serial.replace(ready, '__CONTROL_READY__').replace(pass, ready).replace('__CONTROL_READY__', pass)
			} else {
				changed = serial + '\nHWTEST FAIL injected control\n'
			}
			replace(directory + '/boot/serial.log', changed)!
			expected = if name == 'forbidden' {
				'forbidden serial marker'
			} else if name == 'marker-order' {
				'native Wine marker order differs'
			} else {
				'missing or duplicated exact marker'
			}
		} else if name == 'input-mismatch' {
			mut inputs_map := read_map(directory + '/inputs-verified.json')!
			inputs_map['/control'] = 'changed'
			replace(directory + '/inputs-verified.json', json2.encode(inputs_map))!
			expected = 'Wine input verification differs'
		} else if name in ['missing-fixture-input', 'missing-library-input'] {
			declaration := read_map(directory + '/declaration.json')!
			path := if name == 'missing-fixture-input' {
				declaration['source_root'] + '/tests/packages/wine-native/main.v'
			} else {
				os.dir(declaration['compiler']) + '/vlib/builtin/array.v'
			}
			input_update(directory, path, '', '')!
			expected = 'missing required input'
		} else if name in ['package-v-argv', 'package-cc-argv'] {
			file := 'build-package/' + if name == 'package-v-argv' {
				'v.log.argv.json'
			} else {
				'cc.log.argv.json'
			}
			mut command := json2.decode[[]string](os.read_file(directory + '/' + file)!)!
			command[0] = '/control/unadmitted-package-compiler'
			replace(directory + '/' + file, json2.encode(command))!
			mut generated := read_map(directory + '/generated-before-boot.json')!
			generated[file] = digest(directory + '/' + file)!
			replace(directory + '/generated-before-boot.json', json2.encode(generated))!
			expected = if name == 'package-v-argv' {
				'V producer argv differs'
			} else {
				'C producer argv differs'
			}
		} else if name.starts_with('missing-generated-') || name.starts_with('missing-package-') || name in [
			'changed-generated-c',
			'changed-package',
			'changed-account',
			'changed-sandbox',
			'translator-resealed-smoke',
		] {
			mut generated := read_map(directory + '/generated-before-boot.json')!
			if name.starts_with('missing-package-') {
				generated.delete(if name == 'missing-package-c' {
					'build-package/package.c'
				} else if name == 'missing-package-log' {
					'build-package/cc.log'
				} else {
					'build-package/cc.log.argv.json'
				})
				expected = 'required generated output inventory differs'
			} else if name.starts_with('missing-generated-') {
				generated.delete(if name == 'missing-generated-c' {
					'build-guest/guest.c'
				} else if name == 'missing-generated-log' {
					'build-guest/cc.log'
				} else {
					'build-guest/cc.log.argv.json'
				})
				expected = 'required generated output inventory differs'
			} else {
				file := if name == 'changed-generated-c' {
					'build-guest/guest.c'
				} else if name == 'changed-package' {
					'extras/usr/bin/vinix-package'
				} else if name == 'changed-account' {
					'extras/usr/sbin/vinix-account'
				} else if name == 'changed-sandbox' {
					'extras/usr/bin/vinix-sandbox'
				} else {
					'extras/usr/libexec/wine-qualification/qemu-original'
				}
				replace(directory + '/' + file, 'changed native output\n')!
				if name != 'changed-generated-c' {
					generated[file] = digest(directory + '/' + file)!
				}
				expected = if name == 'changed-generated-c' {
					'required generated output differs'
				} else if name == 'changed-package' {
					'staged package CLI differs from its captured producer'
				} else if name == 'changed-account' {
					'staged account/package tool differs'
				} else if name == 'changed-sandbox' {
					'staged sandbox differs'
				} else {
					'Wine translator smoke output differs from its input'
				}
			}
			replace(directory + '/generated-before-boot.json', json2.encode(generated))!
		} else if name == 'producer-c-output-only' {
			file := 'build/wine-runner.c'
			replace(selected_prepared + '/' + file, 'changed producer C\n')!
			mut outputs := read_map(selected_prepared + '/outputs.json')!
			outputs[file] = digest(selected_prepared + '/' + file)!
			replace(selected_prepared + '/outputs.json', json2.encode(outputs))!
			input_update(directory, '', selected_prepared + '/outputs.json', digest(selected_prepared + '/outputs.json')!)!
			expected = 'input digest mismatch'
		} else if name.starts_with('producer-missing-') {
			file := if name == 'producer-missing-c' {
				'build/wine-runner.c'
			} else if name == 'producer-missing-log' {
				'logs/cc.log'
			} else if name == 'producer-missing-argv' {
				'logs/cc.log.argv.json'
			} else if name == 'producer-missing-inf' {
				'prepared/' + architecture + '/runtime/root/usr/share/wine/wine.inf'
			} else {
				'prepared/' + architecture + '/runtime/root/usr/share/wine/nls/' + if name.ends_with('locale') {
					'locale.nls'
				} else {
					'l_intl.nls'
				}
			}
			os.rm(selected_prepared + '/' + file)!
			mut outputs := read_map(selected_prepared + '/outputs.json')!
			outputs.delete(file)
			replace(selected_prepared + '/outputs.json', json2.encode(outputs))!
			input_update(directory, selected_prepared + '/' + file, selected_prepared + '/outputs.json', digest(selected_prepared + '/outputs.json')!)!
			expected = 'missing required producer output'
		} else if name in ['producer-changed-locale', 'producer-changed-intl', 'producer-changed-inf'] {
			file := 'prepared/' + architecture + '/runtime/root/usr/share/wine/' + if name.ends_with('inf') {
				'wine.inf'
			} else {
				'nls/' + if name.ends_with('locale') { 'locale.nls' } else { 'l_intl.nls' }
			}
			replace(selected_prepared + '/' + file, 'changed Wine NLS resource\n')!
			reseal_producer(directory, selected_prepared, file)!
			expected = 'Wine data resource differs from its distribution input'
		} else if name in ['producer-v-argv', 'producer-cc-argv'] {
			file := if name == 'producer-v-argv' {
				'logs/v.log.argv.json'
			} else {
				'logs/cc.log.argv.json'
			}
			mut command := json2.decode[[]string](os.read_file(selected_prepared + '/' + file)!)!
			command[0] = '/control/unadmitted-compiler'
			replace(selected_prepared + '/' + file, json2.encode(command))!
			reseal_producer(directory, selected_prepared, file)!
			expected = if name == 'producer-v-argv' {
				'V producer argv differs'
			} else {
				'C producer argv differs'
			}
		} else if name == 'pe-executable-binding' {
			mut record := read_map(selected_prepared + '/pe-producer.json')!
			record['executable'] = '/control/other.exe'
			replace(selected_prepared + '/pe-producer.json', json2.encode(record))!
			reseal_producer(directory, selected_prepared, 'pe-producer.json')!
			expected = 'Wine PE executable binding differs'
		} else if name == 'resealed-prepared-pe' {
			file := 'prepared/' + architecture + '/application/bin/program.exe'
			replace(selected_prepared + '/' + file, 'changed PE\n')!
			reseal_producer(directory, selected_prepared, file)!
			expected = 'Wine prepared PE differs from its admitted producer'
		} else if name == 'source-offer-closure' {
			file := 'publisher-notices/source-offer.json'
			text := os.read_file(selected_prepared + '/' + file)!
			if !text.contains('"source_closure_complete":false') {
				return error('control did not locate source closure field')
			}
			replace(selected_prepared + '/' + file, text.replace('"source_closure_complete":false', '"source_closure_complete":true'))!
			reseal_producer(directory, selected_prepared, file)!
			expected = 'local'
		} else if name == 'translator-declaration' {
			file := 'translator-patch.json'
			mut patch := read_map(selected_prepared + '/' + file)!
			patch['after'] = 'unadmitted patch'
			replace(selected_prepared + '/' + file, json2.encode(patch))!
			reseal_producer(directory, selected_prepared, file)!
			expected = 'Wine translator patch declaration differs'
		} else if name == 'translator-resealed-patch' {
			file := 'prepared/' + architecture + '/runtime/bin/qemu-x86_64'
			original := os.read_file(selected_prepared + '/' + file)!
			changed := original.clone()
			unsafe { changed.str[0x85c64] ^= 1 }
			replace(selected_prepared + '/' + file, changed)!
			reseal_producer(directory, selected_prepared, file)!
			mut patch := read_map(selected_prepared + '/translator-patch.json')!
			patch['output_sha256'] = digest(selected_prepared + '/' + file)!
			replace(selected_prepared + '/translator-patch.json', json2.encode(patch))!
			reseal_producer(directory, selected_prepared, 'translator-patch.json')!
			expected = 'Wine translator differs from the exact split-WX patch'
		} else {
			return error('unimplemented Wine control: ' + name)
		}
		out := directory + '/retained'
		log := proof + '/' + name + '.log'
		if admit(retainer, directory, selected_prepared, architecture, out, log)! == 0 || os.exists(out) {
			return error('corrupted Wine evidence accepted or created output: ' + name)
		}
		if !os.read_file(log)!.contains(expected) {
			return error('Wine control failed at a different gate: ' + name + '; expected ' + expected)
		}
		refused << name
	}
	for path, expected in inputs {
		if digest(path)! != expected { return error('Wine control baseline changed: ' + path) }
	}
	os.write_file(proof + '/controls.json', json2.encode(WineControls{
		architecture:    architecture
		baseline:        true
		copied_baseline: true
		refused:         refused
		inputs:          inputs
	}) + '\n')!
	println('WINE EVIDENCE CONTROLS PASS ' + architecture + ': real and copied baselines plus ' + refused.len.str() + ' refusals')
}

fn main() {
	checks() or {
		eprintln(err)
		exit(1)
	}
}
