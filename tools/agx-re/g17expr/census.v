module g17expr

import g17decode as arm
import g17power as power
import imageextract as macho
import json2
import math
import math.big
import traceanalysis as j

struct CensusRegister {
mut:
	kind   string
	value  big.Integer
	origin string
}

struct CensusOwner {
	address big.Integer
	name    string
}

struct CensusWriter {
	target      j.Value
	name        string
	destination int
	length      int
}

fn census_type(value j.Value) string {
	return match value {
		string { 'str' }
		[]j.Value { 'list' }
		map[string]j.Value { 'dict' }
		else { runtime_allocation_type(value) }
	}
}

fn census_mask(value big.Integer) u64 {
	modulus := big.integer_from_u64(~u64(0)) + big.one_int
	mut reduced := value % modulus
	if reduced.signum < 0 { reduced += modulus }
	bytes, _ := reduced.bytes()
	mut result := u64(0)
	for byte in bytes { result = (result << 8) | u64(byte) }
	return result
}

fn census_pointer(state map[int]CensusRegister, register int) CensusRegister {
	if register == 31 { return CensusRegister{ kind: 'stack' } }
	return state[register] or { CensusRegister{'offset', big.zero_int, 'unknown'} }
}

fn census_back(mut state map[int]CensusRegister, word u32) {
	if back := census_writeback(word) {
		if back[0] != 31 {
			origin := census_pointer(state, back[0])
			if origin.kind == 'offset' {
				state[back[0]] = CensusRegister{'offset', origin.value + big.integer_from_int(back[1]), origin.origin}
			}
		}
	}
}

fn census_bound(position big.Integer, limit j.Value, lower bool, inclusive bool, subtract int) !bool {
	if census_type(limit) == 'float' {
		text := j.encode(limit, false)
		value := unsafe { C.strtod(&char(text.str), nil) } - f64(subtract)
		if math.is_nan(value) { return false }
		if math.is_inf(value, 0) { return if lower { value < 0 } else { value > 0 } }
		whole := power.decimal_integer(j.Value(j.Number{'${value:.17g}'}))!
		if lower {
			return whole < position || (whole == position && (if inclusive {
				math.fmod(value, 1) <= 0
			} else {
				math.fmod(value, 1) < 0
			}))
		}
		return position < whole || (position == whole && math.fmod(value, 1) > 0)
	}
	if census_type(limit) !in ['int', 'bool'] {
		kind := census_type(limit)
		return error(if lower {
			"TypeError: '" + if inclusive { '<=' } else { '<' } + "' not supported between instances of '" + kind + "' and 'int'"
		} else {
			"TypeError: '<' not supported between instances of 'int' and '" + kind + "'"
		})
	}
	value := arm.integer(limit)! - big.integer_from_int(subtract)
	return if lower {
		if inclusive { value <= position } else { value < position }
	} else {
		position < value
	}
}

fn census_overlaps(start big.Integer, length big.Integer, low j.Value, high j.Value) !bool {
	return census_bound(start, high, false, false, 0)! && census_bound(start + length, low, true, false, 0)!
}

fn census_near(start big.Integer, low j.Value, high j.Value) !bool {
	if census_type(low) !in ['int', 'bool', 'float'] {
		return error("TypeError: unsupported operand type(s) for -: '" + census_type(low) + "' and 'int'")
	}
	return census_bound(start, low, true, true, 256)! && census_bound(start, high, false, false, 0)!
}

fn census_site(owner CensusOwner, address big.Integer, word u32, kind string, extra map[string]j.Value) j.Value {
	mut result := {
		'symbol': j.Value(owner.name)
		'offset': scalar(address - owner.address)
		'word':   j.Value(word)
		'kind':   j.Value(kind)
	}
	for key, value in extra { result[key] = value }
	return expr(result)
}

