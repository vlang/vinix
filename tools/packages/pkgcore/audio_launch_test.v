// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import tools.packages.audiopcm

fn audio_launch_check(ok bool, message string) { if !ok { panic(message) } }
fn audio_launch_error(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }

fn audio_launch_fixture(architecture string) (Config, State) {
	key := 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
	return Config{ architecture: architecture, launch_user: 'alex', repositories: [Repository{ id: 'publisher', url: 'https://example.invalid', public_key: key }] },
		State{ generation: 42, architecture: architecture, requested: ['app'], packages: [Installed{ repository: 'publisher', public_key: key, sequence: 7,
			package: Package{ id: 'app', version: '1.2.3', architecture: architecture, name: 'App', license: 'MIT', kind: 'native', entrypoint: 'bin/runner',
				files: [Payload{ path: 'bin/runner', sha256: key, bytes: 1, executable: true }] } }] }
}

fn test_audio_launch_requires_an_exact_portal_and_never_grants_the_device() {
	audiopcm.clear_environment()
	defer { audiopcm.clear_environment() }
	for architecture in ['aarch64', 'x86_64']! {
		config, fixture := audio_launch_fixture(architecture)
		mut packages := fixture.packages.clone()
		last := packages.len - 1
		packages[last] = Installed{ ...packages[last], package: Package{ ...packages[last].package, permissions: ['audio'] } }
		state := State{ ...fixture, packages: packages }
		if mut plan := application_launch_plan(config, '/packages', state, 'app', '/private/app', 1000, 1000, LaunchInput{}) {
			plan.close(); panic('declared audio launched without admitted portal')
		} else { message := err.msg(); audio_launch_check(message.contains('no admitted ordinary-session audio output portal'), 'audio refusal reason'); unsafe { message.free(); err.free() } }
		// A package without the permission never exports the ambient endpoint
		// or an audio pledge/device path to the application sandbox.
		os.setenv('VINIX_AUDIO_SOCKET', '/arbitrary/ambient', true)
		mut plan := application_launch_plan(config, '/packages', fixture, 'app', '/private/app', 1000, 1000, LaunchInput{})!
		audio_launch_check(!plan.arguments.any(it.starts_with('VINIX_AUDIO_') || it.starts_with('/dev/dsp') || it == '/dev/snd'), 'no audio authority without signed permission')
		audio_launch_check('audio' !in plan.arguments[5].split(' '), 'application never receives direct audio pledge')
		plan.close()
		audiopcm.clear_environment()
	}
}

fn test_audio_admission_refuses_alternate_roots_before_opening_state() {
	if mut admission := (Service{ root: '/tmp/not-the-installed-root' }).audio_admission('app') {
		admission.close(); panic('admitted alternate-root audio authority')
	} else { audio_launch_error(err) }
}
