// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

// A restricted scalar-expression translator for the selected Rust tiling
// calculation. It never reads native arithmetic. Unknown names, calls, casts
// and syntax are refused. Model arithmetic is widened; the selected 16K/2048
// bounds keep the source's pre-allocation u32 calculations within range.
struct TilingExpression {
mut:
	tokens []string
	position int
	names map[string]string
}

fn tiling_tokens(source string) ![]string {
	mut tokens := []string{}
	mut i := 0
	for i < source.len {
		if source[i].is_space() { i++; continue }
		start := i
		if source[i].is_letter() || source[i].is_digit() || source[i] == `_` {
			for i < source.len && word(source[i]) { i++ }
		} else if source[i..].starts_with('<<') { i += 2 }
		else if source[i] in [`(`, `)`, `{`, `}`, `,`, `.`, `+`, `-`, `*`, `/`, `|`, `>`] { i++ }
		else { return error('unsupported tiling expression: ' + source[i..]) }
		tokens << source[start..i]
	}
	return tokens
}

fn (mut p TilingExpression) take(value string) ! {
	if p.position >= p.tokens.len || p.tokens[p.position] != value { return error('expected tiling token ' + value) }
	p.position++
}

fn tiling_precedence(token string) int {
	return match token { '>' { 1 } '|' { 2 } '<<' { 3 } '+', '-' { 4 } '*', '/' { 5 } else { 0 } }
}

fn (mut p TilingExpression) primary() !string {
	if p.position >= p.tokens.len { return error('missing tiling expression') }
	token := p.tokens[p.position]; p.position++
	mut out := ''
	if token == '(' {
		out = p.expression(1)!
		p.take(')')!
	} else if token == 'if' {
		condition := p.expression(1)!
		p.take('{')!; yes := p.expression(1)!; p.take('}')!
		p.take('else')!; p.take('{')!; no := p.expression(1)!; p.take('}')!
		out = '(if ' + condition + ' { ' + yes + ' } else { ' + no + ' })'
	} else if token == 'align' {
		p.take('(')!; value := p.expression(1)!; p.take(',')!
		alignment := p.expression(1)!; p.take(')')!
		out = 'reference_align(' + value + ', ' + alignment + ')'
	} else if token[0].is_digit() {
		value := token.trim_string_right('u32').replace('_', '')
		require(value.len > 0 && (if value.starts_with('0x') { value[2..].bytes().all(it.is_hex_digit()) } else { value.bytes().all(it.is_digit()) }), 'unsupported tiling number ' + token)!
		out = 'u64(' + value + ')'
	} else if token in p.names { out = p.names[token] }
	else { return error('unknown tiling name ' + token) }
	for p.position < p.tokens.len {
		if p.tokens[p.position] == 'as' {
			p.position++
			if p.position >= p.tokens.len { return error('missing tiling cast') }
			kind := p.tokens[p.position]; p.position++
			require(kind in ['u16', 'u32', 'usize'], 'unsupported tiling cast ' + kind)!
			out = if kind == 'usize' { 'u64(' + out + ')' } else { 'u64(' + kind + '(' + out + '))' }
		} else if p.tokens[p.position] == '.' {
			p.position++
			p.take('div_ceil')!; p.take('(')!
			divisor := p.expression(1)!; p.take(')')!
			out = 'reference_div_ceil(' + out + ', ' + divisor + ')'
		} else { break }
	}
	return out
}

fn (mut p TilingExpression) expression(minimum int) !string {
	mut out := p.primary()!
	for p.position < p.tokens.len {
		op := p.tokens[p.position]
		precedence := tiling_precedence(op)
		if precedence < minimum { break }
		p.position++
		right := p.expression(precedence + 1)!
		out = '(' + out + ' ' + op + ' ' + right + ')'
	}
	return out
}

