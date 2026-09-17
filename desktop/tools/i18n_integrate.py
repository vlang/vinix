#!/usr/bin/env python3
from pathlib import Path
import json


def edit(path, fn):
    p = Path(path)
    old = p.read_text()
    new = fn(old)
    if new == old:
        raise SystemExit(f'{path}: patch made no change')
    p.write_text(new)


def one(text, old, new, label):
    if old not in text:
        raise SystemExit(f'{label}: pattern not found: {old[:100]!r}')
    return text.replace(old, new, 1)


def patch_app_process(text):
    text = one(text,
        'const app_protocol_version = u8(5)\nconst app_request_header_size = 124\nconst app_response_header_size = 116',
        'const app_protocol_version = u8(6)\nconst app_request_header_size = 128\nconst app_response_header_size = 120',
        'app protocol sizes')
    text = one(text,
        '\twire_put_i32(mut out, int(state.settings.theme))\n\twire_put_i32(mut out, if state.settings.clock_24_hour',
        '\twire_put_i32(mut out, int(state.settings.theme))\n\twire_put_i32(mut out, int(state.settings.language))\n\twire_put_i32(mut out, if state.settings.clock_24_hour',
        'wire put language')
    text = one(text,
        '\ttheme := reader.take_i32()!\n\tclock_24_hour := reader.take_i32()!',
        '\ttheme := reader.take_i32()!\n\tlanguage := reader.take_i32()!\n\tclock_24_hour := reader.take_i32()!',
        'wire take language')
    text = one(text,
        '\t\t|| theme < int(ThemeKind.default_) || theme > int(ThemeKind.macos)\n\t\t|| clock_24_hour',
        '\t\t|| theme < int(ThemeKind.default_) || theme > int(ThemeKind.macos)\n\t\t|| language < int(SystemLanguage.en) || language > int(SystemLanguage.ru)\n\t\t|| clock_24_hour',
        'wire validate language')
    text = one(text,
        '\t\t\ttheme: unsafe { ThemeKind(theme) }\n\t\t\tclock_24_hour:',
        '\t\t\ttheme: unsafe { ThemeKind(theme) }\n\t\t\tlanguage: unsafe { SystemLanguage(language) }\n\t\t\tclock_24_hour:',
        'wire reconstruct language')
    old = '''fn apply_app_state(mut desktop Desktop, state AppWireState) {
\twallpaper_changed := desktop.settings.wallpaper_color != state.settings.wallpaper_color
\t\t|| desktop.settings.wallpaper_image != state.settings.wallpaper_image
\tclock_changed := desktop.settings.clock_24_hour != state.settings.clock_24_hour
\t\t|| desktop.settings.clock_show_seconds != state.settings.clock_show_seconds
\t\t|| desktop.settings.clock_show_date != state.settings.clock_show_date
\t\t|| desktop.settings.clock_show_weekday != state.settings.clock_show_weekday
\tdesktop.settings = state.settings
\tdesktop.accept_capture_request(state.capture_request)
\tif wallpaper_changed {
\t\tdesktop.invalidate_wallpaper()
\t}
\tif clock_changed {
\t\tdesktop.taskbar_clock_sampled = false
\t\tdesktop.dirty = true
\t}
'''
    new = '''fn apply_app_state(mut desktop Desktop, state AppWireState) {
\twallpaper_changed := desktop.settings.wallpaper_color != state.settings.wallpaper_color
\t\t|| desktop.settings.wallpaper_image != state.settings.wallpaper_image
\tlanguage_changed := desktop.settings.language != state.settings.language
\tclock_changed := desktop.settings.clock_24_hour != state.settings.clock_24_hour
\t\t|| desktop.settings.clock_show_seconds != state.settings.clock_show_seconds
\t\t|| desktop.settings.clock_show_date != state.settings.clock_show_date
\t\t|| desktop.settings.clock_show_weekday != state.settings.clock_show_weekday
\tdesktop.settings = state.settings
\tdesktop_i18n_set_language(state.settings.language)
\tdesktop.accept_capture_request(state.capture_request)
\tif wallpaper_changed {
\t\tdesktop.invalidate_wallpaper()
\t}
\tif clock_changed || language_changed {
\t\tdesktop.taskbar_clock_sampled = false
\t\tdesktop.dirty = true
\t}
'''
    text = one(text, old, new, 'apply app language')
    text = one(text,
        '\t\tdesktop.settings = state.settings\n\t\tdesktop.capture.request = state.capture_request',
        '\t\tdesktop.settings = state.settings\n\t\tdesktop_i18n_set_language(state.settings.language)\n\t\tdesktop.capture.request = state.capture_request',
        'child app language sync')
    return text


