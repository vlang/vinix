// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise evidence admission without changing the real run or desktop build.
module main

import crypto.sha256
import json2
import os

struct Receipt {
	architecture   string
	platform       string
	artifacts      map[string]string
	artifact_paths map[string]string
}

struct Control {
	name   string
	code   int
	output string
}

struct Evidence {
	arguments []string
	artifacts map[string]string
	controls  []Control
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn call(program string, args []string) Control {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(args)
	child.set_redirect_stdio()
	child.run()
	output := child.stdout_slurp() + child.stderr_slurp()
	child.wait()
	return Control{ code: child.code, output: output }
}

fn clone_run(original string, work string, receipt Receipt) ! {
	os.mkdir_all(work)!
	for _, path in receipt.artifact_paths {
		if !path.starts_with(original + '/') { continue }
		name := path[original.len + 1..]
		if '..' in name.split('/') { return error('unsafe artifact path') }
		target := work + '/' + name
		if os.is_link(target) || os.exists(target) { continue }
		os.mkdir_all(os.dir(target))!
		os.symlink(path, target)!
	}
	os.cp(original + '/qualification.json', work + '/qualification.json')!
}

fn save_receipt(work string, receipt Receipt, artifacts map[string]string,
	paths map[string]string) ! {
	os.write_file(work + '/qualification.json', json2.encode(Receipt{
		architecture:   receipt.architecture
		platform:       receipt.platform
		artifacts:      artifacts
		artifact_paths: paths
	}))!
}

fn replace_artifact(work string, receipt Receipt, name string, text string) ! {
	original := os.abs_path(os.args[2])
	path := receipt.artifact_paths[name]
	if !path.starts_with(original + '/') { return error('replacement is outside the native run') }
	file := work + path[original.len..]
	os.rm(file)!
	os.write_file(file, text)!
	mut artifacts := receipt.artifacts.clone()
	mut paths := receipt.artifact_paths.clone()
	artifacts[name] = digest(file)!
	paths[name] = os.real_path(file)
	save_receipt(work, receipt, artifacts, paths)!
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}

fn check() ! {
	$if prod {
	} $else {
		return error('compile the evidence controls with -prod')
	}
	if sha256.sum($embed_file('software-maintenance-evidence-check.v').to_string().bytes()).hex() != digest(@FILE)! {
		return error('evidence control source changed after compilation')
	}
	if os.args.len != 8 {
		return error('use RETAINER RUN DESKTOP_BUILD KERNEL CONTROLLER PROOF_DIRECTORY ARCH')
	}
	program := os.abs_path(os.args[1])
	original := os.abs_path(os.args[2])
	build := os.abs_path(os.args[3])
	proof := os.abs_path(os.args[6])
	if os.exists(proof) { return error('proof directory exists') }
	os.mkdir_all(proof)!
	receipt := json2.decode[Receipt](os.read_file(original + '/qualification.json')!)!
	installed := receipt.platform.ends_with('installed-root-two-boots')
	base := [original, build, os.abs_path(os.args[4]), os.abs_path(os.args[5]), proof + '/baseline',
		os.args[7]]
	baseline := call(program, base)
	if baseline.code != 0 { return error('baseline rejected: ' + baseline.output) }
	mut controls := [Control{ name: 'baseline', code: baseline.code, output: baseline.output }]
	mut names := ['missing-screenshot', 'missing-required-artifact-digest', 'artifact-pin-mismatch',
		'desktop-source-mismatch', 'frozen-source-mismatch', 'artifact-path-mismatch',
		'missing-success-marker', 'duplicate-identity-marker', 'kernel-panic']
	if installed {
		names << ['missing-reboot-success-marker', 'reboot-kernel-panic', 'missing-shutdown-event',
			'missing-reboot-shutdown-event', 'non-guest-shutdown-event',
			'non-guest-reboot-shutdown-event', 'wrong-shutdown-reason', 'wrong-reboot-shutdown-reason',
			'reset-event', 'panic-event', 'wrong-shutdown-boot', 'string-shutdown-boot',
			'duplicate-shutdown-event']
	}
	names << ['missing-start-marker', 'missing-refresh-marker', 'wrong-refresh-version', 'wrong-refresh-active',
		'missing-upgrade-marker', 'missing-retained-state', 'missing-cache-only',
		'wrong-cache-approval', 'wrong-uninstall-state', 'wrong-rollback-version',
		'maintenance-order', 'missing-child-retirement',
		'install-proposal-missing', 'upgrade-proposal-missing', 'rollback-proposal-missing',
		'remove-proposal-missing', 'reinstall-proposal-missing', 'proposal-duplicate',
		'proposal-generation', 'proposal-requested-set', 'proposal-previous-version',
		'proposal-version', 'proposal-publisher', 'proposal-permissions', 'proposal-action',
		'proposal-rollback-target', 'proposal-remove-requested', 'proposal-order']
	identity := 'SOFTWARE MAINTENANCE ordinary-compositor uid=1000 home=/home/alex PASS'
	success := if installed {
		'SOFTWARE MAINTENANCE INSTALLED BOOT 1 acquired refreshed upgraded pointer-saved checkpoint PASS'
	} else {
		'SOFTWARE GRAPHICAL ordinary-counter two-pointer-events persisted uid=1000 PASS'
	}
	for name in names {
		work := proof + '/' + name
		clone_run(original, work, receipt)!
		mut args := base.clone()
		args[0] = work
		args[4] = work + '/retained'
		mut reason := ''
		match name {
			'missing-start-marker' {
				text := os.read_file(receipt.artifact_paths['serial-2'])!.replace('SOFTWARE MAINTENANCE START', '')
				replace_artifact(work, receipt, 'serial-2', text)!
				reason = 'missing or duplicated exact marker'
			}
			'missing-refresh-marker', 'wrong-refresh-version', 'wrong-refresh-active',
			'missing-upgrade-marker', 'missing-retained-state', 'missing-cache-only',
			'wrong-cache-approval', 'wrong-uninstall-state', 'wrong-rollback-version',
			'maintenance-order', 'missing-child-retirement' {
				key := if name in ['missing-retained-state', 'missing-cache-only', 'wrong-cache-approval',
					'wrong-uninstall-state', 'wrong-rollback-version'] { 'serial-2' } else { 'serial' }
				mut text := os.read_file(receipt.artifact_paths[key])!
				marker := match name {
					'missing-refresh-marker', 'wrong-refresh-version', 'wrong-refresh-active' {
						'SOFTWARE MAINTENANCE refreshed signed=1.1.0 active=1.0.0 approvals=2 PASS'
					}
					'missing-upgrade-marker' { 'SOFTWARE MAINTENANCE upgraded version=1.1.0 approvals=3 private=2 launcher PASS' }
					'missing-retained-state' { 'SOFTWARE MAINTENANCE INSTALLED BOOT 2 exact tools accounts trust state private-data retained PASS' }
					'missing-cache-only' { 'SOFTWARE MAINTENANCE cache-only both repository payload directories absent PASS' }
					'wrong-cache-approval' { 'SOFTWARE MAINTENANCE cache-reinstalled version=1.1.0 approvals=6 private=3 launcher PASS' }
					'wrong-uninstall-state' { 'SOFTWARE MAINTENANCE uninstalled requested=[] packages=[] launcher-absent approvals=5 private=3 PASS' }
					'wrong-rollback-version' { 'SOFTWARE MAINTENANCE rolled-back version=1.0.0 approvals=4 private=3 launcher PASS' }
					'maintenance-order' { 'SOFTWARE MAINTENANCE newer signed medium available PASS' }
					else { 'SOFTWARE MAINTENANCE native Counter launch child closed PASS' }
				}
				reason = 'missing or duplicated exact marker'
				if name == 'wrong-refresh-version' { text = text.replace(marker, marker.replace('signed=1.1.0', 'signed=1.0.0')) }
				else if name == 'wrong-refresh-active' { text = text.replace(marker, marker.replace('active=1.0.0', 'active=1.1.0')) }
				else if name == 'wrong-cache-approval' { text = text.replace(marker, marker.replace('approvals=6', 'approvals=5')) }
				else if name == 'wrong-uninstall-state' { text = text.replace(marker, marker.replace('packages=[]', 'packages=[counter]')) }
				else if name == 'wrong-rollback-version' { text = text.replace(marker, marker.replace('version=1.0.0', 'version=1.1.0')) }
				else {
					text = text.split_into_lines().filter(it.trim_right('\r') != marker).join('\n') + '\n'
					if name == 'maintenance-order' { text += marker + '\n'; reason = 'maintenance state, review and approval order differs' }
					if name == 'missing-child-retirement' { reason = 'missing or duplicated native Counter retirement marker' }
				}
				replace_artifact(work, receipt, key, text)!
			}
			'install-proposal-missing', 'upgrade-proposal-missing', 'rollback-proposal-missing',
			'remove-proposal-missing', 'reinstall-proposal-missing', 'proposal-duplicate',
			'proposal-generation', 'proposal-requested-set', 'proposal-previous-version',
			'proposal-version', 'proposal-publisher', 'proposal-permissions', 'proposal-action',
			'proposal-rollback-target', 'proposal-remove-requested', 'proposal-order' {
				second := name.starts_with('rollback-') || name.starts_with('remove-') ||
					name.starts_with('reinstall-') || name in ['proposal-rollback-target', 'proposal-remove-requested']
				key := if second { 'serial-2' } else { 'serial' }
				prefix := 'SOFTWARE MAINTENANCE PROPOSAL '
				mut lines := os.read_file(receipt.artifact_paths[key])!.split_into_lines()
				proposals := lines.filter(it.starts_with(prefix))
				index := if name.starts_with('install-') { 0 } else if name.starts_with('remove-') || name == 'proposal-remove-requested' { 1 }
					else if name.starts_with('reinstall-') { 2 } else if second { 0 } else { 1 }
				if index >= proposals.len { return error('baseline lacks required maintenance proposal') }
				original_line := proposals[index]
				reason = 'missing or duplicated complete maintenance proposal'
				if name.ends_with('-missing') { lines = lines.filter(it != original_line) }
				else if name == 'proposal-duplicate' { lines << original_line }
				else if name == 'proposal-order' {
					lines = lines.filter(it != original_line); lines << original_line
					reason = 'maintenance proposal follows its read-only observation'
				} else {
					mut proposal := json2.decode[json2.Any](original_line.all_after(prefix))!.as_map()
					reason = 'maintenance proposal differs from the exact complete package set or generation'
					if name == 'proposal-generation' { proposal['generation'] = json2.Any(77) }
					else if name == 'proposal-requested-set' { proposal['requested'] = json2.Any([]json2.Any{}) }
					else if name == 'proposal-rollback-target' { proposal['target_generation'] = json2.Any(77) }
					else {
						mut rows := proposal['rows']!.as_array()
						mut row := rows[0].as_map()
						match name {
							'proposal-previous-version' { row['installed_version'] = json2.Any('0.0.0') }
							'proposal-version' { row['version'] = json2.Any('9.9.9') }
							'proposal-publisher' { row['public_key'] = json2.Any('') }
							'proposal-permissions' { row['permissions'] = json2.Any([]json2.Any{}) }
							'proposal-action' { row['action'] = json2.Any('keep') }
							else { row['requested'] = json2.Any(true) }
						}
						rows[0] = json2.Any(row); proposal['rows'] = json2.Any(rows)
						reason = 'maintenance proposal has incomplete signed publisher, permission or action details'
					}
					replacement := prefix + json2.encode(proposal)
					lines = lines.map(if it == original_line { replacement } else { it })
				}
				replace_artifact(work, receipt, key, lines.join('\n') + '\n')!
			}
			'missing-screenshot' {
				os.rm(work + '/15-reinstalled-counter-three.png')!
				reason = 'exact required screenshot set'
			}
			'missing-required-artifact-digest', 'artifact-pin-mismatch', 'artifact-path-mismatch' {
				mut artifacts := receipt.artifacts.clone()
				mut paths := receipt.artifact_paths.clone()
				if name == 'missing-required-artifact-digest' {
					artifacts.delete('serial')
					paths.delete('serial')
					reason = 'missing required artifact digest: serial'
				} else if name == 'artifact-pin-mismatch' {
					artifacts['serial'] = '0'.repeat(64)
					reason = 'receipt mismatch: serial'
				} else {
					paths['serial'] = original + '/different-serial.log'
					reason = 'receipt input path mismatch: serial'
				}
				save_receipt(work, receipt, artifacts, paths)!
			}
			'desktop-source-mismatch' {
				private_build := work + '/desktop-build'
				os.mkdir_all(private_build + '/source')!
				os.symlink(build + '/vinix-desktop', private_build + '/vinix-desktop')!
				os.symlink(build + '/source/desktop', private_build + '/source/desktop')!
				mut manifest := json2.decode[map[string]string](os.read_file(build + '/desktop-build.json')!)!
				manifest['desktop/main.v'] = '0'.repeat(64)
				manifest_text := json2.encode(manifest)
				os.write_file(private_build + '/desktop-build.json', manifest_text)!
				os.rm(work + '/desktop-build.json')!
				os.write_file(work + '/desktop-build.json', manifest_text)!
				mut artifacts := receipt.artifacts.clone()
				mut paths := receipt.artifact_paths.clone()
				for key, path in {
					'desktop-build':          work + '/desktop-build.json'
					'desktop-build-original': private_build + '/desktop-build.json'
				} {
					artifacts[key] = digest(path)!
					paths[key] = os.real_path(path)
				}
				save_receipt(work, receipt, artifacts, paths)!
				args[1] = private_build
				reason = 'maintenance compositor differs from the frozen c035 first-run snapshot'
			}
			'frozen-source-mismatch' {
				key := 'source/software-maintenance-check.v'
				path := work + '/' + key
				source := os.read_file(path)!
				os.rm(path)!
				os.write_file(path, source + '\n// bounded negative control\n')!
				mut artifacts := receipt.artifacts.clone()
				mut paths := receipt.artifact_paths.clone()
				artifacts[key] = digest(path)!
				paths[key] = os.real_path(path)
				save_receipt(work, receipt, artifacts, paths)!
				reason = 'qualified maintenance fixture differs from the embedded source'
			}
			'missing-success-marker', 'duplicate-identity-marker', 'kernel-panic',
			'missing-reboot-success-marker', 'reboot-kernel-panic' {
				serial_name := if name.starts_with('reboot-') || name.starts_with('missing-reboot-') {
					'serial-2'
				} else {
					'serial'
				}
				mut text := os.read_file(receipt.artifact_paths[serial_name])!
				if name.starts_with('missing-') {
					marker := if serial_name == 'serial-2' {
						'SOFTWARE MAINTENANCE INSTALLED BOOT 2 retained rollback uninstall cache-reinstall pointer-saved PASS'
					} else {
						success
					}
					text = text.split_into_lines().filter(it.trim_space() != marker).join('\n') + '\n'
					reason = 'missing or duplicated exact marker'
				} else if name == 'duplicate-identity-marker' {
					text += '\n' + identity + '\n'
					reason = 'missing or duplicated exact marker'
				} else {
					text += '\nKERNEL PANIC bounded negative control\n'
					reason = 'forbidden serial marker'
				}
				replace_artifact(work, receipt, serial_name, text)!
			}
			'missing-shutdown-event', 'missing-reboot-shutdown-event',
			'non-guest-shutdown-event', 'non-guest-reboot-shutdown-event',
			'wrong-shutdown-reason', 'wrong-reboot-shutdown-reason',
			'reset-event', 'panic-event', 'wrong-shutdown-boot', 'string-shutdown-boot',
			'duplicate-shutdown-event' {
				key := if name.contains('reboot') { 'shutdown-2' } else { 'shutdown-1' }
				mut records := []string{}
				mut matched := 0
				for index, line in os.read_file(receipt.artifact_paths[key])!.split_into_lines() {
					mut object := json2.decode[json2.Any](line)!.as_map()
					event := (object['event'] or { json2.Any('') }).str()
					if event == 'SHUTDOWN' {
						matched++
						if name.starts_with('missing-') { continue }
						if name.starts_with('non-guest-')
							|| (name.starts_with('wrong-') && name != 'wrong-shutdown-boot') {
							mut data := (object['data'] or { return error('baseline shutdown lacks data') }).as_map()
							if name.starts_with('non-guest-') {
								data['guest'] = json2.Any(false)
							} else {
								data['reason'] = json2.Any('host-qmp-quit')
							}
							object['data'] = json2.Any(data)
						}
						if name == 'reset-event' { object['event'] = json2.Any('RESET') }
						if name == 'panic-event' { object['event'] = json2.Any('GUEST_PANICKED') }
						if name == 'duplicate-shutdown-event' { records << line }
					}
					if index == 0 && name == 'wrong-shutdown-boot' {
						object['graphical_boot'] = json2.Any(2)
					}
					if index == 0 && name == 'string-shutdown-boot' {
						object['graphical_boot'] = json2.Any('1')
					}
					records << json2.encode(object)
				}
				if matched != 1 { return error('baseline lacks one shutdown event: ' + key) }
				reason = if name.starts_with('missing-') || name.starts_with('duplicate-') {
					'exact guest SHUTDOWN event'
				} else if name == 'reset-event' || name == 'panic-event' {
					'forbidden QMP power event'
				} else if name == 'wrong-shutdown-boot' || name == 'string-shutdown-boot' {
					'QMP shutdown boot binding differs'
				} else {
					'QMP did not report guest-initiated shutdown'
				}
				replace_artifact(work, receipt, key, records.join('\n') + '\n')!
			}
			else { return error('unknown control') }
		}
		result := call(program, args)
		if result.code == 0 || !result.output.contains(reason) {
			return error('control did not refuse for intended reason: ' + name + ': ' + result.output)
		}
		if os.exists(work + '/retained') {
			return error('failed admission wrote retained output: ' + name)
		}
		controls << Control{ name: name, code: result.code, output: result.output }
		println('PASS ' + name)
	}
	artifacts := {
		'control-source':       digest(@FILE)!
		'control-controller':   digest(os.executable())!
		'compiler':             digest(@VEXE)!
		'retention-controller': digest(program)!
		'native-qualification': digest(original + '/qualification.json')!
	}
	os.write_file(proof + '/controls.json', json2.encode(Evidence{
		arguments: os.args[1..]
		artifacts: artifacts
		controls:  controls
	}))!
	println('PASS maintenance evidence controls: baseline accepted, ' + names.len.str() + ' corruptions rejected')
}
