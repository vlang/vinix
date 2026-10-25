// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

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
 // settled. Walk every View parent even when the child's flag is already set.
 text = framework_replace_method(text, 'requestLayout()V', '.method public requestLayout()V
.locals 2
iget-wide v0, p0, Landroid/view/View;->widget:J
invoke-virtual {p0, v0, v1}, Landroid/view/View;->native_requestLayout(J)V
:parent
const/4 v0, 1
iput-boolean v0, p0, Landroid/view/View;->layoutRequested:Z
iget-object v0, p0, Landroid/view/View;->parent:Landroid/view/ViewParent;
instance-of v1, v0, Landroid/view/View;
if-eqz v1, :done
check-cast v0, Landroid/view/View;
move-object p0, v0
goto :parent
:done
return-void
.end method')!
 return text
}
