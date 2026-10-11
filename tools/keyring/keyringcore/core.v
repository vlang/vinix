// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The credential store: one file per account holding secrets -- passwords
// for networks and sites, tokens, keys -- that nothing can read without the
// account's password.
//
// Every secret is encrypted with one random key, the store key. The store
// key is never written down; what the file holds is the store key wrapped
// twice: once under a key made from the login password, once under a key
// made from a recovery key that is shown when the store is created and
// kept by its owner on paper. Either unwraps it. Changing the password
// re-wraps the store key and touches no secret. An administrator who sets
// a new password for someone cannot give them their secrets back -- that
// is the point -- and the recovery key is what does.
//
// The file says nothing about what it holds beyond how many items: the
// names of services and accounts are inside the encryption.
//
//	vinix-keyring 1
//	slot password <cost> <salt> <nonce> <wrapped store key>
//	slot recovery <salt> <nonce> <wrapped store key>
//	check <nonce> <a constant, encrypted>
//	item <id> <nonce> <encrypted service, account and secret>
//
// with binary fields in base64. Encryption is XChaCha20-Poly1305 with a
// random 24-byte nonce; each line's kind and, for an item, its id are
// authenticated with it, so a line cannot be moved to stand for another.
// The password key is scrypt at the cost in the slot; the recovery key has
// 160 bits of its own and is only hashed.
module keyringcore

import crypto.scrypt
import crypto.sha256
import encoding.base64
import os
import x.crypto.chacha20poly1305

pub const key_bytes = 32
pub const max_items = 1024
pub const max_name = 256
pub const max_secret = 8192
pub const max_file = 16 * 1024 * 1024

const nonce_bytes = 24
const salt_bytes = 16
const recovery_bytes = 20
const magic = 'vinix-keyring 1'
const check_text = 'vinix-keyring check'
// Letters and digits that are not mistaken for one another on paper.
const recovery_alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

pub struct Cost {
pub:
	ln u32 = 15
	r  u32 = 8
	p  u32 = 1
}

fn (c Cost) valid() bool {
	return c.ln >= 10 && c.ln <= 18 && c.r >= 1 && c.r <= 16 && c.p >= 1 && c.p <= 16
}

struct Slot {
mut:
	cost    Cost
	salt    []u8
	nonce   []u8
	wrapped []u8
}

struct Sealed {
	id      string
	nonce   []u8
	wrapped []u8
}

pub struct Store {
mut:
	password Slot
	recovery Slot
	check    Sealed
	items    []Sealed
}

// What an item is once it is open.
pub struct Item {
pub:
	service string
	account string
	secret  []u8
}

pub fn wipe(mut secret []u8) {
	for i in 0 .. secret.len {
		secret[i] = 0
	}
}

fn random(count int) ![]u8 {
	mut file := os.open('/dev/urandom') or { return error('cannot open /dev/urandom') }
	defer { file.close() }
	mut bytes := []u8{len: count}
	mut done := 0
	for done < count {
		got := file.read(mut bytes[done..]) or { return error('cannot read /dev/urandom') }
		if got <= 0 {
			return error('cannot read /dev/urandom')
		}
		done += got
	}
	return bytes
}

fn seal(key []u8, context string, plaintext []u8) !([]u8, []u8) {
	nonce := random(nonce_bytes)!
	wrapped := chacha20poly1305.encrypt(plaintext, key, nonce, context.bytes()) or {
		return error('encryption failed')
	}
	return nonce, wrapped
}

fn open(key []u8, context string, nonce []u8, wrapped []u8) ![]u8 {
	if nonce.len != nonce_bytes || key.len != key_bytes {
		return error('malformed store')
	}
	return chacha20poly1305.decrypt(wrapped, key, nonce, context.bytes()) or {
		return error('wrong key')
	}
}

fn password_key(password []u8, salt []u8, cost Cost) ![]u8 {
	if password.len == 0 || password.len > 1024 || !cost.valid() {
		return error('invalid password or cost')
	}
	return scrypt.scrypt(password, salt, u64(1) << cost.ln, cost.r, cost.p, u64(key_bytes)) or {
		return error('scrypt failed')
	}
}

