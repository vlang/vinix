// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

// Valid SDK metadata on either side of the byte limit, without large payloads.
fn generation_metadata_fixture(delta int) State {
	mut packages := []Installed{}; mut requested := []string{}
	for index in 0 .. 32 {
		id := 'item-' + index.str(); requested << id
		packages << Installed{ repository: 'trusted', public_key: 'a'.repeat(64), sequence: 1,
			package: Package{ id: id, name: id, version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT',
				arguments: []string{len: 64, init: 'x'.repeat(4096)}, files: [Payload{ path: 'asset', sha256: 'b'.repeat(64) }] } }
	}
	state := State{ generation: 9, previous: 8, architecture: 'aarch64', requested: requested, packages: packages }
	text := json2.encode(state)
	mut excess := text.len - max_metadata - delta
	unsafe { text.free() }
	assert excess > 0 && excess < 64 * 4096
	mut arguments := packages[0].package.arguments.clone()
	for index in 0 .. arguments.len {
		shrink := if excess > arguments[index].len { arguments[index].len } else { excess }
		arguments[index] = arguments[index][..arguments[index].len - shrink].clone()
		excess -= shrink
	}
	packages[0] = Installed{ ...packages[0], package: Package{ ...packages[0].package, arguments: arguments } }
	return State{ ...state, packages: packages }
}

fn test_generation_metadata_checks_exact_encoded_bytes_and_future_counter_widths() {
	for delta in [-1, 0, 1] {
		state := generation_metadata_fixture(delta)
		if delta > 0 {
			if _ := encode_generation_state(state) { assert false } else { assert err.msg().contains('installed state exceeds metadata limit') }
		} else {
			text := encode_generation_state(state)!
			assert text.len == max_metadata + delta
			decoded := decode_persistent_state(text, 'aarch64')!
			assert decoded == state
			close_decoded_state(decoded)
			unsafe { text.free() }
		}
		if delta == 0 {
			if _ := encode_generation_state(State{ ...state, generation: 10 }) { assert false }
		}
	}
	println('STATE PREFLIGHT exact metadata byte boundary, reader round-trip and future generation counter width PASS')
}

fn test_oversized_activation_preserves_abandoned_work_and_never_stages_any_operation() {
	directory := os.temp_dir() + '/vinix-state-preflight-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(directory + '/generations/.stage-sentinel')!; os.mkdir(directory + '/objects')!
	defer { os.rmdir_all(directory) or {} }
	os.write_file(directory + '/generations/.stage-sentinel/keep', 'interrupted work')!
	state := generation_metadata_fixture(1)
	plan := Plan{ requested: state.requested, packages: state.packages }
	for operation in ['install', 'upgrade', 'deploy', 'remove'] {
		if _ := activate_repair_plan_locked(Config{ architecture: 'aarch64' }, directory, State{}, plan, operation, [], TransactionOptions{}) { assert false }
		else { assert err.msg().contains('installed state exceeds metadata limit') }
		assert os.read_file(directory + '/generations/.stage-sentinel/keep')! == 'interrupted work'
		assert os.ls(directory + '/generations')! == ['.stage-sentinel'] && os.ls(directory + '/objects')!.len == 0
		assert !os.exists(directory + '/current') && !os.is_link(directory + '/current')
	}
	println('STATE PREFLIGHT install/upgrade/deploy/remove reject before stage retirement, object acquisition or activation PASS')
}

fn test_generation_metadata_encoding_retires_success_and_refusal_scratch() {
	$if track_heap ? {
		small := State{ generation: 1, architecture: 'aarch64' }
		large := generation_metadata_fixture(1)
		C.vinix_heap_begin()
		for _ in 0 .. 64 {
			text := encode_generation_state(small)!
			unsafe { text.free() }
		}
		for _ in 0 .. 8 {
			if _ := encode_generation_state(large) { assert false }
			else { message := err.msg(); unsafe { message.free(); err.free() } }
		}
		kept := C.vinix_heap_end()
		assert kept == 0 && C.vinix_heap_count() == 0, 'generation metadata retained ${kept} bytes'
		println('STATE PREFLIGHT 64 accepted and 8 oversized encodings retain zero tracked bytes PASS')
	}
}
