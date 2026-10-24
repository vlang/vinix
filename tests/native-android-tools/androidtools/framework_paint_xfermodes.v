// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Keep the native bitmap compositor's transfer mode in step with Paint's Java
// state. Other PorterDuff modes retain their existing backend behavior.
fn framework_paint_xfermodes(smali string) ! {
	path := smali + '/android/graphics/Paint.smali'
	mut text := os.read_file(path)!
	text = framework_replace_method(text, 'setXfermode(Landroid/graphics/Xfermode;)Landroid/graphics/Xfermode;', '.method public setXfermode(Landroid/graphics/Xfermode;)Landroid/graphics/Xfermode;
.locals 4
const/4 v0, 3
instance-of v1, p1, Landroid/graphics/PorterDuffXfermode;
if-eqz v1, :apply
move-object v1, p1
check-cast v1, Landroid/graphics/PorterDuffXfermode;
iget v0, v1, Landroid/graphics/PorterDuffXfermode;->porterDuffMode:I
:apply
iget-wide v2, p0, Landroid/graphics/Paint;->paint:J
invoke-static {v2, v3, v0}, Landroid/graphics/Paint;->native_set_xfermode(JI)V
iput-object p1, p0, Landroid/graphics/Paint;->xfermode:Landroid/graphics/Xfermode;
return-object p1
.end method')!
	text += '\n.method private static native native_set_xfermode(JI)V\n.end method\n'
	for signature in ['<init>(Landroid/graphics/Paint;)V', 'set(Landroid/graphics/Paint;)V'] {
		start := text.index(' ' + signature + '\n') or { return error('missing Paint method ' + signature) }
		end := start + (text[start..].index('.end method') or { return error('unterminated Paint method') })
		mut body := text[start..end]
		copy := 'iget-object v0, p1, Landroid/graphics/Paint;->xfermode:Landroid/graphics/Xfermode;\niput-object v0, p0, Landroid/graphics/Paint;->xfermode:Landroid/graphics/Xfermode;\n'
		body = body.replace('return-void', copy + 'return-void')
		text = text[..start] + body + text[end..]
	}
	os.write_file(path, text)!
}
