// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// WS currently draws axis-aligned layouts, clipping at each ancestor. Query
// those same bounds in Java: no toolkit widget or native desktop coordinates
// are involved. Location queries must remain independent of visible clipping.
fn framework_view_geometry(smali string) ! {
 path := smali + '/android/view/View.smali'
 mut text := os.read_file(path)!
 text = framework_replace_method(text, 'getGlobalVisibleRect(Landroid/graphics/Rect;)Z',
  '.method public getGlobalVisibleRect(Landroid/graphics/Rect;)Z\n.locals 1\nconst/4 v0, 0\n' +
  'invoke-virtual {p0, p1, v0}, Landroid/view/View;->getGlobalVisibleRect(Landroid/graphics/Rect;Landroid/graphics/Point;)Z\nmove-result v0\nreturn v0\n.end method')!
 text = framework_replace_method(text, 'getGlobalVisibleRect(Landroid/graphics/Rect;Landroid/graphics/Point;)Z',
  '.method public getGlobalVisibleRect(Landroid/graphics/Rect;Landroid/graphics/Point;)Z\n.locals 8\n' + '
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
invoke-virtual {p1, v2, v3}, Landroid/graphics/Rect;->offset(II)V
if-eqz p2, :clip
invoke-virtual {p2, v2, v3}, Landroid/graphics/Point;->offset(II)V
:clip
invoke-virtual {v1}, Landroid/view/View;->getWidth()I
move-result v4
invoke-virtual {v1}, Landroid/view/View;->getHeight()I
move-result v5
const/4 v6, 0
invoke-virtual {p1, v6, v6, v4, v5}, Landroid/graphics/Rect;->intersect(IIII)Z
move-result v6
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
