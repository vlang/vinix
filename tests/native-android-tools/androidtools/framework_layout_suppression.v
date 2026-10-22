// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Suppression guards ViewGroup.layout before View.layout mutates any bounds or
// enters the native backend. One later request schedules a fresh traversal;
// stale arguments from suppressed layout attempts must never be replayed.
fn framework_layout_suppression(smali string) ! {
 path := smali + '/android/view/ViewGroup.smali'
 mut text := os.read_file(path)!
 text += '\n.field private vinixSuppressLayout:Z\n.field private vinixLayoutWhileSuppressed:Z\n'
 text = framework_replace_method(text, 'suppressLayout(Z)V', touch_method('public suppressLayout(Z)V', '
iput-boolean p1, p0, Landroid/view/ViewGroup;->vinixSuppressLayout:Z
if-nez p1, :done
iget-boolean v0, p0, Landroid/view/ViewGroup;->vinixLayoutWhileSuppressed:Z
if-eqz v0, :done
invoke-virtual {p0}, Landroid/view/View;->requestLayout()V
const/4 v0, 0
iput-boolean v0, p0, Landroid/view/ViewGroup;->vinixLayoutWhileSuppressed:Z
:done
return-void'))!
 text = framework_replace_method(text, 'isLayoutSuppressed()Z', touch_method('public isLayoutSuppressed()Z',
  'iget-boolean v0, p0, Landroid/view/ViewGroup;->vinixSuppressLayout:Z\nreturn v0'))!
 text = framework_replace_method(text, 'layout(IIII)V', touch_method('public final layout(IIII)V', '
iget-boolean v0, p0, Landroid/view/ViewGroup;->vinixSuppressLayout:Z
if-eqz v0, :layout
const/4 v0, 1
iput-boolean v0, p0, Landroid/view/ViewGroup;->vinixLayoutWhileSuppressed:Z
return-void
:layout
invoke-super {p0, p1, p2, p3, p4}, Landroid/view/View;->layout(IIII)V
return-void'))!
 os.write_file(path, text)!
}
