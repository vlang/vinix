// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Capture, the hosted-application windows, first-run setup and the window
// switcher in Russian and Spanish.
module main

import os
import ui2

fn i18n_apps_has_text(root ui2.Element, text string) bool {
	if root.text == text || root.placeholder == text {
		return true
	}
	return root.children.any(i18n_apps_has_text(it, text))
}

fn i18n_apps_element(root ui2.Element, name string) ?ui2.Element {
	if root.id == name || root.action_id == name {
		return root
	}
	for child in root.children {
		if found := i18n_apps_element(child, name) {
			return found
		}
	}
	return none
}

fn i18n_apps_desktop() Desktop {
	return Desktop{
		canvas: Canvas{
			width:  1024
			height: 720
			scale:  1
		}
	}
}

fn test_capture_speaks_the_desktop_language() {
	defer {
		set_desktop_language(.en)
	}
	mut app := CaptureApp{}
	set_desktop_language(.ru)
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 560, 396))!
	assert i18n_apps_has_text(tree, 'ЗАХВАТ ЭКРАНА')
	assert i18n_apps_has_text(tree, 'Снимок экрана')
	assert i18n_apps_has_text(tree, '3 секунды')
	assert i18n_apps_has_text(tree, 'PNG  |  весь рабочий стол  |  с указателем')
	assert i18n_apps_has_text(tree, 'Сделать снимок')
	assert i18n_apps_has_text(tree, 'Готово к захвату')
	free_tree(tree)

	set_desktop_language(.es)
	app.page = .video
	begin_frame_elements()
	video := app.build(ui2.rect(0, 0, 560, 396))!
	assert i18n_apps_has_text(video, 'Grabar el escritorio')
	assert i18n_apps_has_text(video, 'Fluido  10 fps')
	assert i18n_apps_has_text(video, 'Vídeo AVI  |  hasta 640 x 480  |  con puntero  |  sin audio')
	assert i18n_apps_has_text(video, 'Iniciar grabación')
	free_tree(video)

	// The lists keep their English separators and words exactly.
	set_desktop_language(.en)
	begin_frame_elements()
	english := app.build(ui2.rect(0, 0, 560, 396))!
	assert i18n_apps_has_text(english, 'AVI video  |  up to 640 x 480  |  pointer included  |  no audio')
	assert i18n_apps_has_text(english, 'Start recording')
	free_tree(english)
	app.page = .screenshot
	begin_frame_elements()
	screenshot := app.build(ui2.rect(0, 0, 560, 396))!
	assert i18n_apps_has_text(screenshot, 'PNG  |  full desktop  |  includes the pointer')
	free_tree(screenshot)
}

fn test_capture_status_counts_in_each_language() {
	defer {
		set_desktop_language(.en)
	}
	recording := CaptureReport{
		phase:      .recording
		elapsed_ms: 65_000
		frames:     12
		width:      640
		height:     480
		fps:        10
	}
	countdown := CaptureReport{
		phase:      .screenshot_countdown
		elapsed_ms: 2_500
	}

	set_desktop_language(.en)
	title, detail := capture_status_text(recording)
	assert title == 'Recording  01:05'
	assert detail == '12 frames  |  640 x 480  |  10 fps'
	waiting, hint := capture_status_text(countdown)
	assert waiting == 'Screenshot in 3'
	assert hint == 'Restore this window to cancel.'

	set_desktop_language(.ru)
	ru_title, ru_detail := capture_status_text(recording)
	assert ru_title == 'Запись  01:05'
	assert ru_detail == '12 кадров  |  640 x 480  |  10 к/с'
	ru_waiting, _ := capture_status_text(countdown)
	assert ru_waiting == 'Снимок через 3 секунды'
	_, ru_one := capture_status_text(CaptureReport{
		...recording
		frames: 21
	})
	assert ru_one.starts_with('21 кадр  |')

	set_desktop_language(.es)
	saved, path := capture_status_text(CaptureReport{
		phase:   .screenshot_saved
		file_id: 20260928120000
		width:   2048
		height:  1536
	})
	assert saved == 'Captura guardada  2048 x 1536'
	// Paths stay as the file system spells them.
	assert path == '/root/Screenshot-20260928120000.png'
	failed, reason := capture_status_text(CaptureReport{
		phase: .failed
	})
	assert failed == 'Error en la captura'
	assert reason == 'No se pudo escribir el archivo en /root.'
}

