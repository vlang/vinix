module entropy

import crypto.sha256
import encoding.hex

fn test_vectors() {
	for message in ['', 'abc', 'a'.repeat(55), 'b'.repeat(56), 'c'.repeat(128)] {
		mut digest := [32]u8{}
		sha256_digest(message.str, u64(message.len), &digest)
		assert hex.encode(digest[..]) == sha256.hexhash(message)
	}
	mut g := Generator{}
	mut key := [32]u8{}
	mut output := [64]u8{}
	assert !g.fill(&output[0], 64)
	g.seed(&key[0])
	g.block(&output[0])
	assert hex.encode(output[..]) == '76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586'
	mut next := [32]u8{}
	derive(&key[0], &key, &next)
	assert key != next
	g.seed(&key[0])
	assert g.fill(&output[0], 64)
	first := output
	assert g.fill(&output[0], 64)
	assert output != first
}