fn recovery_key_bytes(text string) ![]u8 {
	mut bits := u64(0)
	mut count := 0
	mut characters := 0
	mut out := []u8{cap: recovery_bytes}
	for i in 0 .. text.len {
		mut ch := text[i]
		if ch == `-` || ch == ` ` {
			continue
		}
		characters++
		if ch >= `a` && ch <= `z` {
			ch -= 32
		}
		value := recovery_alphabet.index_u8(ch)
		if value < 0 {
			return error('not a recovery key')
		}
		bits = (bits << 5) | u64(value)
		count += 5
		if count >= 8 {
			count -= 8
			out << u8(bits >> count)
			bits &= (u64(1) << count) - 1
		}
	}
	// Exactly the characters that make 160 bits: one more would be five
	// bits that mean nothing, and a key with a spare character is two keys.
	if out.len != recovery_bytes || characters != recovery_bytes * 8 / 5 || bits != 0 {
		return error('not a recovery key')
	}
	return out
}

// 160 bits as eight groups of four characters.
fn recovery_key_text(bytes []u8) string {
	mut out := []u8{cap: 40}
	mut bits := u64(0)
	mut count := 0
	for b in bytes {
		bits = (bits << 8) | u64(b)
		count += 8
		for count >= 5 {
			count -= 5
			if out.len > 0 && (out.len + 1) % 5 == 0 {
				out << `-`
			}
			out << recovery_alphabet[int((bits >> count) & 31)]
		}
		bits &= (u64(1) << count) - 1
	}
	return out.bytestr()
}

fn recovery_wrapping_key(recovery []u8, salt []u8) []u8 {
	mut material := 'vinix-keyring recovery 1'.bytes()
	material << salt
	material << recovery
	return sha256.sum(material)
}

// A new, empty store for `password`. Returns the store, its key -- the
// store is open -- and the recovery key, which is shown once and not kept.
pub fn create(password []u8, cost Cost) !(Store, []u8, string) {
	key := random(key_bytes)!
	mut store := Store{}
	store.check = seal_named(key, 'check', '', check_text.bytes())!
	store.set_password(key, password, cost)!
	recovery := store.new_recovery(key)!
	return store, key, recovery
}

fn seal_named(key []u8, kind string, id string, plaintext []u8) !Sealed {
	nonce, wrapped := seal(key, 'vinix-keyring ${kind} ${id}', plaintext)!
	return Sealed{
		id:      id
		nonce:   nonce
		wrapped: wrapped
	}
}

// Whether `key` is this store's key.
fn (s &Store) holds(key []u8) bool {
	plain := open(key, 'vinix-keyring check ', s.check.nonce, s.check.wrapped) or { return false }
	return plain == check_text.bytes()
}

// The store key, from the password.
pub fn (s &Store) unlock(password []u8) ![]u8 {
	mut wrapping := password_key(password, s.password.salt, s.password.cost)!
	defer { wipe(mut wrapping) }
	key := open(wrapping, 'vinix-keyring slot password', s.password.nonce, s.password.wrapped) or {
		return error('wrong password')
	}
	if !s.holds(key) {
		return error('the store is damaged')
	}
	return key
}

// The store key, from the recovery key.
pub fn (s &Store) unlock_with_recovery(recovery string) ![]u8 {
	mut bytes := recovery_key_bytes(recovery)!
	mut wrapping := recovery_wrapping_key(bytes, s.recovery.salt)
	defer {
		wipe(mut bytes)
		wipe(mut wrapping)
	}
	key := open(wrapping, 'vinix-keyring slot recovery', s.recovery.nonce, s.recovery.wrapped) or {
		return error('wrong recovery key')
	}
	if !s.holds(key) {
		return error('the store is damaged')
	}
	return key
}

// Wrap the store key under a new password. The old password is not needed:
// holding the store key is what entitles.
pub fn (mut s Store) set_password(key []u8, password []u8, cost Cost) ! {
	if key.len != key_bytes || (s.password.wrapped.len > 0 && !s.holds(key)) {
		return error('not this store\'s key')
	}
	salt := random(salt_bytes)!
	mut wrapping := password_key(password, salt, cost)!
	defer { wipe(mut wrapping) }
	nonce, wrapped := seal(wrapping, 'vinix-keyring slot password', key)!
	s.password = Slot{
		cost:    cost
		salt:    salt
		nonce:   nonce
		wrapped: wrapped
	}
}

