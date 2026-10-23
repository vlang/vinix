// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_view_traversal(smali string) ! {
 path := smali + '/android/view/ViewTreeObserver.smali'
 mut text := os.read_file(path)!
 signature := 'addOnPreDrawListener(Landroid/view/ViewTreeObserver$OnPreDrawListener;)V'
 start := text.index('.method public ' + signature + '\n') or { return error('missing pre-draw registration') }
 end := start + (text[start..].index('.end method') or { return error('unterminated pre-draw registration') })
 original := text[start..end]
 eager := '    invoke-interface {p1}, Landroid/view/ViewTreeObserver$OnPreDrawListener;->onPreDraw()Z\n'
 if original.count(eager) != 1 { return error('unexpected pre-draw registration dispatch') }
 // Registration retains the listener. Only the WS traversal may invoke it,
 // after layout, with its return value participating in frame cancellation.
 text = text[..start] + original.replace(eager, '') + text[end..]
 // The provider merges every other listener list but drops OnDraw listeners.
 // Preserve these alongside the pre-draw callbacks registered before attachment.
 merge_start := text.index('.method merge(Landroid/view/ViewTreeObserver;)V\n') or { return error('missing observer merge') }
 merge_end := merge_start + (text[merge_start..].index('.end method') or { return error('unterminated observer merge') })
 merge := text[merge_start..merge_end]
 kill := '    invoke-direct {p1}, Landroid/view/ViewTreeObserver;->kill()V'
 if merge.count(kill) != 1 { return error('unexpected observer merge termination') }
 text = text[..merge_start] + merge.replace(kill, '
    iget-object v0, p1, Landroid/view/ViewTreeObserver;->mOnDrawListeners:Ljava/util/ArrayList;
    if-eqz v0, :vinix_draw_merged
    iget-object v1, p0, Landroid/view/ViewTreeObserver;->mOnDrawListeners:Ljava/util/ArrayList;
    if-nez v1, :vinix_draw_append
    iput-object v0, p0, Landroid/view/ViewTreeObserver;->mOnDrawListeners:Ljava/util/ArrayList;
    goto :vinix_draw_merged
    :vinix_draw_append
    invoke-virtual {v1, v0}, Ljava/util/ArrayList;->addAll(Ljava/util/Collection;)Z
    :vinix_draw_merged
' + kill) + text[merge_end..]
 os.write_file(path, text)!
 // A detached view owns one floating observer until attachment merges it into
 // the window observer. Repeated queries must retain both identity and listeners.
 view_path := smali + '/android/view/View.smali'
 view := os.read_file(view_path)!
 os.write_file(view_path, framework_replace_method(view,
  'getViewTreeObserver()Landroid/view/ViewTreeObserver;', touch_method('public getViewTreeObserver()Landroid/view/ViewTreeObserver;', '
# The native backend can know the activity before this view is attached.
iget-object v0, p0, Landroid/view/View;->vinixWindowToken:Landroid/os/IBinder;
if-eqz v0, :floating
iget-wide v0, p0, Landroid/view/View;->widget:J
invoke-virtual {p0, v0, v1}, Landroid/view/View;->native_get_window(J)Landroid/view/Window;
move-result-object v0
if-eqz v0, :floating
iget-object v1, v0, Landroid/view/Window;->view_tree_observer:Landroid/view/ViewTreeObserver;
if-nez v1, :window_ready
new-instance v1, Landroid/view/ViewTreeObserver;
invoke-direct {v1, v0}, Landroid/view/ViewTreeObserver;-><init>(Landroid/view/Window;)V
iput-object v1, v0, Landroid/view/Window;->view_tree_observer:Landroid/view/ViewTreeObserver;
:window_ready
return-object v1
:floating
iget-object v0, p0, Landroid/view/View;->floating_observer:Landroid/view/ViewTreeObserver;
if-nez v0, :done
new-instance v0, Landroid/view/ViewTreeObserver;
const/4 v1, 0
invoke-direct {v0, v1}, Landroid/view/ViewTreeObserver;-><init>(Landroid/view/Window;)V
iput-object v0, p0, Landroid/view/View;->floating_observer:Landroid/view/ViewTreeObserver;
:done
return-object v0'))!)!
}
