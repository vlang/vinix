// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

import tools.packages.audiopcm
import os

fn (request &Request) validate_audio_shape() ! {
	if request.format in [1, 2] && request.audio.path == '' && request.audio.device == 0 && request.audio.inode == 0 && request.audio.worker == 0 && request.audio.generation == 0 && request.audio.manifest == '' { return }
	if request.format != 3 || !request.audio.valid_binding() { return error('invalid isolated audio capability') }
	audiopcm.path_owner(request.audio.path)!
}

pub fn (request &Request) validate_audio(uid u32) ! {
	request.validate_audio_shape()!
	if request.format != 3 { return }
	if !audiopcm.admit('/', request.audio, uid, 0) { return error('isolated audio endpoint identity changed') }
}

// Only the fixed capability crosses this boundary. Clear every ambient audio
// value even for requests without audio, before creating the isolated login.
pub fn (request &Request) forward_audio(uid u32, transport int) !int {
	audiopcm.clear_environment()
	request.validate_audio(uid)!
	if request.format != 3 { return -1 }
	audiopcm.account_admission(request.audio, uid, transport)!
	fd := audiopcm.root_bootstrap(request.audio, request.arguments[1])!
	request.audio.export_environment()
	os.setenv('VINIX_AUDIO_BOOTSTRAP_FD', '3', true)
	return fd
}
