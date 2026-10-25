// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Android 26 added tooltip text independently of content descriptions and
// long-click listeners. Preserve the caller's CharSequence, including spans.
// Native WS does not yet render the platform's hover/long-press tooltip popup.
fn framework_view_tooltips(smali string) ! {
	path := smali + '/android/view/View.smali'
	mut text := os.read_file(path)!
	text += '\n.field private vinixTooltipText:Ljava/lang/CharSequence;\n'
	text = framework_replace_method(text, 'getTooltipText()Ljava/lang/CharSequence;',
		signature_method('public getTooltipText()Ljava/lang/CharSequence;',
			'iget-object v0, p0, Landroid/view/View;->vinixTooltipText:Ljava/lang/CharSequence;\nreturn-object v0'))!
	text = framework_replace_method(text, 'setTooltipText(Ljava/lang/CharSequence;)V',
		signature_method('public setTooltipText(Ljava/lang/CharSequence;)V', '
invoke-static {p1}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z
move-result v0
if-eqz v0, :store
const/4 p1, 0
:store
iput-object p1, p0, Landroid/view/View;->vinixTooltipText:Ljava/lang/CharSequence;
return-void'))!
	// All public View constructors delegate here. TypedArray resolves XML,
	// resources, theme values and both default-style arguments consistently.
	// Match Android's virtual setter dispatch only for a present attribute.
	constructor := '<init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V'
	start := text.index(' ' + constructor + '\n') or { return error('missing View constructor') }
	end := start + (text[start..].index('.end method') or { return error('unterminated View constructor') })
	assert text[start..end].count('return-void') == 1
	text = text[..start] + text[start..end].replace('return-void',
		'invoke-direct {p0, p1, p2, p3, p4}, Landroid/view/View;->vinixInitTooltip(Landroid/content/Context;Landroid/util/AttributeSet;II)V\nreturn-void') + text[end..]
	text += signature_method('private vinixInitTooltip(Landroid/content/Context;Landroid/util/AttributeSet;II)V', '
const/4 v0, 1
new-array v0, v0, [I
const/4 v1, 0
const v2, 0x01010534
aput v2, v0, v1
invoke-virtual {p1, p2, v0, p3, p4}, Landroid/content/Context;->obtainStyledAttributes(Landroid/util/AttributeSet;[III)Landroid/content/res/TypedArray;
move-result-object v0
invoke-virtual {v0, v1}, Landroid/content/res/TypedArray;->hasValueOrEmpty(I)Z
move-result v2
if-eqz v2, :absent
invoke-virtual {v0, v1}, Landroid/content/res/TypedArray;->getText(I)Ljava/lang/CharSequence;
move-result-object v1
invoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V
invoke-virtual {p0, v1}, Landroid/view/View;->setTooltipText(Ljava/lang/CharSequence;)V
return-void
:absent
invoke-virtual {v0}, Landroid/content/res/TypedArray;->recycle()V
return-void')
	os.write_file(path, text)!
	attr := smali + '/android/R$attr.smali'
	mut attrs := os.read_file(attr)!
	if !attrs.contains(' tooltipText:I') {
		attrs += '\n.field public static final tooltipText:I = 0x01010534\n'
		os.write_file(attr, attrs)!
	}
}