fn tiling_expression(source string, names map[string]string) !string {
	// Only these scalar cmdbuf members are used by the selected formulas.
	mut text := source
	for member in ['ppp_ctrl', 'vertex_helper.cfg', 'width_px', 'height_px', 'layers', 'utile_width_px', 'utile_height_px'] {
		text = text.replace('cmdbuf.' + member, 'input_' + member.replace('.', '_'))
	}
	mut parser := TilingExpression{tokens: tiling_tokens(text)!, names: names}
	out := parser.expression(1)!
	require(parser.position == parser.tokens.len, 'trailing tiling expression tokens')!
	return out
}

fn tiling_statement(source string, name string) !string {
	markers := ['let ' + name + ' =', 'let mut ' + name + ' =']
	for marker in markers {
		if position := source.index(marker) {
			rest := source[position + marker.len..]
			end := rest.index(';') or { return error('unterminated tiling statement ' + name) }
			return rest[..end].trim_space()
		}
	}
	return error('missing tiling statement ' + name)
}

pub fn tiling_reference_v(render string, util string) !string {
	align := section(util, 'pub(crate) fn align<T>(', '/// Aligns an integer type down', 'Asahi tiling align')!
	require(align.contains('(a + b - one) & !(b - one)') && align.contains('let one: T = !def / !def;'), 'Asahi power-of-two align changed')!
	calc_raw := section(render, 'fn get_tiling_params(', '/// Submit work to a render queue.', 'Asahi tiling calculation')!
	calc := calc_raw.split_into_lines().map(it.all_before('//')).join('\n')
	validation := section(render, 'pub(super) fn submit_render(', 'let mut vtx_user_timestamps:', 'Asahi dimension validation')!
	require_order(validation, ['cmdbuf.width_px == 0', 'cmdbuf.height_px == 0', 'cmdbuf.width_px > 16384', 'cmdbuf.height_px > 16384', 'return Err(EINVAL)'], 'Asahi tiling dimension bounds')!
	require_order(calc, ['if layers == 0 || layers > 2048', 'return Err(EINVAL)', '(32, 32) | (32, 16) | (16, 16) => ()'], 'Asahi layer and uTile bounds')!
	require_order(calc, ['let meta1_layer_stride = if num_clusters > 1', '} else {\n            0\n        }', 'if num_clusters > 1 {', 'min_tvb_blocks = min_tvb_blocks.max(7 + 2 * layers)'], 'Asahi single-cluster specialization')!
	mut names := map[string]string{}
	names['num_clusters'] = 'u64(1)'
	for member, field in {'width_px': 'width', 'height_px': 'height', 'layers': 'layers', 'utile_width_px': 'utile_width', 'utile_height_px': 'utile_height', 'ppp_ctrl': 'ppp', 'vertex_helper_cfg': 'helper'} { names['input_' + member] = 'u64(input.' + field + ')' }
	for field in ['width', 'height', 'layers'] { names[field] = 'u64(input.' + field + ')' }
	require_order(calc, ['let width: u32 = cmdbuf.width_px as u32;', 'let height: u32 = cmdbuf.height_px as u32;', 'let layers: u32 = cmdbuf.layers as u32;'], 'Asahi tiling input widths')!
	require_order(render, ['let samples_log2 = match cmdbuf.samples {', '1 => 0,', '2 => 1,', '4 => 2,', 'return Err(EINVAL);', 'let utile_config = ((tile_info.utile_width / 16) << 12)', '| ((tile_info.utile_height / 16) << 14)', '| samples_log2;'], 'Asahi packed uTile configuration')!
	mut code := 'fn reference_tile(input Input) G13TileInfo {\n'
	for name in ['tile_width', 'tile_height', 'utile_width', 'utile_height', 'utiles_per_tile_x', 'utiles_per_tile_y', 'utiles_per_tile', 'tiles_x', 'tiles_y', 'tiles', 'mtiles_x', 'mtiles_y', 'mtiles', 'tiles_per_mtile_x', 'tiles_per_mtile_y', 'tiles_per_mtile', 'mtile_x1', 'mtile_x2', 'mtile_x3', 'mtile_y1', 'mtile_y2', 'mtile_y3', 'rgn_entry_size', 'rgn_size', 'tilemap_size', 'tpc_entry_size', 'tpc_mtile_stride', 'tpc_size', 'min_tvb_blocks'] {
		expression := tiling_expression(tiling_statement(calc, name)!, names)!
		code += '\t' + name + ' := ' + expression + '\n'
		names[name] = name
	}
	// width/height/layers are parameters of the modeled calculation, not its
	// returned TileInfo. Their casts above retain the source scalar widths.
	return code + tiling_return_v(calc, names)!
}

