module g17expr

import os
import encoding.hex
import traceanalysis as j
import json2

fn census_fixture_row(row map[string]j.Value) {
	request := at(row, 'request').as_map()
	before := j.encode(expr(request), false)
	data := hex.decode(text(request, 'image')) or { []u8{} }
	old := data.clone()
	result := query(data, text(request, 'operation'), request) or {
		assert 'error' in row
		kind := text(row, 'exception')
		prefix := if kind in ['TypeError', 'IndexError', 'OverflowError'] {
			kind + ': '
		} else if kind == 'error' {
			'struct.error: '
		} else {
			''
		}
		assert err.msg() == prefix + text(row, 'error')
		assert j.encode(expr(request), false) == before
		assert data == old
		return
	}
	assert 'result' in row
	assert j.decode(j.encode(result, false)) or { panic(err) } == at(row, 'result')
	assert j.encode(expr(request), false) == before
	assert data == old
}

fn test_census_finds_direct_derived_and_escaping_member_writes() {
	fixture := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/original-census.json')) or { panic(err) }) or { panic(err) }
	for row in fixture.arr() { census_fixture_row(row.as_map()) }
}

fn test_census_width_bounds_and_confident_decoder_masks() {
	fixture := (j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/census-boundaries.json')) or { panic(err) }) or { panic(err) }).as_map()
	for row in at(fixture, 'controls').arr() { census_fixture_row(row.as_map()) }
	for item in at(fixture, 'decoders').arr() {
		row := item.as_map()
		word := u32(at(row, 'word').u64())
		mut store := j.Value(json2.null)
		if found := census_store(word) {
			store = j.Value([j.Value(found.base), j.Value(found.immediate), j.Value(found.width),
				j.Value(found.form)])
		}
		assert (j.decode(j.encode(store, false)) or {panic(err)}) == at(row, 'store'), word.hex()
		mut indexed := j.Value(json2.null)
		if found := census_register_store(word) { indexed = j.Value(found.map(j.Value(it))) }
		assert (j.decode(j.encode(indexed, false)) or {panic(err)}) == at(row, 'indexed'), word.hex()
		assert (j.decode(j.encode(j.Value(census_written_registers(word).map(j.Value(it))), false)) or {panic(err)}) == at(row, 'written'), word.hex()
		assert census_is_call(word) == (at(row, 'call') == j.Value(true))
		mut back := j.Value(json2.null)
		if found := census_writeback(word) { back = j.Value(found.map(j.Value(it))) }
		assert (j.decode(j.encode(back, false)) or {panic(err)}) == at(row, 'back'), word.hex()
	}
}
