#!/usr/bin/env python3
from pathlib import Path


def one(text, old, new, label):
    if old not in text:
        raise SystemExit(f'{label}: pattern not found')
    return text.replace(old, new, 1)

p = Path('desktop/tools/tests/preferences_test.v')
text = p.read_text()
text = one(text,
    '\t\t\ttheme: .macos\n\t\t\tclock_24_hour: false',
    '\t\t\ttheme: .macos\n\t\t\tlanguage: .ru\n\t\t\tclock_24_hour: false',
    'custom language')
text = one(text,
    'theme=macos\\nclock_24_hour=false',
    'theme=macos\\nlanguage=ru\\nclock_24_hour=false',
    'serialized language')
text = one(text, '\tfor field in 0 .. 9 {', '\tfor field in 0 .. 10 {', 'field count')
text = one(text,
    '\t\t\t5 { settings.clock_24_hour = false }\n\t\t\t6 { settings.clock_show_seconds = false }\n\t\t\t7 { settings.clock_show_date = false }\n\t\t\telse { settings.clock_show_weekday = false }',
    '\t\t\t5 { settings.language = .ru }\n\t\t\t6 { settings.clock_24_hour = false }\n\t\t\t7 { settings.clock_show_seconds = false }\n\t\t\t8 { settings.clock_show_date = false }\n\t\t\telse { settings.clock_show_weekday = false }',
    'language field mutation')
text = one(text,
    '\tassert p.settings.taskbar_mode == .standard\n\tassert p.settings.clock_24_hour',
    '\tassert p.settings.taskbar_mode == .standard\n\tassert p.settings.language == .en\n\tassert p.settings.clock_24_hour',
    'default English')
text = one(text,
    "\t\t'version=1\\ntaskbar_mode=9', 'version=1\\ntheme=other',",
    "\t\t'version=1\\ntaskbar_mode=9', 'version=1\\ntheme=other',\n\t\t'version=1\\nlanguage=fr', 'version=1\\nlanguage=en\\nlanguage=ru',",
    'invalid language values')
p.write_text(text)

# Simplify the generated localization regression to avoid test-only ownership noise.
p = Path('desktop/tools/tests/localization_test.v')
text = p.read_text()
text = text.replace("\tassert SettingsCategory.settings.title() == 'Настройки' if false\n", '')
old = '''fn test_cyrillic_glyphs_are_present() {
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
'''
new = '''fn test_cyrillic_glyphs_are_present() {
\tfaces := load_fonts()
\tassert faces.len > 0
\tassert faces[0].glyph_for(u32(0x042f)).width > 0
\tassert faces[0].text_width('Настройки') > 0
}
'''
if old in text:
    text = text.replace(old, new, 1)
p.write_text(text)

print('localization test expectations updated')
