// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Animation bounds affect this view without measuring or laying out children.
// Keep ATL's size cache in sync so a subsequent layout does not repeat the
// size callback for the same dimensions. WS reads the Java bounds directly.
fn framework_view_frame_bounds(smali string) ! {
 path := smali + '/android/view/View.smali'
 mut text := os.read_file(path)!
 text = framework_replace_method(text, 'setLeftTopRightBottom(IIII)V',
  touch_method('public final setLeftTopRightBottom(IIII)V', '
invoke-virtual {p0, p1, p2, p3, p4}, Landroid/view/View;->setFrame(IIII)Z
return-void'))!
 text = framework_replace_method(text, 'setFrame(IIII)Z',
  touch_method('protected setFrame(IIII)Z', '
iget v0, p0, Landroid/view/View;->left:I
if-ne v0, p1, :changed
iget v0, p0, Landroid/view/View;->top:I
if-ne v0, p2, :changed
iget v0, p0, Landroid/view/View;->right:I
if-ne v0, p3, :changed
iget v0, p0, Landroid/view/View;->bottom:I
if-ne v0, p4, :changed
const/4 v0, 0
return v0
:changed
iget v0, p0, Landroid/view/View;->right:I
iget v1, p0, Landroid/view/View;->left:I
sub-int/2addr v0, v1
iget v1, p0, Landroid/view/View;->bottom:I
iget v2, p0, Landroid/view/View;->top:I
sub-int/2addr v1, v2
sub-int v2, p3, p1
sub-int v3, p4, p2
iput p1, p0, Landroid/view/View;->left:I
iput p2, p0, Landroid/view/View;->top:I
iput p3, p0, Landroid/view/View;->right:I
iput p4, p0, Landroid/view/View;->bottom:I
iput v2, p0, Landroid/view/View;->oldWidth:I
iput v3, p0, Landroid/view/View;->oldHeight:I
if-ne v0, v2, :size
if-eq v1, v3, :invalidate
:size
invoke-virtual {p0, v2, v3, v0, v1}, Landroid/view/View;->onSizeChanged(IIII)V
:invalidate
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
const/4 v0, 1
return v0'))!
 os.write_file(path, text)!
}
