// SPDX-License-Identifier: GPL-2.0-or-later
module signing

import encoding.hex

struct SigningVector {
	seed string
	key string
	message string
	signature string
}

// Public reference data from RFC 8032 section 7.1. These seeds must never be
// enrolled as repository publishers. The expected bytes are independent of V.
const signing_vectors = [
	SigningVector{ seed: '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
		key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', message: '',
		signature: 'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b' },
	SigningVector{ seed: '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
		key: '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c', message: '72',
		signature: '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00' },
	SigningVector{ seed: 'c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7',
		key: 'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025', message: 'af82',
		signature: '6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a' },
]

fn test_package_signing_matches_rfc8032_and_refuses_modified_or_noncanonical_signatures() {
	for vector in signing_vectors {
		seed := hex.decode(vector.seed)!
		key := PublicKey(hex.decode(vector.key)!)
		message := hex.decode(vector.message)!
		expected := hex.decode(vector.signature)!
		secret := new_key_from_seed(seed)
		assert secret.public_key() == key
		assert sign(secret, message)! == expected
		assert verify(key, message, expected)!
		mut modified := expected.clone()
		modified[0] ^= 1
		assert !(verify(key, message, modified) or { false })
		assert !(verify(key, [...message, u8(0)], expected) or { false })
		assert !verify(key, message, expected[..63])!
		assert !verify(key, message, [...expected, u8(0)])!
		// Adding the group order to S preserves the point equation, but S must
		// remain canonical. This catches signature malleability independently.
		order := hex.decode('edd3f55c1a631258d69cf7a2def9de14000000000000000000000000000000010')!
		mut noncanonical := expected.clone()
		mut carry := u16(0)
		for i in 0 .. 32 {
			value := u16(noncanonical[32 + i]) + u16(order[i]) + carry
			noncanonical[32 + i] = u8(value & 255)
			carry = value >> 8
		}
		assert !(verify(key, message, noncanonical) or { false })
	}
	println('Package signing: RFC8032 keys/signatures and tamper/canonical-scalar refusal passed')
}
