// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Admit the complete signed closure before reserving its sequence and again
// before publication. A late refusal must retain any already reserved floor.
fn verify_release_stage(stage string, text string, signature string, objects map[string]Payload, reserved bool) ! {
	entries := {'index.json': u64(0), 'index.sig': u64(0), 'objects': u64(0)}
	index_path := stage + '/index.json'
	signature_path := stage + '/index.sig'
	objects_path := stage + '/objects'
	signed_text := signature + '\n'
	defer { unsafe { entries.free(); index_path.free(); signature_path.free(); objects_path.free(); signed_text.free() } }
	export_stage_directory(stage, entries, if reserved { u32(0o755) } else { u32(0o700) })!
	export_stage_metadata(index_path, text)!
	export_stage_metadata(signature_path, signed_text)!
	mut lengths := map[string]u64{}
	defer { unsafe { lengths.free() } }
	for hash, payload in objects {
		defer { unsafe { hash.free() } }
		lengths[hash] = payload.bytes
	}
	export_stage_payloads(objects_path, lengths, if reserved { u32(0o755) } else { u32(0) })!
}
