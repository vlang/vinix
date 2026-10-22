module loginproof

import crypto.sha256
import os

fn test_digest_matches_known_sha256_for_empty_and_chunked_file() {
	path := os.temp_dir() + '/vinix-login-proof-' + os.getpid().str()
	defer { os.rm(path) or {} }
	for content in ['', 'abc', 'chunked evidence\n'.repeat(150000)] {
		os.write_file(path, content) or { panic(err) }
		assert digest(path) or { panic(err) } == sha256.hexhash(content)
	}
}

fn test_exact_ordered_outcome_markers_refuse_missing_duplicate_panic_and_reordered_log() {
	valid := markers.join('\n') + '\n'
	serial(valid) or { panic(err) }
	mut corruptions := [valid.replace(markers[3] + '\n', ''), valid + markers[3] + '\n',
		valid + 'KERNEL PANIC: bounded refusal control\n']
	mut reordered := markers.clone()
	reordered[2], reordered[3] = reordered[3], reordered[2]
	corruptions << reordered.join('\n')
	for text in corruptions {
		mut refused := false
		serial(text) or { refused = true }
		assert refused
	}
}

fn test_relative_output_paths_cannot_escape_evidence_root() {
	assert relative('source/guest/main.v')
	for value in ['', '/tmp/output', '../outside', 'source/../outside', 'source//file',
		'source/./file', 'source\x00/file'] {
		assert !relative(value)
	}
}
