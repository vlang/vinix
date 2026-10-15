// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

module main

import os
import ui2
import encoding.binary

fn app_selection_test_element(root ui2.Element, name string) ?ui2.Element {
	if root.id == name || root.action_id == name {
		return root
	}
	for child in root.children {
		if found := app_selection_test_element(child, name) {
			return found
		}
	}
	return none
}

fn app_selection_test_has_action_prefix(root ui2.Element, prefix string) bool {
	if root.action_id.starts_with(prefix) || root.id.starts_with(prefix) {
		return true
	}
	for child in root.children {
		if app_selection_test_has_action_prefix(child, prefix) {
			return true
		}
	}
	return false
}

fn app_selection_test_has_image(root ui2.Element, path string) bool {
	if root.image_path == path {
		return true
	}
	return root.children.any(app_selection_test_has_image(it, path))
}

fn app_selection_test_has_text(root ui2.Element, text string) bool {
	if root.text == text {
		return true
	}
	return root.children.any(app_selection_test_has_text(it, text))
}

fn app_selection_test_desktop() Desktop {
	return Desktop{
		canvas: Canvas{
			width:  1024
			height: 720
			scale:  1
		}
	}
}

// Host tests must not depend on which of these happen to exist on the build
// machine, so start from a state where nothing is installed.
fn app_selection_test_state() AppSelectionState {
	mut state := new_app_selection_state()
	for i in 0 .. state.installed.len {
		state.installed[i] = false
		state.available[i] = true
	}
	state.focus = 0
	return state
}

fn app_selection_test_button_label(mut state AppSelectionState) string {
	desktop := app_selection_test_desktop()
	begin_frame_elements()
	root := state.element(&desktop)
	defer { free_tree(root) }
	button := app_selection_test_element(root, action_apps_install) or {
		panic('missing install button')
	}
	return button.text
}

fn test_app_selection_offers_the_optional_apps_this_machine_can_install() {
	assert first_run_app_catalogue.map(it.title) == ['Firefox', 'Chromium', 'VOffice', 'Minecraft',
		'Blender', 'VLC', 'VSCodium', 'Zed', 'Neovim', 'KeePassXC', 'Discord', 'Telegram', 'Slack',
		'Spotify', 'OBS Studio', 'Steam', 'iOS']
	assert first_run_app_catalogue.map(it.package_name) == ['firefox', 'chromium', 'voffice',
		'minecraft', 'blender', 'vlc-qt', 'vscodium', 'zed', 'neovim', 'keepassxc', 'discord',
		'telegram-desktop', 'slack', 'spotify', 'obs-studio', 'steam', 'ios-runtime']
	$if arm64 {
		assert first_run_apps.len == first_run_app_catalogue.len
	} $else {
		// VOffice, Minecraft and the native iOS runner require AArch64.
		assert first_run_apps.len == first_run_app_catalogue.len - 3
		assert !first_run_apps.any(it.package_name in ['voffice', 'minecraft', 'ios-runtime'])
	}

	desktop := app_selection_test_desktop()
	mut state := app_selection_test_state()
	begin_frame_elements()
	root := state.element(&desktop)
	defer { free_tree(root) }

	assert root.kind == .screen
	assert app_selection_test_element(root, 'apps.window') != none
	assert app_selection_test_element(root, action_apps_install) != none
	assert app_selection_test_element(root, 'taskbar') == none
	assert !app_selection_test_has_action_prefix(root, 'task.')
	assert !app_selection_test_has_action_prefix(root, 'shortcut.')
	assert !app_selection_test_has_action_prefix(root, 'win.')
	assert !app_selection_test_has_action_prefix(root, 'apps.category.')
	for heading in first_run_category_headers {
		label := app_selection_test_element(root, heading) or { panic('missing category heading') }
		assert label.kind == .label && !label.clickable
	}
	assert app_selection_test_element(root, 'apps.toggle.firefox') != none
	assert app_selection_test_element(root, 'apps.toggle.keepassxc') != none
	for category in first_run_categories {
		for i, app in first_run_apps {
			if app.category == category {
				state.scroll_to(app_selection_row_y(i, state.columns) - app_selection_heading_height)
				break
			}
		}
		begin_frame_elements()
		tree := state.element(&desktop)
		for app in first_run_apps {
			if app.category != category {
				continue
			}
			row := app_selection_test_element(tree, app.action) or { panic('missing ${app.title}') }
			assert row.clickable
			assert app_selection_test_has_image(row, app.icon)
			assert !app_selection_test_has_image(row, 'builtin:check')
		}
		free_tree(tree)
	}
}

