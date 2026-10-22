// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_resource_fonts(smali string) ! {
 resources := smali + '/android/content/res/Resources.smali'
 os.write_file(resources, framework_replace_method(os.read_file(resources)!, 'getFont(I)Landroid/graphics/Typeface;',
  '.method public native getFont(I)Landroid/graphics/Typeface;\n.end method')!)!
 face := smali + '/android/graphics/Typeface.smali'
 os.write_file(face, framework_replace_method(os.read_file(face)!, 'finalize()V', '.method protected native finalize()V\n.end method')!)!
 framework_typefaces(smali)!
 paint := smali + '/android/graphics/Paint.smali'
 mut text := os.read_file(paint)! + '\n.field private vinixTypeface:Landroid/graphics/Typeface;\n'
 for signature in ['getTypeface()Landroid/graphics/Typeface;', 'setTypeface(Landroid/graphics/Typeface;)Landroid/graphics/Typeface;', 'measureText(Ljava/lang/String;II)F', 'measureText([CII)F'] {
  text = framework_replace_method(text, signature, '.method public native ' + signature + '\n.end method')!
 }
 for signature in ['measureText(Ljava/lang/String;)F', 'measureText(Ljava/lang/CharSequence;II)F'] {
  start := text.index(' ' + signature + '\n') or { return error('missing Paint method ' + signature) }
  locals := start + (text[start..].index('.registers ') or { return error('missing Paint registers') })
  body := locals + (text[locals..].index('\n') or { return error('missing Paint body') }) + 1
  text = text[..body] + '\nif-nez p1, :text_present\nnew-instance v0, Ljava/lang/IllegalArgumentException;\ninvoke-direct {v0}, Ljava/lang/IllegalArgumentException;-><init>()V\nthrow v0\n:text_present\n' + text[body..]
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
  '.method public setTypeface(Landroid/graphics/Typeface;I)V\n.locals 0\nif-lez p2, :set\ninvoke-static {p1, p2}, Landroid/graphics/Typeface;->create(Landroid/graphics/Typeface;I)Landroid/graphics/Typeface;\nmove-result-object p1\n:set\ninvoke-virtual {p0, p1}, Landroid/widget/TextView;->setTypeface(Landroid/graphics/Typeface;)V\nreturn-void\n.end method')!
 os.write_file(view, view_text)!
}
