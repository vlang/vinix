// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_graphic_text(smali string) ! {
	path := smali + '/android/text/TextUtils.smali'
	mut source := os.read_file(path)!
	if source.contains(' isGraphic(') { return error('graphic text query already exists') }
	source += r'
.method private static vinixGraphicCodePoint(I)Z
.locals 1
invoke-static {p0}, Ljava/lang/Character;->getType(I)I
move-result v0
sparse-switch v0, :excluded
const/4 v0, 1
return v0
:no
const/4 v0, 0
return v0
:excluded
.sparse-switch
0x0 -> :no
0xc -> :no
0xd -> :no
0xe -> :no
0xf -> :no
0x10 -> :no
0x13 -> :no
.end sparse-switch
.end method
.method public static isGraphic(Ljava/lang/CharSequence;)Z
.locals 4
invoke-interface {p0}, Ljava/lang/CharSequence;->length()I
move-result v0
const/4 v1, 0
:next
if-ge v1, v0, :no
invoke-static {p0, v1}, Ljava/lang/Character;->codePointAt(Ljava/lang/CharSequence;I)I
move-result v2
invoke-static {v2}, Landroid/text/TextUtils;->vinixGraphicCodePoint(I)Z
move-result v3
if-nez v3, :yes
invoke-static {v2}, Ljava/lang/Character;->charCount(I)I
move-result v2
add-int/2addr v1, v2
goto :next
:yes
const/4 v0, 1
return v0
:no
const/4 v0, 0
return v0
.end method
.method public static isGraphic(C)Z
.locals 1
invoke-static {p0}, Landroid/text/TextUtils;->vinixGraphicCodePoint(I)Z
move-result v0
return v0
.end method
'
	os.write_file(path, source)!
}
