module g17power

import encoding.hex
import os
import math
import traceanalysis as j

struct FixtureCode {
	address u64
mut:
	bytes []u8
}

struct FixtureImage {
mut:
	bytes   []u8
	symbols map[string]u64
	codes   map[string]FixtureCode
	slots   map[int]u64
}

fn (source FixtureImage) data() []u8 { return source.bytes }

fn (source FixtureImage) symbols() !map[string]u64 { return source.symbols }

fn (source FixtureImage) vtable(_ string, slot int) !u64 {
	return source.slots[slot] or { return error('missing fixture vtable slot') }
}

fn (source FixtureImage) code(name string) !(u64, []u8) {
	code := source.codes[name] or { return error('missing fixture code') }
	return code.address, code.bytes
}

fn (_ FixtureImage) file_offset(address u64) !int { return int(address) }

fn sparse_fixture(value j.Value) []u8 {
	object := value.as_map()
	mut result := []u8{len: j.value(object, 'bytes').int()}
	for entry in j.value(object, 'chunks').arr() {
		pair := entry.arr()
		offset := pair[0].int()
		bytes := hex.decode(j.string_value(pair[1])) or { panic(err) }
		for index, byte in bytes { result[offset + index] = byte }
	}
	return result
}

fn linear_fixture() (FixtureImage, []u8) {
	object := j.object(j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/linear-recovery.json')) or { panic(err) }) or { panic(err) }) or { panic(err) }
	mut symbols := map[string]u64{}
	for name, address in j.value(object, 'symbols').as_map() { symbols[name] = address.u64() }
	mut codes := map[string]FixtureCode{}
	for name, raw in j.value(object, 'codes').as_map() {
		code := raw.as_map()
		codes[name] = FixtureCode{j.value(code, 'address').u64(), sparse_fixture(j.value(code, 'code'))}
	}
	mut slots := map[int]u64{}
	for key, address in j.value(object, 'slots').as_map() { slots[key.int()] = address.u64() }
	return FixtureImage{sparse_fixture(j.value(object, 'image')), symbols, codes, slots}, sparse_fixture(j.value(object, 'power_code'))
}

fn test_recovers_independent_linear_power_transfer_fixture() {
	source, code := linear_fixture()
	result := recover_with_source(source, code) or { panic(err) }
	assert j.value(result, 'die_dependent') == j.Value(true)
	tables := j.value(result, 'tables').arr()
	primary := tables[0].as_map()
	afr := tables[1].as_map()
	assert j.value(primary, 'offset').u64() == 0x18c8
	assert j.value(afr, 'offset').u64() == 0x1948
	assert j.value(primary, 'matrix_source_offset').u64() == 0x1c630
	assert j.value(primary, 'matrix_row_bytes').u64() == 0x40
	assert j.value(primary, 'matrix_column_count_offset').u64() == 0x4e4
	assert floating(j.value(primary, 'clamp')) or { panic(err) } == 48500.0
	assert j.value(afr, 'matrix_source_offset').u64() == 0x1ca30
	assert j.value(afr, 'matrix_row_bytes').u64() == 8
	assert j.value(afr, 'matrix_column_count_offset').u64() == 0x4ec
	assert j.value(afr, 'clamp').arr().map(floating(it) or { panic(err) }) == [
		38600.0,
		24800.0,
	]
	assert j.value(result, 'maximum_state_value').u64() == 100
	chip := j.value(result, 'chip_leakage').as_map()
	assert j.value(chip, 'fuse_physical_address').u64() == 0x2388374000
	assert j.value(chip, 'fuse_bytes').u64() == 0x1000
	assert j.value(chip, 'fuse_word_offsets').arr().map(it.u64()) == [u64(0x198), 0x19c, 0x1a0]
	assert j.value(chip, 'core_selectors').arr().map(it.int()) == [0, 1, 2, 3, 0, 1, 2, 3]
	assert j.value(chip, 'core_descriptors').arr().map(j.value(it.as_map(), 'primary_shift').int()) == [
		8,
		22,
		22,
		8,
	]
	field := j.value(chip, 'group_field').as_map()
	for name, expected in {
		'low_word_offset':  0x19c
		'high_word_offset': 0x1a0
		'right_shift':      25
		'width':            12
		'multiplier':       2
	} {
		assert j.value(field, name).int() == expected
	}
	model := j.value(result, 'leakage_model').as_map()
	assert floating(j.value(model, 'temperature')) or { panic(err) } == 110.0
	assert j.value(model, 'input_linear') == j.Value(true)
	assert j.value(model, 'pow_terms').int() == 4
	assert j.string_value(j.value(model, 'factor_formula')).contains('max(V-1.06,0)')
	assert j.value(j.value(model, 'vdd_gpu').as_map(), 'buckets').int() == 2
	assert records(j.value(j.value(model, 'vdd_gpu').as_map(), 'default_records')) or { panic(err) }[0] == [
		1000.0,
		1.0,
		1.0,
		1.0,
		1.0,
		1.0,
		1.0,
		1.0,
		1.0,
		1.0,
		1.0,
	]
	assert j.value(j.value(model, 'afr').as_map(), 'default_thresholds').arr().map(floating(it) or { panic(err) }) == [
		1000.0,
		-1.0,
	]
}

fn test_rejects_independent_linear_power_stub_and_normalization_changes() {
	mut source, code := linear_fixture()
	source.slots[0xfd0] = 0x7f0000
	if _ := recover_with_source(source, code) {
		assert false
	}
	source, _ = linear_fixture()
	mut function := source.codes[linear_provider]
	function.bytes = function.bytes.clone()
	function.bytes[0x2f0] = 0x8f
	source.codes[linear_provider] = function
	if _ := recover_with_source(source, code) {
		assert false
	}
}

fn test_recovery_rejects_changed_fuse_descriptors_selectors_and_catch_all() {
	for position in [0x6000, 0x6020 + 8, 0x2000 + 0x58, 0x3000 + 0x58] {
		mut source, code := linear_fixture()
		if position >= 0x6000 {
			source.bytes[position] ^= 1
		} else {
			bits := math.f64_bits(1.0)
			for index in 0 .. 8 { source.bytes[position + index] = u8(bits >> (index * 8)) }
		}
		if _ := recover_with_source(source, code) {
			assert false
		}
	}
}

fn test_recovery_rejects_every_changed_instruction_proof() {
	providers := {
		'G17 linear power-transfer call':                 ''
		'G17 inlined AFR linear power-transfer producer': ''
		'G17 linear power-transfer normalisation':        linear_provider
		'G17 maximum-performance power matrix':           main_provider
		'G17 CS maximum-performance power matrix':        afr_provider
		'G17 chip-leakage fuse decode':                   chip_leakage_provider
	}
	mut checked := 0
	for label, provider in providers {
		for offset, _ in proof_words(label) {
			mut source, code := linear_fixture()
			if provider == '' {
				code[offset] ^= 1
			} else {
				mut function := source.codes[provider]
				function.bytes[offset] ^= 1
				source.codes[provider] = function
			}
			if _ := recover_with_source(source, code) {
				assert false
			}
			checked++
		}
	}
	assert checked == 89
}

fn test_recovery_preserves_missing_initializer_key_error() {
	mut source, code := linear_fixture()
	key := '__ZN14AGXArmFirmware27initPowerAndPerformanceDataEv'
	source.symbols.delete(key)
	if _ := recover_with_source(source, code) {
		assert false
	} else {
		assert err.msg() == 'KeyError: ' + key
	}
}
