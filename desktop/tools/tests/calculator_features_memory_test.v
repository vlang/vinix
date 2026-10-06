// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn calculator_memory_random_write(fd int, bits u64) {
	mut bytes := [8]u8{}
	for index in 0 .. 8 { bytes[index] = u8(bits >> u32((7 - index) * 8)) }
	assert desktop_write(fd, &bytes[0], 8) == 8
}

fn test_calculator_random_repeated_entropy_failure_operand_history_and_wire_release_memory() {
	mut app := new_calculator_app()
	app.handle('calculator.mode.scientific')!
	for size in [ui2.rect(0, 0, 540, 430), ui2.rect(0, 0, 620, 566)]! {
		begin_frame_elements()
		free_tree(app.build(size)!)
	}
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { desktop_close(pair[0]) desktop_close(pair[1]) }
	assert C.fcntl(pair[0], C.F_SETFL, C.O_NONBLOCK) == 0
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for bits in [u64(0), u64(1) << 63, calculator_programmer_max]! {
			app.key_input('c2+1e-')
			app.scientific_random_from_fd(-1)
			assert app.calculator.display == '1e-' && app.exponent_input
			calculator_memory_random_write(pair[1], bits)
			app.scientific_random_from_fd(pair[0])
			assert !app.exponent_input && app.scientific_status == ''
			assert calculator_numeric_value(app.calculator.display) >= 0 && calculator_numeric_value(app.calculator.display) < 1
			app.key_input('==')
			app.handle('calculator.memory.add')!
			app.handle('calculator.history.1')!
		}
		app.scientific_random_from_fd(pair[0])
		assert app.scientific_status == 'calculator.random.unavailable'
		app.handle('calculator.scientific.random')!
		assert app.scientific_status == ''
		for size in [ui2.rect(0, 0, 540, 430), ui2.rect(0, 0, 620, 566)]! {
			begin_frame_elements()
			tree := app.build(size)!
			mut encoded := []u8{cap: 65536}
			unsafe { encoded.flags |= .noslices }
			encode_app_element(tree, mut encoded)!
			mut reader := WireReader{ data: encoded }
			decoded := decode_app_element(mut reader, 0)!
			free_tree(decoded)
			free_tree(tree)
			unsafe { encoded.free() }
		}
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_calculator_random_complete_init_entropy_and_close_release_all_memory() {
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := new_calculator_app()
		app.handle('calculator.mode.scientific')!
		app.scientific_random_from_fd(-1)
		assert app.scientific_status == 'calculator.random.unavailable'
		app.handle('calculator.scientific.random')!
		assert app.scientific_status == ''
		app.key_input('7')
		assert app.calculator.display == '7'
		app.close_app()
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}

fn test_calculator_ee_root_editing_domains_history_memory_and_wire_release_owned_memory() {
	mut app := new_calculator_app()
	app.handle('calculator.mode.scientific')!
	for size in [ui2.rect(0, 0, 540, 430), ui2.rect(0, 0, 620, 566)]! {
		begin_frame_elements()
		free_tree(app.build(size)!)
	}
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.key_input('c1.25e-3')
		app.press('±')
		app.press('±')
		app.key_input('\x7f\x7f\x7fe-3+1=')
		app.handle('calculator.memory.add')!
		app.key_input('c27')
		app.handle('calculator.scientific.root')!
		app.key_input('9')
		app.handle('calculator.scientific.sqrt')!
		app.key_input('==')
		assert !app.calculator.has_error
		app.key_input('c')
		app.paste_input('-8')
		app.handle('calculator.scientific.root')!
		app.paste_input('-3')
		app.key_input('=')
		assert app.calculator.display == '-0.5'
		for invalid in ['1e', '1e-', '1e309']! {
			app.key_input('c')
			app.key_input(invalid)
			app.handle('calculator.scientific.sqrt')!
			assert app.calculator.has_error
		}
		app.key_input('c16')
		app.handle('calculator.scientific.root')!
		app.key_input('0=')
		assert app.calculator.has_error
		app.handle('calculator.memory.recall')!
		app.handle('calculator.history.0')!
		app.handle('calculator.mode.basic')!
		app.handle('calculator.scientific.ee')!
		app.handle('calculator.mode.programmer')!
		app.paste_input('18446744073709551615')
		app.handle('calculator.scientific.root')!
		assert app.integer.value == calculator_programmer_max
		app.handle('calculator.mode.scientific')!
		for size in [ui2.rect(0, 0, 540, 430), ui2.rect(0, 0, 620, 566)]! {
			begin_frame_elements()
			tree := app.build(size)!
			mut encoded := []u8{cap: 65536}
			unsafe { encoded.flags |= .noslices }
			encode_app_element(tree, mut encoded)!
			mut reader := WireReader{ data: encoded }
			decoded := decode_app_element(mut reader, 0)!
			free_tree(decoded)
			free_tree(tree)
			unsafe { encoded.free() }
		}
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_calculator_ee_root_complete_init_finite_boundary_resize_and_close_release_memory() {
	mut warm := new_calculator_app()
	warm.handle('calculator.mode.scientific')!
	for size in [ui2.rect(0, 0, 540, 430), ui2.rect(0, 0, 620, 566)]! {
		begin_frame_elements()
		free_tree(warm.build(size)!)
	}
	warm.close_app()
	unsafe { free(warm) }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := new_calculator_app()
		app.handle('calculator.mode.scientific')!
		app.key_input('1.7976931348623157e308+0=')
		app.handle('calculator.scientific.ee')!
		app.press('±')
		app.press('±')
		app.key_input('\x7f\x7f8')
		app.key_input('c27')
		app.handle('calculator.scientific.root')!
		app.key_input('3=')
		assert app.calculator.display == '3'
		for size in [ui2.rect(0, 0, 540, 430), ui2.rect(0, 0, 620, 566)]! {
			begin_frame_elements()
			free_tree(app.build(size)!)
		}
		app.close_app()
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}

fn test_calculator_interaction_and_history_release_owned_allocations() {
	mut app := new_calculator_app()
	begin_frame_elements()
	warm := app.build(ui2.rect(0, 0, 340, 510))!
	free_tree(warm)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.key_input('c1.25+2.5=')
		app.key_input('%')
		app.handle('calculator.memory.add')!
		app.handle('calculator.memory.recall')!
		app.key_input('c123\x7f')
		app.paste_input(' -42.25 ')
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 340, 510))!
		free_tree(tree)
	}
	app.close_app()
	live := C.vinix_heap_end()
	assert live == 0, 'calculator retained ${live} bytes after closing'
}

