// SPDX-License-Identifier: GPL-2.0-or-later
module asahipolicy

fn test_disk_allocation_and_action_guards() {
	for disk in ['', 'disk', 'disk-1', 'disk1s2', 'disk١', 'disk1\n', 'disk 0'] {
		config(disk, '32000000000') or {
			assert err.msg() == 'Invalid target disk identifier'
			continue
		}
		assert false, disk
	}
	for size in ['0', '15999999999', '-1', 'wrong', '9223372036854775808'] {
		config('disk0', size) or { continue }
		assert false, size
	}
	selected := config('disk0', '32000000000') or { panic(err) }
	for current in ['disk0', 'disk4'] {
		for system in ['disk0', 'disk4'] {
			for mask in 0 .. 16 {
				mut available := []string{}
				for index, name in ['d', 'w', 'f', 'r'] {
					if mask & (1 << index) != 0 { available << name }
				}
				for free in [i64(0), 31_999_999_999, 32_000_000_000, 64_000_000_000] {
					golden := if current != 'disk0' {
						if 'd' in available { 'd' } else { '' }
					} else if current != system {
						if 'w' in available { 'w' } else { '' }
					} else if 'f' in available && free >= 32_000_000_000 {
						'f'
					} else if 'r' in available {
						'r'
					} else {
						''
					}
					actual := selected.action(current, system, available, [1, free]) or {
						assert golden == ''
						continue
					}
					assert actual == golden && actual != ''
				}
			}
		}
	}
}

fn test_booted_container_uniqueness_and_external_eligibility() {
	for length in 0 .. 10 {
		for mask in 0 .. (1 << length) {
			mut matches := []bool{}
			mut indices := []int{}
			for index in 0 .. length {
				matching := mask & (1 << index) != 0
				matches << matching
				if matching { indices << index }
			}
			actual := resize_candidate(matches) or {
				assert indices.len != 1
				continue
			}
			assert indices.len == 1 && actual == indices[0]
		}
	}
	selected := config('disk4', '16000000000') or { panic(err) }
	selected.select_external(['disk4', 'disk5']) or { panic(err) }
	if _ := selected.select_external(['disk5']) {
		assert false
	}
}

fn test_alignment_macos_margin_and_stub_partition_accounting() {
	assert free_margin(true) == 38_000_000_000 && free_margin(false) == 1_000_000_000
	for allocation in [i64(16_000_000_000), 32_000_000_000, 100_000_000_000] {
		selected := config('disk0', allocation.str()) or { panic(err) }
		for total in [i64(500_000_000_000), 500_000_000_001, 999_999_999_999] {
			value := selected.macos_size(total, i64(38_000_000_000)) or { panic(err) }
			assert value % 1_048_576 == 0 && value >= total - allocation && value - (total - allocation) < 1_048_576
			if _ := selected.macos_size(total, value + 1) {
				assert false
			}
		}
		assert selected.os_partition(allocation, allocation) or { panic(err) } == allocation - 2_499_805_184
		if _ := selected.os_partition(allocation - 1, 0) {
			assert false
		}
		if _ := selected.os_partition(allocation * 2, allocation + 1) {
			assert false
		}
	}
	assert newest_version(0) == -1 && newest_version(3) == 2
	signed_profile(['Vinix']) or { panic(err) }
	for names in [[]string{}, ['Other'], ['Vinix', 'Other']] {
		signed_profile(names) or {
			assert err.msg().contains('signed Vinix')
			continue
		}
		assert false
	}
	assert completion(false)[2].contains('25 seconds') && completion(false)[3].contains('HOLD')
	assert completion(true)[1].contains('After restart')
}
