// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_child_states(smali string) ! {
	view := smali + '/android/view/View.smali'
	mut text := os.read_file(view)!
	// Drawable queries must dispatch to overrides, including ViewGroup's child
	// aggregation. Construct fresh arrays so reserved slots cannot retain states.
	text = framework_replace_method(text, 'getDrawableState()[I', touch_method('public final getDrawableState()[I', '
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/view/View;->onCreateDrawableState(I)[I
move-result-object v0
return-object v0'))!
	mut create := 'const/4 v0, 0\n'
	for i, query in ['isEnabled', 'isSelected', 'isPressed', 'isActivated'] {
		create += 'invoke-virtual {p0}, Landroid/view/View;->${query}()Z\nmove-result v${i + 1}\nadd-int/2addr v0, v${i + 1}\n'
	}
	create += 'add-int/2addr v0, p1\nnew-array v0, v0, [I\nconst/4 v5, 0\n'
	for i, state in ['0x101009e', '0x10100a1', '0x10100a7', '0x10102fe'] {
		create += 'if-eqz v${i + 1}, :skip${i}\nconst v6, ${state}\naput v6, v0, v5\nadd-int/lit8 v5, v5, 1\n:skip${i}\n'
	}
	text = framework_replace_method(text, 'onCreateDrawableState(I)[I', touch_method('protected onCreateDrawableState(I)[I', create + 'return-object v0'))!
	text = framework_replace_method(text, 'mergeDrawableStates([I[I)[I', touch_method('protected static mergeDrawableStates([I[I)[I', '
array-length v0, p0
:scan
if-lez v0, :copy
add-int/lit8 v1, v0, -1
aget v2, p0, v1
if-nez v2, :copy
move v0, v1
goto :scan
:copy
const/4 v1, 0
array-length v2, p1
invoke-static {p1, v1, p0, v0, v2}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V
return-object p0'))!
	text = framework_replace_method(text, 'refreshDrawableState()V', touch_method('public refreshDrawableState()V', '
invoke-virtual {p0}, Landroid/view/View;->drawableStateChanged()V
invoke-virtual {p0}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v0
instance-of v1, v0, Landroid/view/ViewGroup;
if-eqz v1, :done
check-cast v0, Landroid/view/ViewGroup;
invoke-virtual {v0, p0}, Landroid/view/ViewGroup;->childDrawableStateChanged(Landroid/view/View;)V
:done
return-void'))!
	text = framework_replace_method(text, 'drawableStateChanged()V', touch_method('protected drawableStateChanged()V', '
invoke-virtual {p0}, Landroid/view/View;->getBackground()Landroid/graphics/drawable/Drawable;
move-result-object v0
if-eqz v0, :done
invoke-virtual {v0}, Landroid/graphics/drawable/Drawable;->isStateful()Z
move-result v1
if-eqz v1, :done
invoke-virtual {p0}, Landroid/view/View;->getDrawableState()[I
move-result-object v1
invoke-virtual {v0, v1}, Landroid/graphics/drawable/Drawable;->setState([I)Z
move-result v1
if-eqz v1, :done
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
:done
return-void'))!
	for state in ['Selected', 'Activated'] {
		field := 'vinix' + state
		text += '\n.field private ${field}:Z\n'
		text = framework_replace_method(text, 'is${state}()Z', touch_method('public is${state}()Z', 'iget-boolean v0, p0, Landroid/view/View;->${field}:Z\nreturn v0'))!
		text = framework_replace_method(text, 'set${state}(Z)V', child_state_setter(state, field))!
	}
	text = framework_replace_method(text, 'setPressed(Z)V', child_state_setter('Pressed', 'pressed'))!
	// Keep the native enabled/visibility update and notify stateful backgrounds.
	start := text.index(' setEnabled(Z)V\n') or { return error('missing setEnabled') }
	end := start + (text[start..].index('.end method') or { return error('unterminated setEnabled') })
	assert text[start..end].count('return-void') == 1
	text = text[..start] + text[start..end].replace('iput-boolean p1, p0, Landroid/view/View;->atl_enabled:Z', 'iget-boolean v0, p0, Landroid/view/View;->atl_enabled:Z\nif-eq v0, p1, :vinix_done\niput-boolean p1, p0, Landroid/view/View;->atl_enabled:Z').replace('return-void', 'invoke-virtual {p0}, Landroid/view/View;->refreshDrawableState()V\n:vinix_done\nreturn-void') + text[end..]
	os.write_file(view, text)!

	group := smali + '/android/view/ViewGroup.smali'
	mut groups := os.read_file(group)!
	groups += '\n.field private vinixAddStatesFromChildren:Z\n'
	groups = framework_replace_method(groups, 'addStatesFromChildren()Z', touch_method('public addStatesFromChildren()Z', 'iget-boolean v0, p0, Landroid/view/ViewGroup;->vinixAddStatesFromChildren:Z\nreturn v0'))!
	groups = framework_replace_method(groups, 'setAddStatesFromChildren(Z)V', touch_method('public setAddStatesFromChildren(Z)V', '
iput-boolean p1, p0, Landroid/view/ViewGroup;->vinixAddStatesFromChildren:Z
invoke-virtual {p0}, Landroid/view/View;->refreshDrawableState()V
return-void'))!
	groups = framework_replace_method(groups, 'childDrawableStateChanged(Landroid/view/View;)V', touch_method('public childDrawableStateChanged(Landroid/view/View;)V', '
invoke-direct {p0}, Landroid/view/ViewGroup;->vinixRefreshChildStates()V
return-void'))!
	groups += touch_method('private vinixRefreshChildStates()V', '
iget-boolean v0, p0, Landroid/view/ViewGroup;->vinixAddStatesFromChildren:Z
if-eqz v0, :done
invoke-virtual {p0}, Landroid/view/View;->refreshDrawableState()V
:done
return-void')
	// The Java list has already changed when each native hook runs. Refresh
	// here so background selectors also track additions and removals.
	mut lines := []string{}
	mut hooks := 0
	for line in groups.split_into_lines() {
		lines << line
		if line.contains('Landroid/view/ViewGroup;->native_addView(') || line.contains('Landroid/view/ViewGroup;->native_removeView(') {
			lines << 'invoke-direct {p0}, Landroid/view/ViewGroup;->vinixRefreshChildStates()V'
			hooks++
		}
	}
	assert hooks == 4
	groups = lines.join('\n') + '\n'
	groups = framework_replace_method(groups, 'onCreateDrawableState(I)[I', touch_method('protected onCreateDrawableState(I)[I', '
iget-boolean v0, p0, Landroid/view/ViewGroup;->vinixAddStatesFromChildren:Z
if-nez v0, :children
invoke-super {p0, p1}, Landroid/view/View;->onCreateDrawableState(I)[I
move-result-object v0
return-object v0
:children
invoke-virtual {p0}, Landroid/view/ViewGroup;->getChildCount()I
move-result v0
const/4 v1, 0
move v2, p1
:count
if-ge v1, v0, :allocate
invoke-virtual {p0, v1}, Landroid/view/ViewGroup;->getChildAt(I)Landroid/view/View;
move-result-object v3
invoke-virtual {v3}, Landroid/view/View;->getDrawableState()[I
move-result-object v3
if-eqz v3, :next
array-length v4, v3
add-int/2addr v2, v4
:next
add-int/lit8 v1, v1, 1
goto :count
:allocate
invoke-super {p0, v2}, Landroid/view/View;->onCreateDrawableState(I)[I
move-result-object v2
const/4 v1, 0
:merge
if-ge v1, v0, :done
invoke-virtual {p0, v1}, Landroid/view/ViewGroup;->getChildAt(I)Landroid/view/View;
move-result-object v3
invoke-virtual {v3}, Landroid/view/View;->getDrawableState()[I
move-result-object v3
if-eqz v3, :merged
invoke-static {v2, v3}, Landroid/view/View;->mergeDrawableStates([I[I)[I
move-result-object v2
:merged
add-int/lit8 v1, v1, 1
goto :merge
:done
return-object v2'))!
	os.write_file(group, groups)!
}

fn child_state_setter(state string, field string) string {
	return touch_method('public set${state}(Z)V', '
iget-boolean v0, p0, Landroid/view/View;->${field}:Z
if-eq v0, p1, :done
iput-boolean p1, p0, Landroid/view/View;->${field}:Z
invoke-virtual {p0}, Landroid/view/View;->refreshDrawableState()V
:done
return-void')
}
