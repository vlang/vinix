// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// A widget allocation is not a window attachment. Compose relies on this
// distinction when inflating a subtree before its lifecycle owner is a parent.
fn framework_view_attachment(smali string) ! {
 path := smali + '/android/view/View.smali'
 mut text := os.read_file(path)!
 text += '\n.field public vinixWindowToken:Landroid/os/IBinder;\n.field private vinixAttachListeners:Ljava/util/concurrent/CopyOnWriteArrayList;\n'
 for name in ['getWindowToken', 'getApplicationWindowToken'] {
  text = framework_replace_method(text, name + '()Landroid/os/IBinder;', '.method public ' + name + '()Landroid/os/IBinder;\n.locals 1\niget-object v0, p0, Landroid/view/View;->vinixWindowToken:Landroid/os/IBinder;\nreturn-object v0\n.end method')!
 }
 for event in ['AttachedToWindow', 'DetachedFromWindow'] {
  // The provider dispatched a single listener inside the overridable hook.
  // Dispatch all listeners outside it, including when a subclass omits super.
  start := text.index('.method protected on' + event + '()V') or { return error('missing view attachment hook') }
  end := start + (text[start..].index('.end method') or { return error('unterminated attachment hook') })
  original := text[start..end]
  first := original.index('    iget-object v0, p0, Landroid/view/View;->onAttachStateChangeListener:') or { return error('unexpected attachment listener dispatch') }
  last := original.index('    :cond_9') or { return error('unexpected attachment hook label') }
  replacement := original[..first] + original[last..]
  text = text[..start] + replacement + text[end..]
 }
 for adding in [true, false] {
  name := if adding { 'addOnAttachStateChangeListener' } else { 'removeOnAttachStateChangeListener' }
  mut body := '.method public ' + name + '(Landroid/view/View$OnAttachStateChangeListener;)V\n.locals 1\niget-object v0, p0, Landroid/view/View;->vinixAttachListeners:Ljava/util/concurrent/CopyOnWriteArrayList;\n'
  if adding {
   body += 'if-nez v0, :ready\nnew-instance v0, Ljava/util/concurrent/CopyOnWriteArrayList;\ninvoke-direct {v0}, Ljava/util/concurrent/CopyOnWriteArrayList;-><init>()V\niput-object v0, p0, Landroid/view/View;->vinixAttachListeners:Ljava/util/concurrent/CopyOnWriteArrayList;\n:ready\ninvoke-virtual {v0, p1}, Ljava/util/concurrent/CopyOnWriteArrayList;->add(Ljava/lang/Object;)Z\n'
  } else {
   body += 'if-eqz v0, :done\ninvoke-virtual {v0, p1}, Ljava/util/concurrent/CopyOnWriteArrayList;->remove(Ljava/lang/Object;)Z\n'
  }
  text = framework_replace_method(text, name + '(Landroid/view/View$OnAttachStateChangeListener;)V', body + ':done\nreturn-void\n.end method')!
 }
 text += '
.method public final vinixAttachToWindow(Landroid/os/IBinder;)V
.locals 3
iget-object v0, p0, Landroid/view/View;->vinixWindowToken:Landroid/os/IBinder;
if-eq v0, p1, :done
if-eqz p1, :detach
if-eqz v0, :attach
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/view/View;->vinixAttachToWindow(Landroid/os/IBinder;)V
:attach
iput-object p1, p0, Landroid/view/View;->vinixWindowToken:Landroid/os/IBinder;
invoke-virtual {p0}, Landroid/view/View;->onAttachedToWindow()V
invoke-direct {p0, p1}, Landroid/view/View;->vinixNotifyAttachment(Landroid/os/IBinder;)V
invoke-direct {p0, p1}, Landroid/view/View;->vinixAttachChildren(Landroid/os/IBinder;)V
return-void
:detach
invoke-direct {p0, p1}, Landroid/view/View;->vinixAttachChildren(Landroid/os/IBinder;)V
invoke-virtual {p0}, Landroid/view/View;->onDetachedFromWindow()V
invoke-direct {p0, p1}, Landroid/view/View;->vinixNotifyAttachment(Landroid/os/IBinder;)V
iput-object p1, p0, Landroid/view/View;->vinixWindowToken:Landroid/os/IBinder;
:done
return-void
.end method

.method private vinixNotifyAttachment(Landroid/os/IBinder;)V
.locals 3
iget-object v0, p0, Landroid/view/View;->vinixAttachListeners:Ljava/util/concurrent/CopyOnWriteArrayList;
if-eqz v0, :done
invoke-virtual {v0}, Ljava/util/concurrent/CopyOnWriteArrayList;->iterator()Ljava/util/Iterator;
move-result-object v0
:loop
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :done
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/view/View$OnAttachStateChangeListener;
if-eqz p1, :detach
invoke-interface {v1, p0}, Landroid/view/View$OnAttachStateChangeListener;->onViewAttachedToWindow(Landroid/view/View;)V
goto :loop
:detach
invoke-interface {v1, p0}, Landroid/view/View$OnAttachStateChangeListener;->onViewDetachedFromWindow(Landroid/view/View;)V
goto :loop
:done
return-void
.end method

.method private vinixAttachChildren(Landroid/os/IBinder;)V
.locals 4
instance-of v0, p0, Landroid/view/ViewGroup;
if-eqz v0, :done
move-object v0, p0
check-cast v0, Landroid/view/ViewGroup;
iget-object v0, v0, Landroid/view/ViewGroup;->children:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->toArray()[Ljava/lang/Object;
move-result-object v0
const/4 v1, 0
:loop
array-length v2, v0
if-ge v1, v2, :done
aget-object v2, v0, v1
check-cast v2, Landroid/view/View;
invoke-virtual {v2}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v3
if-ne v3, p0, :next
invoke-virtual {v2, p1}, Landroid/view/View;->vinixAttachToWindow(Landroid/os/IBinder;)V
:next
add-int/lit8 v1, v1, 1
goto :loop
:done
return-void
.end method
'
 os.write_file(path, text)!
 group := smali + '/android/view/ViewGroup.smali'
 mut group_text := os.read_file(group)!
 for entry in [
  ['removeViewInternal(Landroid/view/View;)V', 'v0', 'p1']!,
  ['removeAllViews()V', 'v2', 'v0']!,
  ['removeDetachedView(Landroid/view/View;Z)V', 'v0', 'p1']!,
 ] {
  signature := entry[0]
  start := group_text.index(' ' + signature + '\n') or { return error('missing child removal ' + signature) }
  end := start + (group_text[start..].index('.end method') or { return error('unterminated child removal') })
  original := group_text[start..end]
  assignment := 'iput-object ' + entry[1] + ', ' + entry[2] + ', Landroid/view/View;->parent:Landroid/view/ViewParent;'
  if !original.contains(assignment) { return error('unexpected child removal ' + signature) }
  group_text = group_text[..start] + original.replace(assignment,
   'invoke-virtual {' + entry[2] + ', ' + entry[1] + '}, Landroid/view/View;->vinixAttachToWindow(Landroid/os/IBinder;)V\n\n    ' + assignment) + group_text[end..]
 }
 os.write_file(group, group_text)!
 // The native add hook propagates the parent's token after Java has updated
 // the child list. Removal above detaches before the parent link is cleared.
 window := smali + '/android/view/Window.smali'
 os.write_file(window, os.read_file(window)! + '\n.field public vinixWindowToken:Landroid/os/IBinder;\n')!
}
