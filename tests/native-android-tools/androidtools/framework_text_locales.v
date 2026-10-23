// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Keep the real ordered locale list on Paint (including copies and reset) and
// let TextView share it through its TextPaint. This does not add script shaping
// or locale-sensitive glyph fallback to the native rasterizer.
fn framework_text_locales(smali string) ! {
 paint := 'Landroid/graphics/Paint;'
 list := 'Landroid/os/LocaleList;'
 locale := 'Ljava/util/Locale;'
 file := smali + '/android/graphics/Paint.smali'
 mut text := os.read_file(file)! + '\n.field private vinixTextLocales:${list}\n'
 for sig in ['<init>()V', '<init>(Landroid/graphics/Paint;)V', 'set(Landroid/graphics/Paint;)V', 'reset()V'] {
  start := text.index(' ' + sig + '\n') or { return error('missing Paint ' + sig) }
  end := start + (text[start..].index('.end method') or { return error('unterminated Paint ' + sig) })
  mut body := text[start..end]
  init := if sig in ['<init>()V', 'reset()V'] {
   'invoke-static {}, ${list}->getAdjustedDefault()${list}\nmove-result-object v0\n'
  } else { 'iget-object v0, p1, ${paint}->vinixTextLocales:${list}\n' }
  body = body.replace('return-void', init + 'iput-object v0, p0, ${paint}->vinixTextLocales:${list}\n' + if sig.starts_with('set(') { ':locale_done\nreturn-void' } else { 'return-void' })
  if sig.starts_with('set(') {
   at := body.index('    iget-wide') or { return error('missing Paint.set native body') }
   body = body[..at] + 'if-eq p0, p1, :locale_done\n' + body[at..]
  }
  text = text[..start] + body + text[end..]
 }
 text += touch_method('public getTextLocales()${list}', 'iget-object v0, p0, ${paint}->vinixTextLocales:${list}\nreturn-object v0')
 text = framework_replace_method(text, 'getTextLocale()${locale}', touch_method('public getTextLocale()${locale}', 'invoke-virtual {p0}, ${paint}->getTextLocales()${list}\nmove-result-object v0\nconst/4 v1, 0\ninvoke-virtual {v0, v1}, ${list}->get(I)${locale}\nmove-result-object v0\nreturn-object v0'))!
 invalid := '\n:invalid\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "text locales cannot be null or empty"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0'
 text += touch_method('public setTextLocales(${list})V', 'if-eqz p1, :invalid\ninvoke-virtual {p1}, ${list}->isEmpty()Z\nmove-result v0\nif-nez v0, :invalid\niput-object p1, p0, ${paint}->vinixTextLocales:${list}\nreturn-void' + invalid)
 text += touch_method('public setTextLocale(${locale})V', 'if-eqz p1, :invalid\nconst/4 v0, 1\nnew-array v0, v0, [Ljava/util/Locale;\nconst/4 v1, 0\naput-object p1, v0, v1\nnew-instance v1, ${list}\ninvoke-direct {v1, v0}, ${list}-><init>([Ljava/util/Locale;)V\ninvoke-virtual {p0, v1}, ${paint}->setTextLocales(${list})V\nreturn-void' + invalid)
 os.write_file(file, text)!
 view := 'Landroid/widget/TextView;'
 mut widget := os.read_file(smali + '/android/widget/TextView.smali')!
 for plural, kind in {'': locale, 's': list} {
  widget += touch_method('public getTextLocale${plural}()${kind}', 'invoke-virtual {p0}, ${view}->getPaint()Landroid/text/TextPaint;\nmove-result-object v0\ninvoke-virtual {v0}, ${paint}->getTextLocale${plural}()${kind}\nmove-result-object v0\nreturn-object v0')
  widget += touch_method('public setTextLocale${plural}(${kind})V', 'invoke-virtual {p0}, ${view}->getPaint()Landroid/text/TextPaint;\nmove-result-object v0\ninvoke-virtual {v0, p1}, ${paint}->setTextLocale${plural}(${kind})V\ninvoke-virtual {p0}, ${view}->nullLayouts()V\ninvoke-virtual {p0}, Landroid/view/View;->requestLayout()V\ninvoke-virtual {p0}, Landroid/view/View;->invalidate()V\nreturn-void')
 }
 os.write_file(smali + '/android/widget/TextView.smali', widget)!
}
