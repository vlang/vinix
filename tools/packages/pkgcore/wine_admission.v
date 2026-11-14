// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// One owner. Runtime metadata borrows prepared state until close; do not copy
// this admission, mutate its metadata, or close it while a consumer uses it.
// The shared generation lease remains held throughout that lifetime.
pub struct WineAdmission {
pub:
	generation u64
	runtime Package
mut:
	prepared PreparedLaunch
}

pub fn (mut admission WineAdmission) close() {
	admission.prepared.close()
	admission = WineAdmission{}
}

fn wine_runtime_index(state State, id string) !int {
	mut runtime := ''
	for installed in state.packages {
		if installed.package.id != id { continue }
		if installed.package.kind != 'windows' || installed.package.runtime == '' {
			return error('Wine admission requires a Windows application with an explicit runtime')
		}
		runtime = installed.package.runtime
		if !installed.package.dependencies.any(it.id == runtime) {
			return error('Wine runtime must be an explicit application dependency')
		}
	}
	if runtime == '' { return error('Wine application is not installed') }
	for index, installed in state.packages {
		if installed.package.id == runtime {
			if installed.package.kind != 'runtime' { return error('Wine dependency is not a runtime package') }
			return index
		}
	}
	return error('Wine runtime is not installed')
}

// Same current policy, publisher-key, namespace and payload checks as launch.
// This does not acquire a prefix guard, authenticate a running Wine server,
// approve migration or start a process. Consumer must coordinate the prefix.
pub fn (service Service) wine_admission(id string) !WineAdmission {
	if service.root != '' { return error('Wine admission requires the installed real root') }
	mut prepared := service.prepare_launch(id)!
	mut accepted := false
	defer { if !accepted { prepared.close() } }
	if prepared.lease < 0 { return error('Wine admission requires an ordinary account') }
	validate_state(prepared.state, prepared.config.architecture)!
	index := wine_runtime_index(prepared.state, id)!
	verify_launch_payloads(prepared.config, prepared.directory, prepared.state, id)!
	accepted = true
	return WineAdmission{generation: prepared.state.generation, runtime: prepared.state.packages[index].package, prepared: prepared}
}
