// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.audiopcm

// This gate runs in the seat-owning launcher before group shedding. It uses
// the same reader/generation lease and exact payload/policy/key verification
// as execution. The isolated child repeats admission with fresh current state.
pub struct AudioAdmission {
pub:
	allowed bool
	generation u64
	manifest string
mut:
	prepared PreparedLaunch
}

pub fn (mut admission AudioAdmission) close() {
	admission.prepared.close()
	unsafe { admission.manifest.free() }
	admission = AudioAdmission{}
}

pub fn (service Service) audio_admission(id string) !AudioAdmission {
	if service.root != '' { return error('audio launch requires the installed real root') }
	mut prepared := service.prepare_launch(id)!
	mut accepted := false
	defer { if !accepted { prepared.close() } }
	if prepared.lease < 0 { return error('audio launch requires an ordinary account') }
	validate_state(prepared.state, prepared.config.architecture)!
	mut selected := -1
	for at, installed in prepared.state.packages { if installed.package.id == id { selected = at; break } }
	if selected < 0 || prepared.state.packages[selected].package.kind in ['runtime', 'data'] { return error('application is not installed: ${id}') }
	p := prepared.state.packages[selected].package
	check_policy(p, prepared.config.policy)!
	if !prepared.config.repositories.any(it.id == prepared.state.packages[selected].repository && it.public_key == prepared.state.packages[selected].public_key) { return error('${id}: publisher key has been revoked') }
	if 'audio' !in p.permissions { accepted = true; return AudioAdmission{ prepared: prepared } }
	verify_launch_payloads(prepared.config, prepared.directory, prepared.state, id)!
	manifest := package_metadata_digest(p)!
	accepted = true
	return AudioAdmission{ allowed: true, generation: prepared.state.generation, manifest: manifest, prepared: prepared }
}

fn launch_audio(mut args []string, id string, uid int, generation u64, p Package) ! {
	mut capability := audiopcm.environment()!
	defer { capability.close() }
	manifest := package_metadata_digest(p)!
	defer { unsafe { manifest.free() } }
	if uid != int(C.geteuid()) || capability.path == '' || capability.generation != generation || capability.manifest != manifest || !audiopcm.admit('/', capability, u32(uid), 0) { return error('${id}: no admitted ordinary-session audio output portal') }
	launch_unveil(mut args, capability.path, 'rw')
	launch_environment(mut args, 'VINIX_AUDIO_SOCKET=' + capability.path)
	device := capability.device.str()
	inode := capability.inode.str()
	worker := capability.worker.str()
	number := capability.generation.str()
	defer { unsafe { device.free(); inode.free(); worker.free(); number.free() } }
	launch_environment(mut args, 'VINIX_AUDIO_DEVICE=' + device)
	launch_environment(mut args, 'VINIX_AUDIO_INODE=' + inode)
	launch_environment(mut args, 'VINIX_AUDIO_WORKER=' + worker)
	launch_environment(mut args, 'VINIX_AUDIO_GENERATION=' + number)
	launch_environment(mut args, 'VINIX_AUDIO_MANIFEST=' + capability.manifest)
	launch_environment(mut args, 'VINIX_AUDIO_PROTOCOL=1')
}