fn test_calculator_scientific_operations_modes_history_and_errors_release_owned_memory() {
	mut app := new_calculator_app()
	app.handle('calculator.mode.scientific')!
	app.key_input('30')
	app.handle('calculator.scientific.sin')!
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 620, 576))!)
	// The compact view uses a persistent frame pool; warm its slot before
	// measuring transient layouts, operations, and history strings.
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 340, 510))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.handle('calculator.angle.degrees')!
		for index, action in calculator_scientific_actions {
			app.key_input('c')
			app.paste_input(['9', '4', '-3', '30', '60', '45', '.5', '.5', '1', '1', '100', '0',
				'0', '0', '-2', '-8', '8', '1', '1', '1', '1', '2', '.5']![index])
			app.handle(action)!
		}
		app.key_input('c2+9')
		app.handle('calculator.scientific.sqrt')!
		app.key_input('==')
		app.handle('calculator.memory.add')!
		app.handle('calculator.memory.recall')!
		app.handle('calculator.history.0')!
		app.key_input('c')
		app.paste_input('1e308')
		app.handle('calculator.scientific.square')!
		assert app.calculator.has_error
		app.handle('calculator.scientific.pi')!
		app.handle('calculator.angle.radians')!
		app.key_input('/2=')
		app.handle('calculator.scientific.tan')!
		assert app.calculator.has_error
		for size in [ui2.rect(0, 0, 620, 576), ui2.rect(0, 0, 340, 510), ui2.rect(0, 0, 760, 620)]! {
			begin_frame_elements()
			free_tree(app.build(size)!)
		}
		app.key_input('\x13')
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 340, 540))!)
		app.key_input('\x13\x04')
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_calculator_scientific_init_resize_and_close_release_all_owned_memory() {
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := new_calculator_app()
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 340, 540))!)
		app.handle('calculator.mode.scientific')!
		app.handle('calculator.scientific.pi')!
		for size in [ui2.rect(0, 0, 620, 576), ui2.rect(0, 0, 760, 620)]! {
			begin_frame_elements()
			free_tree(app.build(size)!)
		}
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}

