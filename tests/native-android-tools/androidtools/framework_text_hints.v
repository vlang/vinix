// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Keep API state in Java and pass a plain rendering copy to WS. Mutable hints
// are snapshotted, as text edits and TextWatchers must not own or change them.
fn framework_text_hints(smali string) ! {
	owner := 'Landroid/widget/TextView;'
	colors := 'Landroid/content/res/ColorStateList;'
	path := smali + '/android/widget/TextView.smali'
	mut text := os.read_file(path)! + '\n.field private vinixHint:Ljava/lang/CharSequence;\n.field private vinixHintColors:${colors}\n'
	text += '\n.method protected native native_setHint(JLjava/lang/CharSequence;)V\n.end method\n'
	text = framework_replace_method(text, 'getHint()Ljava/lang/CharSequence;', touch_method('public getHint()Ljava/lang/CharSequence;',
		'iget-object v0, p0, ${owner}->vinixHint:Ljava/lang/CharSequence;\nreturn-object v0'))!
	text = framework_replace_method(text, 'setHint(Ljava/lang/CharSequence;)V', touch_method('public setHint(Ljava/lang/CharSequence;)V', '
if-eqz p1, :store
instance-of v0, p1, Landroid/text/Spanned;
if-eqz v0, :plain
invoke-static {p1}, Landroid/text/SpannedString;->valueOf(Ljava/lang/CharSequence;)Landroid/text/SpannedString;
move-result-object p1
goto :store
:plain
invoke-interface {p1}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;
move-result-object p1
:store
iput-object p1, p0, ${owner}->vinixHint:Ljava/lang/CharSequence;
const-string v2, ""
if-eqz p1, :native_hint
invoke-interface {p1}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;
move-result-object v2
:native_hint
iget-wide v0, p0, Landroid/view/View;->widget:J
invoke-virtual {p0, v0, v1, v2}, ${owner}->native_setHint(JLjava/lang/CharSequence;)V
invoke-virtual {p0}, Landroid/view/View;->requestLayout()V
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
return-void'))!
	text = framework_replace_method(text, 'setHintTextColor(I)V', touch_method('public setHintTextColor(I)V', '
invoke-static {p1}, ${colors}->valueOf(I)${colors}
move-result-object v0
invoke-virtual {p0, v0}, ${owner}->setHintTextColor(${colors})V
return-void'))!
	text = framework_replace_method(text, 'setHintTextColor(${colors})V', touch_method('public setHintTextColor(${colors})V', '
iput-object p1, p0, ${owner}->vinixHintColors:${colors}
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
return-void'))!
	text += touch_method('public final getHintTextColors()${colors}', 'iget-object v0, p0, ${owner}->vinixHintColors:${colors}\nreturn-object v0')
	// The provider's old getter returned a constant cyan rather than WS state.
	text = framework_replace_method(text, 'getCurrentTextColor()I', '.method public native getCurrentTextColor()I\n.end method')!
	text += touch_method('public final getCurrentHintTextColor()I', '
iget-object v0, p0, ${owner}->vinixHintColors:${colors}
if-nez v0, :hint_color
invoke-virtual {p0}, ${owner}->getCurrentTextColor()I
move-result v0
return v0
:hint_color
invoke-virtual {p0}, Landroid/view/View;->getDrawableState()[I
move-result-object v1
const/4 v2, 0
invoke-virtual {v0, v1, v2}, ${colors}->getColorForState([II)I
move-result v0
return v0')
	text += touch_method('protected drawableStateChanged()V', '
invoke-super {p0}, Landroid/view/View;->drawableStateChanged()V
iget-object v0, p0, ${owner}->vinixHintColors:${colors}
if-eqz v0, :done
invoke-virtual {v0}, ${colors}->isStateful()Z
move-result v0
if-eqz v0, :done
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
:done
return-void')
	// Read hint colors while the constructor's existing TypedArrays are live.
	// TextView's direct color overrides its TextAppearance color.
	for i, label in ['cond_78', 'cond_9c'] {
		array := if i == 0 { 'v0' } else { 'v1' }
		index := if i == 0 { '5' } else { '7' }
		needle := '    :' + label + '\n'
		if text.count(needle) != 1 { return error('missing TextView hint style insertion: ' + label) }
		text = text.replace(needle, needle + '
const/4 v2, ${index}
invoke-virtual {${array}, v2}, Landroid/content/res/TypedArray;->hasValueOrEmpty(I)Z
move-result v2
if-eqz v2, :vinix_hint_${label}
const/4 v2, ${index}
invoke-virtual {${array}, v2}, Landroid/content/res/TypedArray;->getColorStateList(I)${colors}
move-result-object v2
invoke-virtual {p0, v2}, ${owner}->setHintTextColor(${colors})V
:vinix_hint_${label}
')
	}
	before := 'invoke-virtual {p1, p2, v0, p3, v4}, Landroid/content/Context;->obtainStyledAttributes(Landroid/util/AttributeSet;[III)Landroid/content/res/TypedArray;'
	if text.count(before) != 1 { return error('missing TextView constructor attributes') }
	text = text.replace(before, before.replace('p3, v4', 'p3, p4'))
	os.write_file(path, text)!
	// EditText formerly kept a second native-only hint, bypassing TextView state.
	edit := smali + '/android/widget/EditText.smali'
	mut editable := os.read_file(edit)!
	for signature, body in {
		'getHint()Ljava/lang/CharSequence;': 'invoke-super {p0}, ${owner}->getHint()Ljava/lang/CharSequence;\nmove-result-object v0\nreturn-object v0'
		'setHint(Ljava/lang/CharSequence;)V': 'invoke-super {p0, p1}, ${owner}->setHint(Ljava/lang/CharSequence;)V\nreturn-void'
	} {
		editable = framework_replace_method(editable, signature, touch_method('public ' + signature, body))!
	}
	os.write_file(edit, editable)!
}
