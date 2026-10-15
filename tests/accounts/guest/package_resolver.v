// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.pkgcore

fn qualify_package_resolver(mut t Test, architecture string) ! {
	config := pkgcore.Config{architecture: architecture, repositories: [pkgcore.Repository{
		id: 'resolver-fixture', url: 'https://example.invalid', public_key: 'a'.repeat(64)}]}
	for count in [4096, 512, 1024] {
		mut names := []string{cap: count}
		for i in 0 .. count { names << 'node-' + i.str() }
		mut candidates := []pkgcore.Installed{cap: count}
		for i in 0 .. count {
			mut dependencies := []pkgcore.Dependency{cap: 128}
			if count == 4096 {
				if i + 1 < count { dependencies << pkgcore.Dependency{id: names[i + 1]} }
			} else {
				for offset in 1 .. 129 { dependencies << pkgcore.Dependency{id: names[(i + offset) % count]} }
			}
			candidates << pkgcore.Installed{repository: 'resolver-fixture', public_key: config.repositories[0].public_key,
				sequence: 1, package: pkgcore.Package{id: names[i], name: names[i], version: '1.0.0', architecture: 'all',
				kind: 'data', license: 'MIT', dependencies: dependencies}}
		}
		catalog := pkgcore.Catalog{packages: candidates}
		if count == 1024 {
			if _ := pkgcore.resolve(catalog, config, pkgcore.State{}, [names[0]], true) { assert false } else {
				assert err.msg().contains('search limit'), err.msg()
				unsafe { err.free() }
			}
		} else {
			plan := pkgcore.resolve(catalog, config, pkgcore.State{}, [names[0]], true)!
			assert plan.packages.len == count && plan.packages.all(it.package.architecture == 'all')
			unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() }
		}
		for candidate in candidates { unsafe { (&array(&candidate.package.dependencies)).free() } }
		unsafe { (&array(&candidates)).free() }
		for name in names { unsafe { name.free() } }
		unsafe { (&array(&names)).free() }
	}
	t.say('PACKAGE RESOLVER chain-4096 dense-cycle-512 explicit-search-limit bounded-iterative PASS')
	base := pkgcore.Package{ id: 'app', name: 'Application', version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT',
		dependencies: [pkgcore.Dependency{id: 'absent', minimum: '1.0.0', before: '3.0.0'}] }
	catalog := pkgcore.Catalog{ packages: [pkgcore.Installed{ package: base, repository: 'resolver-fixture' },
		pkgcore.Installed{ package: pkgcore.Package{ ...base, version: '2.0.0', proprietary: true, license: 'Vendor-EULA' }, repository: 'resolver-fixture' }] }
	if _ := pkgcore.resolve(catalog, config, pkgcore.State{}, ['app'], true) { assert false } else {
		message := err.msg()
		assert message.contains('absent') && !message.contains('Vendor-EULA') && message.len <= 4096, message
		assert message.contains('Dependency path: app -> absent') && message.ends_with('Requirement: absent >= 1.0.0 < 3.0.0'), message
		unsafe { message.free(); err.free() }
	}
	t.say('PACKAGE RESOLVER current-cause dependency-path bounded-diagnostic PASS')
	mut installed := []pkgcore.Installed{cap: 21}
	mut requested := []string{cap: 22}
	for i in 0 .. 21 {
		id := if i == 0 { 'base' } else { 'node-' + i.str() }
		requested << id
		installed << pkgcore.Installed{repository: 'resolver-fixture', public_key: config.repositories[0].public_key, sequence: 1,
			package: pkgcore.Package{id: id, name: id, version: '1.0.0', architecture: architecture, kind: 'data', license: 'MIT'}}
	}
	new_base := pkgcore.Installed{ ...installed[0], package: pkgcore.Package{ ...installed[0].package, version: '2.0.0' } }
	addon := pkgcore.Installed{ ...installed[0], package: pkgcore.Package{ ...installed[0].package, id: 'zz-addon',
		dependencies: [pkgcore.Dependency{id: 'base', minimum: '2.0.0'}] } }
	requested << 'zz-addon'
	plan := pkgcore.resolve(pkgcore.Catalog{packages: [...installed, new_base, addon]}, config,
		pkgcore.State{packages: installed}, requested, false)!
	assert plan.packages.len == 22 && plan.packages.filter(it.package.id == 'base')[0].package.version == '2.0.0'
	unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() }
	t.say('PACKAGE RESOLVER installed-preference single-choice late-version-backtracking PASS')
}
