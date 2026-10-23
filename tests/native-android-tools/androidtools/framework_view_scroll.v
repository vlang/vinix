// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_view_scroll(smali string) ! {
 path := smali + '/android/view/View.smali'
 mut text := os.read_file(path)!
 text = framework_replace_method(text, 'scrollTo(II)V', touch_method('public scrollTo(II)V', '
iget v0, p0, Landroid/view/View;->scrollX:I
iget v1, p0, Landroid/view/View;->scrollY:I
if-ne v0, p1, :changed
if-eq v1, p2, :done
:changed
iput p1, p0, Landroid/view/View;->scrollX:I
iput p2, p0, Landroid/view/View;->scrollY:I
invoke-virtual {p0, p1, p2, v0, v1}, Landroid/view/View;->onScrollChanged(IIII)V
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
:done
return-void'))!
 // Both setters go through virtual scrollTo, preserving subclass clamping.
 for axis, other in {'X': 'Y', 'Y': 'X'} {
  args := if axis == 'X' { 'p0, p1, v0' } else { 'p0, v0, p1' }
  text = framework_replace_method(text, 'setScroll${axis}(I)V', touch_method('public setScroll${axis}(I)V', '
invoke-virtual {p0}, Landroid/view/View;->getScroll${other}()I
move-result v0
invoke-virtual {${args}}, Landroid/view/View;->scrollTo(II)V
return-void'))!
 }
 os.write_file(path, text)!
}