fn test_calculator_hyperbolic_boundaries_domains_wire_and_mode_cycles_release_owned_memory() {
	mut app := new_calculator_app()
	app.handle('calculator.mode.scientific')!
	for size in [ui2.rect(0, 0, 540, 430), ui2.rect(0, 0, 620, 566)]! {
		begin_frame_elements()
		free_tree(app.build(size)!)
	}
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for angle in ['calculator.angle.degrees', 'calculator.angle.radians']! {
			app.handle(angle)!
			for index, action in ['calculator.scientific.sinh', 'calculator.scientific.cosh',
				'calculator.scientific.tanh', 'calculator.scientific.asinh',
				'calculator.scientific.acosh', 'calculator.scientific.atanh']! {
				app.key_input('c')
				app.paste_input(['710', '-710', '-1e308', '-1e308', '1e308', '.999999999999999']![index])
				app.handle(action)!
				assert !app.calculator.has_error
			}
		}
		for index, action in ['calculator.scientific.sinh', 'calculator.scientific.cosh',
			'calculator.scientific.acosh', 'calculator.scientific.atanh']! {
			app.key_input('c')
			app.paste_input(['711', '-711', '.5', '1']![index])
			app.handle(action)!
			assert app.calculator.has_error
		}
		app.key_input('c1')
		app.handle('calculator.scientific.asinh')!
		app.handle('calculator.mode.basic')!
		app.handle('calculator.scientific.cosh')!
		app.handle('calculator.mode.programmer')!
		app.handle('calculator.scientific.sinh')!
		app.handle('calculator.mode.scientific')!
		app.handle('calculator.history.0')!
		app.key_input('+2=')
		for size in [ui2.rect(0, 0, 540, 430), ui2.rect(0, 0, 620, 566)]! {
			begin_frame_elements()
			tree := app.build(size)!
			mut encoded := []u8{cap: 65536}
			unsafe { encoded.flags |= .noslices }
			encode_app_element(tree, mut encoded)!
			mut reader := WireReader{ data: encoded }
			decoded := decode_app_element(mut reader, 0)!
			free_tree(decoded)
			free_tree(tree)
			unsafe { encoded.free() }
		}
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn calculator_programmer_memory_warm_frames(mut app CalculatorApp) {
	app.handle('calculator.mode.programmer') or { panic(err) }
	app.key_input('1+1=')
	for _ in 0 .. 24 { app.key_input('=') }
	for size in [ui2.rect(0, 0, 620, 576), ui2.rect(0, 0, 760, 640), ui2.rect(0, 0, 340, 510)]! {
		begin_frame_elements()
		free_tree(app.build(size) or { panic(err) })
	}
}

fn test_calculator_programmer_operations_all_bases_history_and_frames_release_owned_memory() {
	mut app := new_calculator_app()
	calculator_programmer_memory_warm_frames(mut app)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for action in calculator_programmer_base_actions {
			app.handle(action)!
			app.key_input('\x1b')
			app.paste_input('0xFFFFFFFFFFFFFFFF')
			app.handle('calculator.programmer.and')!
			app.paste_input('0xFF')
			app.handle('calculator.programmer.equals')!
			app.handle('calculator.programmer.not')!
			app.handle('calculator.programmer.shr')!
			app.paste_input('0x3F')
			app.handle('calculator.programmer.equals')!
			assert app.integer.value == 1
		}
		app.handle('calculator.programmer.base.dec')!
		app.key_input('\x1b7/0=')
		assert app.integer.has_error
		app.key_input('3+5==')
		app.handle('calculator.programmer.history.0')!
		for size in [ui2.rect(0, 0, 620, 576), ui2.rect(0, 0, 760, 640), ui2.rect(0, 0, 340, 510)]! {
			begin_frame_elements()
			free_tree(app.build(size)!)
		}
		app.key_input('\x10')
		app.key_input('c2+3=')
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 620, 576))!)
		app.key_input('\x10')
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_calculator_programmer_invalid_entry_domain_and_parse_paths_release_owned_memory() {
	mut app := new_calculator_app()
	calculator_programmer_memory_warm_frames(mut app)
	too_long := '1'.repeat(70)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.handle('calculator.programmer.base.dec')!
		app.key_input('\x1b42+')
		for value in ['-1', '1.5', '1e3', '1\n2', '2+3=', '0b2',
			'18446744073709551616', '0x10000000000000000', '数字']! {
			app.paste_input(value)
			assert app.integer.value == 42
		}
		app.paste_input(too_long)
		app.paste_input('0xFF')
		app.key_input('=')
		assert app.integer.value == 297
		app.key_input('\x1b1<64=')
		assert app.integer.has_error
		app.key_input('9')
		app.handle('calculator.programmer.base.hex')!
		app.key_input('ABC\x7f')
		app.handle('calculator.programmer.base.bin')!
		app.key_input('9')
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 620, 576))!)
	}
	app.close_app()
	assert C.vinix_heap_end() == 0
	unsafe { too_long.free() }
}

