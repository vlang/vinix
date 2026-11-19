// SPDX-License-Identifier: GPL-2.0-or-later
module pacmandb

fn test_vercmp_matches_libalpm() {
	cases := [
		['1.5.0', '1.5.0', '0'],
		['1.5.1', '1.5.0', '1'],
		['1.5.1', '1.5', '1'],
		['1.5.0-1', '1.5.0-2', '-1'],
		['1.5.0-2', '1.5.1-1', '-1'],
		['1.5-1', '1.5', '0'],
		['1.5', '1.5-1', '0'],
		['1.0a', '1.0alpha', '-1'],
		['1.0alpha', '1.0b', '-1'],
		['1.0rc', '1.0', '-1'],
		['1.0', '1.0.1', '-1'],
		['1.001', '1.1', '0'],
		['1:1.0', '2.0', '1'],
		['2.0', '1:1.0', '-1'],
		['1:26.3.0_devel.20261107.231485.b7b03c5b3b8-3', '1:26.3.1-1', '-1'],
		['23.1.5-1.2', '23.1', '1'],
	]
	for c in cases {
		assert vercmp(c[0], c[1]) == c[2].int(), '${c[0]} vs ${c[1]}'
	}
}

fn test_soname_provision_needs_its_version() {
	llvm := Package{
		name:     'llvm-libs'
		version:  '23.1.5-1.2'
		provides: ['libLLVM.so=23.1-64']
	}
	assert llvm.satisfies(parse_dep('libLLVM.so=23.1-64'))
	assert !llvm.satisfies(parse_dep('libLLVM.so=22.1-64'))
	assert llvm.satisfies(parse_dep('llvm-libs>=23'))
	assert !llvm.satisfies(parse_dep('llvm-libs<23'))
	bare := Package{
		name:     'x'
		version:  '1-1'
		provides: ['opengl-driver']
	}
	assert bare.satisfies(parse_dep('opengl-driver'))
	assert !bare.satisfies(parse_dep('opengl-driver>=1'))
}

fn test_chosen_provider_wins_over_a_named_package() {
	db := Db{
		repos:    ['omarchy', 'extra']
		packages: {
			'omarchy': [
				Package{
					repo:     'omarchy'
					name:     'mesa-aurora'
					version:  '1:26.3.0-3'
					provides: ['mesa=1:26.3.0']
				},
			]
			'extra':   [
				Package{
					repo:    'extra'
					name:    'mesa'
					version: '1:26.3.1-1'
				},
				Package{
					repo:    'extra'
					name:    'mesa-utils'
					version: '9.0.0-7'
					depends: ['mesa']
				},
			]
		}
	}
	with_aurora := db.closure(['mesa-aurora', 'mesa-utils'])!
	assert with_aurora.map(it.name) == ['mesa-aurora', 'mesa-utils']
	without := db.closure(['mesa-utils'])!
	assert without.map(it.name) == ['mesa-utils', 'mesa']
	if _ := db.closure(['absent']) {
		assert false
	}
}