// Replace the recovery key. The one before stops working.
pub fn (mut s Store) new_recovery(key []u8) !string {
	if key.len != key_bytes || !s.holds(key) {
		return error('not this store\'s key')
	}
	mut bytes := random(recovery_bytes)!
	salt := random(salt_bytes)!
	mut wrapping := recovery_wrapping_key(bytes, salt)
	nonce, wrapped := seal(wrapping, 'vinix-keyring slot recovery', key)!
	s.recovery = Slot{
		salt:    salt
		nonce:   nonce
		wrapped: wrapped
	}
	text := recovery_key_text(bytes)
	wipe(mut bytes)
	wipe(mut wrapping)
	return text
}

fn valid_name(name string) bool {
	if name.len == 0 || name.len > max_name {
		return false
	}
	for i in 0 .. name.len {
		if name[i] < 0x20 || name[i] == 0x7f {
			return false
		}
	}
	return true
}

fn put_u32(mut out []u8, value u32) {
	out << u8(value)
	out << u8(value >> 8)
	out << u8(value >> 16)
	out << u8(value >> 24)
}

fn encode_item(item Item) []u8 {
	mut out := []u8{cap: 12 + item.service.len + item.account.len + item.secret.len}
	put_u32(mut out, u32(item.service.len))
	out << item.service.bytes()
	put_u32(mut out, u32(item.account.len))
	out << item.account.bytes()
	put_u32(mut out, u32(item.secret.len))
	out << item.secret
	return out
}

fn decode_item(data []u8) !Item {
	mut at := 0
	mut parts := [][]u8{}
	for _ in 0 .. 3 {
		if data.len - at < 4 {
			return error('damaged item')
		}
		length := int(u32(data[at]) | (u32(data[at + 1]) << 8) | (u32(data[at + 2]) << 16) | (u32(data[at + 3]) << 24))
		at += 4
		if length < 0 || length > max_secret || data.len - at < length {
			return error('damaged item')
		}
		parts << data[at..at + length].clone()
		at += length
	}
	if at != data.len {
		return error('damaged item')
	}
	return Item{
		service: parts[0].bytestr()
		account: parts[1].bytestr()
		secret:  parts[2]
	}
}

fn (s &Store) open_item(key []u8, sealed Sealed) !Item {
	mut plain := open(key, 'vinix-keyring item ${sealed.id}', sealed.nonce, sealed.wrapped) or {
		return error('damaged item')
	}
	defer { wipe(mut plain) }
	return decode_item(plain)
}

fn (s &Store) find(key []u8, service string, account string) int {
	for index, sealed in s.items {
		item := s.open_item(key, sealed) or { continue }
		if item.service == service && item.account == account {
			return index
		}
	}
	return -1
}

// Store a secret, replacing the one under the same service and account.
pub fn (mut s Store) put(key []u8, item Item) ! {
	if !s.holds(key) {
		return error('not this store\'s key')
	}
	if !valid_name(item.service) || !valid_name(item.account) {
		return error('invalid service or account name')
	}
	if item.secret.len == 0 || item.secret.len > max_secret {
		return error('a secret is between 1 and ${max_secret} bytes')
	}
	existing := s.find(key, item.service, item.account)
	if existing < 0 && s.items.len >= max_items {
		return error('the store is full')
	}
	id := random(8)!.hex()
	mut plain := encode_item(item)
	sealed := seal_named(key, 'item', id, plain)!
	wipe(mut plain)
	if existing >= 0 {
		s.items[existing] = sealed
	} else {
		s.items << sealed
	}
}

pub fn (s &Store) get(key []u8, service string, account string) ![]u8 {
	if !s.holds(key) {
		return error('not this store\'s key')
	}
	index := s.find(key, service, account)
	if index < 0 {
		return error('no such item')
	}
	return s.open_item(key, s.items[index])!.secret
}

pub fn (mut s Store) delete(key []u8, service string, account string) ! {
	if !s.holds(key) {
		return error('not this store\'s key')
	}
	index := s.find(key, service, account)
	if index < 0 {
		return error('no such item')
	}
	s.items.delete(index)
}

// What the store holds, without the secrets.
pub fn (s &Store) list(key []u8) ![]Item {
	if !s.holds(key) {
		return error('not this store\'s key')
	}
	mut listed := []Item{cap: s.items.len}
	for sealed in s.items {
		item := s.open_item(key, sealed)!
		listed << Item{
			service: item.service
			account: item.account
		}
	}
	return listed
}

pub fn (s &Store) count() int {
	return s.items.len
}

fn b64(data []u8) string {
	return base64.encode(data)
}

