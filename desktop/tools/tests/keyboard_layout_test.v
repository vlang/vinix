// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

__global (
	keyboard_test_caps_queries int
)

fn keyboard_test_counting_caps(_ int) bool {
	keyboard_test_caps_queries++
	return false
}

fn keyboard_test_input(caps bool) KeyboardInput {
	return KeyboardInput{
		read_caps: if caps {
			fn (_ int) bool {
				return true
			}
		} else {
			fn (_ int) bool {
				return false
			}
		}
	}
}

fn keyboard_test_settings(layout KeyboardLayout) Settings {
	return Settings{
		keyboard_layouts: KeyboardLayout.us.bit() | layout.bit()
		keyboard_layout:  layout
	}
}

// keyboard_typed is what `keys`, as the console delivers them, types in one
// read with the given input source.
fn keyboard_typed(layout KeyboardLayout, keys string) string {
	mut input := keyboard_test_input(false)
	mut settings := keyboard_test_settings(layout)
	text, switched := input.translate(keys, mut settings, -1, 0)
	assert !switched
	return text
}

fn keyboard_typed_with_caps(layout KeyboardLayout, keys string) string {
	mut input := keyboard_test_input(true)
	mut settings := keyboard_test_settings(layout)
	text, _ := input.translate(keys, mut settings, -1, 0)
	return text
}

fn keyboard_test_element(root ui2.Element, id string) ?ui2.Element {
	if root.id == id {
		return root
	}
	for child in root.children {
		found := keyboard_test_element(child, id) or { continue }
		return found
	}
	return none
}

fn test_keyboard_tables_cover_every_key() {
	assert keymap_us_lower.len == keymap_key_count
	assert keymap_us_upper.len == keymap_key_count
	for layout in keyboard_layouts {
		keymap := keymap_for(layout) or {
			assert layout == .us
			continue
		}
		assert keymap.lower.len == keymap_key_count, layout.title()
		assert keymap.upper.len == keymap_key_count, layout.title()
		assert keymap.option.len == keymap_key_count, layout.title()
		assert keyboard_layout_from_code(layout.code())? == layout
		assert layout.badge().len == 2
	}
	// Every printable US byte names a key.
	for b in 0x20 .. 0x7f {
		if b != 0x20 {
			assert keymap_us_slots[b] >= 0, 'US ${rune(b)}'
		}
	}
}

fn test_keyboard_us_input_is_returned_as_it_came() {
	mut input := keyboard_test_input(false)
	mut settings := Settings{}
	keys := 'hello\x1b[A\x03§'
	text, switched := input.translate(keys, mut settings, -1, 0)
	assert !switched
	assert text.str == keys.str
	// Without a second input source Ctrl-Space still reaches the application.
	nul, _ := input.translate('\x00', mut settings, -1, 0)
	assert nul == '\x00'
}

fn test_keyboard_russian_letters_punctuation_and_shift() {
	assert keyboard_typed(.russian, 'ghbdtn') == 'привет'
	assert keyboard_typed(.russian, 'Ghbdtn? Vbh!') == 'Привет, Мир!'
	assert keyboard_typed(.russian, '`~[]{};\':",.<>/') == 'ёЁхъХЪжэЖЭбюБЮ.'
	assert keyboard_typed(.russian, '@#$^&') == '"№;:?'
	assert keyboard_typed(.russian, '\\|§±') == '\\//|'
}

fn test_keyboard_caps_lock_capitalises_letters_on_any_key() {
	// The console applied Caps Lock to the US letters already: `Q` came from
	// the q key. The Russian letters on US punctuation need it applied here.
	assert keyboard_typed_with_caps(.russian, 'Q;[') == 'ЙЖХ'
	// Shift with Caps Lock types small letters on both kinds of key.
	assert keyboard_typed_with_caps(.russian, 'q:') == 'йж'
	// Caps Lock leaves a key that is not a letter in the layout alone, even
	// where the US layout has a letter: French m is on the US comma key, and
	// its US m key types a comma.
	assert keyboard_typed_with_caps(.french, 'M') == ','
	assert keyboard_typed_with_caps(.french, ';') == 'M'
	assert keyboard_typed_with_caps(.german, '[;\'') == 'ÜÖÄ'
	assert keyboard_typed_with_caps(.german, '1-') == '1ß'
	// Caps Lock is only asked for when a key needs it, and once per read.
	keyboard_test_caps_queries = 0
	mut input := KeyboardInput{
		read_caps: keyboard_test_counting_caps
	}
	mut settings := keyboard_test_settings(.russian)
	input.translate('ghbdtn', mut settings, -1, 0)
	assert keyboard_test_caps_queries == 0
	input.translate(';\'[', mut settings, -1, 0)
	assert keyboard_test_caps_queries == 1
}