fn test_calculator_programmer_complete_init_mode_switch_resize_close_release_owned_memory() {
	mut warm := new_calculator_app()
	calculator_programmer_memory_warm_frames(mut warm)
	warm.close_app()
	unsafe { free(warm) }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := new_calculator_app()
		app.key_input('2+3=')
		app.handle('calculator.mode.programmer')!
		app.paste_input('18446744073709551615')
		app.key_input('+1=~')
		for size in [ui2.rect(0, 0, 620, 576), ui2.rect(0, 0, 760, 640), ui2.rect(0, 0, 340, 510)]! {
			begin_frame_elements()
			free_tree(app.build(size)!)
		}
		app.handle('calculator.mode.scientific')!
		assert app.calculator.display == '5'
		app.handle('calculator.scientific.sqrt')!
		app.key_input('\x10\x02')
		assert app.integer.value == calculator_programmer_max
		app.close_app()
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}

fn test_calculator_programmer_width_cycles_history_recall_wire_and_live_masking_release_memory() {
	mut app := new_calculator_app()
	calculator_programmer_memory_warm_frames(mut app)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for index, action in calculator_programmer_width_actions {
			app.handle('calculator.programmer.width.64')!
			app.handle('calculator.programmer.base.dec')!
			app.key_input('\x1b')
			app.paste_input('18446744073709551615')
			app.handle(action)!
			assert app.integer.value == [u64(255), 65535, 4294967295, calculator_programmer_max]![index]
			app.key_input('+1=~')
			assert app.integer.history.last().width == calculator_programmer_widths[index]
			app.handle('calculator.programmer.width.8')!
			app.handle('calculator.programmer.history.0')!
			assert app.integer.width == calculator_programmer_widths[index]
			assert app.integer.value == [u64(255), 65535, 4294967295, calculator_programmer_max]![index]
			for size in [ui2.rect(0, 0, 540, 560), ui2.rect(0, 0, 620, 576),
				ui2.rect(0, 0, 760, 640), ui2.rect(0, 0, 340, 400)]! {
				begin_frame_elements()
				tree := app.build(size)!
				mut encoded := []u8{cap: 65536}
				unsafe { encoded.flags |= .noslices }
				encode_app_element(tree, mut encoded)!
				mut reader := WireReader{ data: encoded }
				decoded := decode_app_element(mut reader, 0)!
				free_tree(decoded)
				free_tree(tree)
				unsafe { encoded.free() }
			}
		}
		app.handle('calculator.programmer.width.64')!
		app.key_input('\x1b300+300=')
		app.handle('calculator.programmer.width.8')!
		app.key_input('=')
		assert app.integer.value == 132 && app.integer.last_operand == 44
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_calculator_programmer_width_overflow_shift_errors_and_recovery_release_memory() {
	mut app := new_calculator_app()
	calculator_programmer_memory_warm_frames(mut app)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for index, action in calculator_programmer_width_actions {
			app.handle(action)!
			app.handle('calculator.programmer.base.dec')!
			app.key_input('\x1b42+')
			app.paste_input(['256', '65536', '4294967296', '18446744073709551616']![index])
			assert app.integer.value == 42 && app.integer.accumulator == 42
			assert app.integer.pending == .add && app.integer.status == 'calculator.programmer.error.range'
			app.paste_input('0x01')
			app.key_input('=')
			assert app.integer.value == 43
			app.key_input('\x1b1<')
			count := calculator_integer_text(u64(calculator_programmer_widths[index]), 10)
			app.paste_input(count)
			unsafe { count.free() }
			app.key_input('=')
			assert app.integer.has_error && app.integer.status == 'calculator.programmer.error.shift'
			app.handle('calculator.programmer.width.8')!
			assert app.integer.has_error
			app.key_input('3+5==')
			assert app.integer.value == 13 && app.integer.width == 8
			app.integer.set_width(7)
			assert app.integer.width == 8
		}
	}
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_calculator_programmer_width_init_mode_memory_resize_and_close_release_memory() {
	mut warm := new_calculator_app()
	calculator_programmer_memory_warm_frames(mut warm)
	warm.close_app()
	unsafe { free(warm) }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := new_calculator_app()
		app.key_input('2+3=')
		app.handle('calculator.memory.add')!
		app.handle('calculator.mode.programmer')!
		for action in calculator_programmer_width_actions {
			app.handle(action)!
			app.key_input('\x1b~')
			for size in [ui2.rect(0, 0, 620, 576), ui2.rect(0, 0, 340, 400)]! {
				begin_frame_elements()
				free_tree(app.build(size)!)
			}
		}
		app.handle('calculator.mode.basic')!
		assert app.calculator.display == '5' && app.memory == 5 && app.has_memory
		app.handle('calculator.mode.scientific')!
		app.handle('calculator.scientific.sqrt')!
		app.handle('calculator.mode.programmer')!
		app.handle('calculator.programmer.width.8')!
		app.handle('calculator.programmer.history.0')!
		assert app.integer.width == 64 && app.integer.value == calculator_programmer_max
		app.close_app()
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}

fn test_calculator_copy_native_requests_acknowledgements_frames_and_close_release_memory() {
	saved := app_compositor_features
	app_compositor_features = app_features
	defer { app_compositor_features = saved }
	mut warm := new_calculator_app()
	for mode in ['calculator.mode.basic', 'calculator.mode.scientific', 'calculator.mode.programmer']! {
		warm.handle(mode)!
		warm.handle('calculator.copy')!
		for size in [ui2.rect(0, 0, 620, 566), ui2.rect(0, 0, 340, 510), ui2.rect(0, 0, 340, 400)]! {
			begin_frame_elements()
			free_tree(warm.build(size)!)
		}
	}
	warm.close_app()
	unsafe { free(warm) }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut native := open_native_calculator()
		mut app := unsafe { &CalculatorApp(native) }
		for mode in ['calculator.mode.basic', 'calculator.mode.scientific', 'calculator.mode.programmer']! {
			app.handle(mode)!
			if app.programmer {
				app.handle('calculator.programmer.base.hex')!
				app.paste_input('0xFFFFFFFFFFFFFFFF')
			} else {
				app.key_input('c2+')
				app.paste_input('-12.500')
			}
			app.key_input('\x03')
			old_sequence := app.copy_client.sequence
			packet := native_app_text_copy_request(mut native)
			assert packet.len > text_copy_header_size
			app.handle('calculator.copy')!
			stale := text_copy_reply(old_sequence, true)
			native_app_receive_text_copy(mut native, editor_bytes_text(stale))
			assert app.copy_client.status_key() == 'clipboard.copy.pending'
			unsafe { stale.free() packet.free() }
			current := native_app_text_copy_request(mut native)
			ack := text_copy_reply(app.copy_client.sequence, false)
			native_app_receive_text_copy(mut native, editor_bytes_text(ack))
			assert app.copy_client.status_key() == 'clipboard.copy.failed'
			unsafe { current.free() ack.free() }
			app.handle('calculator.copy')!
			accepted := native_app_text_copy_request(mut native)
			ok := text_copy_reply(app.copy_client.sequence, true)
			native_app_receive_text_copy(mut native, editor_bytes_text(ok))
			assert app.copy_client.status_key() == 'clipboard.copy.copied'
			unsafe { accepted.free() ok.free() }
			for size in [ui2.rect(0, 0, 620, 566), ui2.rect(0, 0, 340, 510), ui2.rect(0, 0, 340, 400)]! {
				begin_frame_elements()
				free_tree(app.build(size)!)
			}
			app.key_input('=')
			if app.programmer {
				app.key_input('\x1b7/0=\x03')
			} else {
				app.key_input('c1/0=\x03')
			}
			assert native_app_text_copy_request(mut native).len == 0
			assert app.copy_client.status_key() == 'clipboard.copy.empty'
		}
		app.handle('calculator.mode.basic')!
		app.key_input('c9\x03')
		// Closing an undispatched request owns and releases its packet too.
		app.close_app()
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}
