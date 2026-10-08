// SPDX-License-Identifier: GPL-2.0-or-later
module transcriptcore

pub struct WakeResult {
pub:
	completed                       bool
	boot_process_reaped             bool
	old_completed                   bool
	old_smc_efault                  bool
	old_permission_contracts_passed bool
	old_alignment_mismatches        []string
	old_alignment_contracts_passed  bool
	new_passed                      bool
	passed                          bool
}

pub fn wake_verdict(raw string, reaped bool) WakeResult {
	text := raw.replace('\r', '')
	old_marker := 'WAKE-OP-VARIANT-BEGIN:old'
	new_marker := 'WAKE-OP-VARIANT-BEGIN:new'
	end_marker := 'WAKE-OP-GUEST-END'
	old_start := text.index(old_marker) or { -1 }
	new_start := text.index(new_marker) or { -1 }
	end := text.index(end_marker) or { -1 }
	markers := [old_marker, new_marker, end_marker]
	mut unique := true
	for marker in markers { unique = unique && text.count(marker) == 1 }
	ordered := 0 <= old_start && old_start < new_start && new_start < end && unique
	old := if ordered { text[old_start..new_start] } else { '' }
	new := if ordered { text[new_start..end] } else { '' }
	old_lines := old.split('\n')
	new_lines := new.split('\n')
	permissions := ['write-only-secondary', 'write-only-operation-stored-value',
		'read-only-primary-wake', 'read-only-primary-wake-op', 'read-only-secondary',
		'prot-none-secondary', 'unmapped-secondary']
	alignments := ['misaligned-primary', 'misaligned-secondary']
	old_completed := old_lines.filter(it.starts_with('WAKE-OP-VARIANT-EXIT:old:')) == ['WAKE-OP-VARIANT-EXIT:old:1']
	old_smc := 'WAKE-OP SMC result=-1 errno=14 word=17' in old_lines
	old_permissions := permissions.all('WAKE-OP CHECK ' + it + ' PASS' in old_lines)
	new_passed := new_lines.filter(it == 'WAKE-OP PASS failures=0').len == 1 && new_lines.filter(it.starts_with('WAKE-OP-VARIANT-EXIT:new:')) == ['WAKE-OP-VARIANT-EXIT:new:0']
	return WakeResult{ordered, reaped, old_completed, old_smc, old_permissions, alignments.filter('WAKE-OP CHECK ' + it + ' FAIL' in old_lines), alignments.all('WAKE-OP CHECK ' + it + ' PASS' in old_lines), new_passed, ordered && reaped && old_completed && old_smc && old_permissions && new_passed}
}
