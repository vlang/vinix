// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module keyringcore

const cheap = Cost{
	ln: 10
}

fn unlock_fails(store Store, password string) bool {
	store.unlock(password.bytes()) or { return true }
	return false
}

fn recover_fails(store Store, recovery string) bool {
	store.unlock_with_recovery(recovery) or { return true }
	return false
}

fn get_fails(store Store, key []u8, service string, account string) bool {
	store.get(key, service, account) or { return true }
	return false
}

fn list_fails(store Store, key []u8) bool {
	store.list(key) or { return true }
	return false
}

fn put_fails(mut store Store, key []u8, item Item) bool {
	store.put(key, item) or { return true }
	return false
}

fn delete_fails(mut store Store, key []u8, service string, account string) bool {
	store.delete(key, service, account) or { return true }
	return false
}

fn password_fails(mut store Store, key []u8) bool {
	store.set_password(key, 'new password'.bytes(), cheap) or { return true }
	return false
}

fn recovery_fails(mut store Store, key []u8) bool {
	store.new_recovery(key) or { return true }
	return false
}

fn parse_fails(text string) bool {
	parse(text) or { return true }
	return false
}

fn test_create_store_and_use() ! {
	mut store, key, recovery := create('login password'.bytes(), cheap)!
	assert key.len == 32
	assert recovery.len == 39 && recovery.count('-') == 7
	store.put(key, service: 'wifi', account: 'Home Network', secret: 'hunter2hunter2'.bytes())!
	store.put(key, service: 'mail.example.org', account: 'alex', secret: [u8(0), 1, 2, 255])!
	assert store.get(key, 'wifi', 'Home Network')! == 'hunter2hunter2'.bytes()
	assert store.get(key, 'mail.example.org', 'alex')! == [u8(0), 1, 2, 255]
	listed := store.list(key)!
	assert listed.len == 2 && listed[0].service == 'wifi' && listed[0].secret.len == 0
	// The same name again replaces.
	store.put(key, service: 'wifi', account: 'Home Network', secret: 'changed'.bytes())!
	assert store.count() == 2
	assert store.get(key, 'wifi', 'Home Network')! == 'changed'.bytes()
	store.delete(key, 'wifi', 'Home Network')!
	assert store.count() == 1
	assert get_fails(store, key, 'wifi', 'Home Network')
	assert delete_fails(mut store, key, 'wifi', 'Home Network')
	for bad in [
		Item{
			service: ''
			account: 'a'
			secret:  [u8(1)]
		},
		Item{
			service: 'a\nb'
			account: 'a'
			secret:  [u8(1)]
		},
		Item{
			service: 'a'
			account: 'a'
		},
		Item{
			service: 'a'
			account: 'a'
			secret:  []u8{len: max_secret + 1}
		},
	] {
		assert put_fails(mut store, key, bad), bad.service
	}
}

fn test_the_file_gives_nothing_away() ! {
	mut store, key, _ := create('login password'.bytes(), cheap)!
	store.put(key, service: 'bank.example.com', account: 'alexander', secret: 'correct horse'.bytes())!
	text := store.format()
	for word in ['bank', 'example', 'alexander', 'correct', 'horse', 'login'] {
		assert !text.contains(word), word
	}
	assert text.starts_with('vinix-keyring 1\nslot password ln=10,r=8,p=1 ')
	// And reads back, to a store that opens with the same things.
	back := parse(text)!
	assert back.format() == text
	again := back.unlock('login password'.bytes())!
	assert again == key
	assert back.get(again, 'bank.example.com', 'alexander')! == 'correct horse'.bytes()
}

fn test_wrong_keys() ! {
	mut store, key, recovery := create('login password'.bytes(), cheap)!
	store.put(key, service: 's', account: 'a', secret: 'x'.bytes())!
	assert unlock_fails(store, 'login passwore')
	assert unlock_fails(store, '')
	mut other := key.clone()
	other[0] ^= 1
	assert get_fails(store, other, 's', 'a')
	assert put_fails(mut store, other, Item{
		service: 's'
		account: 'b'
		secret:  'x'.bytes()
	})
	assert list_fails(store, other)
	assert password_fails(mut store, other)
	assert recovery_fails(mut store, other)
	// The right recovery key, however it is typed, and wrong ones.
	assert store.unlock_with_recovery(recovery)! == key
	assert store.unlock_with_recovery(recovery.to_lower().replace('-', ' '))! == key
	mut wrong := recovery.bytes()
	wrong[0] = if wrong[0] == `A` { `B` } else { `A` }
	assert recover_fails(store, wrong.bytestr())
	assert recover_fails(store, 'not-a-key')
	assert recover_fails(store, recovery + 'A')
	assert recover_fails(store, '')
}

