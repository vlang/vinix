// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Window already creates its decor in the constructor. Peeking must expose
// that same view without creating, attaching or replacing anything.
pub fn framework_window_decor(smali string) ! {
	path := smali + '/android/view/Window.smali'
	source := framework_replace_method(os.read_file(path)!, 'peekDecorView()Landroid/view/View;', r'
.method public peekDecorView()Landroid/view/View;
.locals 1
iget-object v0, p0, Landroid/view/Window;->decorView:Landroid/view/ViewGroup;
return-object v0
.end method')!
	os.write_file(path, source)!
}