fn census_codes(code []u8, code_address big.Integer, ordered []CensusOwner, low j.Value, high j.Value, writers []CensusWriter) !j.Value {
	mut stores := []j.Value{}
	mut globals := []j.Value{}
	mut routines := []j.Value{}
	mut escapes := []j.Value{}
	mut sites := []j.Value{}
	mut indexed_count := 0
	mut routine_count := 0
	mut owner_index := -1
	mut state := map[int]CensusRegister{}
	for instruction in arm.words(code) {
		word := instruction.word
		address := code_address + big.integer_from_int(instruction.offset)
		mut advanced := false
		for owner_index + 1 < ordered.len && ordered[owner_index + 1].address <= address {
			owner_index++
			advanced = true
		}
		if advanced {
			state = map[int]CensusRegister{}
			for argument in 0 .. 8 {
				state[argument] = CensusRegister{'offset', big.zero_int, 'arg' + argument.str()}
			}
		}
		owner := if owner_index >= 0 { ordered[owner_index] } else { CensusOwner{code_address, ''} }
		if store := census_store(word) {
			effective := big.integer_from_int(if store.form == 'post' { 0 } else { store.immediate })
			width := big.integer_from_int(store.width)
			origin := census_pointer(state, store.base)
			if origin.kind in ['absolute', 'constant'] {
				if census_overlaps(effective, width, low, high)! {
					globals << census_site(owner, address, word, 'global', {
						'bytes': j.Value(store.width)
					})
				}
			} else if origin.kind == 'offset' {
				for derived in [true, false] {
					if derived && origin.value == big.zero_int { continue }
					start := if derived { origin.value + effective } else { effective }
					if census_overlaps(start, width, low, high)! {
						stores << census_site(owner, address, word, 'store', {
							'member':  scalar(start)
							'bytes':   j.Value(store.width)
							'origin':  j.Value(if derived || origin.value == big.zero_int {
								origin.origin
							} else {
								'unknown'
							})
							'derived': j.Value(derived)
						})
						break
					}
				}
			}
			census_back(mut state, word)
			for register in census_written_registers(word) { state.delete(register) }
			continue
		}
		if indexed := census_register_store(word) {
			origin := census_pointer(state, indexed[0])
			known := state[indexed[1]] or { CensusRegister{} }
			if origin.kind == 'offset' && known.kind == 'constant' {
				start := origin.value + known.value.left_shift(u32(indexed[2]))
				if census_overlaps(start, big.integer_from_int(indexed[3]), low, high)! {
					stores << census_site(owner, address, word, 'store', {
						'member':  scalar(start)
						'bytes':   j.Value(indexed[3])
						'origin':  j.Value(origin.origin)
						'derived': j.Value(true)
					})
				}
			} else if origin.kind == 'offset' && origin.value != big.zero_int {
				if census_near(origin.value, low, high)! {
					stores << census_site(owner, address, word, 'indexed_store', {
						'member':  scalar(origin.value)
						'bytes':   j.Value(indexed[3])
						'origin':  j.Value(origin.origin)
						'derived': j.Value(true)
					})
				}
			} else if origin.kind == 'offset' {
				indexed_count++
				sites << census_site(owner, address, word, 'indexed_store', {
					'origin': j.Value(origin.origin)
					'index':  j.Value(indexed[1])
				})
			}
			continue
		}
		if census_is_call(word) {
			mut target := j.Value(json2.null)
			if found := branch_target('decode_bl_target', Instruction{ offset: address, word: word }) {
				target = scalar(found)
			}
			mut writer_index := -1
			for index, writer in writers {
				if event_values_equal(writer.target, target) {
					writer_index = index
				}
			}
			if writer_index >= 0 {
				writer := writers[writer_index]
				origin := census_pointer(state, writer.destination)
				count := state[writer.length] or { CensusRegister{} }
				zero := state[1] or { CensusRegister{} }
				clears := writer.name in ['_bzero', '___bzero'] || (writer.name == '_memset' && zero.kind == 'constant' && zero.value == big.zero_int)
				if origin.kind == 'offset' {
					mut amount := j.Value(json2.null)
					mut hit := false
					if count.kind == 'constant' {
						hit = census_overlaps(origin.value, count.value, low, high)!
						amount = scalar(count.value)
					} else if origin.value != big.zero_int && census_bound(origin.value, high, false, false, 0)! {
						hit = true
					} else {
						routine_count++
						sites << census_site(owner, address, word, 'memory_routine', {
							'routine': j.Value(writer.name)
							'origin':  j.Value(origin.origin)
						})
					}
					if hit {
						routines << census_site(owner, address, word, 'memory_routine', {
							'routine':     j.Value(writer.name)
							'member':      scalar(origin.value)
							'bytes':       amount
							'origin':      j.Value(origin.origin)
							'clears_only': j.Value(clears)
						})
					}
				}
			} else {
				for argument in 0 .. 8 {
					origin := state[argument] or { continue }
					if origin.kind == 'offset' && origin.value != big.zero_int && census_near(origin.value, low, high)! {
						escapes << census_site(owner, address, word, 'escape', {
							'member':   scalar(origin.value)
							'argument': j.Value(argument)
							'origin':   j.Value(origin.origin)
							'target':   target
						})
					}
				}
			}
			for register in 0 .. 19 { state.delete(register) }
			state.delete(30)
			continue
		}
		written := census_written_registers(word)
		census_back(mut state, word)
		if written.len == 0 { continue }
		destination := written[0]
		mut update := CensusRegister{}
		if _ := fields('decode_adrp', word, address) {
			update.kind = 'absolute'
		} else if word & 0x9f000000 == 0x10000000 {
			update.kind = 'absolute'
		} else if word & 0xff000000 in [u32(0x91000000), 0xd1000000] {
			origin := census_pointer(state, int((word >> 5) & 31))
			mut amount := int((word >> 10) & 4095) << if word & 0x00400000 != 0 { 12 } else { 0 }
			if word & 0x40000000 != 0 { amount = -amount }
			update = origin
			if origin.kind == 'offset' {
				update = CensusRegister{'offset', origin.value + big.integer_from_int(amount), origin.origin}
			} else if origin.kind == 'constant' {
				update = CensusRegister{ kind: 'constant', value: big.integer_from_u64(census_mask(origin.value + big.integer_from_int(amount))) }
			}
		} else if word & 0xffe0ffe0 == 0xaa0003e0 {
			update = state[int((word >> 16) & 31)] or { CensusRegister{'offset', big.zero_int, 'unknown'} }
		} else if word & 0xff200000 == 0x8b000000 || word & 0xffe00000 == 0x8b200000 {
			first := census_pointer(state, int((word >> 5) & 31))
			other := state[int((word >> 16) & 31)] or { CensusRegister{} }
			kind := if word & 0xff200000 == 0x8b000000 { (word >> 22) & 3 } else { u32(0) }
			shift := if word & 0xff200000 == 0x8b000000 {
				(word >> 10) & 63
			} else {
				(word >> 10) & 7
			}
			if other.kind == 'constant' && kind == 0 && first.kind == 'offset' {
				update = CensusRegister{'offset', first.value + big.integer_from_u64(census_mask(other.value.left_shift(shift))), first.origin}
			}
		} else if move := fields('decode_move_wide', word, big.zero_int) {
			kind := j.string_value(move[0])
			register := move[1].int()
			shift := u32(move[3].int())
			value := move[2].u64() << shift
			if kind == 'movz' {
				update = CensusRegister{ kind: 'constant', value: big.integer_from_u64(value) }
			} else if kind == 'movn' {
				update = CensusRegister{ kind: 'constant', value: big.integer_from_u64(~value) }
			} else if prior := state[register] {
				if prior.kind == 'constant' {
					update = CensusRegister{ kind: 'constant', value: big.integer_from_u64((census_mask(prior.value) & ~(u64(0xffff) << shift)) | value) }
				}
			}
		} else if move := fields('decode_movz_w', word, big.zero_int) {
			update = CensusRegister{ kind: 'constant', value: arm.integer(move[1])! }
		} else if move := fields('decode_movk_w', word, big.zero_int) {
			if prior := state[move[0].int()] {
				if prior.kind == 'constant' {
					shift := u32(move[2].int())
					update = CensusRegister{ kind: 'constant', value: big.integer_from_u64((census_mask(prior.value) & 0xffffffff & ~(u64(0xffff) << shift)) | (move[1].u64() << shift)) }
				}
			}
		} else if word & 0xffe0ffe0 == 0x2a0003e0 {
			if prior := state[int((word >> 16) & 31)] {
				if prior.kind == 'constant' {
					update = CensusRegister{ kind: 'constant', value: big.integer_from_u64(census_mask(prior.value) & 0xffffffff) }
				}
			}
		} else if word == 0x2a1f03e0 | u32(destination) || word == 0xaa1f03e0 | u32(destination) {
			update = CensusRegister{ kind: 'constant', value: big.zero_int }
		}
		for register in written { state.delete(register) }
		if update.kind != '' && destination != 31 { state[destination] = update }
	}
	return expr({
		'stores':          j.Value(stores)
		'global_stores':   j.Value(globals)
		'memory_routines': j.Value(routines)
		'escapes':         j.Value(escapes)
		'unbounded_sites': j.Value(sites)
		'unbounded':       j.Value([expr({
			'register_indexed_stores':   j.Value(indexed_count)
			'untracked_memory_routines': j.Value(routine_count)
		})])
	})
}