fn tiling_return_v(calc string, values map[string]string) !string {
	mut names := values.clone()
	for field in ['width', 'height', 'layers'] { names[field] = 'u64(input.' + field + ')' }
	mut code := '\treturn G13TileInfo{\n'
	for target, expression in {'tiles_x': 'tiles_x', 'tiles_y': 'tiles_y', 'tiles': 'tiles', 'tiles_per_mtile_x': 'tiles_per_mtile_x', 'tiles_per_mtile_y': 'tiles_per_mtile_y', 'utiles_per_mtile_x': 'tiles_per_mtile_x * utiles_per_tile_x', 'utiles_per_mtile_y': 'tiles_per_mtile_y * utiles_per_tile_y', 'tilemap_size': 'tilemap_size', 'tail_pointer_size': 'tpc_size', 'min_tvb_blocks': 'min_tvb_blocks'} {
		// Return aliases and multipliers are also bound to the selected source.
		field := if target == 'tail_pointer_size' { 'tpc_size' } else { target }
		if expression == field { require(calc.contains('\n            ' + field + ',') || calc.contains(field + ': ' + field + ' as usize,'), 'Asahi tiling return alias changed: ' + field)! }
		else { require(calc.contains(field + ': ' + expression + ','), 'Asahi tiling return expression changed: ' + field)! }
		kind := if target in ['tilemap_size', 'tail_pointer_size'] { 'u64' } else { 'u32' }
		code += '\t\t' + target + ': ' + kind + '(' + tiling_expression(expression, names)! + ')\n'
	}
	require(calc.contains('layermeta_size: if layers > 1 { 0x100 } else { 0 },'), 'Asahi layer metadata size changed')!
	code += '\t\tlayermeta_size: if input.layers > 1 { u64(0x100) } else { u64(0) }\n'
	code += '\t\tutile_config: ((input.utile_width / 16) << 12) | ((input.utile_height / 16) << 14) | input.sample_bits\n'
	code += '\t\tparams: fw.G13TilingParameters{\n'
	params := section(calc, 'params: fw::vertex::raw::TilingParameters {', '__pad: Default::default(),', 'Asahi tiling packed words')!.all_after('TilingParameters {')
	// Split commas only outside if-expression braces and parentheses.
	mut depth := 0
	mut start := 0
	mut count := 0
	for i, ch in params.bytes() {
		if ch in [`(`, `{`] { depth++ }
		if ch in [`)`, `}`] { depth-- }
		if ch != `,` || depth != 0 { continue }
		field := params[start..i].trim_space(); start = i + 1
		name := field.all_before(':')
		expression := if field.contains(':') { field.all_after(':').trim_space() } else { field }
		target := {'rgn_size': 'region_size', 'ppp_ctrl': 'ppp_control', 'te_mtile1': 'te_mtile_1', 'te_mtile2': 'te_mtile_2', 'tpc_stride': 'tail_pointer_stride'}[name] or { name }
		require(target in ['region_size', 'unk_4', 'ppp_control', 'x_max', 'y_max', 'te_screen', 'te_mtile_1', 'te_mtile_2', 'tiles_per_mtile', 'tail_pointer_stride', 'unk_24', 'unk_28', 'helper_cfg'], 'unsupported Asahi tiling word ' + name)!
		kind := if target in ['x_max', 'y_max'] { 'u16' } else { 'u32' }
		code += '\t\t\t' + target + ': ' + kind + '(' + tiling_expression(expression, names)! + ')\n'
		count++
	}
	require(count == 13 && params[start..].trim_space() == '', 'Asahi tiling word count changed')!
	return code + '\t\t}\n\t}\n}\n'
}
