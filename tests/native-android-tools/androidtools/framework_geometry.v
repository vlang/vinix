// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// WS currently draws axis-aligned layouts. Query those same bounds in Java,
// including translations and ViewGroup clipping. Like ViewGroup's Android
// contract, round rectangle bounds outward and the optional Point to nearest
// at each ancestor. Location queries remain independent of visible clipping.
fn framework_view_geometry(smali string) ! {
 framework_viewgroup_clipping(smali)!
 path := smali + '/android/view/View.smali'
 mut text := os.read_file(path)!
 // Retain logical padding and resolve it on demand, like layout direction.
 text += '\n.field private vinixRelativePadding:Z\n.field private vinixPaddingStart:I\n.field private vinixPaddingEnd:I\n'
 text = framework_replace_method(text, 'setPadding(IIII)V', '.method public setPadding(IIII)V\n.locals 1\nconst/4 v0, 0\niput-boolean v0, p0, Landroid/view/View;->vinixRelativePadding:Z\ninvoke-direct {p0, p1, p2, p3, p4}, Landroid/view/View;->vinixSetPadding(IIII)V\nreturn-void\n.end method')!
 text = framework_replace_method(text, 'setPaddingRelative(IIII)V', r'.method public setPaddingRelative(IIII)V
.locals 3
const/4 v0, 1
iput-boolean v0, p0, Landroid/view/View;->vinixRelativePadding:Z
iput p1, p0, Landroid/view/View;->vinixPaddingStart:I
iput p3, p0, Landroid/view/View;->vinixPaddingEnd:I
invoke-virtual {p0}, Landroid/view/View;->getLayoutDirection()I
move-result v0
const/4 v1, 1
move v2, p3
if-ne v0, v1, :apply
move v2, p1
move p1, p3
:apply
invoke-direct {p0, p1, p2, v2, p4}, Landroid/view/View;->vinixSetPadding(IIII)V
return-void
.end method')!
 text = framework_replace_method(text, 'isPaddingRelative()Z', '.method public isPaddingRelative()Z\n.locals 1\niget-boolean v0, p0, Landroid/view/View;->vinixRelativePadding:Z\nreturn v0\n.end method')!
 for side in ['Left', 'Right', 'Start', 'End'] {
  mut body := 'invoke-direct {p0}, Landroid/view/View;->vinixResolvePadding()V\n'
  if side == 'Start' || side == 'End' {
   primary := if side == 'Start' { 'Left' } else { 'Right' }
   other := if side == 'Start' { 'Right' } else { 'Left' }
   body += 'invoke-virtual {p0}, Landroid/view/View;->getLayoutDirection()I\nmove-result v0\nconst/4 v1, 1\nif-eq v0, v1, :rtl\niget v0, p0, Landroid/view/View;->padding' + primary + ':I\nreturn v0\n:rtl\niget v0, p0, Landroid/view/View;->padding' + other + ':I\nreturn v0\n'
  } else {
   body += 'iget v0, p0, Landroid/view/View;->padding' + side + ':I\nreturn v0\n'
  }
  text = framework_replace_method(text, 'getPadding' + side + '()I', '.method public getPadding' + side + '()I\n.locals 2\n' + body + '.end method')!
 }
 text += r'
.method private vinixResolvePadding()V
.locals 4
iget-boolean v0, p0, Landroid/view/View;->vinixRelativePadding:Z
if-eqz v0, :done
iget v0, p0, Landroid/view/View;->vinixPaddingStart:I
iget v1, p0, Landroid/view/View;->vinixPaddingEnd:I
invoke-virtual {p0}, Landroid/view/View;->getLayoutDirection()I
move-result v2
const/4 v3, 1
if-ne v2, v3, :apply
move v2, v0
move v0, v1
move v1, v2
:apply
iget v2, p0, Landroid/view/View;->paddingTop:I
iget v3, p0, Landroid/view/View;->paddingBottom:I
invoke-direct {p0, v0, v2, v1, v3}, Landroid/view/View;->vinixSetPadding(IIII)V
:done
return-void
.end method

.method private vinixSetPadding(IIII)V
.locals 7
iget v0, p0, Landroid/view/View;->paddingLeft:I
if-ne v0, p1, :apply
iget v0, p0, Landroid/view/View;->paddingTop:I
if-ne v0, p2, :apply
iget v0, p0, Landroid/view/View;->paddingRight:I
if-ne v0, p3, :apply
iget v0, p0, Landroid/view/View;->paddingBottom:I
if-eq v0, p4, :done
:apply
iput p1, p0, Landroid/view/View;->paddingLeft:I
iput p2, p0, Landroid/view/View;->paddingTop:I
iput p3, p0, Landroid/view/View;->paddingRight:I
iput p4, p0, Landroid/view/View;->paddingBottom:I
move-object v0, p0
iget-wide v1, p0, Landroid/view/View;->widget:J
move v3, p1
move v4, p2
move v5, p3
move v6, p4
invoke-virtual/range {v0 .. v6}, Landroid/view/View;->native_setPadding(JIIII)V
invoke-virtual {p0}, Landroid/view/View;->requestLayout()V
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
:done
return-void
.end method
'
 measure_start := text.index('.method public final measure(II)V\n') or { return error('missing View measure method') }
 measure_end := measure_start + (text[measure_start..].index('.end method') or { return error('unterminated View measure method') }) + '.end method'.len
 measure_method := text[measure_start..measure_end]
 measure := '    iget-boolean v0, p0, Landroid/view/View;->layoutRequested:Z'
 if measure_method.count(measure) != 1 { return error('unexpected View measurement padding entry') }
 // Resolve before the measure cache check; other methods also read this flag.
 patched_measure := measure_method.replace(measure, '    invoke-direct {p0}, Landroid/view/View;->vinixResolvePadding()V\n\n' + measure)
 text = text[..measure_start] + patched_measure + text[measure_end..]
 text = framework_replace_method(text, 'getGlobalVisibleRect(Landroid/graphics/Rect;)Z',
  '.method public getGlobalVisibleRect(Landroid/graphics/Rect;)Z\n.locals 1\nconst/4 v0, 0\n' +
  'invoke-virtual {p0, p1, v0}, Landroid/view/View;->getGlobalVisibleRect(Landroid/graphics/Rect;Landroid/graphics/Point;)Z\nmove-result v0\nreturn v0\n.end method')!
 text = framework_replace_method(text, 'getGlobalVisibleRect(Landroid/graphics/Rect;Landroid/graphics/Point;)Z',
  '.method public getGlobalVisibleRect(Landroid/graphics/Rect;Landroid/graphics/Point;)Z\n.locals 10\n' + '
invoke-virtual {p0}, Landroid/view/View;->getWidth()I
move-result v0
invoke-virtual {p0}, Landroid/view/View;->getHeight()I
move-result v1
if-lez v0, :empty
if-lez v1, :empty
const/4 v2, 0
invoke-virtual {p1, v2, v2, v0, v1}, Landroid/graphics/Rect;->set(IIII)V
if-eqz p2, :start
iget v0, p0, Landroid/view/View;->scrollX:I
neg-int v0, v0
iget v1, p0, Landroid/view/View;->scrollY:I
neg-int v1, v1
invoke-virtual {p2, v0, v1}, Landroid/graphics/Point;->set(II)V
:start
new-instance v8, Landroid/graphics/RectF;
invoke-direct {v8}, Landroid/graphics/RectF;-><init>()V
move-object v0, p0
const/16 v7, 256
:ancestor
iget-object v1, v0, Landroid/view/View;->parent:Landroid/view/ViewParent;
instance-of v2, v1, Landroid/view/View;
if-eqz v2, :visible
check-cast v1, Landroid/view/View;
iget v2, v0, Landroid/view/View;->left:I
iget v3, v1, Landroid/view/View;->scrollX:I
sub-int/2addr v2, v3
iget v3, v0, Landroid/view/View;->top:I
iget v4, v1, Landroid/view/View;->scrollY:I
sub-int/2addr v3, v4
invoke-virtual {v8, p1}, Landroid/graphics/RectF;->set(Landroid/graphics/Rect;)V
iget v4, v0, Landroid/view/View;->translationX:F
iget v5, v0, Landroid/view/View;->translationY:F
invoke-virtual {v8, v4, v5}, Landroid/graphics/RectF;->offset(FF)V
int-to-float v6, v2
int-to-float v4, v3
invoke-virtual {v8, v6, v4}, Landroid/graphics/RectF;->offset(FF)V
if-eqz p2, :clip
iget v4, p2, Landroid/graphics/Point;->x:I
int-to-float v4, v4
iget v5, v0, Landroid/view/View;->translationX:F
add-float/2addr v4, v5
invoke-static {v4}, Ljava/lang/Math;->round(F)I
move-result v4
iput v4, p2, Landroid/graphics/Point;->x:I
iget v4, p2, Landroid/graphics/Point;->y:I
int-to-float v4, v4
iget v5, v0, Landroid/view/View;->translationY:F
add-float/2addr v4, v5
invoke-static {v4}, Ljava/lang/Math;->round(F)I
move-result v4
iput v4, p2, Landroid/graphics/Point;->y:I
invoke-virtual {p2, v2, v3}, Landroid/graphics/Point;->offset(II)V
:clip
invoke-virtual {v1}, Landroid/view/View;->getWidth()I
move-result v4
invoke-virtual {v1}, Landroid/view/View;->getHeight()I
move-result v5
int-to-float v4, v4
int-to-float v5, v5
const/4 v6, 1
# Bounds are clipped when the parent of this ancestor clips children. The
# root viewport always clips, even when it lets its children overflow.
iget-object v9, v1, Landroid/view/View;->parent:Landroid/view/ViewParent;
if-eqz v9, :bounds
instance-of v2, v9, Landroid/view/ViewGroup;
if-eqz v2, :padding
check-cast v9, Landroid/view/ViewGroup;
invoke-virtual {v9}, Landroid/view/ViewGroup;->getClipChildren()Z
move-result v2
if-eqz v2, :padding
:bounds
const/4 v6, 0
invoke-virtual {v8, v6, v6, v4, v5}, Landroid/graphics/RectF;->intersect(FFFF)Z
move-result v6
if-eqz v6, :rounded
:padding
invoke-direct {v1}, Landroid/view/View;->vinixResolvePadding()V
instance-of v2, v1, Landroid/view/ViewGroup;
if-eqz v2, :rounded
move-object v9, v1
check-cast v9, Landroid/view/ViewGroup;
invoke-virtual {v9}, Landroid/view/ViewGroup;->getClipToPadding()Z
move-result v2
if-eqz v2, :rounded
iget v2, v1, Landroid/view/View;->paddingLeft:I
iget v3, v1, Landroid/view/View;->paddingTop:I
or-int v9, v2, v3
iget v6, v1, Landroid/view/View;->paddingRight:I
or-int/2addr v9, v6
int-to-float v6, v6
sub-float/2addr v4, v6
iget v6, v1, Landroid/view/View;->paddingBottom:I
or-int/2addr v9, v6
int-to-float v6, v6
sub-float/2addr v5, v6
const/4 v6, 1
if-eqz v9, :rounded
int-to-float v2, v2
int-to-float v3, v3
invoke-virtual {v8, v2, v3, v4, v5}, Landroid/graphics/RectF;->intersect(FFFF)Z
move-result v6
:rounded
invoke-virtual {v8, p1}, Landroid/graphics/RectF;->roundOut(Landroid/graphics/Rect;)V
if-eqz v6, :empty
move-object v0, v1
add-int/lit8 v7, v7, -1
if-gtz v7, :ancestor
:empty
const/4 v0, 0
return v0
:visible
const/4 v0, 1
return v0
.end method')!
 // Retain the original protected entrypoint for subclasses invoking it.
 text = framework_replace_method(text, 'native_getGlobalVisibleRect(JLandroid/graphics/Rect;)Z',
  '.method protected native_getGlobalVisibleRect(JLandroid/graphics/Rect;)Z\n.locals 1\n' +
  'invoke-virtual {p0, p3}, Landroid/view/View;->getGlobalVisibleRect(Landroid/graphics/Rect;)Z\nmove-result v0\nreturn v0\n.end method')!
 text = framework_replace_method(text, 'getLocalVisibleRect(Landroid/graphics/Rect;)Z',
  '.method public final getLocalVisibleRect(Landroid/graphics/Rect;)Z\n.locals 4\n' + '
new-instance v0, Landroid/graphics/Point;
invoke-direct {v0}, Landroid/graphics/Point;-><init>()V
invoke-virtual {p0, p1, v0}, Landroid/view/View;->getGlobalVisibleRect(Landroid/graphics/Rect;Landroid/graphics/Point;)Z
move-result v1
if-eqz v1, :done
iget v2, v0, Landroid/graphics/Point;->x:I
neg-int v2, v2
iget v3, v0, Landroid/graphics/Point;->y:I
neg-int v3, v3
invoke-virtual {p1, v2, v3}, Landroid/graphics/Rect;->offset(II)V
:done
return v1
.end method')!
 text = framework_replace_method(text, 'getLocationOnScreen([I)V',
  '.method public getLocationOnScreen([I)V\n.locals 6\n' + '
array-length v0, p1
const/4 v1, 2
if-lt v0, v1, :bad
const/4 v0, 0
const/4 v1, 0
move-object v2, p0
const/16 v5, 256
:ancestor
iget v3, v2, Landroid/view/View;->left:I
int-to-float v3, v3
add-float/2addr v0, v3
iget v3, v2, Landroid/view/View;->translationX:F
add-float/2addr v0, v3
iget v3, v2, Landroid/view/View;->top:I
int-to-float v3, v3
add-float/2addr v1, v3
iget v3, v2, Landroid/view/View;->translationY:F
add-float/2addr v1, v3
iget-object v3, v2, Landroid/view/View;->parent:Landroid/view/ViewParent;
instance-of v4, v3, Landroid/view/View;
if-eqz v4, :done
check-cast v3, Landroid/view/View;
iget v4, v3, Landroid/view/View;->scrollX:I
int-to-float v4, v4
sub-float/2addr v0, v4
iget v4, v3, Landroid/view/View;->scrollY:I
int-to-float v4, v4
sub-float/2addr v1, v4
move-object v2, v3
add-int/lit8 v5, v5, -1
if-gtz v5, :ancestor
:done
invoke-static {v0}, Ljava/lang/Math;->round(F)I
move-result v0
invoke-static {v1}, Ljava/lang/Math;->round(F)I
move-result v1
const/4 v2, 0
aput v0, p1, v2
const/4 v2, 1
aput v1, p1, v2
return-void
:bad
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "location must have at least two elements"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
.end method')!
 os.write_file(path, text)!
}

fn framework_viewgroup_clipping(smali string) ! {
 path := smali + '/android/view/ViewGroup.smali'
 // Negative flags preserve Android's enabled defaults without depending on
 // which constructor a subclass calls.
 mut text := os.read_file(path)! + '\n.field private vinixDontClipChildren:Z\n.field private vinixDontClipToPadding:Z\n'
 for property in ['Children', 'ToPadding'] {
  field := 'Landroid/view/ViewGroup;->vinixDontClip' + property + ':Z'
  text = framework_replace_method(text, 'getClip' + property + '()Z',
   touch_method('public getClip' + property + '()Z', 'iget-boolean v0, p0, ' + field + '\nxor-int/lit8 v0, v0, 1\nreturn v0'))!
  text = framework_replace_method(text, 'setClip' + property + '(Z)V',
   touch_method('public setClip' + property + '(Z)V', 'xor-int/lit8 v0, p1, 1\niget-boolean v1, p0, ' + field + '\nif-eq v0, v1, :done\niput-boolean v0, p0, ' + field + '\ninvoke-virtual {p0}, Landroid/view/View;->invalidate()V\n:done\nreturn-void'))!
 }
 os.write_file(path, text)!
}
