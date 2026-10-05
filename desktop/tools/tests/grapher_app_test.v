// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import os
import ui2

fn grapher_test_value(source string, x f64, expected f64) {
	program := grapher_parse(source) or { panic('expected valid expression') }
	actual := program.evaluate(x)
	assert actual.valid
	assert math.abs(actual.value - expected) <= 1e-10 * (1 + math.abs(expected))
}

fn test_grapher_parser_precedence_parentheses_and_right_associative_power() {
	grapher_test_value('2+3*4', 0, 14)
	grapher_test_value('(2+3)*4', 0, 20)
	grapher_test_value('-2^2', 0, -4)
	grapher_test_value('(-2)^2', 0, 4)
	grapher_test_value('2^-2', 0, 0.25)
	grapher_test_value('2^3^2', 0, 512)
	grapher_test_value('10-3-2', 0, 5)
	grapher_test_value('12/3/2', 0, 2)
	grapher_test_value('+.25+1e-2', 0, 0.26)
	grapher_test_value('x*x+2*x+1', -3, 4)
}

fn test_grapher_functions_constants_and_radians() {
	grapher_test_value('sin(pi/2)+cos(0)', 0, 2)
	grapher_test_value('tan(pi/4)', 0, 1)
	grapher_test_value('asin(1)+acos(0)', 0, math.pi)
	grapher_test_value('atan(1)', 0, math.pi / 4)
	grapher_test_value('sqrt(9)+abs(-2)', 0, 5)
	grapher_test_value('ln(e)+log(100)', 0, 3)
	grapher_test_value('exp(0)+floor(1.9)+ceil(-1.9)', 0, 1)
	assert grapher_constant('pi/2') != none
	assert grapher_constant('x+1') == none
}

fn test_grapher_rejects_malformed_and_bounded_inputs() {
	for source in ['', '2x', 'sin x', 'sin()', 'x+', '(x', 'x)', '2^^3', '1e+', '.', 'nan', 'inf',
		'1e309', '1e 2', '1e +2', 'x;1', 'X', 'sin(x,1)', 'sqrt(2))', '日本語']! {
		assert grapher_parse(source) == none
	}
	long := 'x+'.repeat(130) + 'x'
	deep := '('.repeat(33) + 'x' + ')'.repeat(33)
	powers := 'x^'.repeat(33) + 'x'
	defer {
		unsafe {
			long.free()
			deep.free()
			powers.free()
		}
	}
	assert grapher_parse(long) == none
	assert grapher_parse(deep) == none
	assert grapher_parse(powers) == none
	steps := 'floor(x)+'.repeat(grapher_step_limit + 1) + 'x'
	defer { unsafe { steps.free() } }
	assert grapher_parse(steps) == none
}

fn test_grapher_domains_and_nonfinite_results_are_gaps() {
	for source in ['1/0', 'sqrt(-1)', 'ln(0)', 'ln(-1)', 'acos(2)', 'asin(-2)', 'exp(1000)', '(-1)^.5',
		'tan(pi/2)', '1e308*1e308']! {
		program := grapher_parse(source) or { panic('expected syntax') }
		assert !program.evaluate(0).valid
	}
	program := grapher_parse('sqrt(x)') or { panic('expected syntax') }
	assert !program.evaluate(-1).valid
	assert program.evaluate(0).valid
	assert program.evaluate(4).value == 2
}

fn test_grapher_range_validation_and_errors_clear_the_plot() {
	mut app := GrapherApp{}
	app.initialize()
	defer { app.close_app() }
	assert app.plotted
	assert app.range == [-10.0, 10.0, -5.0, 5.0]!
	for pair in [[0.0, 0.0]!, [1.0, -1.0]!, [-1e13, 1e13]!, [0.0, 1e-10]!, [0.0, math.inf(1)]!]! {
		assert !grapher_range_valid(pair[0], pair[1])
	}
	app.set_field(1, 'x')
	assert !app.plot()
	assert !app.plotted
	assert app.status == 'grapher.range_invalid'
	app.reset_ranges()
	app.set_field(0, 'sqrt(-1)')
	assert app.plot()
	assert app.status == 'grapher.no_values'
	app.set_field(0, 'sqrt(x)')
	assert app.plot()
	assert app.status == 'grapher.domain_gaps'
	app.set_field(0, 'sin(')
	assert !app.plot()
	assert !app.plotted
	assert app.status == 'grapher.expression_invalid'
}

