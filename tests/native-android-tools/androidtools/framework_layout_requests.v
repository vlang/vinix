// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// ViewParent's provider API omits requestLayout. Declare the interface entry
// and supply it on the non-View window parent; View already schedules the native
// traversal before forwarding to this root.
pub fn framework_layout_request_parents(smali string) ! {
 parent := smali + '/android/view/ViewParent.smali'
 root := smali + '/android/view/WindowManagerImpl$WindowViewParent.smali'
 parent_source := os.read_file(parent)!
 root_source := os.read_file(root)!
 if parent_source.count('.class public interface abstract Landroid/view/ViewParent;\n') != 1 ||
  parent_source.contains(' requestLayout()V\n') {
  return error('unexpected ViewParent layout request entry')
 }
 if root_source.count('.class Landroid/view/WindowManagerImpl$WindowViewParent;\n') != 1 ||
  root_source.count('.implements Landroid/view/ViewParent;\n') != 1 ||
  root_source.contains(' requestLayout()V\n') {
  return error('unexpected window parent layout request entry')
 }
 os.write_file(parent, parent_source + '\n.method public abstract requestLayout()V\n.end method\n')!
 os.write_file(root, root_source + '\n.method public requestLayout()V\n.locals 0\nreturn-void\n.end method\n')!
}

// measure consumes a request before onMeasure. Layout must retain any request
// made since then, including requests from size, layout and listener callbacks.
pub fn framework_layout_requests(source string) !string {
 if source.count('.method public requestLayout()V\n') != 1 {
  return error('unexpected View request entry')
 }
 header := '.method public final vinixPerformLayout(IIII)V'
 if source.count(header) != 1 { return error('unexpected View layout entry') }
 start := source.index(header) or { return error('missing View layout entry') }
 end := start + (source[start..].index('.end method') or { return error('unterminated View layout entry') })
 layout := source[start..end]
 if layout.contains('\n.method ') { return error('unterminated View layout entry') }
 clear := 'const/4 v0, 0\niput-boolean v0, p0, Landroid/view/View;->layoutRequested:Z\n'
 if layout.count(clear) != 1 || !layout.contains(':done\n' + clear) {
  return error('unexpected View layout request reset')
 }
 mut text := source[..start] + layout.replace(clear, '') + source[end..]
 // A directly laid out child can still need measurement while its parent has
 // settled. Always forward requests, including repeated ones, through the
 // parent's implementation so containers can intercept or defer them.
 text = framework_replace_method(text, 'requestLayout()V', '.method public requestLayout()V
.locals 2
iget-wide v0, p0, Landroid/view/View;->widget:J
invoke-virtual {p0, v0, v1}, Landroid/view/View;->native_requestLayout(J)V
const/4 v0, 1
iput-boolean v0, p0, Landroid/view/View;->layoutRequested:Z
iget-object v0, p0, Landroid/view/View;->parent:Landroid/view/ViewParent;
if-eqz v0, :done
invoke-interface {v0}, Landroid/view/ViewParent;->requestLayout()V
:done
return-void
.end method')!
 return text
}