fn unb64(text string, least int, most int) ![]u8 {
	if text.len == 0 || text.len > most * 2 + 8 {
		return error('malformed field')
	}
	for i in 0 .. text.len {
		ch := text[i]
		if !((ch >= `A` && ch <= `Z`) || (ch >= `a` && ch <= `z`) || (ch >= `0` && ch <= `9`)
			|| ch == `+` || ch == `/` || ch == `=`) {
			return error('malformed field')
		}
	}
	data := base64.decode(text)
	// One spelling only: what does not encode back to itself is refused.
	if base64.encode(data) != text || data.len < least || data.len > most {
		return error('malformed field')
	}
	return data
}

pub fn (s &Store) format() string {
	mut lines := [magic]
	lines << 'slot password ln=${s.password.cost.ln},r=${s.password.cost.r},p=${s.password.cost.p} ${b64(s.password.salt)} ${b64(s.password.nonce)} ${b64(s.password.wrapped)}'
	lines << 'slot recovery ${b64(s.recovery.salt)} ${b64(s.recovery.nonce)} ${b64(s.recovery.wrapped)}'
	lines << 'check ${b64(s.check.nonce)} ${b64(s.check.wrapped)}'
	for item in s.items {
		lines << 'item ${item.id} ${b64(item.nonce)} ${b64(item.wrapped)}'
	}
	lines << ''
	return lines.join('\n')
}

fn parse_cost(text string) !Cost {
	parts := text.split(',')
	if parts.len != 3 || !parts[0].starts_with('ln=') || !parts[1].starts_with('r=')
		|| !parts[2].starts_with('p=') {
		return error('malformed cost')
	}
	mut values := []u32{}
	for part in parts {
		digits := part.all_after('=')
		if digits.len == 0 || digits.len > 2 || (digits.len == 2 && digits[0] == `0`) {
			return error('malformed cost')
		}
		for i in 0 .. digits.len {
			if digits[i] < `0` || digits[i] > `9` {
				return error('malformed cost')
			}
		}
		values << u32(digits.int())
	}
	cost := Cost{
		ln: values[0]
		r:  values[1]
		p:  values[2]
	}
	if !cost.valid() {
		return error('cost out of range')
	}
	return cost
}

// A store from the text of its file, or an error: nothing is guessed.
pub fn parse(text string) !Store {
	if text.len > max_file || text.len == 0 || text[text.len - 1] != `\n` {
		return error('not a keyring')
	}
	lines := text[..text.len - 1].split('\n')
	if lines.len < 4 || lines.len > 4 + max_items || lines[0] != magic {
		return error('not a keyring')
	}
	password := lines[1].split(' ')
	recovery := lines[2].split(' ')
	check := lines[3].split(' ')
	if password.len != 6 || password[0] != 'slot' || password[1] != 'password' || recovery.len != 5
		|| recovery[0] != 'slot' || recovery[1] != 'recovery' || check.len != 3
		|| check[0] != 'check' {
		return error('malformed keyring header')
	}
	wrapped_key := key_bytes + 16
	mut store := Store{
		password: Slot{
			cost:    parse_cost(password[2])!
			salt:    unb64(password[3], salt_bytes, salt_bytes)!
			nonce:   unb64(password[4], nonce_bytes, nonce_bytes)!
			wrapped: unb64(password[5], wrapped_key, wrapped_key)!
		}
		recovery: Slot{
			salt:    unb64(recovery[2], salt_bytes, salt_bytes)!
			nonce:   unb64(recovery[3], nonce_bytes, nonce_bytes)!
			wrapped: unb64(recovery[4], wrapped_key, wrapped_key)!
		}
		check:    Sealed{
			nonce:   unb64(check[1], nonce_bytes, nonce_bytes)!
			wrapped: unb64(check[2], check_text.len + 16, check_text.len + 16)!
		}
	}
	mut ids := map[string]bool{}
	for line in lines[4..] {
		fields := line.split(' ')
		if fields.len != 4 || fields[0] != 'item' || fields[1].len != 16 || fields[1] in ids {
			return error('malformed item')
		}
		for i in 0 .. 16 {
			ch := fields[1][i]
			if !((ch >= `0` && ch <= `9`) || (ch >= `a` && ch <= `f`)) {
				return error('malformed item id')
			}
		}
		ids[fields[1]] = true
		store.items << Sealed{
			id:      fields[1]
			nonce:   unb64(fields[2], nonce_bytes, nonce_bytes)!
			wrapped: unb64(fields[3], 12 + 2 + 16, 12 + 2 * max_name + max_secret + 16)!
		}
	}
	return store
}