fn test_app_selection_clicks_toggle_apps_and_confirm() {
	mut state := app_selection_test_state()
	assert app_selection_test_button_label(mut state) == 'Continue'
	assert state.packages().len == 0

	state.handle_action('apps.toggle.chromium')
	state.handle_action('apps.toggle.firefox')
	state.handle_action('apps.toggle.chromium')
	assert state.selected_count() == 1
	assert app_selection_test_button_label(mut state) == 'Install 1 app'
	desktop := app_selection_test_desktop()
	begin_frame_elements()
	root := state.element(&desktop)
	firefox := app_selection_test_element(root, 'apps.toggle.firefox') or { panic('missing row') }
	chromium := app_selection_test_element(root, 'apps.toggle.chromium') or { panic('missing row') }
	assert app_selection_test_has_image(firefox, 'builtin:check')
	assert !app_selection_test_has_image(chromium, 'builtin:check')
	free_tree(root)

	state.handle_action('apps.toggle.chromium')
	assert app_selection_test_button_label(mut state) == 'Install 2 apps'
	// Installed in the order offered, not the order clicked.
	assert state.packages() == ['firefox', 'chromium']
	assert !state.complete
	$if arm64 {
		state.handle_action('apps.toggle.minecraft')
		assert state.packages() == ['firefox', 'chromium', 'minecraft']
		state.handle_action('apps.toggle.minecraft')
	}

	state.handle_action('unrelated.action')
	assert state.selected_count() == 2
	state.handle_action(action_apps_install)
	assert state.complete
}

fn test_app_selection_skips_apps_the_image_already_has() {
	mut state := app_selection_test_state()
	state.installed[0] = true
	state.focus = state.next_available(-1, 1)
	assert state.focus == 1
	state.handle_action('apps.toggle.firefox')
	assert state.selected_count() == 0
	assert state.packages().len == 0

	desktop := app_selection_test_desktop()
	begin_frame_elements()
	root := state.element(&desktop)
	defer { free_tree(root) }
	firefox := app_selection_test_element(root, 'apps.toggle.firefox') or {
		panic('missing Firefox row')
	}
	assert !firefox.clickable && !firefox.enabled
	assert app_selection_test_has_text(firefox, 'Installed')
	// Keyboard focus starts on the first app that can still be chosen.
	focus := app_selection_test_element(root, 'apps.focus') or { panic('missing focus ring') }
	chromium := app_selection_test_element(root, 'apps.toggle.chromium') or {
		panic('missing Chromium row')
	}
	assert focus.frame.y == chromium.frame.y - 1

	for i in 0 .. state.installed.len {
		state.installed[i] = true
	}
	assert state.all_installed()
	assert state.next_available(0, 1) == -1
}

fn test_app_selection_is_keyboard_driven() {
	mut state := app_selection_test_state()
	state.installed[1] = true
	state.key_input(' ')
	assert state.selected[0]
	expected := state.next_available(0, 1)
	state.key_input('\t')
	assert state.focus == expected
	assert first_run_apps[expected].category == .productivity
	state.key_input('\x1b[A')
	assert state.focus == 0
	last := state.next_available(0, -1)
	state.key_input('\x1b[A')
	assert state.focus == last
	state.key_input('\x1b[B')
	assert state.focus == 0
	state.key_input('2')
	assert state.packages() == ['firefox']
	// Larger catalogues must not interpret punctuation or letters as numbers.
	state.key_input(':;@ABCDEFG\x10\x11\x1b')
	assert state.packages() == ['firefox']
	state.key_input('\x1b[C')
	assert state.focus == expected
	state.key_input('\x1b[D')
	assert state.focus == 0
	assert !state.complete

	state.key_input('\r')
	assert state.complete
}

fn test_app_selection_pending_marker_lifecycle() {
	home := os.join_path(os.temp_dir(), 'vinix-app-selection-${os.getpid()}')
	os.mkdir(home) or { panic(err) }
	defer { os.rmdir_all(home) or {} }

	assert !desktop_app_selection_pending(home)
	assert desktop_mark_app_selection_pending(home)
	assert desktop_app_selection_pending(home)
	desktop_finish_app_selection(home)
	assert !desktop_app_selection_pending(home)
}

fn test_first_run_install_command_accepts_only_offered_packages() {
	assert first_run_install_command('') == ''
	assert first_run_install_command('gimp ; rm -rf /') == ''
	command := first_run_install_command('chromium firefox\nchromium firefox;reboot\n')
	assert command.contains('for app in chromium firefox; do ')
	assert command.contains('*) pkg install "\$app"')
	assert !command.contains('reboot')
	assert command.ends_with('exec /bin/zsh -i')
	$if !arm64 {
		// Not offered here, so not installed either.
		assert first_run_install_command('voffice minecraft') == ''
	}
}