fn test_grapher_discontinuities_do_not_connect_division_or_tangent_poles() {
	program := grapher_parse('1/(x-0.123)') or { panic('expected syntax') }
	left := program.evaluate(0.1)
	right := program.evaluate(0.15)
	assert left.valid && right.valid
	assert left.branches != right.branches
	assert !grapher_connect(&program, left, right, 0.1, 0.05, 1000)
	tangent := grapher_parse('tan(x)') or { panic('expected syntax') }
	assert !grapher_connect(&tangent, tangent.evaluate(1.5), tangent.evaluate(1.7), 1.5, 0.2, 1000)
	narrow := grapher_parse('1/((x-.1)*(x-.15))') or { panic('expected syntax') }
	// Both endpoints share the sign, but interior validation catches two poles.
	assert !grapher_connect(&narrow, narrow.evaluate(0), narrow.evaluate(.2), 0, .2, 1e6)
	line := grapher_parse('x') or { panic('expected syntax') }
	assert grapher_connect(&line, line.evaluate(0), line.evaluate(.01), 0, .01, 10)
	stairs := grapher_parse('floor(x)') or { panic('expected syntax') }
	assert !grapher_connect(&stairs, stairs.evaluate(.9), stairs.evaluate(1.1), .9, .2, 1000)
	mut app := GrapherApp{}
	app.initialize()
	defer { app.close_app() }
	app.set_field(0, '1/(x-0.123)')
	assert app.plot()
	step := (app.range[1] - app.range[0]) / f64(grapher_sample_count - 1)
	for index in 1 .. grapher_sample_count {
		if app.range[0] + f64(index - 1) * step < 0.123 && app.range[0] + f64(index) * step > 0.123 {
			assert !app.connect[index]
		}
	}
}

fn test_grapher_keyboard_paste_zoom_and_reset() {
	mut app := GrapherApp{}
	app.initialize()
	defer { app.close_app() }
	app.handle('grapher.expression')!
	app.paste_input('x^2')
	app.key_input('\r')
	assert app.plotted
	assert app.field_text(0) == 'x^2'
	app.handle('grapher.zoom_in')!
	assert app.range == [-5.0, 5.0, -2.5, 2.5]!
	app.handle('grapher.zoom_out')!
	assert app.range == [-10.0, 10.0, -5.0, 5.0]!
	app.handle('grapher.xmin')!
	app.paste_input('-pi')
	app.handle('grapher.plot')!
	assert app.range[0] == -math.pi
	app.handle('grapher.reset')!
	assert app.range[0] == -10
	assert app.field_text(0) == 'x^2'
	app.key_input('\x0c\x01sin(x)')
	assert app.field_text(0) == 'sin(x)'
	app.paste_input('x\n+1')
	assert app.field_text(0) == 'sin(x)'
	assert app.status == 'grapher.input_invalid'
	too_long := 'x'.repeat(257)
	defer { unsafe { too_long.free() } }
	app.key_input('\x01')
	app.paste_input(too_long)
	assert app.field_text(0) == 'sin(x)'
	assert app.status == 'grapher.input_limit'
	app.handle('grapher.path')!
	app.paste_input('/home/test/graph-Ж.csv')
	app.key_input('\x7f')
	assert app.field_text(5) == '/home/test/graph-Ж.cs'
}

