module g17expr

import os
import encoding.hex
import g17decode as arm
import traceanalysis as j

fn legacy_fixture_row(row map[string]j.Value) {
 request := at(row, 'request').as_map()
 before := j.encode(expr(request), false)
 operation := text(request, 'operation')
 data := hex.decode(if operation in ['stores_covering', 'stores_covering_any'] {text(request, 'code')} else {text(request, 'image')}) or {[]u8{}}
 old := data.clone()
 result := (if legacy_handles(operation) {query(data, operation, request)} else {arm.query(data, operation, request)}) or {
  assert 'error' in row
  kind := text(row, 'exception')
  expected := text(row, 'error')
  message := if kind == 'KeyError' {'KeyError: ' + expected[1..expected.len - 1]} else if kind in ['TypeError', 'IndexError', 'OverflowError'] {kind + ': ' + expected} else if kind == 'error' {'struct.error: ' + expected} else {expected}
  assert err.msg() == message
  assert j.encode(expr(request), false) == before
  assert data == old
  return
 }
 assert 'result' in row
 assert (j.decode(j.encode(result, false)) or {panic(err)}) == at(row, 'result')
 assert j.encode(expr(request), false) == before
 assert data == old
}

fn verify_original_legacy(name string) {
 fixture := (j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/original-legacy.json')) or {panic(err)}) or {panic(err)}).as_map()
 assert name in fixture
 for row in at(fixture, name).arr() { legacy_fixture_row(row.as_map()) }
}

fn test_decodes_kernel_authenticated_rebase() { verify_original_legacy('test_decodes_kernel_authenticated_rebase') }

fn test_recovers_checked_ring_accessor() { verify_original_legacy('test_recovers_checked_ring_accessor') }

fn test_recovers_data_master_stride() { verify_original_legacy('test_recovers_data_master_stride') }

fn test_recovers_accelerator_command_fields() { verify_original_legacy('test_recovers_accelerator_command_fields') }

fn test_recovers_complete_accelerator_command_contract() { verify_original_legacy('test_recovers_complete_accelerator_command_contract') }

fn test_recovers_data_master_submission_publication() { verify_original_legacy('test_recovers_data_master_submission_publication') }

fn test_rejects_wrong_data_master_command_type() { verify_original_legacy('test_rejects_wrong_data_master_command_type') }

fn test_recovers_device_control_copy_size() { verify_original_legacy('test_recovers_device_control_copy_size') }

fn test_recovers_g17_accelerator_channel_inputs() { verify_original_legacy('test_recovers_g17_accelerator_channel_inputs') }

fn test_idle_timer_store_is_not_an_accelerator_member_write() { verify_original_legacy('test_idle_timer_store_is_not_an_accelerator_member_write') }

fn test_unit_mask_saturates_the_way_apple_builds_it() {
 for count in [0, 1, 10, 31] { assert (u32(~(~u64(0) << count))) == u32((u64(1) << count) - 1) }
 for count in [32, 40, 63, 64, 225] {
  value := if count > 63 {~u32(0)} else {u32(~(~u64(0) << count))}
  assert value == ~u32(0)
 }
}

fn test_stores_covering_spans_wide_and_paired_stores() { verify_original_legacy('test_stores_covering_spans_wide_and_paired_stores') }

fn test_decodes_g17_selector_logical_immediate() { verify_original_legacy('test_decodes_g17_selector_logical_immediate') }

fn test_resolves_selector_across_mutually_exclusive_call() { verify_original_legacy('test_resolves_selector_across_mutually_exclusive_call') }

fn test_recovers_device_control_ring_bindings() { verify_original_legacy('test_recovers_device_control_ring_bindings') }

fn test_rejects_incomplete_device_control_ring_publication() { verify_original_legacy('test_rejects_incomplete_device_control_ring_publication') }

fn test_legacy_producer_mutations_and_typed_boundaries() {
 fixture := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/legacy-boundaries.json')) or {panic(err)}) or {panic(err)}
 for row in fixture.arr() {legacy_fixture_row(row.as_map())}
}
