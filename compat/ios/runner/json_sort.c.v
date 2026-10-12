// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn json_fold(byte u8) u8 { return if byte >= `A` && byte <= `Z` { byte + 32 } else { byte } }

fn json_digit(byte u8) bool { return byte >= `0` && byte <= `9` }

// The measured ASCII subset of Foundation's numeric/case-insensitive ordering.
// Equal primary weights use lowercase first and shorter numeric spelling first.
fn json_key_compare(a string, b string) int {
	mut i := 0
	mut j := 0
	mut tie := 0
	for i < a.len && j < b.len {
		if json_digit(a[i]) && json_digit(b[j]) {
			start_a := i
			start_b := j
			for i < a.len && a[i] == `0` { i++ }
			for j < b.len && b[j] == `0` { j++ }
			digits_a := i
			digits_b := j
			for i < a.len && json_digit(a[i]) { i++ }
			for j < b.len && json_digit(b[j]) { j++ }
			if i - digits_a != j - digits_b {
				return if i - digits_a < j - digits_b { -1 } else { 1 }
			}
			for offset in 0 .. i - digits_a {
				if a[digits_a + offset] != b[digits_b + offset] {
					return if a[digits_a + offset] < b[digits_b + offset] { -1 } else { 1 }
				}
			}
			if tie == 0 && i - start_a != j - start_b {
				tie = if i - start_a < j - start_b { -1 } else { 1 }
			}
			continue
		}
		left := json_fold(a[i])
		right := json_fold(b[j])
		if left != right {
			return if left == `_` || (right != `_` && left < right) { -1 } else { 1 }
		}
		if tie == 0 && a[i] != b[j] { tie = if a[i] > b[j] { -1 } else { 1 } }
		i++
		j++
	}
	if i != a.len || j != b.len { return if i == a.len { -1 } else { 1 } }
	return tie
}

fn json_key_sift(header &ObjHeader, mut order []int, start int, end int) {
	mut root := start
	for root * 2 + 1 < end {
		mut child := root * 2 + 1
		if child + 1 < end && json_key_compare(string_text(header.keys[order[child]]), string_text(header.keys[order[child + 1]])) < 0 {
			child++
		}
		if json_key_compare(string_text(header.keys[order[root]]), string_text(header.keys[order[child]])) >= 0 {
			return
		}
		order[root], order[child] = order[child], order[root]
		root = child
	}
}

fn json_sort_keys(header &ObjHeader, mut order []int) {
	// Heap sort bounds work to O(n log n) without recursive or scratch allocations.
	for i := order.len / 2; i > 0; i-- { json_key_sift(header, mut order, i - 1, order.len) }
	for end := order.len - 1; end > 0; end-- {
		order[0], order[end] = order[end], order[0]
		json_key_sift(header, mut order, 0, end)
	}
}
