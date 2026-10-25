// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise evidence admission without changing the real run or desktop build.
module main

import crypto.sha256
import json2
import os
import stbi

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
	mut paths := receipt.artifact_paths.clone()
	for key, path in receipt.artifact_paths {
		if !path.starts_with(original + '/') { continue }
		name := path[original.len + 1..]
		if '..' in name.split('/') { return error('unsafe artifact path') }
		target := work + '/' + name
		if os.is_link(target) || os.exists(target) { continue }
		os.mkdir_all(os.dir(target))!
		if receipt.platform == 'qemu-framebuffer-ordinary-seat-release-routing-installed-root-two-boots' &&
			name == 'rootfs/etc/vinix-packages/config.json' {
			// The signed repository checker correctly rejects linked metadata.
			// Preserve that rule in controls with a byte-identical regular copy.
			os.cp(path, target)!
			paths[key] = os.real_path(target)
		} else {
			os.symlink(path, target)!
		}
	}
	if receipt.platform == 'qemu-framebuffer-ordinary-seat-release-routing-installed-root-two-boots' {
		save_receipt(work, receipt, receipt.artifacts, paths)!
	} else {
		os.cp(original + '/qualification.json', work + '/qualification.json')!
	}
}

fn save_receipt(work string, receipt Receipt, artifacts map[string]string,
	paths map[string]string) ! {
	mut saved_paths := paths.clone()
	if receipt.platform == 'qemu-framebuffer-ordinary-seat-release-routing-installed-root-two-boots' {
		for key, path in paths {
			if path.ends_with('/rootfs/etc/vinix-packages/config.json') {
				saved_paths[key] = os.real_path(work + '/rootfs/etc/vinix-packages/config.json')
			}
		}
	}
	os.write_file(work + '/qualification.json', json2.encode(Receipt{
		architecture:   receipt.architecture
		platform:       receipt.platform
		artifacts:      artifacts
		artifact_paths: saved_paths
	}))!
}

fn replace_artifact(work string, receipt Receipt, name string, text string) ! {
	original := os.abs_path(os.args[2])
	path := receipt.artifact_paths[name]
	if !path.starts_with(original + '/') { return error('replacement is outside the native run') }
	file := work + path[original.len..]
	os.rm(file)!
	os.write_file(file, text)!
	repin_artifact(work, receipt, name)!
}

