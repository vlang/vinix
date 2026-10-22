// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_view_traversal(smali string) ! {
 path := smali + '/android/view/ViewTreeObserver.smali'
 text := os.read_file(path)!
 signature := 'addOnPreDrawListener(Landroid/view/ViewTreeObserver$OnPreDrawListener;)V'
 start := text.index('.method public ' + signature + '\n') or { return error('missing pre-draw registration') }
 end := start + (text[start..].index('.end method') or { return error('unterminated pre-draw registration') })
 original := text[start..end]
 eager := '    invoke-interface {p1}, Landroid/view/ViewTreeObserver$OnPreDrawListener;->onPreDraw()Z\n'
 if original.count(eager) != 1 { return error('unexpected pre-draw registration dispatch') }
 // Registration retains the listener. Only the WS traversal may invoke it,
 // after layout, with its return value participating in frame cancellation.
 os.write_file(path, text[..start] + original.replace(eager, '') + text[end..])!
}
