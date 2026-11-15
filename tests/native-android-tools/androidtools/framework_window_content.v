// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// android.R.id.content identifies a child container, not the window's root.
// Layout listeners on that container must see its decor parent.
pub fn framework_window_content_source(original string) !string {
	if original.contains('vinixContentView:') { return error('window content already installed') }
	old := '    iget-object v0, p0, Landroid/view/Window;->decorView:Landroid/view/ViewGroup;\n\n    const v1, 0x1020002\n\n    invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->setId(I)V'
	if original.count(old) != 1 { return error('unexpected window content constructor') }
	mut source := original.replace(old, r'
    iget-object v0, p0, Landroid/view/Window;->decorView:Landroid/view/ViewGroup;
    new-instance v2, Landroid/widget/FrameLayout;
    invoke-direct {v2, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
    const v1, 0x1020002
    invoke-virtual {v2, v1}, Landroid/widget/FrameLayout;->setId(I)V
    iput-object v2, p0, Landroid/view/Window;->vinixContentView:Landroid/view/ViewGroup;
    const/4 v1, -0x1
    new-instance v3, Landroid/widget/FrameLayout$LayoutParams;
    invoke-direct {v3, v1, v1}, Landroid/widget/FrameLayout$LayoutParams;-><init>(II)V
    invoke-virtual {v0, v2, v3}, Landroid/view/ViewGroup;->addView(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V
')
	for method in ['removeAllViews()V', 'addView(Landroid/view/View;)V'] {
		args := if method.starts_with('addView') { 'v0, p1' } else { 'v0' }
		point := '    iget-object v0, p0, Landroid/view/Window;->decorView:Landroid/view/ViewGroup;\n\n    invoke-virtual {' + args + '}, Landroid/view/ViewGroup;->' + method
		if source.count(point) != 1 { return error('unexpected window content mutation') }
		source = source.replace(point, point.replace('->decorView:', '->vinixContentView:'))
	}
	return source + '\n.field private vinixContentView:Landroid/view/ViewGroup;\n'
}

pub fn framework_window_content(smali string) ! {
	path := smali + '/android/view/Window.smali'
	os.write_file(path, framework_window_content_source(os.read_file(path)!)!)!
}
