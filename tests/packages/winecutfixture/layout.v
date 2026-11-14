// SPDX-License-Identifier: GPL-2.0-or-later
module winecutfixture

pub fn names(scaled bool) []string {
	mut result := []string{cap: if scaled { 741 } else { 3 }}
	result << 'a.dll'; result << 'b.dll'
	if scaled {
		for index in 2 .. 740 { result << 'builtin-${index:04}.dll' }
		result << 'z.dll'
	} else { result << 'c.dll' }
	return result
}

pub fn points(scaled bool, all_syncs bool) []int {
	if scaled { return [1112, 2219, 2221, 2222] }
	return if all_syncs { [1, 2, 3, 4, 5, 6, 7, 8] } else { [1, 2, 3] }
}

pub struct Boundary {
pub:
	replaced int
	added bool
	staged bool
}

pub fn boundary(point int, old_count int) !Boundary {
	if old_count < 1 || old_count > 899 || point < 1 || point > old_count * 3 + 2 {
		return error('invalid migration sync boundary')
	}
	return Boundary{
		replaced: if point > old_count * 3 { old_count } else { (point + 1) / 3 }
		added: point > old_count * 3
		staged: point <= old_count * 3 && point % 3 == 1
	}
}