// A hosted window keeps which message it shows, so the words follow the
// language even while the window stays open.
fn test_hosted_windows_follow_the_language() {
	defer {
		set_desktop_language(.en)
	}
	mut chromium := HostedX11App{
		failed:  true
		failure: .chromium_missing
	}
	mut blender := NativeSurfaceApp{
		starting: .blender_starting
	}

	set_desktop_language(.ru)
	begin_frame_elements()
	tree := chromium.build(ui2.rect(0, 0, 640, 480))!
	assert i18n_apps_has_text(tree, 'Chromium не установлен. Выполните pkg install chromium в Терминале.')
	free_tree(tree)
	begin_frame_elements()
	starting := blender.build(ui2.rect(0, 0, 640, 480))!
	assert i18n_apps_has_text(starting, 'Запуск нативного Blender…')
	free_tree(starting)

	set_desktop_language(.es)
	begin_frame_elements()
	spanish := chromium.build(ui2.rect(0, 0, 640, 480))!
	assert i18n_apps_has_text(spanish, 'Chromium no está instalado. Ejecuta pkg install chromium en Terminal.')
	free_tree(spanish)

	set_desktop_language(.en)
	begin_frame_elements()
	english := chromium.build(ui2.rect(0, 0, 640, 480))!
	assert i18n_apps_has_text(english, 'Chromium is not installed. Run pkg install chromium in Terminal.')
	free_tree(english)
	assert HostedText.windows_exited.text() == 'The Windows application exited.'
	assert HostedText.doom_wad_missing.text() == 'DOOM WAD is missing. Set VINIX_DOOM_WAD and rebuild the image.'
	assert HostedText.gothic_data_missing.text() == "Gothic II's data is missing. Copy Data, _work and System to /usr/share/games/gothic2."
	assert HostedText.roblox_apk_missing.text() == 'Copy your Roblox APK to ~/Roblox.apk, or set VINIX_ROBLOX_APK to its path.'
	assert HostedText.roblox_missing.text() == 'Roblox runtime is missing. Rebuild the desktop with --with-roblox.'
	assert SurfaceText.blender_exited.text() == 'Blender exited.'
}

fn test_app_selection_in_spanish() {
	defer {
		set_desktop_language(.en)
	}
	desktop := i18n_apps_desktop()
	mut state := new_app_selection_state()
	for i in 0 .. state.installed.len {
		state.installed[i] = false
	}
	state.installed[3] = true
	state.handle_action('apps.toggle.firefox')
	state.handle_action('apps.toggle.chromium')

	set_desktop_language(.es)
	begin_frame_elements()
	root := state.element(&desktop)
	defer { free_tree(root) }
	assert i18n_apps_has_text(root, 'Elige tus aplicaciones')
	assert i18n_apps_has_text(root, 'Navegador web de Mozilla')
	assert i18n_apps_has_text(root, 'Instalada')
	// Product names are not translated.
	assert i18n_apps_has_text(root, 'Firefox')
	button := i18n_apps_element(root, action_apps_install) or { panic('missing install button') }
	assert button.text == 'Instalar 2 aplicaciones'

	set_desktop_language(.ru)
	for label in app_selection_install_labels {
		assert label.text().len > 0
	}
	assert app_selection_install_labels[1].text() == 'Установить 1 приложение'
	assert app_selection_install_labels[4].text() == 'Установить 4 приложения'
}

// The install messages are pasted into shell quotes, so no language may use a
// character that would end them or start an expansion.
fn test_first_run_install_messages_are_safe_inside_shell_quotes() {
	for language in desktop_languages {
		for key in ['app_selection.install.started', 'app_selection.install.failed',
			'app_selection.install.done'] {
			text := desktop_translations[language.code()][key]
			assert text.len > 0, '${language.code()} lacks ${key}'
			for ch in ["'", '"', '$', '`', '\\'] {
				assert !text.contains(ch), '${language.code()} ${key} contains ${ch}'
			}
		}
	}
}