fn census_image(image CommandImage, low j.Value, high j.Value, kernel_symbols map[string]j.Value) !j.Value {
	symbols := image.symbols()!
	mut ordered := []CensusOwner{}
	for name, address in symbols { ordered << CensusOwner{address, name} }
	ordered.sort_with_compare(fn (a &CensusOwner, b &CensusOwner) int {
		if a.address != b.address { return if a.address < b.address { -1 } else { 1 } }
		return if a.name == b.name {
			0
		} else if a.name < b.name {
			-1
		} else {
			1
		}
	})
	mut writers := []CensusWriter{}
	for name, arguments in {
		'_memcpy':  [0, 2]
		'_memmove': [0, 2]
		'_memset':  [0, 2]
		'_bzero':   [0, 1]
		'___bzero': [0, 1]
	} {
		if target := kernel_symbols[name] {
			writers << CensusWriter{target, name, arguments[0], arguments[1]}
		}
	}
	for command in macho.load_commands(image.bytes, 0)! {
		if command.command != macho.lc_segment_64 { continue }
		segment := macho.parse_segment(image.bytes, command)!
		if segment.name != '__TEXT_EXEC' { continue }
		start := big.integer_from_u64(segment.file_offset)
		begin := string_offset(image.bytes, start)
		end := string_offset(image.bytes, start + big.integer_from_u64(segment.file_size))
		return census_codes(if begin < end { image.bytes[begin..end] } else { []u8{} }, big.integer_from_u64(segment.virtual_address), ordered, low, high, writers)
	}
	return error('Mach-O has no __TEXT_EXEC segment')
}