def patch_render(text):
    text = one(text,
        'fn (mut d Desktop) render_clipped(root ui2.Element, clip Clip) {\n\t// clear()',
        'fn (mut d Desktop) render_clipped(root ui2.Element, clip Clip) {\n\tdesktop_i18n_set_language(d.settings.language)\n\t// clear()',
        'renderer language sync')
    text = one(text,
        '\tface := d.face_for(el.text_style)\n\ttext, text_owned := face.truncate(el.text, w)\n',
        '\tface := d.face_for(el.text_style)\n\tsource_text := if el.id == desktop_i18n_raw_text_id { el.text } else { desktop_i18n_text(el.text) }\n\ttext, text_owned := face.truncate(source_text, w)\n',
        'renderer label translation')
    text = one(text,
        '\tface := d.face_for(el.text_style)\n\tinner := if el.text_style.align == .center && el.image_path.len == 0 { w } else { text_w }\n\ttext, text_owned := face.truncate(el.text, inner)\n',
        '\tface := d.face_for(el.text_style)\n\tinner := if el.text_style.align == .center && el.image_path.len == 0 { w } else { text_w }\n\tsource_text := if el.id == desktop_i18n_raw_text_id { el.text } else { desktop_i18n_text(el.text) }\n\ttext, text_owned := face.truncate(source_text, inner)\n',
        'renderer button translation')
    return text