fn test_keyboard_german_french_spanish_portuguese_letters() {
	assert keyboard_typed(.german, 'Yyzz[;\'-') == 'Zzyyüöäß'
	assert keyboard_typed(.german, '§±/?') == '<>-_'
	assert keyboard_typed(.french, 'qwertyazm;') == 'azertyqw,m'
	assert keyboard_typed(.french, '1234567890!@#') == '&é"\'(-è_çà123'
	assert keyboard_typed(.spanish, ';:\\|=+') == 'ñÑçÇ¡¿'
	assert keyboard_typed(.portuguese, ";:'\"=+") == 'çÇºª«»'
}

fn test_keyboard_dead_keys_compose_accents() {
	// German: ´ is left of Backspace, ^ left of 1, ` is Shift-´.
	assert keyboard_typed(.german, '=e=E`a+o') == 'éÉâò'
	// Spanish: ´ and ¨ right of L, ` and ^ right of P.
	assert keyboard_typed(.spanish, '\'a"u[e{o') == 'áüèô'
	// French: ^ and ¨ right of P.
	assert keyboard_typed(.french, '[e{i') == 'êï'
	// Portuguese: ~ and ^ left of Return, ´ and ` right of +.
	assert keyboard_typed(.portuguese, '\\a|o]e}a') == 'ãôéà'
	// Space or the same dead key again types the accent itself.
	assert keyboard_typed(.german, '= ``') == '´^'
	// A letter the accent has no form for keeps both.
	assert keyboard_typed(.german, '=x') == '´x'
	// A second, different dead key types the first accent and waits.
	assert keyboard_typed(.spanish, '[\'e') == '`é'
	// Backspace and the other control keys drop a waiting accent.
	assert keyboard_typed(.german, '=\x7fe') == '\x7fe'
	// An accent typed at the end of one read lands on the next read's letter.
	mut input := keyboard_test_input(false)
	mut settings := keyboard_test_settings(.french)
	first, _ := input.translate('[', mut settings, -1, 0)
	assert first == ''
	second, _ := input.translate('o', mut settings, -1, 0)
	assert second == 'ô'
}

fn test_keyboard_option_types_the_altgr_level() {
	assert keyboard_typed(.german, '\x1bq\x1be\x1b7\x1b8\x1b9\x1b0\x1b-\x1b]\x1bm\x1b§') == '@€{[]}\\~µ|'
	assert keyboard_typed(.french, '\x1b0\x1b3\x1b4\x1b5\x1b6\x1b8\x1b-\x1b=\x1be') == '@#{[|\\]}€'
	assert keyboard_typed(.spanish, '\x1b2\x1b3\x1b1\x1b`\x1b[\x1b]\x1b\'\x1b\\\x1be') == '@#|\\[]{}€'
	assert keyboard_typed(.portuguese, '\x1b2\x1b7\x1b8\x1b9\x1b0\x1b§\x1be') == '@{[]}\\€'
	// Option on a dead key waits for the letter too.
	assert keyboard_typed(.portuguese, '\x1b[u') == 'ü'
	// Caps Lock does not stop Option-Q typing @ on a German keyboard.
	assert keyboard_typed_with_caps(.german, '\x1bQ') == '@'
	// Without an AltGr character the chord stays Meta on the US key, so
	// Alt-b and Alt-f still move by words in a shell.
	assert keyboard_typed(.german, '\x1bb\x1bf') == '\x1bb\x1bf'
	assert keyboard_typed(.russian, '\x1bf\x1b.') == '\x1bf\x1b.'
	assert keyboard_typed(.german, '\x1bQ') == '\x1bQ'
}

