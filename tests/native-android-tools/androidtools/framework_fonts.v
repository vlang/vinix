// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_resource_fonts(smali string) ! {
 resources := smali + '/android/content/res/Resources.smali'
 os.write_file(resources, framework_replace_method(os.read_file(resources)!, 'getFont(I)Landroid/graphics/Typeface;',
  '.method public native getFont(I)Landroid/graphics/Typeface;\n.end method')!)!
 face := smali + '/android/graphics/Typeface.smali'
 os.write_file(face, framework_replace_method(os.read_file(face)!, 'finalize()V', '.method protected native finalize()V\n.end method')!)!
 paint := smali + '/android/graphics/Paint.smali'
 mut text := os.read_file(paint)! + '\n.field private vinixTypeface:Landroid/graphics/Typeface;\n'
 for signature in ['getTypeface()Landroid/graphics/Typeface;', 'setTypeface(Landroid/graphics/Typeface;)Landroid/graphics/Typeface;'] {
  text = framework_replace_method(text, signature, '.method public native ' + signature + '\n.end method')!
 }
 for signature in ['<init>(Landroid/graphics/Paint;)V', 'set(Landroid/graphics/Paint;)V', 'reset()V'] {
  start := text.index(' ' + signature + '\n') or { return error('missing Paint method ' + signature) }
  end := start + (text[start..].index('.end method') or { return error('unterminated Paint method') })
  original := text[start..end]
  copy := if signature == 'reset()V' { 'const/4 v0, 0\n' } else { 'iget-object v0, p1, Landroid/graphics/Paint;->vinixTypeface:Landroid/graphics/Typeface;\n' }
  text = text[..start] + original.replace('return-void', copy + 'iput-object v0, p0, Landroid/graphics/Paint;->vinixTypeface:Landroid/graphics/Typeface;\nreturn-void') + text[end..]
 }
 os.write_file(paint, text)!
 view := smali + '/android/widget/TextView.smali'
 mut view_text := os.read_file(view)! + '\n.field private vinixTypeface:Landroid/graphics/Typeface;\n'
 for signature in ['getTypeface()Landroid/graphics/Typeface;', 'setTypeface(Landroid/graphics/Typeface;)V'] {
  view_text = framework_replace_method(view_text, signature, '.method public native ' + signature + '\n.end method')!
 }
 view_text = framework_replace_method(view_text, 'setTypeface(Landroid/graphics/Typeface;I)V',
  '.method public setTypeface(Landroid/graphics/Typeface;I)V\n.locals 0\ninvoke-virtual {p0, p1}, Landroid/widget/TextView;->setTypeface(Landroid/graphics/Typeface;)V\nreturn-void\n.end method')!
 os.write_file(view, view_text)!
}
