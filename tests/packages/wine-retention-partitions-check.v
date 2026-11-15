// SPDX-License-Identifier: GPL-2.0-or-later
// Verify that retained partition results cover the complete refusal matrix.
module main

import os
import json2

struct Report {
	baseline bool
	copied_baseline bool
	refused []string
}

fn expected_cases() []string {
	mut names := ['package-flag', 'linked-mode', 'hidden-import', 'raw-outcome', 'deadline', 'missing-marker', 'duplicate-marker', 'marker-cr', 'vm-memory',
		'resource-manifest', 'resource-input', 'resource-query', 'resource-flag', 'linked-resource']
	for program in ['guest', 'package'] {
		for kind in ['manifest', 'input', 'query', 'flag', 'linked'] { names << program + '-resource-' + kind }
	}
	names << ['bridge-c-trace', 'bridge-c-manifest', 'guest-c-pin', 'package-c-command', 'guest-c-linked']
	names << ['bridge-link-proof', 'bridge-link-response', 'bridge-link-linked', 'guest-link-output', 'package-link-argv']
	names << ['bridge-host-baseline', 'bridge-host-environment', 'guest-host-trace', 'package-host-pin', 'guest-host-linked']
	names << ['bridge-v-host-baseline', 'bridge-v-host-environment', 'guest-v-host-trace', 'package-v-host-pin', 'guest-v-host-linked']
	names << ['bridge-host-binding', 'bridge-host-input', 'controller-host-binding', 'controller-host-input', 'controller-host-linked',
		'bridge-host-link-input', 'controller-host-link-input']
	return names
}

fn check() ! {
	if os.args.len != 2 { return error('usage: CHECK PARTITION_OUTPUT_PREFIX') }
	mut seen := map[string]bool{}
	expected := expected_cases()
	for partition in 0 .. 4 {
		path := os.args[1] + partition.str() + '/result.json'
		st := os.lstat(path)!
		if st.get_filetype() != .regular || st.size > 65536 { return error('ordinary bounded partition result required') }
		result := json2.decode[Report](os.read_file(path)!)!
		mut assigned := []string{}
		for index, name in expected { if index % 4 == partition { assigned << name } }
		if !result.baseline || !result.copied_baseline || result.refused != assigned {
			return error('partition baselines or refusal count differ')
		}
		for name in result.refused {
			if name == '' || name in seen { return error('empty or repeated partition refusal') }
			seen[name] = true
		}
	}
	if seen.len != 51 || 'bridge-host-link-input' !in seen || 'controller-host-link-input' !in seen {
		return error('complete host-link retention matrix required')
	}
	println('WINE RETENTION PARTITIONS PASS four real/copied baselines; fifty-one unique exact refusals')
}

fn main() { check() or { eprintln(err); exit(1) } }