fn test_keyboard_option_bracket_is_told_apart_from_a_sequence() {
	// Spanish types [ with Option on the key right of P, which is also how
	// every CSI starts. What follows says which it was.
	assert keyboard_typed(.spanish, '\x1b[\x1b]') == '[]'
	assert keyboard_typed(.spanish, '\x1b[x') == '[x'
	assert keyboard_typed(.spanish, '\x1b[A\x1b[3~\x1b[57444;1:3u') == '\x1b[A\x1b[3~\x1b[57444;1:3u'
	// At the end of a read it waits for the next one: nothing, or a key
	// pressed later, settles it as Option-[...
	mut input := keyboard_test_input(false)
	mut settings := keyboard_test_settings(.spanish)
	held, _ := input.translate('\x1b[', mut settings, -1, 0)
	assert held == ''
	assert input.escape == .bracket
	settled, _ := input.translate('', mut settings, -1, 1)
	assert settled == '['
	input.translate('\x1b[', mut settings, -1, 100)
	later, _ := input.translate('A', mut settings, -1, 100 + keyboard_sequence_gap_ms + 1)
	assert later == '[A'
	// ...and the rest of a sequence arriving at once makes it that sequence.
	input.translate('\x1b[', mut settings, -1, 200)
	rest, _ := input.translate('1;9A', mut settings, -1, 201)
	assert rest == '\x1b[1;9A'
	// Portuguese has the diaeresis there, which then waits for its letter.
	assert keyboard_typed(.portuguese, '\x1b[u') == 'ü'
	// Layouts with nothing on Option-[ never hold it back.
	mut russian := keyboard_test_input(false)
	mut russian_settings := keyboard_test_settings(.russian)
	passed, _ := russian.translate('\x1b[', mut russian_settings, -1, 0)
	assert passed == '\x1b['
	mut desktop := Desktop{}
	desktop.settings = keyboard_test_settings(.spanish)
	desktop.keyboard = keyboard_test_input(false)
	desktop.dirty = false
	desktop.type_with_layout('\x1b[', -1)
	assert desktop.dirty
}

fn test_keyboard_games_and_virtual_machines_get_the_us_keys() {
	mut desktop := Desktop{}
	desktop.settings = keyboard_test_settings(.russian)
	desktop.keyboard = keyboard_test_input(false)
	desktop.apps << NativeApp(&RemoteApp{
		keyboard: true
		us_keys:  true
	})
	desktop.windows << Window{
		id:        7
		app_index: 0
	}
	desktop.focus = 7
	assert desktop.focused_app_wants_us_keys()
	keys := 'wasd\x1b[A'
	assert desktop.type_with_layout(keys, -1).str == keys.str
	desktop.focus = 0
	assert !desktop.focused_app_wants_us_keys()
	assert desktop.type_with_layout('wasd', -1) == 'цфыв'
}

fn test_keyboard_sequences_and_control_bytes_pass_untouched() {
	for layout in keyboard_layouts {
		for keys in ['\x1b[A\x1b[D', '\x1b[119;9u', '\x1b[9;10u', '\x1b[57444;1:3u', '\x1bOP',
			'\x1b[3~', '\x03\x17\t\r\x7f', '\x1b\x1b[A', '\x1b\x7f', '\x1b'] {
			assert keyboard_typed(layout, keys) == keys, '${layout.title()} ${keys.bytes()}'
		}
	}
	// A letter after a sequence is typed in the layout again.
	assert keyboard_typed(.russian, '\x1b[Af') == '\x1b[Aа'
}

