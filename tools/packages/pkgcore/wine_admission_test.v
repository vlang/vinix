// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn test_wine_runtime_selection_requires_explicit_installed_runtime() {
	app := Package{id: 'app', kind: 'windows', runtime: 'wine', dependencies: [Dependency{id: 'wine'}]}
	runtime := Package{id: 'wine', kind: 'runtime'}
	state := State{packages: [Installed{package: app}, Installed{package: runtime}]}
	assert wine_runtime_index(state, 'app')! == 1
	for candidate in [Package{...app, kind: 'native'}, Package{...app, runtime: ''}, Package{...app, dependencies: []}] {
		if _ := wine_runtime_index(State{packages: [Installed{package: candidate}, Installed{package: runtime}]}, 'app') {
			assert false, 'invalid Windows runtime selection accepted'
		}
	}
	for candidate in [State{}, State{packages: [Installed{package: app}]},
		State{packages: [Installed{package: app}, Installed{package: Package{...runtime, kind: 'native'}}]}] {
		if _ := wine_runtime_index(candidate, 'app') { assert false, 'missing or wrong-kind runtime accepted' }
	}
}

fn test_wine_admission_refuses_alternate_roots_and_close_is_repeatable() {
	if mut admission := (Service{root: '/tmp/not-installed'}).wine_admission('app') {
		admission.close(); assert false, 'alternate-root Wine admission accepted'
	} else { assert err.msg().contains('installed real root') }
	mut empty := WineAdmission{}
	empty.close(); empty.close()
	fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert fd >= 0
	mut owner := WineAdmission{prepared: PreparedLaunch{lease: fd}}
	owner.close()
	assert C.fcntl(fd, C.F_GETFD) < 0
	reused := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert reused == fd
	owner.close()
	assert C.fcntl(reused, C.F_GETFD) >= 0
	C.close(reused)
}
