module signing

import crypto.rand
import crypto.sha512
import crypto.subtle
import tools.packages.signing.internal.edwards25519

fn signing_hash512(first []u8, second []u8, third []u8) []u8 {
	mut digest := sha512.new()
	defer { unsafe { digest.free(); free(digest) } }
	digest.write(first) or { panic(err) }
	digest.write(second) or { panic(err) }
	digest.write(third) or { panic(err) }
	mut out := []u8{len: sha512.size}
	digest.checksum_into(mut out)
	return out
}

// public_key_size is the sizeof public keys in bytes
pub const public_key_size = 32

// private_key_size is the sizeof private keys in bytes
pub const private_key_size = 64

// signature_size is the size of signatures generated and verified by this modules, in bytes.
pub const signature_size = 64

// seed_size is the size of private key seeds in bytes
pub const seed_size = 32

// `PublicKey` is Ed25519 public keys.
pub type PublicKey = []u8

// equal reports whether p and x have the same value.
pub fn (p PublicKey) equal(x []u8) bool {
	return subtle.constant_time_compare(p, PublicKey(x)) == 1
}

// PrivateKey is Ed25519 private keys
pub type PrivateKey = []u8

// seed returns the private key seed corresponding to priv.
// RFC 8032's private keys correspond to seeds in this module.
pub fn (priv PrivateKey) seed() []u8 {
	mut seed := []u8{len: seed_size}
	copy(mut seed, priv[..32])
	return seed
}

// public_key returns the []u8 corresponding to priv.
pub fn (priv PrivateKey) public_key() PublicKey {
	assert priv.len == private_key_size
	mut publickey := []u8{len: public_key_size}
	copy(mut publickey, priv[32..])
	return PublicKey(publickey)
}

// currentyly x not `crypto.PrivateKey`
pub fn (priv PrivateKey) equal(x []u8) bool {
	return subtle.constant_time_compare(priv, PrivateKey(x)) == 1
}

// sign signs the given message with priv.
pub fn (priv PrivateKey) sign(message []u8) ![]u8 {
	/*
	if opts.HashFunc() != crypto.Hash(0) {
		return nil, errors.New("ed25519: cannot sign hashed message")
	}*/

	return sign(priv, message)
}

// sign`signs the message with privatekey and returns a signature
pub fn sign(privatekey PrivateKey, message []u8) ![]u8 {
	mut signature := []u8{len: signature_size}
	sign_generic(mut signature, privatekey, message) or { unsafe { signature.free() }; return err }
	return signature
}

fn sign_generic(mut signature []u8, privatekey []u8, message []u8) ! {
	if privatekey.len != private_key_size {
		panic('ed25519: bad private key length: ${privatekey.len}')
	}
	seed, publickey := privatekey[..seed_size], privatekey[seed_size..]

	mut h := signing_hash512(seed, [], [])
	defer { unsafe { h.free() } }
	mut s := edwards25519.new_scalar_owned()
	defer { unsafe { free(s) } }
	s.set_bytes_with_clamping(h[..32])!
	mut prefix := unsafe { h[32..] }

	msg_digest := signing_hash512(prefix, message, [])
	defer { unsafe { msg_digest.free() } }

	mut r := edwards25519.new_scalar_owned()
	defer { unsafe { free(r) } }
	r.set_uniform_bytes(msg_digest)!

	mut rr := edwards25519.Point{}
	rr.scalar_base_mult(mut r)

	encoded_r := rr.bytes()
	defer { unsafe { encoded_r.free() } }
	hram_digest := signing_hash512(encoded_r, publickey, message)
	defer { unsafe { hram_digest.free() } }
	mut k := edwards25519.new_scalar_owned()
	defer { unsafe { free(k) } }
	k.set_uniform_bytes(hram_digest)!

	mut ss := edwards25519.new_scalar_owned()
	defer { unsafe { free(ss) } }
	ss.multiply_add(k, s, r)

	encoded_s := ss.bytes()
	defer { unsafe { encoded_s.free() } }
	copy(mut signature[..32], encoded_r)
	copy(mut signature[32..], encoded_s)
}

// verify reports whether sig is a valid signature of message by publickey.
pub fn verify(publickey PublicKey, message []u8, sig []u8) !bool {
	if publickey.len != public_key_size {
		return error('ed25519: bad public key length: ${publickey.len}')
	}

	if sig.len != signature_size || sig[63] & 224 != 0 {
		return false
	}

	mut aa := edwards25519.Point{}
	aa.set_bytes(publickey)!

	hram_digest := signing_hash512(sig[..32], publickey, message)
	defer { unsafe { hram_digest.free() } }

	mut k := edwards25519.new_scalar_owned()
	defer { unsafe { free(k) } }
	k.set_uniform_bytes(hram_digest)!

	mut ss := edwards25519.new_scalar_owned()
	defer { unsafe { free(ss) } }
	ss.set_canonical_bytes(sig[32..])!

	// [S]B = R + [k]A --> [k](-A) + [S]B = R
	mut minus_a := edwards25519.Point{}
	minus_a.negate(aa)
	mut rr := edwards25519.Point{}
	rr.vartime_double_scalar_base_mult(k, minus_a, ss)

	encoded_r := rr.bytes()
	defer { unsafe { encoded_r.free() } }
	return subtle.constant_time_compare(sig[..32], encoded_r) == 1
}

// generate_key generates a public/private key pair entropy using `crypto.rand`.
pub fn generate_key() !(PublicKey, PrivateKey) {
	mut seed := rand.bytes(seed_size)!
	defer { unsafe { seed.free() } }

	privatekey := new_key_from_seed(seed)
	mut publickey := []u8{len: public_key_size}
	copy(mut publickey, privatekey[32..])

	return publickey, privatekey
}

// new_key_from_seed calculates a private key from a seed. private keys of RFC 8032
// correspond to seeds in this module
pub fn new_key_from_seed(seed []u8) PrivateKey {
	// Outline the function body so that the returned key can be stack-allocated.
	mut privatekey := []u8{len: private_key_size}
	new_key_from_seed_generic(mut privatekey, seed)
	return PrivateKey(privatekey)
}

fn new_key_from_seed_generic(mut privatekey []u8, seed []u8) {
	if seed.len != seed_size {
		panic('ed25519: bad seed length: ${seed.len}')
	}

	mut h := signing_hash512(seed, [], [])
	defer { unsafe { h.free() } }
	mut s := edwards25519.new_scalar_owned()
	defer { unsafe { free(s) } }
	s.set_bytes_with_clamping(h[..32]) or { panic(err) }
	mut aa := edwards25519.Point{}
	aa.scalar_base_mult(mut s)

	mut publickey := aa.bytes()
	defer { unsafe { publickey.free() } }

	copy(mut privatekey, seed)
	copy(mut privatekey[32..], publickey)
}
