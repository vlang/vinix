// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn i18n_files_element(tree ui2.Element, id string) ?ui2.Element {
	if tree.id == id {
		return tree
	}
	for child in tree.children {
		if found := i18n_files_element(child, id) {
			return found
		}
	}
	return none
}

fn i18n_files_texts(tree ui2.Element, mut out []string) {
	if tree.text.len > 0 {
		out << tree.text
	}
	if tree.accessibility_label.len > 0 {
		out << tree.accessibility_label
	}
	for child in tree.children {
		i18n_files_texts(child, mut out)
	}
}

fn i18n_files_entry(browser &FileBrowser, name string) FileEntry {
	for entry in browser.entries {
		if entry.name == name {
			return entry
		}
	}
	panic('missing entry ${name}')
}

fn test_files_list_kinds_and_dates_follow_the_language() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.ru)
	assert files_list_kind_text('folder', true) == 'Папка'
	assert files_list_kind_text('photo.JPG', false) == 'Рисунок JPEG'
	assert files_list_kind_text('main.v', false) == 'Код на V'
	assert files_list_kind_text('book.pdf', false) == 'Файл PDF'
	assert files_list_kind_text('notes.md', false) == 'Markdown'
	assert files_list_modified_text(0, 0) == '01 янв. 1970 00:00'
	// 2026-05-09 12:00 UTC: May takes its full genitive form.
	assert files_list_modified_text(1778328000, 0) == '09 мая 2026 12:00'
	set_desktop_language(.es)
	assert files_list_kind_text('plain', false) == 'Documento'
	assert files_list_kind_text('book.pdf', false) == 'Archivo PDF'
	assert files_list_modified_text(1789000000, 0) == '10 sept 2026 00:26'
	set_desktop_language(.en)
	assert files_list_modified_text(1789000000, 0) == '10 Sep 2026 00:26'
	assert files_list_kind_text('book.pdf', false) == 'PDF file'
}

fn test_files_list_header_and_sort_targets_are_translated() ! {
	defer {
		set_desktop_language(.en)
	}
	mut app := FileBrowserApp{}
	app.settings = default_files_settings()
	app.browser.entries = [
		FileEntry{
			name:   'src'
			is_dir: true
		},
	]
	set_desktop_language(.ru)
	app.browser.sort_column = .size
	tree := app.build(ui2.rect(0, 0, 1000, 360))!
	name := i18n_files_element(tree, 'files.list.header.name') or { panic('missing Name') }
	assert name.text == 'Имя'
	modified := i18n_files_element(tree, 'files.list.header.modified') or { panic('missing Date') }
	assert modified.text == 'Дата изменения'
	size := i18n_files_element(tree, files_action_sort_size) or { panic('missing Size target') }
	assert size.tooltip == 'Сортировать по размеру'
	assert size.accessibility_label == 'Сортировать по размеру'
	assert size.accessibility_value == 'по возрастанию'
	kind := i18n_files_element(tree, files_action_sort_kind) or { panic('missing Kind target') }
	assert kind.tooltip == 'Сортировать по типу'
	free_tree(tree)
	set_desktop_language(.es)
	app.browser.sort_descending = true
	spanish := app.build(ui2.rect(0, 0, 1000, 360))!
	header := i18n_files_element(spanish, 'files.list.header.modified') or { panic('missing Date') }
	assert header.text == 'Fecha de modificación'
	sorted := i18n_files_element(spanish, files_action_sort_size) or { panic('missing Size target') }
	assert sorted.accessibility_value == 'descendente'
	free_tree(spanish)
}