fn test_password_change_and_recovery() ! {
	mut store, key, recovery := create('first password'.bytes(), cheap)!
	store.put(key, service: 's', account: 'a', secret: 'kept'.bytes())!
	before := store.format().split_into_lines()
	store.set_password(key, 'second password'.bytes(), cheap)!
	// No secret was touched: only the password's wrapping of the key.
	after := store.format().split_into_lines()
	assert after[1] != before[1] && after[2] == before[2] && after[3] == before[3]
		&& after[4] == before[4]
	assert store.unlock('second password'.bytes())! == key
	assert unlock_fails(store, 'first password')
	// An administrator set a new login password without knowing the old
	// one: the store does not open with it. The recovery key opens it, and
	// then the new password is made to.
	mut recovered := parse(store.format())!
	assert unlock_fails(recovered, 'set by an administrator')
	recovered_key := recovered.unlock_with_recovery(recovery)!
	recovered.set_password(recovered_key, 'set by an administrator'.bytes(), cheap)!
	assert recovered.get(recovered.unlock('set by an administrator'.bytes())!, 's', 'a')! == 'kept'.bytes()
	// A new recovery key retires the old one.
	fresh := recovered.new_recovery(recovered_key)!
	assert fresh != recovery
	assert recovered.unlock_with_recovery(fresh)! == recovered_key
	assert recover_fails(recovered, recovery)
}

fn test_tampering_is_noticed() ! {
	mut store, key, _ := create('login password'.bytes(), cheap)!
	store.put(key, service: 'one', account: 'a', secret: 'first'.bytes())!
	store.put(key, service: 'two', account: 'a', secret: 'second'.bytes())!
	lines := store.format().split_into_lines()
	// Two items with their encrypted halves exchanged: each is sealed under
	// its own id, so neither opens.
	first := lines[4].split(' ')
	second := lines[5].split(' ')
	mut swapped := lines.clone()
	swapped[4] = 'item ${first[1]} ${second[2]} ${second[3]}'
	swapped[5] = 'item ${second[1]} ${first[2]} ${first[3]}'
	crossed := parse(swapped.join('\n') + '\n')!
	assert get_fails(crossed, key, 'one', 'a')
	assert list_fails(crossed, key)
	// A check line with a character changed: the right password no longer
	// vouches for the store.
	check := lines[3].split(' ')
	mut changed := check[2].bytes()
	changed[4] = if changed[4] == `A` { `B` } else { `A` }
	mut tampered := lines.clone()
	tampered[3] = 'check ${check[1]} ${changed.bytestr()}'
	if damaged := parse(tampered.join('\n') + '\n') {
		assert unlock_fails(damaged, 'login password')
	}
	// The password slot of another store: its key is not this store's.
	other, _, _ := create('login password'.bytes(), cheap)!
	mut grafted := lines.clone()
	grafted[1] = other.format().split_into_lines()[1]
	assert unlock_fails(parse(grafted.join('\n') + '\n')!, 'login password')
}

fn test_parse_is_strict() ! {
	mut store, key, _ := create('login password'.bytes(), cheap)!
	store.put(key, service: 's', account: 'a', secret: 'x'.bytes())!
	good := store.format()
	lines := good.split_into_lines()
	for bad in [
		'',
		good[..good.len - 1],
		good.replace('vinix-keyring 1', 'vinix-keyring 2'),
		good.replace('ln=10', 'ln=30'),
		good.replace('ln=10', 'ln=010'),
		good.replace('slot recovery', 'slot password'),
		good + lines[4] + '\n', // the same item twice
		good.replace('item ', 'item x'),
		lines[..3].join('\n') + '\n', // no check line
		good.replace('\ncheck ', '\ncheck  '),
		good + 'trailer\n',
	] {
		assert parse_fails(bad), 'accepted: ${bad#[..60]}'
	}
}

fn test_recovery_key_text() ! {
	bytes := []u8{len: 20, init: u8(index * 13 + 1)}
	text := recovery_key_text(bytes)
	assert text.len == 39
	assert recovery_key_bytes(text)! == bytes
	for ch in text {
		assert ch == `-` || recovery_alphabet.contains_u8(ch)
	}
	// Nothing that looks like something else.
	for confusing in ['0', '1', 'O', 'I'] {
		assert !recovery_alphabet.contains(confusing)
	}
}