def patch_settings(text):
    text = one(text,
        'enum SettingsCategory {\n\tappearance\n\tdate_time\n',
        'enum SettingsCategory {\n\tappearance\n\tlanguage_region\n\tdate_time\n',
        'language category enum')
    text = one(text,
        'const settings_categories = [SettingsCategory.appearance, .date_time, .theme, .wallpaper, .wifi,\n\t.display, .battery]\n',
        'const settings_categories = [SettingsCategory.appearance, .language_region, .date_time, .theme,\n\t.wallpaper, .wifi, .display, .battery]\n',
        'language category order')
    old = '''fn (c SettingsCategory) title() string {
\treturn match c {
\t\t.appearance { 'Appearance' }
\t\t.date_time { 'Date & Time' }
\t\t.theme { 'Theme' }
\t\t.wallpaper { 'Wallpaper' }
\t\t.wifi { 'Wi-Fi' }
\t\t.display { 'Display' }
\t\t.battery { 'Battery' }
\t}
}
'''
    new = '''fn (c SettingsCategory) title() string {
\treturn match c {
\t\t.appearance { desktop_tr('settings.category.appearance') }
\t\t.language_region { desktop_tr('settings.category.language_region') }
\t\t.date_time { desktop_tr('settings.category.date_time') }
\t\t.theme { desktop_tr('settings.category.theme') }
\t\t.wallpaper { desktop_tr('settings.category.wallpaper') }
\t\t.wifi { desktop_tr('settings.category.wifi') }
\t\t.display { desktop_tr('settings.category.display') }
\t\t.battery { desktop_tr('settings.category.battery') }
\t}
}
'''
    text = one(text, old, new, 'localized settings categories')
    text = one(text,
        "const settings_action_taskbar = 'settings.taskbar.'\n",
        "const settings_action_taskbar = 'settings.taskbar.'\nconst settings_action_language = 'settings.language.'\n",
        'language action')
    text = one(text,
        '\treturn match a.category {\n\t\t.appearance { a.appearance_pane(width) }\n\t\t.date_time { a.date_time_pane(width) }\n',
        '\treturn match a.category {\n\t\t.appearance { a.appearance_pane(width) }\n\t\t.language_region { a.language_region_pane(width) }\n\t\t.date_time { a.date_time_pane(width) }\n',
        'language pane route')
    marker = 'fn (a &SettingsApp) date_time_pane(width int) []ui2.Element {'
    if marker not in text:
        raise SystemExit('settings date-time marker missing')
    pane = '''fn (a &SettingsApp) language_region_pane(width int) []ui2.Element {
\tsettings := a.desktop.settings
\tinner := width - 2 * settings_padding
\thalf := (inner - settings_row_gap) / 2

\tmut out := frame_elements(9)
\tmut y := settings_padding
\tout << settings_heading(desktop_tr('settings.language.title'), y, width)
\ty += 22
\tout << settings_note(desktop_tr('settings.language.note'), y, width)
\ty += 22
\tout << settings_choice('${settings_action_language}0', desktop_tr('settings.language.english'), settings_padding, y, half, settings.language == .en)
\tout << settings_choice('${settings_action_language}1', desktop_tr('settings.language.russian'), settings_padding + half + settings_row_gap, y, half, settings.language == .ru)
\ty += 28 + 8
\tout << settings_note(desktop_tr('settings.language.immediate'), y, width)
\ty += 16 + 22

\tout << settings_heading(desktop_tr('settings.region.title'), y, width)
\ty += 22
\tout << settings_note(desktop_tr('settings.region.note'), y, width)
\ty += 22
\tout << settings_choice('', if settings.language == .ru { desktop_tr('settings.region.russia') } else { desktop_tr('settings.region.us') }, settings_padding, y, inner, true)
\treturn out
}

'''
    text = text.replace(marker, pane + marker, 1)
    handler = '''\tif event_id.starts_with(settings_action_language) {
\t\ta.desktop.settings.language = if event_id.ends_with('1') { SystemLanguage.ru } else { SystemLanguage.en }
\t\tdesktop_i18n_set_language(a.desktop.settings.language)
\t\treturn
\t}
'''
    text = one(text,
        '\tif event_id.starts_with(settings_action_clock_format) {\n',
        handler + '\tif event_id.starts_with(settings_action_clock_format) {\n',
        'language handler')
    return text


def patch_files(text):
    text = one(text, "ui2.label('', a.current_path(),", "ui2.label(desktop_i18n_raw_text_id, a.current_path(),", 'files current path raw')
    if text.count("ui2.label('', entry.name,") < 2:
        raise SystemExit('files: expected two entry.name labels')
    text = text.replace("ui2.label('', entry.name,", "ui2.label(desktop_i18n_raw_text_id, entry.name,", 2)
    text = one(text, "ui2.label('', column_name,", "ui2.label(desktop_i18n_raw_text_id, column_name,", 'files column name raw')
    text = one(text, "b.error = 'cannot open ${path}'", "b.error = '${desktop_tr('files.cannot_open')} ${path}'", 'files error prefix')
    return text


def patch_editor(text):
    text = one(text,
        "frame_child(ui2.label('', editor_bytes_text(a.path),",
        "frame_child(ui2.label(desktop_i18n_raw_text_id, editor_bytes_text(a.path),",
        'editor path raw')
    text = one(text,
        "lines << ui2.label('', editor_slice_text(a.text, position, end - position),",
        "lines << ui2.label(desktop_i18n_raw_text_id, editor_slice_text(a.text, position, end - position),",
        'editor document raw')
    text = one(text,
        'editor_append(mut a.status, prefix)',
        'editor_append(mut a.status, desktop_i18n_text(prefix))',
        'editor dynamic prefix')
    return text


def patch_vspace(text):
    text = one(text, "ui2.label('', entry.name,", "ui2.label(desktop_i18n_raw_text_id, entry.name,", 'vspace entry name raw')
    text = one(text, "ui2.label('', entry.path,", "ui2.label(desktop_i18n_raw_text_id, entry.path,", 'vspace path raw')
    text = one(text, "ui2.label('', a.scanner.root,", "ui2.label(desktop_i18n_raw_text_id, a.scanner.root,", 'vspace root raw')
    return text