fn test_app_selection_retains_choices_while_scrolling_and_counts_many_apps() {
	mut state := app_selection_test_state()
	for action in ['apps.toggle.firefox', 'apps.toggle.chromium', 'apps.toggle.blender',
		'apps.toggle.vlc', 'apps.toggle.neovim', 'apps.toggle.keepassxc'] {
		state.handle_action(action)
	}
	assert state.selected_count() == 6
	assert app_selection_test_button_label(mut state) == 'Install selected apps'
	state.scroll_to(app_selection_content_height(state.columns))
	state.handle_action('apps.toggle.discord')
	state.handle_action('apps.toggle.slack')
	state.handle_action('apps.toggle.spotify')
	state.handle_action('apps.toggle.steam')
	assert state.selected_count() == 10
	state.scroll_to(0)
	assert state.selected_count() == 10
	assert state.packages() == ['firefox', 'chromium', 'blender', 'vlc-qt', 'neovim', 'keepassxc',
		'discord', 'slack', 'spotify', 'steam']
}

fn test_app_selection_scrolling_keeps_rows_and_hit_targets_inside_the_list() {
	mut state := app_selection_test_state()
	for size in [[1024, 720]!, [640, 480]!] {
		desktop := Desktop{ canvas: Canvas{ width: size[0], height: size[1], scale: 1 } }
		layout := app_selection_layout(size[0], size[1])
		state.prepare_viewport(layout.list_height, layout.columns)
		for offset in [0, 45, 350, app_selection_content_height(state.columns)] {
			state.scroll_to(offset)
			begin_frame_elements()
			tree := state.element(&desktop)
			card := app_selection_test_element(tree, 'apps.window') or { panic('missing card') }
			note := app_selection_test_element(tree, 'apps.note') or { panic('missing note') }
			list := app_selection_test_element(tree, 'apps.list') or { panic('missing list') }
			assert list.frame.y + list.frame.height < note.frame.y
			assert list.frame.x + list.frame.width <= card.frame.width
			for app in first_run_apps {
				row := app_selection_test_element(tree, app.action) or { continue }
				assert row.frame.x >= 0 && row.frame.x + row.frame.width <= list.frame.width
				assert row.frame.y >= 0 && row.frame.y + row.frame.height <= list.frame.height
			}
			free_tree(tree)
		}
	}
}

fn test_app_selection_keyboard_reveals_each_app_in_display_order_and_wraps() {
	mut state := app_selection_test_state()
	desktop := app_selection_test_desktop()
	mut expected := []string{}
	for category in first_run_categories {
		for i, app in first_run_apps {
			if app.category == category && state.available[i] { expected << app.package_name }
		}
	}
	mut visited := []string{}
	for _ in 0 .. expected.len {
		begin_frame_elements()
		tree := state.element(&desktop)
		row := app_selection_test_element(tree, first_run_apps[state.focus].action) or {
			panic('keyboard focus scrolled off screen')
		}
		assert row.frame.height == app_selection_row_height
		visited << first_run_apps[state.focus].package_name
		free_tree(tree)
		state.key_input('\t')
	}
	assert visited == expected
	assert state.focus == 0
	state.key_input('\x1b[F')
	assert state.focus == state.next_available(-1, -1)
	state.key_input('\x1b[H')
	assert state.focus == 0
}

fn test_app_selection_wheel_and_scrollbar_reach_the_bottom_without_losing_choices() {
	mut state := app_selection_test_state()
	state.toggle(0)
	layout := app_selection_layout(1024, 480)
	mut desktop := Desktop{ canvas: Canvas{ width: 1024, height: 480, scale: 1 } }
	desktop.pointer_x = layout.x + 100
	desktop.pointer_y = layout.y + app_selection_row_top + 100
	state.pointer_input(PointerPacket{ scroll: -4 }, &desktop)
	assert state.scroll == 144
	assert state.selected[0]
	state.pointer_input(PointerPacket{ scroll: 100 }, &desktop)
	assert state.scroll == 0
	// Outside the app list, scrolling cannot move the page.
	desktop.pointer_y = layout.y + layout.height - 40
	state.pointer_input(PointerPacket{ scroll: -4 }, &desktop)
	assert state.scroll == 0
	desktop.hover = action_apps_scrollbar
	desktop.pointer_y = layout.y + app_selection_row_top + layout.list_height - 1
	state.pointer_input(PointerPacket{ pressed: button_left, buttons: button_left }, &desktop)
	assert state.scroll == app_selection_content_height(state.columns) - layout.list_height
	assert state.scroll_drag
	state.pointer_input(PointerPacket{ released: button_left }, &desktop)
	assert !state.scroll_drag
	begin_frame_elements()
	tree := state.element(&desktop)
	assert app_selection_test_element(tree, 'apps.toggle.ios') != none
	assert app_selection_test_element(tree, action_apps_install) != none
	free_tree(tree)
	assert state.packages() == ['firefox']
}

