// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Layout callbacks see a snapshot of the registered listeners and the bounds
// from before setFrame. Both parent-driven layout and WS root traversal enter
// vinixPerformLayout, without overwriting those old bounds in the backend.
fn framework_layout_listeners(smali string) ! {
 path := smali + '/android/view/View.smali'
 mut text := os.read_file(path)!
 text += '\n.field private vinixLayoutRequired:Z\n.field private vinixLaidOut:Z\n.field private vinixLayoutListeners:Ljava/util/ArrayList;\n'
 for adding in [true, false] {
  name := if adding { 'addOnLayoutChangeListener' } else { 'removeOnLayoutChangeListener' }
  mut body := 'iget-object v0, p0, Landroid/view/View;->vinixLayoutListeners:Ljava/util/ArrayList;\n'
  if adding {
   body += 'if-nez v0, :ready\nnew-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\niput-object v0, p0, Landroid/view/View;->vinixLayoutListeners:Ljava/util/ArrayList;\n:ready\ninvoke-virtual {v0, p1}, Ljava/util/ArrayList;->contains(Ljava/lang/Object;)Z\nmove-result v1\nif-nez v1, :done\ninvoke-virtual {v0, p1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z\n'
  } else {
   body += 'if-eqz v0, :done\ninvoke-virtual {v0, p1}, Ljava/util/ArrayList;->remove(Ljava/lang/Object;)Z\n'
  }
  text = framework_replace_method(text, name + '(Landroid/view/View$OnLayoutChangeListener;)V', touch_method('public ' + name + '(Landroid/view/View$OnLayoutChangeListener;)V', body + ':done\nreturn-void'))!
 }
 text = framework_replace_method(text, 'isLaidOut()Z', touch_method('public isLaidOut()Z', 'iget-boolean v0, p0, Landroid/view/View;->vinixLaidOut:Z\nreturn v0'))!
 // Measuring marks layout as required even if the resulting bounds stay equal.
 // The provider clears layoutRequested during measure, so it cannot represent
 // this separate flag. Mark it only after onMeasure succeeds.
 measure := '    invoke-virtual {p0, p1, p2}, Landroid/view/View;->onMeasure(II)V'
 if text.count(measure) != 1 { return error('unexpected View measurement entry') }
 text = text.replace(measure, measure + '\n\n    const/4 v0, 1\n    iput-boolean v0, p0, Landroid/view/View;->vinixLayoutRequired:Z')
 text = framework_replace_method(text, 'layout(IIII)V', '.method public layout(IIII)V\n.locals 7\niget-wide v1, p0, Landroid/view/View;->widget:J\nmove-object v0, p0\nmove v3, p1\nmove v4, p2\nmove v5, p3\nmove v6, p4\ninvoke-virtual/range {v0 .. v6}, Landroid/view/View;->native_layout(JIIII)V\nreturn-void\n.end method')!
 // Retain the provider callback for backends that deliver only a size. Native
 // Vinix WS passes all four coordinates directly to vinixPerformLayout.
 text = framework_replace_method(text, 'layoutInternal(II)V', '.method private layoutInternal(II)V\n.locals 5\nmove-object v0, p0\niget v1, p0, Landroid/view/View;->left:I\niget v2, p0, Landroid/view/View;->top:I\nadd-int v3, v1, p1\nadd-int v4, v2, p2\ninvoke-virtual/range {v0 .. v4}, Landroid/view/View;->vinixPerformLayout(IIII)V\nreturn-void\n.end method')!
 text += '
.method public final vinixPerformLayout(IIII)V
.locals 11
# WS may resize a root without a parent measurement pass.
iget-object v0, p0, Landroid/view/View;->parent:Landroid/view/ViewParent;
instance-of v0, v0, Landroid/view/ViewGroup;
if-nez v0, :frame
sub-int v1, p3, p1
sub-int v2, p4, p2
invoke-virtual {p0}, Landroid/view/View;->getMeasuredWidth()I
move-result v0
if-ne v0, v1, :measure
invoke-virtual {p0}, Landroid/view/View;->getMeasuredHeight()I
move-result v0
if-eq v0, v2, :frame
:measure
invoke-virtual {p0}, Landroid/view/View;->requestLayout()V
const/high16 v0, 0x40000000
or-int/2addr v1, v0
or-int/2addr v2, v0
invoke-virtual {p0, v1, v2}, Landroid/view/View;->measure(II)V
:frame
iget v6, p0, Landroid/view/View;->left:I
iget v7, p0, Landroid/view/View;->top:I
iget v8, p0, Landroid/view/View;->right:I
iget v9, p0, Landroid/view/View;->bottom:I
invoke-virtual {p0, p1, p2, p3, p4}, Landroid/view/View;->setFrame(IIII)Z
move-result v1
if-nez v1, :layout
iget-boolean v0, p0, Landroid/view/View;->vinixLayoutRequired:Z
if-eqz v0, :done
:layout
move-object v0, p0
move v2, p1
move v3, p2
move v4, p3
move v5, p4
invoke-virtual/range {v0 .. v5}, Landroid/view/View;->onLayout(ZIIII)V
const/4 v0, 0
iput-boolean v0, p0, Landroid/view/View;->vinixLayoutRequired:Z
move-object v0, p0
move v1, p1
move v2, p2
move v3, p3
move v4, p4
move v5, v6
move v6, v7
move v7, v8
move v8, v9
invoke-direct/range {v0 .. v8}, Landroid/view/View;->vinixNotifyLayout(IIIIIIII)V
:done
const/4 v0, 0
iput-boolean v0, p0, Landroid/view/View;->layoutRequested:Z
const/4 v0, 1
iput-boolean v0, p0, Landroid/view/View;->vinixLaidOut:Z
return-void
.end method

.method private vinixNotifyLayout(IIIIIIII)V
.locals 3
iget-object v0, p0, Landroid/view/View;->vinixLayoutListeners:Ljava/util/ArrayList;
if-eqz v0, :done
invoke-virtual {v0}, Ljava/util/ArrayList;->toArray()[Ljava/lang/Object;
move-result-object v0
const/4 v1, 0
:loop
array-length v2, v0
if-ge v1, v2, :done
aget-object v2, v0, v1
check-cast v2, Landroid/view/View$OnLayoutChangeListener;
invoke-interface/range {v2 .. p8}, Landroid/view/View$OnLayoutChangeListener;->onLayoutChange(Landroid/view/View;IIIIIIII)V
add-int/lit8 v1, v1, 1
goto :loop
:done
return-void
.end method
'
 for point in [
  'iput-object p1, p0, Landroid/view/View;->vinixWindowToken:Landroid/os/IBinder;\ninvoke-virtual {p0}, Landroid/view/View;->onAttachedToWindow()V',
  'invoke-virtual {p0}, Landroid/view/View;->onDetachedFromWindow()V',
 ] {
  if text.count(point) != 1 { return error('unexpected layout attachment state reset') }
  reset := 'const/4 v0, 0\niput-boolean v0, p0, Landroid/view/View;->vinixLaidOut:Z\n'
  text = text.replace(point, if point.starts_with('iput-object') { reset + point } else { point + '\n' + reset })
 }
 os.write_file(path, text)!
 listener := smali + '/android/view/View$OnLayoutChangeListener.smali'
 definition := os.read_file(listener)!
 if definition.contains('onLayoutChange(') { return error('unexpected existing layout listener definition') }
 os.write_file(listener, definition + '\n.method public abstract onLayoutChange(Landroid/view/View;IIIIIIII)V\n.end method\n')!
}
