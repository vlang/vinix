module g17expr

import os
import encoding.hex
import traceanalysis as j
import g17decode as arm
import crypto.sha256

fn layout_fixture_check(row map[string]j.Value) {
	request := at(row, 'request').as_map()
	before := j.encode(expr(request), false)
	data := hex.decode(if 'image' in request {
		text(request, 'image')
	} else if 'driver' in request {
		text(request, 'driver')
	} else {
		''
	}) or { panic(err) }
	original := data.clone()
	result := query(data, text(request, 'operation'), request) or {
		assert 'error' in row
		kind := text(row, 'exception')
		expected := text(row, 'error')
		native := if kind == 'KeyError' {
			'KeyError: ' + expected[1..expected.len - 1]
		} else if kind in ['TypeError', 'IndexError', 'OverflowError'] {
			kind + ': ' + expected
		} else if kind == 'error' {
			'struct.error: ' + expected
		} else {
			expected
		}
		assert err.msg() == native
		assert j.encode(expr(request), false) == before
		assert data == original
		return
	}
	assert 'result' in row
	assert j.decode(j.encode(result, false)) or { panic(err) } == at(row, 'result')
	assert j.encode(expr(request), false) == before
	assert data == original
}

fn verify_original_layout(name string) {
	fixture := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/original-layout.json')) or { panic(err) }) or { panic(err) }
	for row in at(fixture.as_map(), name).arr() { layout_fixture_check(row.as_map()) }
}

fn test_recovers_firmware_root_pointer_offsets() {
	verify_original_layout('test_recovers_firmware_root_pointer_offsets')
}

fn test_recovers_driver_root_stores() { verify_original_layout('test_recovers_driver_root_stores') }

fn test_rejects_incomplete_driver_layout() {
	verify_original_layout('test_rejects_incomplete_driver_layout')
}

fn test_recovers_firmware_shared_data_publications() {
	verify_original_layout('test_recovers_firmware_shared_data_publications')
}

fn test_rejects_incomplete_firmware_shared_data_publications() {
	verify_original_layout('test_rejects_incomplete_firmware_shared_data_publications')
}

fn test_recovers_firmware_shared_platform_fields() {
	verify_original_layout('test_recovers_firmware_shared_platform_fields')
}

fn test_rejects_incomplete_firmware_shared_platform_fields() {
	verify_original_layout('test_rejects_incomplete_firmware_shared_platform_fields')
}

fn test_validates_root_allocation_sizes() {
	verify_original_layout('test_validates_root_allocation_sizes')
}

fn test_recovers_firmware_hardware_config_reads() {
	verify_original_layout('test_recovers_firmware_hardware_config_reads')
}

fn test_recovers_hardware_config_allocation_and_publication() {
	verify_original_layout('test_recovers_hardware_config_allocation_and_publication')
}

fn test_recovers_driver_hardware_config_table_layout() {
	verify_original_layout('test_recovers_driver_hardware_config_table_layout')
}

fn test_rejects_incomplete_driver_hardware_config_layout() {
	verify_original_layout('test_rejects_incomplete_driver_hardware_config_layout')
}

fn test_layout_widths_checked_reads_and_complete_missing_maps() {
	fixture := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/layout-boundaries.json')) or { panic(err) }) or { panic(err) }
	for row in fixture.arr() { layout_fixture_check(row.as_map()) }
}

fn test_checked_driver_layout_contracts_match_complete_original_outputs() {
	root := os.join_path(os.dir(@FILE), '..', 'build')
	driver_path := os.join_path(root, 'kext', 'g17c', 'AGXG17X.macho')
	firmware_path := os.join_path(root, 'firmware', 'g17c', 'armfw.bin')
	if !os.exists(driver_path) || !os.exists(firmware_path) { return }
	driver := os.read_bytes(driver_path) or { panic(err) }
	firmware := os.read_bytes(firmware_path) or { panic(err) }
	before_driver := driver.clone()
	before_firmware := firmware.clone()
	fixture := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/layout-driver-contracts.json')) or { panic(err) }) or { panic(err) }
	assert sha256.hexhash(driver.bytestr()) == text(fixture.as_map(), 'driver_sha256')
	assert sha256.hexhash(firmware.bytestr()) == text(fixture.as_map(), 'firmware_sha256')
	for entry in at(fixture.as_map(), 'records').arr() {
		row := entry.as_map()
		mut request := map[string]j.Value{}
		for key, descriptor in at(row, 'arguments').as_map() {
			fields := descriptor.as_map()
			if 'value' in fields {
				request[key] = at(fields, 'value')
				continue
			}
			if 'symbol' in fields {
				_, code := arm.symbol_code(driver, text(fields, 'symbol')) or { panic(err) }
				request[key] = j.Value(hex.encode(code))
				continue
			}
			request[key] = j.Value(hex.encode(if text(fields, 'artifact') == 'firmware' {
				firmware
			} else {
				driver
			}))
		}
		result := query(driver, text(row, 'operation'), request) or { panic(err) }
		assert j.decode(j.encode(result, false)) or { panic(err) } == at(row, 'result')
		assert driver == before_driver
		assert firmware == before_firmware
	}
}

fn test_retired_fixture_recipes_keep_complete_independent_native_inputs() {
	fixture := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/layout-retired-recipes.json')) or { panic(err) }) or { panic(err) }
	for row in fixture.arr() { layout_fixture_check(row.as_map()) }
}
