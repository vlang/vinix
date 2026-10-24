// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Keep the ColorStateList in ConstantState so newDrawable and mutate retain
// stateful fills. The provider's integer color remains its opacity cache.
fn framework_gradient_colors(smali string) ! {
 state := smali + '/android/graphics/drawable/GradientDrawable$GradientState.smali'
 mut data := os.read_file(state)!
 data += '\n.field public vinixSolidColors:Landroid/content/res/ColorStateList;\n'
 copy := 'iput v0, p0, Landroid/graphics/drawable/GradientDrawable$GradientState;->mSolidColor:I'
 if !data.contains(copy) { return error('missing gradient state copy') }
 data = data.replace(copy, copy + '\niget-object v0, p1, Landroid/graphics/drawable/GradientDrawable$GradientState;->vinixSolidColors:Landroid/content/res/ColorStateList;\niput-object v0, p0, Landroid/graphics/drawable/GradientDrawable$GradientState;->vinixSolidColors:Landroid/content/res/ColorStateList;')
 for signature in ['setSolidColor(I)V', 'setColors([I)V'] {
  start := data.index(' ' + signature + '\n') or { return error('missing gradient color setter') }
  end := start + (data[start..].index('.end method') or { return error('unterminated color setter') })
  body := data[start..end]
  marker := 'invoke-direct {p0}, Landroid/graphics/drawable/GradientDrawable$GradientState;->computeOpacity()V'
  color := if signature.starts_with('setSolidColor') { 'invoke-static {p1}, Landroid/content/res/ColorStateList;->valueOf(I)Landroid/content/res/ColorStateList;\nmove-result-object v0\n' } else { 'const/4 v0, 0\n' }
  data = data[..start] + body.replace(marker, color + 'iput-object v0, p0, Landroid/graphics/drawable/GradientDrawable$GradientState;->vinixSolidColors:Landroid/content/res/ColorStateList;\n' + marker) + data[end..]
 }
 os.write_file(state, data)!
 path := smali + '/android/graphics/drawable/GradientDrawable.smali'
 mut text := os.read_file(path)!
 text = framework_replace_method(text, 'setColor(I)V', '.method public setColor(I)V
.locals 2
iget-object v0, p0, Landroid/graphics/drawable/GradientDrawable;->mGradientState:Landroid/graphics/drawable/GradientDrawable$GradientState;
invoke-virtual {v0, p1}, Landroid/graphics/drawable/GradientDrawable$GradientState;->setSolidColor(I)V
iget-object v0, p0, Landroid/graphics/drawable/GradientDrawable;->mFillPaint:Landroid/graphics/Paint;
invoke-virtual {v0, p1}, Landroid/graphics/Paint;->setColor(I)V
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->setShader(Landroid/graphics/Shader;)Landroid/graphics/Shader;
const/4 v0, 1
iput-boolean v0, p0, Landroid/graphics/drawable/GradientDrawable;->mRectIsDirty:Z
invoke-virtual {p0}, Landroid/graphics/drawable/GradientDrawable;->invalidateSelf()V
return-void
.end method')!
 text += '
.method public setColor(Landroid/content/res/ColorStateList;)V
.locals 2
const/4 v1, 0
if-eqz p1, :set
invoke-virtual {p0}, Landroid/graphics/drawable/GradientDrawable;->getState()[I
move-result-object v0
invoke-virtual {p1, v0, v1}, Landroid/content/res/ColorStateList;->getColorForState([II)I
move-result v1
:set
invoke-virtual {p0, v1}, Landroid/graphics/drawable/GradientDrawable;->setColor(I)V
iget-object v0, p0, Landroid/graphics/drawable/GradientDrawable;->mGradientState:Landroid/graphics/drawable/GradientDrawable$GradientState;
iput-object p1, v0, Landroid/graphics/drawable/GradientDrawable$GradientState;->vinixSolidColors:Landroid/content/res/ColorStateList;
return-void
.end method

.method public getColor()Landroid/content/res/ColorStateList;
.locals 1
iget-object v0, p0, Landroid/graphics/drawable/GradientDrawable;->mGradientState:Landroid/graphics/drawable/GradientDrawable$GradientState;
iget-object v0, v0, Landroid/graphics/drawable/GradientDrawable$GradientState;->vinixSolidColors:Landroid/content/res/ColorStateList;
return-object v0
.end method

.method public isStateful()Z
.locals 3
iget-object v0, p0, Landroid/graphics/drawable/GradientDrawable;->mGradientState:Landroid/graphics/drawable/GradientDrawable$GradientState;
iget-object v1, v0, Landroid/graphics/drawable/GradientDrawable$GradientState;->vinixSolidColors:Landroid/content/res/ColorStateList;
if-eqz v1, :tint
invoke-virtual {v1}, Landroid/content/res/ColorStateList;->isStateful()Z
move-result v2
if-nez v2, :yes
:tint
iget-object v1, v0, Landroid/graphics/drawable/GradientDrawable$GradientState;->mTint:Landroid/content/res/ColorStateList;
if-eqz v1, :no
invoke-virtual {v1}, Landroid/content/res/ColorStateList;->isStateful()Z
move-result v2
if-nez v2, :yes
:no
const/4 v2, 0
return v2
:yes
const/4 v2, 1
return v2
.end method

.method protected onStateChange([I)Z
.locals 5
const/4 v4, 0
iget-object v0, p0, Landroid/graphics/drawable/GradientDrawable;->mGradientState:Landroid/graphics/drawable/GradientDrawable$GradientState;
iget-object v1, v0, Landroid/graphics/drawable/GradientDrawable$GradientState;->vinixSolidColors:Landroid/content/res/ColorStateList;
if-eqz v1, :tint
const/4 v2, 0
invoke-virtual {v1, p1, v2}, Landroid/content/res/ColorStateList;->getColorForState([II)I
move-result v2
iget-object v1, p0, Landroid/graphics/drawable/GradientDrawable;->mFillPaint:Landroid/graphics/Paint;
invoke-virtual {v1}, Landroid/graphics/Paint;->getColor()I
move-result v3
if-eq v2, v3, :tint
invoke-virtual {v1, v2}, Landroid/graphics/Paint;->setColor(I)V
const/4 v4, 1
:tint
iget-object v1, v0, Landroid/graphics/drawable/GradientDrawable$GradientState;->mTint:Landroid/content/res/ColorStateList;
if-eqz v1, :done
iget-object v2, v0, Landroid/graphics/drawable/GradientDrawable$GradientState;->mTintMode:Landroid/graphics/PorterDuff$Mode;
if-eqz v2, :done
iget-object v3, p0, Landroid/graphics/drawable/GradientDrawable;->mTintFilter:Landroid/graphics/PorterDuffColorFilter;
invoke-virtual {p0, v3, v1, v2}, Landroid/graphics/drawable/GradientDrawable;->updateTintFilter(Landroid/graphics/PorterDuffColorFilter;Landroid/content/res/ColorStateList;Landroid/graphics/PorterDuff$Mode;)Landroid/graphics/PorterDuffColorFilter;
move-result-object v3
iput-object v3, p0, Landroid/graphics/drawable/GradientDrawable;->mTintFilter:Landroid/graphics/PorterDuffColorFilter;
const/4 v4, 1
:done
if-eqz v4, :return
invoke-virtual {p0}, Landroid/graphics/drawable/GradientDrawable;->invalidateSelf()V
:return
return v4
.end method
'
 // Construction and mutation rebuild the paint from ConstantState.
 marker := '    :cond_4e\n    return-void'
 if !text.contains(marker) { return error('missing gradient paint initialization') }
 text = text.replace(marker, '    :cond_4e\ninvoke-virtual {p0}, Landroid/graphics/drawable/GradientDrawable;->getState()[I\nmove-result-object v0\ninvoke-virtual {p0, v0}, Landroid/graphics/drawable/GradientDrawable;->onStateChange([I)Z\n    return-void')
 os.write_file(path, text)!
}

// XML fillType belongs to each vector path, including when the renderer reuses
// its temporary Path for paths with different rules. Path.addPath preserves the
// destination fill rule, so apply the parsed rule to that destination explicitly.
fn framework_vector_fill_rules(smali string) ! {
 path := smali + '/android/graphics/drawable/VectorDrawable$VFullPath.smali'
 mut text := os.read_file(path)!
 start := text.index('.method private updateStateFromTypedArray(Landroid/content/res/TypedArray;)V\n') or { return error('missing vector path parser') }
 end := start + (text[start..].index('.end method') or { return error('unterminated vector path parser') })
 parser := text[start..end]
 marker := '    iput v0, p0, Landroid/graphics/drawable/VectorDrawable$VFullPath;->mTrimPathStart:F'
 if parser.count(marker) != 1 { return error('unexpected vector path fill-rule parser entry') }
 text = text[..start] + parser.replace(marker, marker + '\n\n    const/16 v0, 0xd\n    iget v1, p0, Landroid/graphics/drawable/VectorDrawable$VFullPath;->mFillRule:I\n    invoke-virtual {p1, v0, v1}, Landroid/content/res/TypedArray;->getInt(II)I\n    move-result v0\n    iput v0, p0, Landroid/graphics/drawable/VectorDrawable$VFullPath;->mFillRule:I') + text[end..]
 os.write_file(path, text)!
 renderer := smali + '/android/graphics/drawable/VectorDrawable$VPathRenderer.smali'
 mut drawing := os.read_file(renderer)!
 reset := '    invoke-virtual {v3}, Landroid/graphics/Path;->reset()V'
 if drawing.count(reset) != 1 { return error('unexpected vector render-path reset') }
 drawing = drawing.replace(reset, reset + '\n    sget-object v4, Landroid/graphics/Path$FillType;->WINDING:Landroid/graphics/Path$FillType;\n    invoke-virtual {v3, v4}, Landroid/graphics/Path;->setFillType(Landroid/graphics/Path$FillType;)V')
 fill := '    iget v1, p2, Landroid/graphics/drawable/VectorDrawable$VFullPath;->mFillColor:I'
 if drawing.count(fill) != 1 { return error('unexpected vector path fill-rule draw entry') }
 drawing = drawing.replace(fill, '    iget v1, p2, Landroid/graphics/drawable/VectorDrawable$VFullPath;->mFillRule:I\n    if-nez v1, :vinix_even_odd\n    sget-object v1, Landroid/graphics/Path$FillType;->WINDING:Landroid/graphics/Path$FillType;\n    goto :vinix_fill_rule\n    :vinix_even_odd\n    sget-object v1, Landroid/graphics/Path$FillType;->EVEN_ODD:Landroid/graphics/Path$FillType;\n    :vinix_fill_rule\n    invoke-virtual {v3, v1}, Landroid/graphics/Path;->setFillType(Landroid/graphics/Path$FillType;)V\n\n' + fill)
 os.write_file(renderer, drawing)!
}