fn test_keyboard_sequence_split_across_reads() {
	mut input := keyboard_test_input(false)
	mut settings := keyboard_test_settings(.russian)
	head, _ := input.translate('\x1b[1', mut settings, -1, 1000)
	assert head == '\x1b[1'
	tail, _ := input.translate(';5Df', mut settings, -1, 1010)
	assert tail == ';5Dа'
	// An escape that ended a read and a key pressed well after it are two keys.
	escape, _ := input.translate('\x1b', mut settings, -1, 2000)
	assert escape == '\x1b'
	later, _ := input.translate('[f', mut settings, -1, 2000 + keyboard_sequence_gap_ms + 1)
	assert later == 'ха'
	// The same bytes arriving at once are an Option chord whose escape has
	// already gone out, so they stay Meta.
	input.translate('\x1b', mut settings, -1, 3000)
	meta, _ := input.translate('f', mut settings, -1, 3005)
	assert meta == 'f'
	// An empty read ends any sequence the last one was inside of.
	input.translate('\x1b[', mut settings, -1, 4000)
	input.translate('', mut settings, -1, 4001)
	after, _ := input.translate('f', mut settings, -1, 4002)
	assert after == 'а'
}

fn test_keyboard_ctrl_space_cycles_enabled_input_sources() {
	mut input := keyboard_test_input(false)
	mut settings := Settings{
		keyboard_layouts: KeyboardLayout.us.bit() | KeyboardLayout.russian.bit() | KeyboardLayout.german.bit()
	}
	text, switched := input.translate('a\x00a\x00y\x00a', mut settings, -1, 0)
	assert switched
	assert text == 'aфza'
	assert settings.keyboard_layout == .us
	_, again := input.translate('\x00', mut settings, -1, 0)
	assert again
	assert settings.keyboard_layout == .russian
	// Switching drops an accent that was waiting.
	settings.keyboard_layout = .german
	dead, _ := input.translate('=', mut settings, -1, 0)
	assert dead == ''
	switched_away, _ := input.translate('\x00e', mut settings, -1, 0)
	assert switched_away == 'e'
	assert settings.keyboard_layout == .us
	assert keyboard_next_layout(KeyboardLayout.french.bit(), .french) == .french
	assert keyboard_next_layout(keyboard_layout_all_mask, .portuguese) == .us
}

fn test_keyboard_desktop_shows_and_retires_the_input_source_panel() {
	mut desktop := Desktop{}
	desktop.canvas.width = 1280
	desktop.canvas.height = 800
	desktop.settings.keyboard_layouts = KeyboardLayout.us.bit() | KeyboardLayout.spanish.bit()
	desktop.keyboard = keyboard_test_input(false)
	if _ := desktop.keyboard_hud_element() {
		assert false, 'panel before Ctrl-Space'
	}
	assert desktop.keyboard_hud_wait(1000) == 1000
	typed := desktop.type_with_layout('\x00;', -1)
	assert typed == 'ñ'
	assert desktop.settings.keyboard_layout == .spanish
	assert desktop.dirty
	hud := desktop.keyboard_hud_element() or { panic('missing input-source panel') }
	assert hud.children.len == 2
	assert hud.children[1].text == 'Spanish'
	wait := desktop.keyboard_hud_wait(5000)
	assert wait > 0 && wait <= keyboard_hud_ms
	desktop.keyboard.hud_until = monotonic_millis() - 1
	desktop.dirty = false
	desktop.type_with_layout('', -1)
	assert desktop.keyboard.hud_until == 0
	assert desktop.dirty
	if _ := desktop.keyboard_hud_element() {
		assert false, 'panel after it timed out'
	}
}

// keyboard_test_frame builds and renders the desktop, so its hit targets are
// the ones a click would meet, and answers the taskbar's input badge.
fn keyboard_test_frame(mut d Desktop) string {
	tree := d.build_tree()
	d.render(tree)
	mut badge := ''
	if button := keyboard_test_element(tree, action_tray_input) {
		badge = button.children[0].children[0].text.clone()
	}
	free_tree(tree)
	return badge
}

