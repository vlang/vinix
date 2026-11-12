// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_force_layout(smali string) ! {
	path := smali + '/android/view/View.smali'
	// forceLayout marks only this view for the next measurement. Forwarding
	// through virtual requestLayout recurses when TableLayout forces children.
	source := framework_replace_method(os.read_file(path)!, 'forceLayout()V', r'
.method public forceLayout()V
.locals 1
const/4 v0, 1
iput-boolean v0, p0, Landroid/view/View;->layoutRequested:Z
return-void
.end method')!
	os.write_file(path, source)!
}
