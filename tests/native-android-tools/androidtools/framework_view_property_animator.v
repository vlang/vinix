// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Retain the upstream animator, including its scheduling and listener dispatch.
// Z uses the same PropertyValuesHolder path as the existing Y animation.
pub fn framework_view_property_animator(smali string) ! {
 animator_path := smali + '/android/view/ViewPropertyAnimator.smali'
 view_path := smali + '/android/view/View.smali'
 animator := os.read_file(animator_path)!
 mut view := os.read_file(view_path)!
 signature := '.method public translationY(F)Landroid/view/ViewPropertyAnimator;\n'
 if animator.count(signature) != 1 || animator.contains('.method public translationZ(') ||
  view.contains('.field private vinixTranslationZ:F') ||
  !view.contains('.field public static final TRANSLATION_Z:Landroid/util/Property;') {
  return error('unexpected ViewPropertyAnimator translationZ provider input')
 }
 start := animator.index(signature) or { return error('missing translationY') }
 end := start + (animator[start..].index('.end method') or { return error('unterminated translationY') }) + '.end method'.len
 translation_y := animator[start..end]
 if translation_y.count('->TRANSLATION_Y:') != 1 ||
  translation_y.count('->scheduleAutoStart()V') != 1 {
  return error('unexpected ViewPropertyAnimator translationY implementation')
 }
 translation_z := translation_y.replace('translationY(', 'translationZ(').replace('->TRANSLATION_Y:', '->TRANSLATION_Z:')
 view += '\n.field private vinixTranslationZ:F\n'
 view = framework_replace_method(view, 'getTranslationZ()F', '.method public getTranslationZ()F\n.locals 1\n' +
  'iget v0, p0, Landroid/view/View;->vinixTranslationZ:F\nreturn v0\n.end method')!
 view = framework_replace_method(view, 'setTranslationZ(F)V', '.method public setTranslationZ(F)V\n.locals 1\n' +
  'iget v0, p0, Landroid/view/View;->vinixTranslationZ:F\ncmpl-float v0, v0, p1\nif-eqz v0, :done\n' +
  'iput p1, p0, Landroid/view/View;->vinixTranslationZ:F\ninvoke-virtual {p0}, Landroid/view/View;->invalidate()V\n' +
  ':done\nreturn-void\n.end method')!
 // Absolute Z is the elevation plus the animated translation, as for X/Y.
 view = framework_replace_method(view, 'getZ()F', '.method public getZ()F\n.locals 2\n' +
  'invoke-virtual {p0}, Landroid/view/View;->getElevation()F\nmove-result v0\n' +
  'invoke-virtual {p0}, Landroid/view/View;->getTranslationZ()F\nmove-result v1\n' +
  'add-float/2addr v0, v1\nreturn v0\n.end method')!
 // Validate both providers before writing either file.
 os.write_file(animator_path, animator + '\n' + translation_z + '\n')!
 os.write_file(view_path, view)!
}