fn test_app_selection_uses_three_columns_and_adapts_to_narrow_screens() {
	mut state := app_selection_test_state()
	for width in [1024, 800, 640] {
		desktop := Desktop{ canvas: Canvas{ width: width, height: 720, scale: 1 } }
		begin_frame_elements()
		tree := state.element(&desktop)
		firefox := app_selection_test_element(tree, 'apps.toggle.firefox') or { panic('missing Firefox') }
		chromium := app_selection_test_element(tree, 'apps.toggle.chromium') or { panic('missing Chromium') }
		browsers := app_selection_test_element(tree, 'apps.heading.browsers') or { panic('missing heading') }
		assert browsers.frame.x == firefox.frame.x
		assert browsers.frame.y + browsers.frame.height < firefox.frame.y
		if width >= 800 {
			assert firefox.frame.y == chromium.frame.y
			assert firefox.frame.x + firefox.frame.width < chromium.frame.x
		} else {
			assert firefox.frame.x == chromium.frame.x
			assert firefox.frame.y + firefox.frame.height < chromium.frame.y
		}
		if width == 1024 {
			codium := app_selection_test_element(tree, 'apps.toggle.vscodium') or { panic('missing VSCodium') }
			zed := app_selection_test_element(tree, 'apps.toggle.zed') or { panic('missing Zed') }
			neovim := app_selection_test_element(tree, 'apps.toggle.neovim') or { panic('missing Neovim') }
			assert codium.frame.y == zed.frame.y && zed.frame.y == neovim.frame.y
			assert codium.frame.x + codium.frame.width < zed.frame.x
			assert zed.frame.x + zed.frame.width < neovim.frame.x
		}
		$if arm64 {
			voffice := app_selection_test_element(tree, 'apps.toggle.voffice') or { panic('missing VOffice') }
			assert app_selection_test_has_image(voffice, 'asset:voffice')
		}
		free_tree(tree)
	}
}

fn test_app_selection_vertical_arrows_follow_grid_columns_and_skip_unavailable_apps() {
	mut state := app_selection_test_state()
	state.prepare_viewport(452, 3)
	state.set_focus(1) // Chromium, in the second column.
	state.key_input('\x1b[B')
	assert first_run_apps[state.focus].package_name == 'keepassxc'
	state.key_input('\x1b[A')
	$if arm64 {
		assert first_run_apps[state.focus].package_name == 'chromium'
	} $else {
		assert first_run_apps[state.focus].package_name == 'firefox'
	}
	for i, app in first_run_apps {
		if app.package_name == 'keepassxc' { state.available[i] = false }
	}
	state.set_focus(1)
	state.key_input('\x1b[B')
	$if arm64 {
		assert first_run_apps[state.focus].package_name == 'voffice'
	} $else {
		assert first_run_apps[state.focus].category == .development
	}
}

fn test_first_run_install_command_keeps_all_choices_and_routes_vendor_downloads() {
	command := first_run_install_command('vlc-qt telegram-desktop neovim keepassxc obs-studio ios-runtime discord slack spotify steam')
	$if arm64 {
		assert command.contains('for app in vlc-qt telegram-desktop neovim keepassxc obs-studio ios-runtime discord slack spotify steam;')
	} $else {
		assert command.contains('for app in vlc-qt telegram-desktop neovim keepassxc obs-studio discord slack spotify steam;')
	}
	assert command.contains('qt5-qtbase-x11')
	assert command.contains('qt6-qtbase-x11')
	assert command.contains('/usr/bin/vinix-desktop --install-ios-runtime')
	assert command.contains('--install-setup-app "\$app"')
	assert first_run_install_command('discord slack spotify steam').contains('for app in discord slack spotify steam;')
}

fn test_first_run_every_app_is_selectable_without_repository_or_payload_probes() {
	mut state := new_app_selection_state()
	defer { state.close() }
	assert state.available.all(it)
	for i in 0 .. first_run_apps.len {
		state.installed[i] = false
		state.toggle(i)
	}
	assert state.selected_count() == first_run_apps.len
	assert state.packages() == first_run_apps.map(it.package_name)
}

