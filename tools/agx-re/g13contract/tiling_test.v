module g13contract

fn test_tiling_expressions_preserve_precedence_casts_and_ceil_division() {
	names := {'a': 'a', 'b': 'b', 'c': 'c'}
	assert tiling_expression('a | b << 9 | c << 18', names)! == '((a | (b << u64(9))) | (c << u64(18)))'
	assert tiling_expression('align(a.div_ceil(4), 8)', names)! == 'reference_align(reference_div_ceil(a, u64(4)), u64(8))'
	assert tiling_expression('(4 * a) as usize * b as usize', names)! == '(u64((u64(4) * a)) * u64(b))'
	assert tiling_expression('if a > 1 { 0xe000 | (a - 1) } else { 0x8000 }', names)!.contains('if (a > u64(1))')
	assert tiling_expression('32u32', names)! == 'u64(32)'
	for source in ['unknown', 'a.wrapping_mul(b)', 'a as u8', 'a +', 'a; b', 'a % b', 'evil(a)', 'a b', '0xzz'] {
		if _ := tiling_expression(source, names) { assert false, source }
	}
}

fn test_tiling_statement_refuses_missing_or_unterminated_formula() {
	assert tiling_statement('let x = a.div_ceil(4);', 'x')! == 'a.div_ceil(4)'
	assert tiling_statement('let mut x = align(a, 8);', 'x')! == 'align(a, 8)'
	for source in ['let y = 1;', 'let x = 1'] { if _ := tiling_statement(source, 'x') { assert false } }
}