fn test_grapher_exports_exact_samples_and_refuses_overwrite_and_links() {
	temporary := os.join_path(os.temp_dir(), 'vinix-grapher-${os.getpid()}')
	os.mkdir_all(temporary)!
	root := os.real_path(temporary)
	defer {
		os.rmdir_all(root) or {}
		unsafe {
			temporary.free()
			root.free()
		}
	}
	path := disk_utility_join_path(root, 'x-Ж.csv')
	link := disk_utility_join_path(root, 'link.csv')
	parent_link := disk_utility_join_path(root, 'parent')
	linked_path := disk_utility_join_path(parent_link, 'through-link.csv')
	defer {
		unsafe {
			path.free()
			link.free()
			parent_link.free()
			linked_path.free()
		}
	}
	mut app := GrapherApp{}
	app.initialize()
	defer { app.close_app() }
	app.set_field(0, 'sqrt(x)')
	app.set_field(1, '-1')
	app.set_field(2, '1')
	app.set_field(5, path)
	app.export_csv()
	assert app.export_status == 'grapher.export_saved'
	data := os.read_file(path)!
	defer { unsafe { data.free() } }
	assert data.starts_with('x,y\n-1,\n')
	assert data.contains('\n0,0\n')
	assert data.ends_with('1,1\n')
	mut newlines := 0
	for ch in data { if ch == `\n` { newlines++ } }
	assert newlines == grapher_sample_count + 1
	app.export_csv()
	assert app.export_status == 'grapher.export_exists'
	os.symlink(path, link)!
	app.set_field(5, link)
	app.export_csv()
	assert app.export_status == 'grapher.export_exists'
	os.symlink(root, parent_link)!
	app.set_field(5, linked_path)
	app.export_csv()
	assert app.export_status == 'grapher.export_failed'
	app.set_field(5, 'relative.csv')
	app.export_csv()
	assert app.export_status == 'grapher.export_invalid'
}

fn test_grapher_shortened_export_path_uses_exact_field_length() {
	temporary := os.join_path(os.temp_dir(), 'vinix-grapher-short-${os.getpid()}')
	os.mkdir_all(temporary)!
	root := os.real_path(temporary)
	defer {
		os.rmdir_all(root) or {}
		unsafe {
			temporary.free()
			root.free()
		}
	}
	long := disk_utility_join_path(root, 'much-longer-filename.csv')
	short := disk_utility_join_path(root, 'x.csv')
	defer {
		unsafe {
			long.free()
			short.free()
		}
	}
	mut app := GrapherApp{}
	app.initialize()
	defer { app.close_app() }
	app.handle('grapher.path')!
	app.paste_input(long)
	app.key_input('\x01')
	app.paste_input(short)
	app.handle('grapher.export')!
	assert app.export_status == 'grapher.export_saved'
	assert os.exists(short)
	assert !os.exists(long)
}

fn test_grapher_registered_home_alias_default_export_uses_canonical_directory() {
	temporary := os.join_path(os.temp_dir(), 'vinix-grapher-home-${os.getpid()}')
	os.mkdir_all(temporary)!
	root := os.real_path(temporary)
	alias := disk_utility_join_path(root, 'registered-home')
	path := disk_utility_join_path(root, 'graph.csv')
	os.symlink(root, alias)!
	previous := desktop_user_home
	desktop_user_home = alias
	defer {
		desktop_user_home = previous
		os.rmdir_all(root) or {}
		unsafe {
			temporary.free()
			root.free()
			alias.free()
			path.free()
		}
	}
	mut app := GrapherApp{}
	app.initialize()
	defer { app.close_app() }
	assert app.field_text(5) == path
	app.handle('grapher.export')!
	assert app.export_status == 'grapher.export_saved'
	assert os.exists(path)
}

fn test_grapher_resize_and_native_wire_use_supported_finite_elements() {
	mut app := GrapherApp{}
	app.initialize()
	defer { app.close_app() }
	for size in [ui2.rect(0, 0, 840, 636), ui2.rect(0, 0, 320, 380), ui2.rect(0, 0, 440, 410),
		ui2.rect(0, 0, 1600, 900)]! {
		begin_frame_elements()
		tree := app.build(size)!
		mut encoded := []u8{cap: 1024 * 1024}
		unsafe { encoded.flags |= .noslices }
		encode_app_element(tree, mut encoded)!
		mut reader := WireReader{ data: encoded }
		decoded := decode_app_element(mut reader, 0)!
		assert reader.index == encoded.len
		assert decoded.id == 'grapher.body'
		mut charts := 0
		for child in decoded.children {
			if child.id != 'grapher.chart' { continue }
			charts++
			assert child.frame.width == tree.frame.width - 76
			assert child.frame.height == tree.frame.height - 282
			assert child.children.len <= grapher_sample_count + 24
			for mark in child.children {
				assert mark.kind == .view
				assert math.is_finite(mark.frame.x) && math.is_finite(mark.frame.y)
				assert mark.frame.width > 0 && mark.frame.height > 0
			}
		}
		assert charts == 1
		free_tree(decoded)
		free_tree(tree)
		unsafe { encoded.free() }
	}
}
