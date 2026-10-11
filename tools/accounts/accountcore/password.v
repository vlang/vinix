// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Password records. A password is never stored: what the shadow file holds
// is the output of scrypt over it and a random salt, in the modular format
// passlib calls `scrypt`:
//
//	$scrypt$ln=<log2 N>,r=<r>,p=<p>$<salt>$<key>
//
// with the salt and the key in base64 without padding, `.` standing for `+`.
// The cost travels with the record, so raising the default does not lock
// anyone out: an old record is checked at its own cost and replaced at the
// next login (see needs_rehash).
module accountcore

import crypto.scrypt
import crypto.subtle
import encoding.hex
import os

pub const max_hash = 256
pub const min_password = 8
pub const max_password = 256

const salt_bytes = 16
const key_bytes = 32
const scrypt_prefix = r'$scrypt$'

// What a record is checked against; anything outside is refused rather than
// run. The upper bounds are what keeps a hostile record from making a login
// allocate gigabytes.
const min_ln = 10
const max_ln = 18
const max_r = 16
const max_p = 16

// The marker of an account nobody can log in to, and the prefix that turns
// any record into one that matches nothing while keeping what it was.
pub const no_login = '*'
pub const lock_prefix = '!'

pub struct Cost {
pub:
	ln u32 = 15
	r  u32 = 8
	p  u32 = 1
}

// N = 2^15, r = 8, p = 1: 32 MiB and, with V's scrypt, about half a second
// per guess on an M1. That is less work than the parameter sets OWASP's
// password storage guidance lists (it asks for p = 3 at this N); three times
// the wait at every login and unlock was judged too much for what V's
// implementation costs. /etc/vinix/auth.conf can ask for more.
pub const default_cost = Cost{}

fn (c Cost) valid() bool {
	return c.ln >= min_ln && c.ln <= max_ln && c.r >= 1 && c.r <= max_r && c.p >= 1
		&& c.p <= max_p
}

// How much work a cost is, for comparing two of them.
fn (c Cost) work() u64 {
	return (u64(1) << c.ln) * u64(c.r) * u64(c.p)
}

const ab64_alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789./'

fn ab64_encode(data []u8) string {
	mut out := []u8{cap: (data.len * 4 + 2) / 3}
	mut i := 0
	for i + 2 < data.len {
		n := (u32(data[i]) << 16) | (u32(data[i + 1]) << 8) | u32(data[i + 2])
		out << ab64_alphabet[(n >> 18) & 63]
		out << ab64_alphabet[(n >> 12) & 63]
		out << ab64_alphabet[(n >> 6) & 63]
		out << ab64_alphabet[n & 63]
		i += 3
	}
	if data.len - i == 1 {
		n := u32(data[i]) << 16
		out << ab64_alphabet[(n >> 18) & 63]
		out << ab64_alphabet[(n >> 12) & 63]
	} else if data.len - i == 2 {
		n := (u32(data[i]) << 16) | (u32(data[i + 1]) << 8)
		out << ab64_alphabet[(n >> 18) & 63]
		out << ab64_alphabet[(n >> 12) & 63]
		out << ab64_alphabet[(n >> 6) & 63]
	}
	return out.bytestr()
}

fn ab64_value(ch u8) int {
	return match ch {
		`A`...`Z` { int(ch - `A`) }
		`a`...`z` { int(ch - `a`) + 26 }
		`0`...`9` { int(ch - `0`) + 52 }
		`.` { 62 }
		`/` { 63 }
		else { -1 }
	}
}

fn ab64_decode(text string) ![]u8 {
	if text.len % 4 == 1 {
		return error('invalid base64 length')
	}
	mut out := []u8{cap: text.len * 3 / 4}
	mut bits := u32(0)
	mut count := 0
	for i in 0 .. text.len {
		value := ab64_value(text[i])
		if value < 0 {
			return error('invalid base64 character')
		}
		bits = (bits << 6) | u32(value)
		count += 6
		if count >= 8 {
			count -= 8
			out << u8(bits >> count)
			bits &= (u32(1) << count) - 1
		}
	}
	// Bits left over must be zero, or two different texts would decode to
	// the same bytes.
	if bits != 0 {
		return error('invalid base64 padding bits')
	}
	return out
}