fn repin_artifact(work string, receipt Receipt, name string) ! {
	original := os.abs_path(os.args[2])
	path := receipt.artifact_paths[name]
	if !path.starts_with(original + '/') { return error('replacement is outside the native run') }
	file := work + path[original.len..]
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
	if sha256.sum($embed_file('software-graphical-evidence-check.v').to_string().bytes()).hex() != digest(@FILE)! {
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
	release_routing := receipt.platform == 'qemu-framebuffer-ordinary-seat-release-routing-installed-root-two-boots'
	first_run := release_routing || receipt.platform == 'qemu-framebuffer-ordinary-seat-first-run-installed-root-two-boots'
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
	if first_run {
		names << ['missing-first-run-card', 'missing-first-run-proposal-shot',
			'missing-first-run-reboot-shot', 'declaration-architecture', 'declaration-packages',
			'declaration-extra-field', 'missing-pre-ready-identity', 'missing-first-run-proposal',
			'duplicate-first-run-proposal', 'proposal-requested-set', 'proposal-generation',
			'proposal-permissions', 'proposal-publisher', 'missing-unchanged-state',
			'missing-private-decision', 'invalid-private-decision', 'first-run-order',
			'missing-reboot-no-repeat', 'missing-reboot-private-decision', 'reboot-repeated-prompt',
			'reboot-repeated-proposal']
	}
	if release_routing {
		names << ['missing-release-routing-desktop-shot', 'missing-release-routing-extra-shot',
			'missing-release-routing-action-shot', 'missing-release-routing-extra-barrier-shot',
			'missing-release-routing-action-barrier-shot', 'missing-release-routing-controls-digest',
			'release-routing-controls-format', 'release-routing-controls-extra-token',
			'release-routing-controls-action', 'release-routing-controls-region',
			'release-routing-controls-extra-field', 'release-routing-extra-changed-pixel',
			'release-routing-action-changed-pixel', 'release-routing-framebuffer-dimensions',
			'release-routing-extra-baseline-as-barrier', 'release-routing-action-baseline-as-barrier',
			'release-routing-guest-source-mismatch', 'release-routing-migration-source-mismatch',
			'release-routing-session-source-mismatch', 'release-routing-package-source-mismatch',
			'release-routing-dialog-source-mismatch', 'release-routing-dispatch-source-mismatch',
			'release-routing-broker-source-mismatch', 'release-routing-selectors-source-mismatch',
			'release-routing-declaration-format', 'release-routing-declaration-string-format',
			'release-routing-lock-missing', 'release-routing-lock-empty', 'release-routing-lock-duplicate',
			'release-routing-lock-id', 'release-routing-lock-version', 'release-routing-lock-architecture',
			'release-routing-lock-repository', 'release-routing-lock-public-key',
			'release-routing-lock-publisher-mismatch', 'release-routing-lock-sequence',
			'release-routing-lock-wrong-positive-sequence',
			'release-routing-lock-string-sequence', 'release-routing-lock-fractional-sequence',
			'release-routing-lock-metadata', 'release-routing-lock-wrong-hex-metadata',
			'release-routing-lock-extra-field',
			'release-routing-reboot-repeated-client', 'release-routing-review-decision',
			'release-routing-reboot-review-decision']
		for marker in ['client', 'extra-token', 'extra-drained', 'action', 'action-drained', 'acknowledgement'] {
			for mutation in ['missing', 'duplicate', 'reordered'] {
				names << 'release-routing-' + mutation + '-' + marker
			}
		}
	}
	identity := 'SOFTWARE GRAPHICAL ordinary-compositor uid=1000 home=/home/alex PASS'
	success := if installed {
		'SOFTWARE GRAPHICAL INSTALLED BOOT 1 acquired pointer-saved cold-boot checkpoint PASS'
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
			'missing-release-routing-desktop-shot', 'missing-release-routing-extra-shot',
			'missing-release-routing-action-shot', 'missing-release-routing-extra-barrier-shot',
			'missing-release-routing-action-barrier-shot' {
				shot := match name {
					'missing-release-routing-desktop-shot' { 'release-routing-01-desktop' }
					'missing-release-routing-extra-shot' { 'release-routing-02-extra-refused' }
					'missing-release-routing-extra-barrier-shot' { 'release-routing-02-extra-barrier' }
					'missing-release-routing-action-barrier-shot' { 'release-routing-03-action-barrier' }
					else { 'release-routing-03-action-refused' }
				}
				os.rm(work + '/' + shot + '.png')!
				reason = 'exact required screenshot set'
			}
			'release-routing-controls-format', 'release-routing-controls-extra-token',
			'release-routing-controls-action', 'release-routing-controls-region',
			'release-routing-controls-extra-field' {
				mut object := json2.decode[json2.Any](os.read_file(receipt.artifact_paths['release-routing-controls'])!)!.as_map()
				match name {
					'release-routing-controls-format' { object['format'] = json2.Any(2) }
					'release-routing-controls-extra-token' { object['malformed_extra_token'] = json2.Any('Software window') }
					'release-routing-controls-action' { object['malformed_action'] = json2.Any('Software window') }
					'release-routing-controls-region' { object['unchanged_region'] = json2.Any([json2.Any(0), json2.Any(70), json2.Any(1), json2.Any(1)]) }
					else { object['extra'] = json2.Any(true) }
				}
				replace_artifact(work, receipt, 'release-routing-controls', json2.encode(object) + '\n')!
				reason = 'release-routing malformed-action controls differ'
			}
			'release-routing-extra-changed-pixel', 'release-routing-action-changed-pixel',
			'release-routing-framebuffer-dimensions' {
				key := if name == 'release-routing-action-changed-pixel' {
					'release-routing-03-action-refused'
				} else { 'release-routing-02-extra-refused' }
				image := stbi.load(receipt.artifact_paths[key], desired_channels: 3)!
				defer { image.free() }
				if image.width != 1024 || image.height != 768 { return error('baseline framebuffer dimensions differ') }
				unsafe { image.data[(70 * 1024) * 3] ^= u8(1) }
				file := work + '/' + key + '.png'
				os.rm(file)!
				if name == 'release-routing-framebuffer-dimensions' {
					stbi.stbi_write_png(file, 1, 1, 3, image.data, 3)!
					reason = 'release-routing framebuffer dimensions differ'
				} else {
					stbi.stbi_write_png(file, image.width, image.height, 3, image.data, image.width * 3)!
					reason = 'release-routing malformed action changed the desktop'
				}
				repin_artifact(work, receipt, key)!
			}
			'release-routing-extra-baseline-as-barrier', 'release-routing-action-baseline-as-barrier' {
				key := if name == 'release-routing-extra-baseline-as-barrier' {
					'release-routing-02-extra-barrier'
				} else { 'release-routing-03-action-barrier' }
				file := work + '/' + key + '.png'
				os.rm(file)!
				os.cp(receipt.artifact_paths['release-routing-01-desktop'], file)!
				repin_artifact(work, receipt, key)!
				reason = 'release-routing FIFO barrier dialog is not visible'
			}
			'release-routing-declaration-format', 'release-routing-declaration-string-format',
			'release-routing-lock-missing', 'release-routing-lock-empty', 'release-routing-lock-duplicate',
			'release-routing-lock-id', 'release-routing-lock-version', 'release-routing-lock-architecture',
			'release-routing-lock-repository', 'release-routing-lock-public-key',
			'release-routing-lock-publisher-mismatch', 'release-routing-lock-sequence',
			'release-routing-lock-wrong-positive-sequence',
			'release-routing-lock-string-sequence', 'release-routing-lock-fractional-sequence',
			'release-routing-lock-metadata', 'release-routing-lock-wrong-hex-metadata',
			'release-routing-lock-extra-field' {
				mut declaration := json2.decode[json2.Any](os.read_file(receipt.artifact_paths['release-declaration'])!)!.as_map()
				mut locked := declaration['locked']!.as_array()
				if locked.len != 1 { return error('baseline lacks exactly one Counter lock') }
				mut pin := locked[0].as_map()
				match name {
					'release-routing-declaration-format' { declaration['format'] = json2.Any(1) }
					'release-routing-declaration-string-format' { declaration['format'] = json2.Any('2') }
					'release-routing-lock-missing' { declaration.delete('locked') }
					'release-routing-lock-empty' { locked.clear() }
					'release-routing-lock-duplicate' { locked << locked[0] }
					'release-routing-lock-id' { pin['id'] = json2.Any('undeclared.package') }
					'release-routing-lock-version' { pin['version'] = json2.Any('2.0.0') }
					'release-routing-lock-architecture' { pin['architecture'] = json2.Any('wrong-architecture') }
					'release-routing-lock-repository' { pin['repository'] = json2.Any('other') }
					'release-routing-lock-public-key' { pin['public_key'] = json2.Any('z'.repeat(64)) }
					'release-routing-lock-publisher-mismatch' {
						pin['public_key'] = json2.Any(if pin['public_key']!.str() == '0'.repeat(64) { '1'.repeat(64) } else { '0'.repeat(64) })
					}
					'release-routing-lock-sequence' { pin['minimum_sequence'] = json2.Any(0) }
					'release-routing-lock-wrong-positive-sequence' {
						pin['minimum_sequence'] = json2.Any(if pin['minimum_sequence']!.f64() == 1 { 2 } else { 1 })
					}
					'release-routing-lock-string-sequence' { pin['minimum_sequence'] = json2.Any('1') }
					'release-routing-lock-fractional-sequence' { pin['minimum_sequence'] = json2.Any(1.5) }
					'release-routing-lock-metadata' { pin['metadata_sha256'] = json2.Any('z'.repeat(64)) }
					'release-routing-lock-wrong-hex-metadata' {
						pin['metadata_sha256'] = json2.Any(if pin['metadata_sha256']!.str() == '0'.repeat(64) { '1'.repeat(64) } else { '0'.repeat(64) })
					}
					else { pin['extra'] = json2.Any(true) }
				}
				if name != 'release-routing-lock-missing' {
					if locked.len > 0 { locked[0] = json2.Any(pin) }
					declaration['locked'] = json2.Any(locked)
				}
				replace_artifact(work, receipt, 'release-declaration', json2.encode(declaration) + '\n')!
				reason = 'release-routing declaration differs from the exact architecture-matched Counter lock'
			}
			'release-routing-missing-client', 'release-routing-duplicate-client', 'release-routing-reordered-client',
			'release-routing-missing-extra-token', 'release-routing-duplicate-extra-token', 'release-routing-reordered-extra-token',
			'release-routing-missing-extra-drained', 'release-routing-duplicate-extra-drained', 'release-routing-reordered-extra-drained',
			'release-routing-missing-action', 'release-routing-duplicate-action', 'release-routing-reordered-action',
			'release-routing-missing-action-drained', 'release-routing-duplicate-action-drained', 'release-routing-reordered-action-drained',
			'release-routing-missing-acknowledgement', 'release-routing-duplicate-acknowledgement', 'release-routing-reordered-acknowledgement',
			'release-routing-reboot-repeated-client', 'release-routing-review-decision',
			'release-routing-reboot-review-decision' {
				key := if name.contains('reboot-') { 'serial-2' } else { 'serial' }
				marker := if name.ends_with('-extra-token') {
					'SOFTWARE RELEASE ROUTING malformed extra-token enqueued PASS'
				} else if name.ends_with('-extra-drained') {
					'SOFTWARE RELEASE ROUTING malformed extra-token drained PASS'
				} else if name.ends_with('-action') {
					'SOFTWARE RELEASE ROUTING malformed action enqueued PASS'
				} else if name.ends_with('-action-drained') {
					'SOFTWARE RELEASE ROUTING malformed action drained PASS'
				} else if name.ends_with('-acknowledgement') {
					'SOFTWARE RELEASE ROUTING exact software.release-review acknowledged PASS'
				} else { 'SOFTWARE RELEASE ROUTING ordinary client uid=1000 home=/home/alex PASS' }
				mut lines := os.read_file(receipt.artifact_paths[key])!.split_into_lines()
				reason = 'missing or duplicated exact marker'
				if name.contains('-missing-') {
					lines = lines.filter(it.trim_right('\r') != marker)
				} else if name.contains('-duplicate-') {
					lines << marker
				} else if name.contains('-reordered-') {
					lines = lines.filter(it.trim_right('\r') != marker)
					lines << marker
					reason = 'release-routing client, refusal and proposal order differs'
				} else if name == 'release-routing-reboot-repeated-client' {
					lines << marker
					reason = 'release-routing operation repeated on boot 2'
				} else {
					lines = lines.map(it.replace('mode=0600 value=skip PASS', 'mode=0600 value=review PASS'))
				}
				replace_artifact(work, receipt, key, lines.join('\n') + '\n')!
			}
			'missing-first-run-card', 'missing-first-run-proposal-shot',
			'missing-first-run-reboot-shot' {
				shot := match name {
					'missing-first-run-card' { 'first-run-01-card' }
					'missing-first-run-proposal-shot' { 'first-run-02-proposal' }
					else { 'first-run-03-reboot-desktop' }
				}
				os.rm(work + '/' + shot + '.png')!
				reason = 'exact required screenshot set'
			}
			'declaration-architecture', 'declaration-packages', 'declaration-extra-field' {
				mut declaration := json2.decode[json2.Any](os.read_file(receipt.artifact_paths['release-declaration'])!)!.as_map()
				match name {
					'declaration-architecture' {
						declaration['architecture'] = json2.Any('wrong-architecture')
					}
					'declaration-packages' {
						declaration['packages'] = json2.Any([json2.Any('undeclared.package')])
					}
					else { declaration['extra'] = json2.Any(true) }
				}
				replace_artifact(work, receipt, 'release-declaration', json2.encode(declaration) + '\n')!
				reason = if release_routing {
					'release-routing declaration differs from the exact architecture-matched Counter lock'
				} else { 'first-run declaration differs from the complete architecture-matched Counter set' }
			}
			'missing-pre-ready-identity', 'missing-first-run-proposal',
			'duplicate-first-run-proposal', 'proposal-requested-set', 'proposal-generation',
			'proposal-permissions', 'proposal-publisher', 'missing-unchanged-state',
			'missing-private-decision', 'invalid-private-decision', 'first-run-order',
			'missing-reboot-no-repeat', 'missing-reboot-private-decision',
			'reboot-repeated-prompt', 'reboot-repeated-proposal' {
				key := if name.contains('reboot-') { 'serial-2' } else { 'serial' }
				prefix := 'SOFTWARE FIRST RUN PROPOSAL '
				pre_ready := 'SOFTWARE FIRST RUN pre-ready compositor uid=1000 home=/home/alex runtime=0700 PASS'
				unchanged := 'SOFTWARE FIRST RUN review handed to Software without activation or approval PASS'
				value := if release_routing { 'skip' } else { 'review' }
				decision := 'SOFTWARE FIRST RUN private decision owner=1000 mode=0600 value=' + value + ' PASS'
				no_repeat := 'SOFTWARE FIRST RUN BOOT 2 retained ' + value + ' decision no repeated prompt PASS'
				mut lines := os.read_file(receipt.artifact_paths[key])!.split_into_lines()
				reason = 'missing or duplicated exact marker'
				match name {
					'missing-pre-ready-identity' {
						lines = lines.filter(it.trim_right('\r') != pre_ready)
					}
					'missing-unchanged-state' {
						lines = lines.filter(it.trim_right('\r') != unchanged)
					}
					'missing-private-decision', 'missing-reboot-private-decision' {
						lines = lines.filter(it.trim_right('\r') != decision)
					}
					'invalid-private-decision' {
						lines = lines.map(if it.trim_right('\r') == decision {
							decision.replace('mode=0600', 'mode=0666')
						} else {
							it
						})
					}
					'missing-reboot-no-repeat' {
						lines = lines.filter(it.trim_right('\r') != no_repeat)
					}
					'first-run-order' {
						lines = lines.filter(it.trim_right('\r') != pre_ready)
						lines << pre_ready
						reason = 'first-run identity, proposal and approval order differs'
					}
					'reboot-repeated-prompt', 'reboot-repeated-proposal' {
						lines << if name == 'reboot-repeated-prompt' {
							pre_ready
						} else {
							prefix + '{}'
						}
						reason = 'first-run prompt or proposal repeated on boot 2'
					}
					else {
						proposals := lines.filter(it.starts_with(prefix))
						if proposals.len != 1 {
							return error('baseline lacks complete first-run proposal')
						}
						if name == 'missing-first-run-proposal' {
							lines = lines.filter(!it.starts_with(prefix))
						} else if name == 'duplicate-first-run-proposal' {
							lines << proposals[0]
						} else {
							mut proposal := json2.decode[json2.Any](proposals[0].all_after(prefix))!.as_map()
							if name == 'proposal-requested-set' {
								proposal['requested'] = json2.Any([json2.Any('undeclared.package')])
							} else if name == 'proposal-generation' {
								proposal['generation'] = json2.Any(1)
							} else {
								mut rows := proposal['rows']!.as_array()
								mut row := rows[0].as_map()
								if name == 'proposal-permissions' {
									row['permissions'] = json2.Any([]json2.Any{})
								} else {
									row['public_key'] = json2.Any('')
								}
								rows[0] = json2.Any(row)
								proposal['rows'] = json2.Any(rows)
							}
							lines = lines.map(if it.starts_with(prefix) {
								prefix + json2.encode(proposal)
							} else {
								it
							})
						}
						reason = if name in ['missing-first-run-proposal',
							'duplicate-first-run-proposal'] {
							'missing or duplicated complete first-run proposal'
						} else if name in ['proposal-permissions', 'proposal-publisher'] {
							'first-run proposal has incomplete publisher, permission or install details'
						} else {
							'first-run proposal differs from the complete declared Counter set'
						}
					}
				}
				replace_artifact(work, receipt, key, lines.join('\n') + '\n')!
			}
			'missing-screenshot' {
				os.rm(work + '/07-counter-reopened.png')!
				reason = 'exact required screenshot set'
			}
			'missing-required-artifact-digest', 'artifact-pin-mismatch', 'artifact-path-mismatch',
			'missing-release-routing-controls-digest' {
				mut artifacts := receipt.artifacts.clone()
				mut paths := receipt.artifact_paths.clone()
				if name in ['missing-required-artifact-digest', 'missing-release-routing-controls-digest'] {
					key := if name == 'missing-release-routing-controls-digest' { 'release-routing-controls' } else { 'serial' }
					artifacts.delete(key)
					paths.delete(key)
					reason = 'missing required artifact digest: ' + key
				} else if name == 'artifact-pin-mismatch' {
					artifacts['serial'] = '0'.repeat(64)
					reason = 'receipt mismatch: serial'
				} else {
					paths['serial'] = original + '/different-serial.log'
					reason = 'receipt input path mismatch: serial'
				}
				save_receipt(work, receipt, artifacts, paths)!
			}
			'desktop-source-mismatch', 'release-routing-migration-source-mismatch',
			'release-routing-session-source-mismatch', 'release-routing-package-source-mismatch',
			'release-routing-dialog-source-mismatch', 'release-routing-dispatch-source-mismatch',
			'release-routing-broker-source-mismatch', 'release-routing-selectors-source-mismatch' {
				source_name := match name {
					'release-routing-migration-source-mismatch' { 'app_selection_migration.v' }
					'release-routing-session-source-mismatch' { 'session_hub.v' }
					'release-routing-package-source-mismatch' { 'packagecore/release.c.v' }
					'release-routing-dialog-source-mismatch' { 'session_dialog.v' }
					'release-routing-dispatch-source-mismatch' { 'sessiondaemon/dispatch.v' }
					'release-routing-broker-source-mismatch' { 'sessiondaemon/broker.c.v' }
					'release-routing-selectors-source-mismatch' { 'sessioncore/selectors.v' }
					else { 'main.v' }
				}
				private_build := work + '/desktop-build'
				os.mkdir_all(private_build + '/source')!
				os.symlink(build + '/vinix-desktop', private_build + '/vinix-desktop')!
				os.symlink(build + '/source/desktop', private_build + '/source/desktop')!
				mut manifest := json2.decode[map[string]string](os.read_file(build + '/desktop-build.json')!)!
				manifest['desktop/' + source_name] = '0'.repeat(64)
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
				reason = 'qualified desktop identity source differs: ' + source_name
			}
			'frozen-source-mismatch', 'release-routing-guest-source-mismatch' {
				key := if name == 'release-routing-guest-source-mismatch' { 'source/guest/release_routing.v' } else { 'source/software-graphical-check.v' }
				path := work + '/' + key
				source := os.read_file(path)!
				os.rm(path)!
				os.write_file(path, source + '\n// bounded negative control\n')!
				mut artifacts := receipt.artifacts.clone()
				mut paths := receipt.artifact_paths.clone()
				artifacts[key] = digest(path)!
				paths[key] = os.real_path(path)
				save_receipt(work, receipt, artifacts, paths)!
				reason = 'qualified graphical fixture differs from the embedded source'
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
						'SOFTWARE GRAPHICAL INSTALLED BOOT 2 retained Counter reopened and pointer-saved PASS'
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
	println('PASS graphical evidence controls: baseline accepted, ' + names.len.str() + ' corruptions rejected')
}