def patch_terminal(text):
    return one(text,
        "children << ui2.label('', text, ui2.rect(f64(terminal_padding),",
        "children << ui2.label(desktop_i18n_raw_text_id, text, ui2.rect(f64(terminal_padding),",
        'terminal rows raw')


def patch_activity(text):
    # Arbitrary process names are data; known Vinix process names are localized before reaching the renderer.
    text = one(text,
        "cells << ui2.label('', entry.name,",
        "cells << ui2.label(desktop_i18n_raw_text_id, entry.name,",
        'activity process name raw')
    replacements = {
        "'vinix-files' { 'Files' }": "'vinix-files' { desktop_tr('app.files') }",
        "'vinix-calculator' { 'Calculator' }": "'vinix-calculator' { desktop_tr('app.calculator') }",
        "'vinix-cocoa-calculator' { 'Cocoa Calculator' }": "'vinix-cocoa-calculator' { desktop_tr('app.cocoa_calculator') }",
        "'vinix-terminal' { 'Terminal' }": "'vinix-terminal' { desktop_tr('app.terminal') }",
        "'vinix-settings' { 'Settings' }": "'vinix-settings' { desktop_tr('app.settings') }",
        "'vinix-activity' { 'Activity Monitor' }": "'vinix-activity' { desktop_tr('app.activity') }",
        "'vinix-vspace' { 'VSpace' }": "'vinix-vspace' { desktop_tr('app.vspace') }",
        "'vinix-editor' { 'Text Editor' }": "'vinix-editor' { desktop_tr('app.editor') }",
        "'vinix-calendar' { 'Calendar' }": "'vinix-calendar' { desktop_tr('app.calendar') }",
        "'vinix-clock' { 'Clock' }": "'vinix-clock' { desktop_tr('app.clock') }",
        "'vinix-capture' { 'Capture' }": "'vinix-capture' { desktop_tr('app.capture') }",
    }
    changed = 0
    for old, new in replacements.items():
        if old in text:
            text = text.replace(old, new, 1)
            changed += 1
    if changed < 8:
        raise SystemExit(f'activity: localized only {changed} built-in process names')
    return text


def patch_registration(text):
    old = '''\treturn ui2.Element{
\t\t...field
\t\tclickable: true
\t}
'''
    new = '''\treturn ui2.Element{
\t\t...field
\t\tid: desktop_i18n_raw_text_id
\t\taction_id: action
\t\tclickable: true
\t}
'''
    return one(text, old, new, 'registration raw field')


def patch_build(text):
    marker = '"$SCRIPT_DIR/desktop/README.md"'
    idx = text.find(marker)
    if idx < 0:
        raise SystemExit('desktop source staging marker not found')
    # Add translation staging immediately after the source-copy command, before initramfs creation.
    line_end = text.find('\n', idx)
    # AArch64 has the destination on the next line; find end of cp statement.
    if text[line_end-1:line_end] == '\\':
        line_end = text.find('\n', line_end + 1)
    insertion = '''
mkdir -p "$STAGING/root/desktop/translations" "$STAGING/usr/share/vinix/translations"
cp "$SCRIPT_DIR/desktop/translations"/*.json "$STAGING/root/desktop/translations/"
cp "$SCRIPT_DIR/desktop/translations"/*.json "$STAGING/usr/share/vinix/translations/"
'''
    return text[:line_end+1] + insertion + text[line_end+1:]


def patch_test_settings(text):
    # Run a dedicated localization regression with the full staged desktop.
    text = one(text,
        'cp "$root/desktop/tools/tests/clock_settings_test.v" "$work/ui/"\n',
        'cp "$root/desktop/tools/tests/clock_settings_test.v" "$work/ui/"\ncp "$root/desktop/tools/tests/localization_test.v" "$work/ui/"\n',
        'copy localization test')
    text = one(text,
        'for name in settings switcher settings_persistence clock_settings; do\n',
        'for name in settings switcher settings_persistence clock_settings localization; do\n',
        'run localization test')
    return text


