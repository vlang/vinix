// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.pkgcore

fn qualify_package_removal_guidance(mut t Test) ! {
	state := pkgcore.State{requested: ['editor'], packages: [
		pkgcore.Installed{package: pkgcore.Package{id: 'editor', dependencies: [pkgcore.Dependency{id: 'bridge'}]}},
		pkgcore.Installed{package: pkgcore.Package{id: 'bridge', dependencies: [pkgcore.Dependency{id: 'shared'}]}},
		pkgcore.Installed{package: pkgcore.Package{id: 'shared'}}]}
	if _ := pkgcore.desired_roots(state, 'remove', ['shared']) { assert false } else {
		message := err.msg()
		assert message.contains('shared is not explicitly installed; required by requested package editor'), message
		unsafe { message.free(); err.free() }
	}
	if _ := pkgcore.desired_roots(state, 'remove', ['editor', 'shared']) { assert false } else {
		message := err.msg()
		assert message.contains('not explicitly installed') && !message.contains('required by requested package'), message
		unsafe { message.free(); err.free() }
	}
	roots := pkgcore.desired_roots(state, 'remove', ['editor'])!
	assert roots.len == 0 && state.requested == ['editor'] && state.packages.len == 3
	unsafe { (&array(&roots)).free() }
	t.say('PACKAGE REMOVAL implicit-transitive requested-blocker batch-roots borrowed-state PASS')
}