fn test_first_run_install_reports_in_russian() {
	defer {
		set_desktop_language(.en)
	}
	work := os.join_path(os.temp_dir(), 'vinix-i18n-first-run-${os.getpid()}')
	os.mkdir_all(os.join_path(work, 'bin')) or { panic(err) }
	defer { os.rmdir_all(work) or {} }
	fake_pkg := os.join_path(work, 'bin', 'pkg')
	os.write_file(fake_pkg, '#!/bin/sh\n[ "\$2" != chromium ]\n') or { panic(err) }
	os.chmod(fake_pkg, 0o755) or { panic(err) }

	set_desktop_language(.ru)
	command := first_run_install_command('firefox chromium')
	script := command.replace('exec /bin/zsh -i', 'exit 0')
	result := os.execute('PATH="${work}/bin:\$PATH" sh -c ${os.quoted_path(script)}')
	assert result.exit_code == 0
	assert result.output.contains('Установка приложений, выбранных при настройке: firefox chromium')
	assert result.output.contains('Не установлены: chromium. Чтобы повторить попытку, выполните pkg install chromium.')

	set_desktop_language(.es)
	success := first_run_install_command('firefox').replace('exec /bin/zsh -i', 'exit 0')
	ok := os.execute('PATH="${work}/bin:\$PATH" sh -c ${os.quoted_path(success)}')
	assert ok.exit_code == 0
	assert ok.output.contains('Las aplicaciones seleccionadas están instaladas.')
}

fn test_registration_in_russian() {
	defer {
		set_desktop_language(.en)
	}
	home := os.join_path(os.temp_dir(), 'vinix-i18n-registration-${os.getpid()}')
	os.mkdir(home) or { panic(err) }
	defer { os.rmdir_all(home) or {} }
	desktop := i18n_apps_desktop()
	mut state := new_registration_state()
	defer { state.close() }

	set_desktop_language(.ru)
	state.key_input('Alice\tone\ttwo\r', home)
	assert !state.complete
	assert state.error == 'Пароли не совпадают.'
	begin_frame_elements()
	root := state.element(&desktop)
	defer { free_tree(root) }
	assert i18n_apps_has_text(root, 'Создайте пользователя')
	assert i18n_apps_has_text(root, 'Подтверждение пароля')
	assert i18n_apps_has_text(root, 'Пароли не совпадают.')
	button := i18n_apps_element(root, action_registration_create) or { panic('missing button') }
	assert button.text == 'Создать пользователя'
	state.key_input('\x7f\x7f\x7f', home)
	assert state.error == ''
	begin_frame_elements()
	empty := state.element(&desktop)
	defer { free_tree(empty) }
	confirm := i18n_apps_element(empty, action_registration_confirm) or { panic('missing field') }
	assert confirm.placeholder == 'Повторите пароль'
}

// Window titles stay English for the window manager; the panel shows them in
// the desktop's language.
fn test_switcher_shows_titles_in_the_desktop_language() {
	defer {
		set_desktop_language(.en)
	}
	mut desktop := Desktop{
		canvas: new_canvas(1024, 768)
	}
	desktop.spawn('Firefox', .welcome, 10, 10, 300, 200)
	desktop.spawn('Files', .system, 20, 20, 300, 200)
	desktop.spawn('Terminal', .notes, 30, 30, 300, 200)
	set_desktop_language(.ru)
	assert desktop.take_switcher_keys('\x1b[9;9u') == ''
	desktop.switcher.started -= switcher_reveal_ms
	desktop.update_switcher()
	assert desktop.switcher.shown
	assert desktop.switcher_title() == 'Files'
	begin_frame_elements()
	panel := desktop.switcher_element()
	title := i18n_apps_element(panel, 'switcher.title') or { panic('missing title') }
	assert title.text == 'Файлы'
	free_tree(panel)

	desktop.switcher_step(1)
	assert desktop.switcher_title() == 'Firefox'
	begin_frame_elements()
	product := desktop.switcher_element()
	product_title := i18n_apps_element(product, 'switcher.title') or { panic('missing title') }
	assert product_title.text == 'Firefox'
	free_tree(product)
}