fn app_selection_test_ios_payload() []u8 {
	// ELF64 header, one executable PT_LOAD and an ARM64 RET instruction.
	mut data := []u8{len: 124}
	data[0] = 0x7f
	data[1] = `E`
	data[2] = `L`
	data[3] = `F`
	data[4] = 2
	data[5] = 1
	data[6] = 1
	binary.little_endian_put_u16_at(mut data, 2, 16)
	binary.little_endian_put_u16_at(mut data, 183, 18)
	binary.little_endian_put_u32_at(mut data, 1, 20)
	binary.little_endian_put_u64_at(mut data, 0x1078, 24)
	binary.little_endian_put_u64_at(mut data, 64, 32)
	binary.little_endian_put_u16_at(mut data, 64, 52)
	binary.little_endian_put_u16_at(mut data, 56, 54)
	binary.little_endian_put_u16_at(mut data, 1, 56)
	binary.little_endian_put_u32_at(mut data, 1, 64)
	binary.little_endian_put_u32_at(mut data, 5, 68)
	binary.little_endian_put_u64_at(mut data, 0x1000, 80)
	binary.little_endian_put_u64_at(mut data, 124, 96)
	binary.little_endian_put_u64_at(mut data, 124, 104)
	binary.little_endian_put_u32_at(mut data, 0xd65f03c0, 120)
	return data
}

fn test_first_run_ios_runtime_requires_a_static_arm64_elf() {
	valid := app_selection_test_ios_payload()
	assert first_run_ios_elf(valid)
	assert !first_run_ios_elf([]u8{})
	mut wrong_arch := valid.clone()
	wrong_arch[18] = 62
	assert !first_run_ios_elf(wrong_arch)
	mut dynamic := valid.clone()
	dynamic[64] = 3
	assert !first_run_ios_elf(dynamic)
	mut overflow := valid.clone()
	binary.little_endian_put_u64_at(mut overflow, ~u64(0), 32)
	assert !first_run_ios_elf(overflow)
	mut outside := valid.clone()
	binary.little_endian_put_u64_at(mut outside, 0x2000, 24)
	assert !first_run_ios_elf(outside)
}

fn test_first_run_ios_runtime_installs_only_a_valid_payload() {
	root := os.join_path(os.temp_dir(), 'vinix-setup-runtime-${os.getpid()}')
	os.mkdir_all(os.dir(root + first_run_ios_payload))!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + first_run_ios_payload, 'invalid runtime')!
	if _ := first_run_install_ios_runtime(root) {
		assert false, 'invalid runner was accepted'
	}
	assert !os.exists('${root}/usr/bin/run-ios')
	$if arm64 {
		valid := app_selection_test_ios_payload()
		os.write_file_array(root + first_run_ios_payload, valid)!
		first_run_install_ios_runtime(root)!
		assert os.read_bytes('${root}/usr/bin/run-ios')! == valid
		assert os.stat('${root}/usr/bin/run-ios')!.mode & 0o777 == 0o755
		assert os.read_file('${root}/var/lib/vinix-pkg/ios-runtime.files')! == 'usr/bin/run-ios\n'
		assert !os.exists('${root}/usr/bin/.run-ios-setup')
	}
}

fn test_first_run_install_command_reports_failures_and_continues() {
	work := os.join_path(os.temp_dir(), 'vinix-first-run-install-${os.getpid()}')
	os.mkdir_all(os.join_path(work, 'bin')) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	fake_pkg := os.join_path(work, 'bin', 'pkg')
	log := os.join_path(work, 'pkg.log')
	os.write_file(fake_pkg, '#!/bin/sh\necho "\$*" >> "${log}"\n[ "\$2" != chromium ]\n') or {
		panic(err)
	}
	os.chmod(fake_pkg, 0o755) or { panic(err) }

	command := first_run_install_command('firefox chromium')
	// Stop where the Terminal would hand over to the interactive shell.
	script := command.replace('exec /bin/zsh -i', 'exit 0')
	result := os.execute('PATH="${work}/bin:\$PATH" sh -c ${os.quoted_path(script)}')
	assert result.exit_code == 0
	assert os.read_file(log) or { '' } == 'install firefox\ninstall chromium\n'
	assert result.output.contains('Installing the apps chosen during setup: firefox chromium')
	assert result.output.contains('Not installed: chromium. Run vinix-desktop --install-setup-app chromium to try again.')

	success := first_run_install_command('firefox').replace('exec /bin/zsh -i', 'exit 0')
	ok := os.execute('PATH="${work}/bin:\$PATH" sh -c ${os.quoted_path(success)}')
	assert ok.exit_code == 0
	assert ok.output.contains('The selected apps are installed.')
}
