// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn editor_method(signature string, body string) string {
	return '.method public ' + signature + '\n.locals 5\n' + body + '\n.end method\n'
}

fn framework_editor_actions(smali string) ! {
	path := smali + '/android/widget/TextView.smali'
	mut text := os.read_file(path)! + '\n.field private vinixImeOptions:I\n'
	for signature, body in {
		'setImeOptions(I)V':                                                            'iput p1, p0, Landroid/widget/TextView;->vinixImeOptions:I\nreturn-void'
		'getImeOptions()I':                                                             'iget v0, p0, Landroid/widget/TextView;->vinixImeOptions:I\nreturn v0'
		'setOnEditorActionListener(Landroid/widget/TextView$OnEditorActionListener;)V': 'iput-object p1, p0, Landroid/view/View;->vinixWsEditorAction:Ljava/lang/Object;\nreturn-void'
	} {
		text = framework_replace_method(text, signature, editor_method(signature, body))!
	}
	text += editor_method('onEditorAction(I)V', '
iget-object v0, p0, Landroid/view/View;->vinixWsEditorAction:Ljava/lang/Object;
check-cast v0, Landroid/widget/TextView$OnEditorActionListener;
if-eqz v0, :done
const/4 v1, 0
invoke-interface {v0, p0, p1, v1}, Landroid/widget/TextView$OnEditorActionListener;->onEditorAction(Landroid/widget/TextView;ILandroid/view/KeyEvent;)Z
:done
return-void')
	// WS transports Enter as text. Explicit IME actions carry a null KeyEvent;
	// an ordinary hardware Enter carries IME_NULL and KEYCODE_ENTER instead.
	text += editor_method('vinixEditorEnter(Z)Z', '
invoke-virtual {p0}, Landroid/widget/TextView;->getImeOptions()I
move-result v0
const v1, 0x40000000
and-int/2addr v1, v0
if-nez v1, :hardware
and-int/lit16 v0, v0, 255
const/4 v1, 1
if-le v0, v1, :hardware
invoke-virtual {p0, v0}, Landroid/widget/TextView;->onEditorAction(I)V
const/4 v0, 1
return v0
:hardware
iget-object v0, p0, Landroid/view/View;->vinixWsEditorAction:Ljava/lang/Object;
check-cast v0, Landroid/widget/TextView$OnEditorActionListener;
if-eqz v0, :default
new-instance v1, Landroid/view/KeyEvent;
const/4 v2, 0
const/16 v3, 66
invoke-direct {v1, v2, v3}, Landroid/view/KeyEvent;-><init>(II)V
invoke-interface {v0, p0, v2, v1}, Landroid/widget/TextView$OnEditorActionListener;->onEditorAction(Landroid/widget/TextView;ILandroid/view/KeyEvent;)Z
move-result v0
if-eqz v0, :default
return v0
:default
return p1')
	os.write_file(path, text)!
}