fn test_keyboard_taskbar_menu_lists_and_chooses_input_sources() {
	mut d := Desktop{
		canvas: new_scaled_canvas(1280, 720, 1280, 720, 1)
		fonts:  load_fonts()
	}
	defer { unsafe { free(d.canvas.pixels) } }
	d.tray.preferences_loaded = true
	d.update_taskbar_clock_at(1_790_000_000)
	// One input source has nothing to switch between, so no button.
	assert keyboard_test_frame(mut d) == ''
	if _ := d.hit_target_named(action_tray_input) {
		assert false, 'input menu with a single input source'
	}
	clock_alone := d.taskbar_layout(0)

	d.settings.keyboard_layouts = KeyboardLayout.us.bit() | KeyboardLayout.russian.bit() | KeyboardLayout.german.bit()
	assert keyboard_test_frame(mut d) == 'EN'
	button := d.hit_target_named(action_tray_input) or { panic('missing input menu button') }
	assert d.tooltip_text(action_tray_input) == 'English (US)'
	// It sits right against the time, in the room the clock's box leaves
	// free, so a 24-hour clock costs the window buttons nothing.
	layout := d.taskbar_layout(0)
	assert layout == clock_alone
	clock_text := d.clock_text_width()
	assert clock_text > 0 && clock_text < taskbar_clock_width
	assert button.x + button.width + taskbar_item_gap == layout.status_right - clock_text
	// A 12-hour clock with seconds is wider; the taskbar then makes up only
	// the difference, and the button still clears the build stamp.
	d.settings.clock_24_hour = false
	d.taskbar_clock_sampled = false
	// 22:13:20 UTC, drawn as 10:13:20 PM.
	d.update_taskbar_clock_at(1_790_000_000 + 8 * 3600)
	assert d.taskbar_clock_time == '10:13:20 PM'
	keyboard_test_frame(mut d)
	wide := d.hit_target_named(action_tray_input) or { panic('missing input menu button') }
	wide_layout := d.taskbar_layout(0)
	assert d.input_menu_span() > 0
	assert wide_layout.status_width == clock_alone.status_width + d.input_menu_span()
	assert wide.x + wide.width + taskbar_item_gap == wide_layout.status_right - d.clock_text_width()
	build_end := wide_layout.status_right - wide_layout.status_width + wide_layout.tray_span +
		taskbar_build_width
	assert wide.x >= build_end + taskbar_item_gap
	d.settings.clock_24_hour = true

	d.handle_tray_action(action_tray_input)
	assert d.tray.flyout == .input
	keyboard_test_frame(mut d)
	russian_index := keyboard_layouts.index(KeyboardLayout.russian)
	russian := d.hit_target_named(tray_input_layout_actions[russian_index]) or {
		panic('missing Russian row')
	}
	d.hit_target_named(tray_input_layout_actions[keyboard_layouts.index(KeyboardLayout.german)]) or {
		panic('missing German row')
	}
	d.hit_target_named(action_tray_keyboard_settings) or { panic('missing Keyboard settings') }
	if _ := d.hit_target_named(tray_input_layout_actions[keyboard_layouts.index(KeyboardLayout.spanish)]) {
		assert false, 'an input source that is off in the menu'
	}
	assert russian.y + russian.height <= d.canvas.height - taskbar_height

	// Picking one switches typing to it, drops a waiting accent and closes
	// the menu.
	d.keyboard.dead = dead_acute
	d.on_pointer_down(russian.x + 4, russian.y + 4)
	assert d.settings.keyboard_layout == .russian
	assert d.keyboard.dead == 0
	assert d.tray.flyout == .none_
	assert keyboard_test_frame(mut d) == 'RU'
	assert d.tooltip_text(action_tray_input) == 'Russian'
	assert d.type_with_layout('q', -1) == 'й'

	// Only enabled input sources can be chosen.
	d.handle_tray_action(tray_input_layout_actions[keyboard_layouts.index(KeyboardLayout.spanish)])
	d.handle_tray_action('${tray_input_layout_prefix}99')
	assert d.settings.keyboard_layout == .russian

	// Settings turning the others off takes the button and its menu away.
	d.handle_tray_action(action_tray_input)
	assert d.tray.flyout == .input
	d.settings.keyboard_layouts = KeyboardLayout.russian.bit()
	assert keyboard_test_frame(mut d) == ''
	assert d.tray.flyout == .none_
}