fn test_files_listing_relabels_after_a_language_change() ! {
	defer {
		set_desktop_language(.en)
	}
	root := os.join_path(os.temp_dir(), 'vinix-i18n-files-relabel-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'folder'))!
	os.write_file(os.join_path(root, 'picture.png'), 'png')!
	os.write_file(os.join_path(root, 'readme.txt'), 'text')!
	defer { os.rmdir_all(root) or {} }

	mut browser := FileBrowser{}
	browser.read(root.clone())
	prepare_file_rows(mut browser.entries, files_action_row)
	browser.set_list_sort(.kind)
	assert browser.entries.map(it.kind_text) == ['Folder', 'PNG image', 'Plain text']
	set_desktop_language(.ru)
	browser.relabel_entries()
	// Sorted by kind, the listing takes the new language's order.
	assert browser.entries.map(it.kind_text) == ['Папка', 'Простой текст', 'Рисунок PNG']
	assert browser.entries.map(it.name) == ['folder', 'readme.txt', 'picture.png']
	for index, entry in browser.entries {
		assert entry.row_action == '${files_action_row}${index}'
	}
	assert i18n_files_entry(&browser, 'picture.png').size_text == '3 Б'
	set_desktop_language(.es)
	browser.relabel_entries()
	assert browser.entries.map(it.kind_text) == ['Carpeta', 'Imagen PNG', 'Texto plano']
	browser.free_entries()
}

fn test_files_new_items_and_copies_are_named_in_the_language() ! {
	defer {
		set_desktop_language(.en)
	}
	root := os.join_path(os.temp_dir(), 'vinix-i18n-files-names-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	set_desktop_language(.ru)
	folder := create_unique_item(root, .folder)!
	assert folder == os.join_path(root, 'Новая папка')
	second := create_unique_item(root, .folder)!
	assert second == os.join_path(root, 'Новая папка (2)')
	set_desktop_language(.es)
	file := create_unique_item(root, .file)!
	assert file == os.join_path(root, 'Nuevo archivo')
	copy := file_context_unique_copy_destination(root, file)!
	assert copy == os.join_path(root, 'Nuevo archivo copia')
	os.write_file(copy, '')!
	again := file_context_unique_copy_destination(root, file)!
	assert again == os.join_path(root, 'Nuevo archivo copia (2)')
	set_desktop_language(.en)
	english := file_context_unique_copy_destination(root, file)!
	assert english == os.join_path(root, 'Nuevo archivo copy')
}

fn test_files_settings_window_and_default_tags_are_translated() ! {
	defer {
		set_desktop_language(.en)
	}
	mut app := FilesContextApp{
		settings_only: true
	}
	app.files.settings = default_files_settings()
	set_desktop_language(.ru)
	mut labels := []string{}
	general := app.build(ui2.rect(0, 0, 540, 550))!
	i18n_files_texts(general, mut labels)
	free_tree(general)
	assert 'Настройки Файлов' in labels
	assert 'Готово' in labels
	assert 'Показывать скрытые файлы и папки' in labels
	app.handle(files_settings_tags)!
	labels.clear()
	tags := app.build(ui2.rect(0, 0, 540, 550))!
	i18n_files_texts(tags, mut labels)
	free_tree(tags)
	assert 'Красный' in labels
	assert 'Показывать «Красный» в боковой панели' in labels
	assert 'Окрашивать папки в цвет тегов' in labels
	// The stored name stays English, so the tag follows the next language too.
	assert app.files.settings.tags[0].name == 'Red'
	set_desktop_language(.es)
	assert app.files.settings.tags[0].display_name() == 'Rojo'
	// A renamed tag is shown as the user typed it.
	app.files.settings.tags[1].name = 'Red'
	assert app.files.settings.tags[1].display_name() == 'Red'
	// Editing a built-in tag starts from the name on screen; leaving it as
	// it is keeps the English name.
	app.settings_selected = 0
	app.handle(files_settings_rename)!
	assert rename_buffer_text(app.settings_name) == 'Rojo'
	app.settings_key_input('\n')
	assert app.files.settings.tags[0].name == 'Red'
}

fn test_files_commander_and_quicklook_messages_are_translated() ! {
	defer {
		set_desktop_language(.en)
	}
	root := os.join_path(os.temp_dir(), 'vinix-i18n-files-empty-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	mut app := FileBrowserApp{}
	app.settings = default_files_settings()
	app.browser.read(root.clone())
	app.handle(files_action_view_commander)!
	set_desktop_language(.es)
	mut labels := []string{}
	tree := app.build(ui2.rect(0, 0, 700, 340))!
	i18n_files_texts(tree, mut labels)
	free_tree(tree)
	assert 'Esta carpeta está vacía.' in labels

	mut preview := FilesQuickLook{}
	preview.show('/tmp/does-not-exist.txt')
	assert preview.message == 'No se puede previsualizar este archivo.'
	// A preview left open follows the language.
	set_desktop_language(.ru)
	labels.clear()
	view := preview.build(ui2.rect(0, 0, 700, 400))
	i18n_files_texts(view, mut labels)
	free_tree(view)
	assert 'Не удалось просмотреть этот файл.' in labels
	preview.close()
}

fn test_files_sizes_use_the_languages_units_and_decimal_comma() {
	defer {
		set_desktop_language(.en)
	}
	assert human_size(512) == '512 B'
	assert human_size(1536) == '1.5 KB'
	assert human_size(20 * 1024 * 1024) == '20 MB'
	set_desktop_language(.ru)
	assert human_size(512) == '512 Б'
	assert human_size(1536) == '1,5 КБ'
	assert human_size(u64(3) * 1024 * 1024 * 1024) == '3,0 ГБ'
	assert human_size(20 * 1024 * 1024) == '20 МБ'
	set_desktop_language(.es)
	assert human_size(1536) == '1,5 KB'
	assert human_size(512) == '512 B'
}

fn test_files_sidebar_and_toolbar_are_translated() ! {
	defer {
		set_desktop_language(.en)
	}
	root := os.join_path(os.temp_dir(), 'vinix-i18n-files-sidebar-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	desktop_use_user_home(root.clone())
	mut app := FileBrowserApp{}
	app.settings = default_files_settings()
	app.browser.read(root.clone())
	set_desktop_language(.ru)
	mut labels := []string{}
	tree := app.build(ui2.rect(0, 0, 700, 600))!
	i18n_files_texts(tree, mut labels)
	for text in ['Избранное', 'Места', 'Теги', 'Домашняя папка', 'Рабочий стол', 'Загрузки',
		'Компьютер', 'Красный', 'Вверх', 'Эта папка пуста.'] {
		assert text in labels, text
	}
	list := i18n_files_element(tree, files_action_view_list) or { panic('missing List view') }
	assert list.tooltip == 'Просмотр в виде списка'
	assert list.accessibility_value == 'выбрано'
	free_tree(tree)
	// Only the labels are translated: the folders keep their names on disk.
	for location in files_locations {
		if location.action == 'files.location.downloads' {
			assert location.path == os.join_path(root, 'Downloads')
			assert location.display_title() == 'Загрузки'
		}
	}

	// A tag's results are headed with its translated name.
	app.handle('${files_action_tag_prefix}0')!
	labels.clear()
	results := app.build(ui2.rect(0, 0, 700, 600))!
	i18n_files_texts(results, mut labels)
	free_tree(results)
	assert 'Красный' in labels
	assert 'Нет файлов с этим тегом.' in labels
}

fn test_files_window_follows_a_language_change_in_every_view() ! {
	defer {
		set_desktop_language(.en)
	}
	root := os.join_path(os.temp_dir(), 'vinix-i18n-files-follow-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'folder'))!
	os.write_file(os.join_path(root, 'notes.txt'), 'hello')!
	defer { os.rmdir_all(root) or {} }
	mut app := FileBrowserApp{}
	app.settings = default_files_settings()
	app.browser.read(root.clone())
	english := app.build(ui2.rect(0, 0, 1000, 400))!
	free_tree(english)
	assert i18n_files_entry(&app.browser, 'notes.txt').kind_text == 'Plain text'
	assert i18n_files_entry(&app.browser, 'notes.txt').size_text == '5 B'

	// The application process learns the language with its next request;
	// the build that follows remakes what the listing kept.
	set_desktop_language(.ru)
	mut labels := []string{}
	russian := app.build(ui2.rect(0, 0, 1000, 400))!
	i18n_files_texts(russian, mut labels)
	free_tree(russian)
	assert i18n_files_entry(&app.browser, 'folder').kind_text == 'Папка'
	assert i18n_files_entry(&app.browser, 'notes.txt').size_text == '5 Б'
	assert 'Простой текст' in labels && '5 Б' in labels

	app.set_view_mode(.commander)
	app.set_view_mode(.columns)
	set_desktop_language(.es)
	columns := app.build(ui2.rect(0, 0, 1000, 400))!
	free_tree(columns)
	assert i18n_files_entry(&app.columns[app.columns.len - 1].browser, 'notes.txt').kind_text == 'Texto plano'
	assert i18n_files_entry(&app.dual_left, 'folder').kind_text == 'Carpeta'
	assert i18n_files_entry(&app.dual_right, 'notes.txt').size_text == '5 B'

	// A directory that could not be opened says so in the new language too.
	missing := os.join_path(root, 'missing')
	app.set_view_mode(.list)
	app.browser.read(missing)
	assert app.browser.error == 'No se puede abrir ${missing}'
	set_desktop_language(.ru)
	failed := app.build(ui2.rect(0, 0, 1000, 400))!
	free_tree(failed)
	assert app.browser.error == 'Не удаётся открыть ${missing}'
	set_desktop_language(.en)
	app.follow_language()
	assert app.browser.error == 'cannot open ${missing}'
}