struct Record {
	cost Cost
	salt []u8
	key  []u8
}

fn parse_small(text string) !u32 {
	if text.len == 0 || text.len > 3 || (text.len > 1 && text[0] == `0`) {
		return error('invalid number')
	}
	mut value := u32(0)
	for i in 0 .. text.len {
		if text[i] < `0` || text[i] > `9` {
			return error('invalid number')
		}
		value = value * 10 + u32(text[i] - `0`)
	}
	return value
}

fn parse_record(hash string) !Record {
	if hash.len > max_hash || !hash.starts_with(scrypt_prefix) {
		return error('not a scrypt record')
	}
	parts := hash[scrypt_prefix.len..].split(r'$')
	if parts.len != 3 {
		return error('malformed scrypt record')
	}
	settings := parts[0].split(',')
	if settings.len != 3 || !settings[0].starts_with('ln=') || !settings[1].starts_with('r=')
		|| !settings[2].starts_with('p=') {
		return error('malformed scrypt parameters')
	}
	cost := Cost{
		ln: parse_small(settings[0][3..])!
		r:  parse_small(settings[1][2..])!
		p:  parse_small(settings[2][2..])!
	}
	if !cost.valid() {
		return error('scrypt parameters out of range')
	}
	salt := ab64_decode(parts[1])!
	key := ab64_decode(parts[2])!
	if salt.len < 8 || salt.len > 64 || key.len != key_bytes {
		return error('malformed scrypt record')
	}
	return Record{
		cost: cost
		salt: salt
		key:  key
	}
}

fn format_record(cost Cost, salt []u8, key []u8) string {
	return '${scrypt_prefix}ln=${cost.ln},r=${cost.r},p=${cost.p}$' + ab64_encode(salt) + r'$' +
		ab64_encode(key)
}

// Overwrite a secret before its memory goes back to the allocator.
pub fn wipe(mut secret []u8) {
	for i in 0 .. secret.len {
		secret[i] = 0
	}
}

