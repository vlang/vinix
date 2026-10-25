// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The WS view stores pixels. Keep conversion at the Java API boundary and
// keep its TextPaint in the same units as native measurement and drawing.
pub fn framework_text_size(smali string) ! {
 path := smali + '/android/widget/TextView.smali'
 mut text := os.read_file(path)!
 if text.contains('native_setTextSize(F)V') {
  return error('TextView text size is already extended')
 }
 owner := 'Landroid/widget/TextView;'
 // ATL's two style reads already resolve their dimensions to pixels. They
 // must bypass the public one-argument SP convenience method.
 for register in ['v2', 'v0'] {
  before := 'invoke-virtual {p0, ${register}}, ${owner}->setTextSize(F)V'
  if text.count(before) != 1 { return error('unexpected TextView style size call: ' + register) }
  text = text.replace(before, 'const/4 v3, 0\ninvoke-direct {p0, ${register}, v3}, ${owner}->vinixSetTextSizePixels(FZ)V')
 }
 // Preserve WS's existing 18px default when no style supplies a size, while
 // initializing the previously independent TextPaint to the same value.
 init := '    iput-object v0, p0, ${owner}->paint:Landroid/text/TextPaint;'
 if text.count(init) != 1 { return error('unexpected TextView paint initialization') }
 text = text.replace(init, init + '\nconst/high16 v2, 0x41900000\ninvoke-virtual {v0, v2}, Landroid/graphics/Paint;->setTextSize(F)V\niput v2, p0, ${owner}->vinixTextSizePixels:F')
 text += '\n.field private vinixTextSizePixels:F\n'
 text = framework_replace_method(text, 'setTextSize(F)V', touch_method('public setTextSize(F)V', '
const/4 v0, 2
invoke-virtual {p0, v0, p1}, ${owner}->setTextSize(IF)V
return-void'))!
 text = framework_replace_method(text, 'setTextSize(IF)V', touch_method('public setTextSize(IF)V', '
invoke-virtual {p0}, Landroid/view/View;->getResources()Landroid/content/res/Resources;
move-result-object v0
invoke-virtual {v0}, Landroid/content/res/Resources;->getDisplayMetrics()Landroid/util/DisplayMetrics;
move-result-object v0
invoke-static {p1, p2, v0}, Landroid/util/TypedValue;->applyDimension(IFLandroid/util/DisplayMetrics;)F
move-result v0
const/4 v1, 1
invoke-direct {p0, v0, v1}, ${owner}->vinixSetTextSizePixels(FZ)V
return-void'))!
 text = framework_replace_method(text, 'getTextSize()F', touch_method('public getTextSize()F', '
iget-object v0, p0, ${owner}->paint:Landroid/text/TextPaint;
invoke-virtual {v0}, Landroid/graphics/Paint;->getTextSize()F
move-result v0
return v0'))!
 text += touch_method('private vinixSetTextSizePixels(FZ)V', '
const/4 v0, 0
cmpl-float v0, p1, v0
if-ltz v0, :done
iget-object v0, p0, ${owner}->paint:Landroid/text/TextPaint;
invoke-virtual {v0}, Landroid/graphics/Paint;->getTextSize()F
move-result v1
cmpl-float v1, v1, p1
if-nez v1, :update
iget v1, p0, ${owner}->vinixTextSizePixels:F
cmpl-float v1, v1, p1
if-eqz v1, :done
:update
invoke-virtual {v0, p1}, Landroid/graphics/Paint;->setTextSize(F)V
invoke-direct {p0, p1}, ${owner}->native_setTextSize(F)V
iput p1, p0, ${owner}->vinixTextSizePixels:F
if-eqz p2, :done
invoke-virtual {p0}, ${owner}->nullLayouts()V
invoke-virtual {p0}, Landroid/view/View;->requestLayout()V
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
:done
return-void')
 text += '\n.method private native native_setTextSize(F)V\n.end method\n'
 os.write_file(path, text)!
 // ATL has no-op overrides on Button/EditText and native overrides on the
 // checked widgets. All must use TextView's conversion and invalidation path.
 for class, parent in {'Button': 'TextView', 'EditText': 'TextView',
  'CompoundButton': 'Button', 'CheckBox': 'CompoundButton', 'RadioButton': 'CompoundButton'} {
  widget := smali + '/android/widget/' + class + '.smali'
  source := framework_replace_method(os.read_file(widget)!, 'setTextSize(F)V',
   '.method public setTextSize(F)V\n.locals 0\ninvoke-super {p0, p1}, Landroid/widget/${parent};->setTextSize(F)V\nreturn-void\n.end method')!
  os.write_file(widget, source)!
 }
}