fn census_query(data []u8, operation string, request map[string]j.Value) !j.Value {
	if 'census_options_text' in request {
		return census_query(data, operation, power.decode_device_json(text(request, 'census_options_text'))!.as_map())
	}
	if operation == 'census_g17_member_writes' {
		return census_image(command_image(data, request, 'image')!, at(request, 'low'), at(request, 'high'), at(request, 'kernel_symbols').as_map())
	}
	code := runtime_bytes(request, 'code')!
	if code.len < 4 {
		return census_codes(code, big.zero_int, []CensusOwner{}, at(request, 'low'), at(request, 'high'), []CensusWriter{})
	}
	mut ordered := []CensusOwner{}
	for value in at(request, 'ordered').arr() {
		row := value.arr()
		ordered << CensusOwner{arm.integer(row[0])!, j.string_value(row[1])}
	}
	mut writers := []CensusWriter{}
	for pair in at(request, 'memory_writer_pairs').arr() {
		row := pair.arr()
		values := row[1].arr()
		arguments := values[1].arr()
		writers << CensusWriter{row[0], j.string_value(values[0]), arguments[0].int(), arguments[1].int()}
	}
	for target, value in at(request, 'memory_writers').as_map() {
		values := value.arr()
		arguments := values[1].arr()
		writers << CensusWriter{j.Value(j.Number{target}), j.string_value(values[0]), arguments[0].int(), arguments[1].int()}
	}
	return census_codes(code, arm.integer(at(request, 'code_address'))!, ordered, at(request, 'low'), at(request, 'high'), writers)
}
