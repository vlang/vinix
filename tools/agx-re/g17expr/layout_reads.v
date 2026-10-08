module g17expr

import g17decode as arm
import math.big
import traceanalysis as j

struct LayoutOrigin {
	offset  big.Integer
	indexed bool
}

struct LayoutRead {
	offset  big.Integer
	width   int
	indexed bool
}

fn layout_read_add(mut reads []LayoutRead, offset big.Integer, width int, indexed bool) {
	item := LayoutRead{offset, width, indexed}
	if item !in reads { reads << item }
}

fn firmware_config_reads(firmware []u8) !j.Value {
	_, end := layout_magic_span(firmware, 'firmware')!
	code := firmware[end..int_min(firmware.len, end + 0x800)]
	mut origins := map[int]LayoutOrigin{}
	mut constants := map[int]big.Integer{}
	mut reads := []LayoutRead{}
	for instruction in arm.words(code) {
		if move := fields('decode_move_wide', instruction.word, big.zero_int) {
			if j.string_value(move[0]) == 'movz' {
				constants[move[1].int()] = (arm.integer(move[2])!).left_shift(u32(move[3].int()))
				origins.delete(move[1].int())
				continue
			}
		}
		if move := fields('decode_movz_w', instruction.word, big.zero_int) {
			constants[move[0].int()] = arm.integer(move[1])!
			origins.delete(move[0].int())
			continue
		}
		if load := fields('decode_load_unsigned', instruction.word, big.zero_int) {
			if base := origins[load[1].int()] {
				layout_read_add(mut reads, base.offset + arm.integer(load[2])!, load[3].int(), base.indexed)
			}
			if load[3].int() == 8 && load[1].int() == 19 && load[2].int() == 0 {
				origins[load[0].int()] = LayoutOrigin{big.zero_int, false}
			} else {
				origins.delete(load[0].int())
			}
			constants.delete(load[0].int())
			continue
		}
		if load := fields('decode_load_register', instruction.word, big.zero_int) {
			if base := origins[load[1].int()] {
				if offset := constants[load[2].int()] {
					layout_read_add(mut reads, base.offset + offset, load[3].int(), base.indexed)
				}
			}
			origins.delete(load[0].int())
			constants.delete(load[0].int())
			continue
		}
		if add := fields('decode_add_immediate', instruction.word, big.zero_int) {
			if source := origins[add[1].int()] {
				origins[add[0].int()] = LayoutOrigin{source.offset + arm.integer(add[2])!, source.indexed}
			} else {
				origins.delete(add[0].int())
			}
			if source := constants[add[1].int()] {
				constants[add[0].int()] = source + arm.integer(add[2])!
			} else {
				constants.delete(add[0].int())
			}
			continue
		}
		if add := fields('decode_add_register', instruction.word, big.zero_int) {
			if source := origins[add[1].int()] {
				if constant := constants[add[2].int()] {
					origins[add[0].int()] = LayoutOrigin{source.offset + (constant.left_shift(u32(add[3].int()))), source.indexed}
				} else {
					origins[add[0].int()] = LayoutOrigin{source.offset, true}
				}
			} else {
				origins.delete(add[0].int())
			}
			constants.delete(add[0].int())
			continue
		}
		if pair := fields('decode_pair_q', instruction.word, big.zero_int) {
			if j.string_value(pair[0]) == 'load' {
				if base := origins[pair[3].int()] {
					layout_read_add(mut reads, base.offset + arm.integer(pair[4])!, 32, base.indexed)
				}
			}
		}
	}
	required := layout_required_reads()
	missing := required.filter(it !in reads)
	if missing.len > 0 {
		return error('incomplete firmware hardware-config read map: ' + layout_missing_reads(missing, reads.len))
	}
	if !contains_words(code, [u32(0xf9400268), 0x52837209, 0x911442c0, 0x8b090101, 0x52802902]) {
		return error('firmware 0x1b90 configuration copy was not found')
	}
	reads.sort_with_compare(fn (a &LayoutRead, b &LayoutRead) int {
		if a.offset != b.offset { return if a.offset < b.offset { -1 } else { 1 } }
		if a.width != b.width { return a.width - b.width }
		return int(a.indexed) - int(b.indexed)
	})
	return expr({
		'firmware_direct_reads': j.Value(reads.map(expr({
			'offset':  scalar(it.offset)
			'bytes':   j.Value(it.width)
			'indexed': j.Value(it.indexed)
		})))
		'firmware_bulk_reads':   j.Value([
			expr({
				'offset': j.Value(0x19c8)
				'bytes':  j.Value(0x80)
			}),
			expr({
				'offset': j.Value(0x1b90)
				'bytes':  j.Value(0x148)
			}),
		])
	})
}

fn layout_required_reads() []LayoutRead {
	// Order of the original fixed integer-tuple set, before difference insertion.
	return [LayoutRead{big.integer_from_int(0x8f0), 8, false},
		LayoutRead{big.integer_from_int(0xfc8), 4, true},
		LayoutRead{big.integer_from_int(0x19c8), 32, false},
		LayoutRead{big.integer_from_int(0x1408), 4, true},
		LayoutRead{big.integer_from_int(0x2610), 8, false},
		LayoutRead{big.integer_from_int(0xe90), 16, false},
		LayoutRead{big.integer_from_int(0x1008), 4, true},
		LayoutRead{big.integer_from_int(0x26f9), 1, false}]
}

fn layout_tuple_hash(item LayoutRead) u64 {
	mut accumulator := u64(2870177450012600261)
	for lane in [item.offset.str().u64(), u64(item.width), u64(item.indexed)] {
		accumulator += lane * u64(14029467366897019727)
		accumulator = (accumulator << 31) | (accumulator >> 33)
		accumulator *= u64(11400714785074694791)
	}
	accumulator += u64(3) ^ (u64(2870177450012600261) ^ u64(3527539))
	return if accumulator == ~u64(0) { u64(1546275796) } else { accumulator }
}

fn layout_set_insert(mut table []int, index int, hash u64) {
	mask := table.len - 1
	mut position := int(hash & u64(mask))
	mut perturb := hash
	for {
		probes := if position + 9 <= mask { 9 } else { 0 }
		for step in 0 .. probes + 1 {
			if table[position + step] < 0 {
				table[position + step] = index
				return
			}
		}
		perturb >>= 5
		position = int((u64(position) * 5 + 1 + perturb) & u64(mask))
	}
}

fn layout_missing_reads(items []LayoutRead, read_count int) string {
	mut ordered := items.clone()
	if read_count >= 2 {
		mut table := []int{len: 8, init: -1}
		for index, item in items {
			layout_set_insert(mut table, index, layout_tuple_hash(item))
			if (index + 1) * 5 >= (table.len - 1) * 3 {
				old := table.clone()
				table = []int{len: 32, init: -1}
				for entry in old {
					if entry >= 0 {
						layout_set_insert(mut table, entry, layout_tuple_hash(items[entry]))
					}
				}
			}
		}
		ordered = []LayoutRead{}
		for entry in table { if entry >= 0 { ordered << items[entry] } }
	}
	return '{' + ordered.map('(' + it.offset.str() + ', ' + it.width.str() + ', ' + if it.indexed {
		'True'
	} else {
		'False'
	} + ')').join(', ') + '}'
}
