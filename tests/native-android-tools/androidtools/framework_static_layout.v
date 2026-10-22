// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Preserve the Android builder option on the built layout. WS currently uses
// one font per layout, so there are no fallback runs to enlarge line metrics.
// Keep the option available to the renderer when font fallback is implemented.
fn framework_static_layout_fallback(smali string) ! {
 builder := 'Landroid/text/StaticLayout$Builder;'
 layout := 'Landroid/text/Layout;'
 path := smali + '/android/text/StaticLayout$Builder.smali'
 mut text := os.read_file(path)! + '\n.field private vinixFallbackLineSpacing:Z\n'
 text = framework_replace_method(text, 'setUseLineSpacingFromFallbacks(Z)${builder}',
  touch_method('public setUseLineSpacingFromFallbacks(Z)${builder}',
   'iput-boolean p1, p0, ${builder}->vinixFallbackLineSpacing:Z\nreturn-object p0'))!
 text = framework_replace_method(text, 'build()Landroid/text/StaticLayout;',
  touch_method('public build()Landroid/text/StaticLayout;', '
iget-object v0, p0, ${builder}->layout:Landroid/text/StaticLayout;
iget-boolean v1, p0, ${builder}->vinixFallbackLineSpacing:Z
iput-boolean v1, v0, ${layout}->vinixFallbackLineSpacing:Z
return-object v0'))!
 os.write_file(path, text)!
 layout_path := smali + '/android/text/Layout.smali'
 mut base := os.read_file(layout_path)! + '\n.field vinixFallbackLineSpacing:Z\n'
 base = framework_replace_method(base, 'isFallbackLineSpacingEnabled()Z',
  touch_method('public isFallbackLineSpacingEnabled()Z',
   'iget-boolean v0, p0, ${layout}->vinixFallbackLineSpacing:Z\nreturn v0'))!
 os.write_file(layout_path, base)!
}