fn test_keyboard_settings_pane_enables_and_selects_input_sources() {
	mut desktop := Desktop{}
	mut app := SettingsApp{
		desktop:  &desktop
		category: .keyboard
	}
	keyboard_index := settings_categories.index(SettingsCategory.keyboard)
	assert keyboard_index >= 0
	assert SettingsCategory.keyboard.title() == 'Keyboard'

	mut root := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	keyboard_test_element(root, '${settings_action_category}${keyboard_index}') or {
		panic('missing Keyboard category')
	}
	us_toggle := keyboard_test_element(root, '${settings_action_keyboard_enable}0') or {
		panic('missing English toggle')
	}
	assert us_toggle.checked && us_toggle.accessibility_role == 'checkbox'
	russian_index := keyboard_layouts.index(KeyboardLayout.russian)
	if _ := keyboard_test_element(root, '${settings_action_keyboard_current}${russian_index}') {
		assert false, 'a layout that is off offered as the current one'
	}

	// Turn Russian on, then type with it.
	app.handle('${settings_action_keyboard_enable}${russian_index}') or { panic(err) }
	assert desktop.settings.keyboard_layouts == KeyboardLayout.us.bit() | KeyboardLayout.russian.bit()
	assert desktop.settings.keyboard_layout == .us
	root = app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
	keyboard_test_element(root, '${settings_action_keyboard_current}${russian_index}') or {
		panic('missing Russian choice')
	}
	app.handle('${settings_action_keyboard_current}${russian_index}') or { panic(err) }
	assert desktop.settings.keyboard_layout == .russian

	// Turning off the current input source moves typing to the first left on,
	// and the last one cannot be turned off.
	app.handle('${settings_action_keyboard_enable}${russian_index}') or { panic(err) }
	assert desktop.settings.keyboard_layouts == KeyboardLayout.us.bit()
	assert desktop.settings.keyboard_layout == .us
	app.handle('${settings_action_keyboard_enable}0') or { panic(err) }
	assert desktop.settings.keyboard_layouts == KeyboardLayout.us.bit()
	// A layout that is off cannot be chosen, and out-of-range ids do nothing.
	app.handle('${settings_action_keyboard_current}${russian_index}') or { panic(err) }
	app.handle('${settings_action_keyboard_enable}99') or { panic(err) }
	assert desktop.settings.keyboard_layout == .us
	assert keyboard_settings_valid(desktop.settings.keyboard_layouts, desktop.settings.keyboard_layout)

	// Every layout's pane builds, and says what it types.
	for layout in keyboard_layouts {
		desktop.settings.keyboard_layouts = keyboard_layout_all_mask
		desktop.settings.keyboard_layout = layout
		app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
		preview := keyboard_previews[int(layout)]
		assert preview.letters.starts_with('Types: ')
	}
	assert keyboard_previews[int(KeyboardLayout.russian)].letters == 'Types: й ц у к е н г ш щ з х ъ'
	assert keyboard_previews[int(KeyboardLayout.german)].option.contains('@')
	assert keyboard_previews[int(KeyboardLayout.french)].accents.contains('^')
	assert keyboard_previews[int(KeyboardLayout.russian)].accents == ''
}

fn test_keyboard_settings_cross_the_application_protocol() {
	state := AppWireState{
		settings: Settings{
			keyboard_layouts: KeyboardLayout.us.bit() | KeyboardLayout.portuguese.bit()
			keyboard_layout:  .portuguese
		}
	}
	mut out := []u8{}
	wire_put_state(mut out, state)
	assert out.len == app_request_header_size - 20
	mut reader := WireReader{
		data: out
	}
	decoded := wire_take_state(mut reader) or { panic(err) }
	assert decoded.settings == state.settings

	// A current input source that is not enabled, or none enabled at all, is
	// a damaged message.
	for settings in [Settings{
		keyboard_layouts: KeyboardLayout.us.bit()
		keyboard_layout:  .german
	}, Settings{
		keyboard_layouts: 0
	}] {
		mut bad := []u8{}
		wire_put_state(mut bad, AppWireState{ settings: settings })
		mut bad_reader := WireReader{
			data: bad
		}
		accepted := wire_take_state(mut bad_reader) or { continue }
		assert false, 'accepted ${accepted.settings.keyboard_layouts}'
	}

	// Settings choosing a new input source drops an accent the compositor
	// was holding for the old one.
	mut desktop := Desktop{}
	desktop.keyboard.dead = dead_acute
	apply_app_state(mut desktop, state)
	assert desktop.settings.keyboard_layout == .portuguese
	assert desktop.keyboard.dead == 0
}
