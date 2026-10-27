// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

// The provider's fresh-child path already inserts through addViewInternal.
// Returning here keeps it out of the separate temporary-detach reattach path.
// Inserting twice leaves a drawable orphan after removeView removes one entry.
pub fn framework_child_attach(source string) !string {
	header := '.method public attachViewToParent(Landroid/view/View;ILandroid/view/ViewGroup$LayoutParams;)V\n'
	if source.count(header) != 1 { return error('missing exact child attach method') }
	start := source.index(header) or { return error('missing child attach method') }
	end := start + (source[start..].index('.end method') or { return error('unterminated child attach method') })
	body := source[start..end]
	point := '    invoke-virtual {p0, p1, p2, p3, v0}, Landroid/view/ViewGroup;->addViewInternal(Landroid/view/View;ILandroid/view/ViewGroup$LayoutParams;Z)V\n\n    :cond_c'
	if body.count(point) != 1 || !body.contains('    if-nez v0, :cond_c\n')
		|| !body.contains('Landroid/view/ViewGroup;->detachedChildren:Ljava/util/ArrayList;')
		|| body.count('->addViewInternal(') != 1 {
		return error('unexpected or already corrected child attach method')
	}
	return source[..start] + body.replace(point, point.replace('\n\n    :cond_c', '\n\n    return-void\n\n    :cond_c')) + source[end..]
}