pub fn random_bytes(count int) ![]u8 {
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

// What a new password must satisfy. This is a floor, not an estimate of
// strength: the cost of each guess is what scrypt is for.
pub fn check_new_password(name string, password []u8) ! {
	if password.len < min_password {
		return error('the password must be at least ${min_password} characters')
	}
	if password.len > max_password {
		return error('the password is too long')
	}
	mut same := true
	for i in 1 .. password.len {
		if password[i] == 0 || password[i] == `\n` {
			return error('the password contains a character that cannot be typed')
		}
		if password[i] != password[0] {
			same = false
		}
	}
	if password[0] == 0 || password[0] == `\n` {
		return error('the password contains a character that cannot be typed')
	}
	if same {
		return error('the password is one character repeated')
	}
	if password.bytestr().to_lower() == name.to_lower() {
		return error('the password is the account name')
	}
}

fn scrypt_key(password []u8, salt []u8, cost Cost) ![]u8 {
	return scrypt.scrypt(password, salt, u64(1) << cost.ln, cost.r, cost.p, u64(key_bytes)) or {
		return error('scrypt failed')
	}
}

// The record for a password, with a salt of its own.
pub fn hash_password(password []u8, cost Cost) !string {
	if !cost.valid() {
		return error('scrypt parameters out of range')
	}
	if password.len == 0 || password.len > max_password {
		return error('invalid password length')
	}
	salt := random_bytes(salt_bytes)!
	mut key := scrypt_key(password, salt, cost)!
	record := format_record(cost, salt, key)
	wipe(mut key)
	return record
}

// A salt and key that belong to nobody, checked when there is no record to
// check, so that a name that does not exist costs what one that does costs.
const decoy_salt = [u8(0x76), 0x69, 0x6e, 0x69, 0x78, 0x2d, 0x64, 0x65, 0x63, 0x6f, 0x79, 0x2d,
	0x73, 0x61, 0x6c, 0x74]

// Whether `password` is the one a shadow record was made from. A locked
// record, a record that is not scrypt and a missing record all answer no,
// after the same work as a real comparison.
pub fn verify_password(hash string, password []u8) bool {
	return verify_password_at(hash, password, default_cost)
}

// The same, with the cost of the comparison that is made when there is no
// record to compare with.
pub fn verify_password_at(hash string, password []u8, decoy Cost) bool {
	usable := password.len > 0 && password.len <= max_password
	record := parse_record(hash) or {
		// Includes '*', '!...' and the empty field: none of them is ever a
		// match, least of all for an empty password.
		probe := if usable { password } else { decoy_salt }
		mut wasted := scrypt_key(probe, decoy_salt, decoy) or { return false }
		wipe(mut wasted)
		return false
	}
	probe := if usable { password } else { decoy_salt }
	mut key := scrypt_key(probe, record.salt, record.cost) or { return false }
	same := subtle.constant_time_compare(key, record.key) == 1
	wipe(mut key)
	return same && usable
}

// Whether a record that just matched should be replaced by one at `cost`.
pub fn needs_rehash(hash string, cost Cost) bool {
	record := parse_record(hash) or { return false }
	return record.cost.work() < cost.work() || record.salt.len < salt_bytes
}

pub fn is_locked(hash string) bool {
	return hash.starts_with(lock_prefix)
}

// Whether any password at all can match this record.
pub fn has_password(hash string) bool {
	parse_record(hash) or { return false }
	return true
}

// The record the desktop's registration wrote before there were accounts:
// eight `key=value` lines with a hex name, salt and scrypt key. Returns the
// name the person typed and a shadow record for the same password.
pub fn import_registration(record string) !(string, string) {
	if record.len == 0 || record.len > 1024 {
		return error('not a registration record')
	}
	lines := record.trim_space().split_into_lines()
	if lines.len != 8 || lines[0] != 'version=1' || !lines[1].starts_with('name=')
		|| lines[2] != 'kdf=scrypt' || lines[3] != 'n=16384' || lines[4] != 'r=8'
		|| lines[5] != 'p=1' || !lines[6].starts_with('salt=') || !lines[7].starts_with('hash=') {
		return error('not a registration record')
	}
	name := hex.decode(lines[1][5..]) or { return error('registration record: invalid name') }
	salt := hex.decode(lines[6][5..]) or { return error('registration record: invalid salt') }
	key := hex.decode(lines[7][5..]) or { return error('registration record: invalid hash') }
	if name.len == 0 || name.len > 48 || salt.len != 16 || key.len != key_bytes {
		return error('registration record: invalid field length')
	}
	return name.bytestr(), format_record(Cost{ ln: 14, r: 8, p: 1 }, salt, key)
}

// A login name for a person's display name: its letters and digits in lower
// case, other runs replaced by one hyphen. The registration used the same
// rule to name the home directory, so an imported account keeps its home.
pub fn login_name_for(display string) string {
	mut out := []u8{cap: display.len}
	mut separator := false
	for i in 0 .. display.len {
		mut ch := display[i]
		if ch >= `A` && ch <= `Z` {
			ch += 32
		}
		if (ch >= `a` && ch <= `z`) || (ch >= `0` && ch <= `9`) {
			if separator && out.len > 0 {
				out << `-`
			}
			out << ch
			separator = false
		} else if out.len > 0 {
			separator = true
		}
	}
	mut name := out.bytestr()
	if name.len > max_name {
		name = name[..max_name].trim_right('-')
	}
	if name.len == 0 {
		return 'user'
	}
	if name[0] >= `0` && name[0] <= `9` {
		name = ('u' + name)
		if name.len > max_name {
			name = name[..max_name].trim_right('-')
		}
	}
	return name
}