edit('desktop/app_process.v', patch_app_process)
edit('desktop/render.v', patch_render)
edit('desktop/settings_app.v', patch_settings)
edit('desktop/files.v', patch_files)
edit('desktop/editor.v', patch_editor)
edit('desktop/vspace.v', patch_vspace)
edit('desktop/terminal.v', patch_terminal)
edit('desktop/activity.v', patch_activity)
edit('desktop/registration.v', patch_registration)
edit('build-desktop-aarch64.sh', patch_build)
edit('build-desktop-amd64.sh', patch_build)
edit('desktop/tools/test-settings.sh', patch_test_settings)

# Complete keys needed by source-formatted strings and the region preview.
for language, values in {
    'en': {
        'clock.am': 'AM',
        'clock.pm': 'PM',
        'settings.region.us': 'United States',
        'settings.region.russia': 'Russia',
        'files.cannot_open': 'cannot open',
    },
    'ru': {
        'clock.am': 'ДП',
        'clock.pm': 'ПП',
        'settings.region.us': 'Соединённые Штаты',
        'settings.region.russia': 'Россия',
        'files.cannot_open': 'не удалось открыть',
    },
}.items():
    path = Path(f'desktop/translations/{language}.json')
    data = json.loads(path.read_text())
    data.update(values)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')

Path('desktop/tools/tests/localization_test.v').write_text(r'''// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn localization_find(root ui2.Element, action string) ?ui2.Element {
\tif root.id == action || root.action_id == action {
\t\treturn root
\t}
\tfor child in root.children {
\t\tfound := localization_find(child, action) or { continue }
\t\treturn found
\t}
\treturn none
}

fn test_builtin_i18n_catalog_switches_english_and_russian() {
\tdesktop_i18n_loaded = false
\tdesktop_i18n_set_language(.en)
\tassert desktop_tr('app.settings') == 'Settings'
\tassert desktop_tr('settings.language.title') == 'System Language'
\tdesktop_i18n_set_language(.ru)
\tassert desktop_tr('app.settings') == 'Настройки'
\tassert desktop_tr('settings.language.title') == 'Язык системы'
\tassert desktop_i18n_text('Files') == 'Файлы'
\tassert desktop_month_short(.ru, 1) == 'янв'
\tassert desktop_weekday_short(.ru, 4) == 'Чт'
}

fn test_language_region_is_ui2_and_changes_shared_setting() {
\tmut desktop := Desktop{}
\tdesktop_i18n_set_language(.en)
\tmut app := SettingsApp{ desktop: &desktop, category: .language_region }
\troot := app.build(ui2.rect(0, 0, 620, 376)) or { panic(err) }
\trussian := localization_find(root, '${settings_action_language}1') or { panic('missing Russian ui2 choice') }
\tassert russian.kind == .button
\tassert russian.text == 'Русский'
\tapp.handle('${settings_action_language}1') or { panic(err) }
\tassert desktop.settings.language == .ru
\tassert desktop_i18n_current_language() == .ru
\tassert SettingsCategory.settings.title() == 'Настройки' if false
}

fn test_language_round_trips_through_app_wire_state() {
\tstate := AppWireState{
\t\tsettings: Settings{ language: .ru }
\t\trequested_scale: desktop_scale_100
\t}
\tmut encoded := []u8{}
\twire_put_state(mut encoded, state)
\tmut reader := WireReader{ data: encoded }
\tdecoded := wire_take_state(mut reader) or { panic(err) }
\tassert reader.index == encoded.len
\tassert decoded.settings.language == .ru
}

fn test_cyrillic_glyphs_are_present() {
\tfaces := load_fonts()
\tdefer {
\t\tfor face in faces {
\t\t\tunsafe {
\t\t\t\tface.glyphs.free()
\t\t\t\tface.pixels.free()
\t\t\t}
\t\t}
\t\tunsafe { faces.free() }
\t}
\tassert faces.len > 0
\tassert faces[0].glyph_for(u32(0x042f)).width > 0
\tassert faces[0].text_width('Настройки') > 0
}
''')

print('desktop i18n integration patches applied')
