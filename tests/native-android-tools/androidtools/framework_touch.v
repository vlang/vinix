// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn touch_method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 10\n' + body + '\n.end method\n'
}

// Keep gesture ownership in Java fields so the collector traces captured views.
// WS supplies one pointer; Android subclasses still get normal virtual dispatch,
// interception, cancellation and coordinates relative to each receiving view.
fn framework_view_touch(smali string) ! {
	path := smali + '/android/view/View.smali'
	mut view := os.read_file(path)! + '\n.field private vinixClickable:I\n.field private vinixContextClickable:Z\n'
	for signature, body in {
		'isContextClickable()Z': 'iget-boolean v0, p0, Landroid/view/View;->vinixContextClickable:Z\nreturn v0'
		'setContextClickable(Z)V': 'iput-boolean p1, p0, Landroid/view/View;->vinixContextClickable:Z\nreturn-void'
		'isClickable()Z': '
iget v0, p0, Landroid/view/View;->vinixClickable:I
if-eqz v0, :default
add-int/lit8 v0, v0, -1
return v0
:default
instance-of v0, p0, Landroid/widget/Button;
if-nez v0, :done
instance-of v0, p0, Landroid/widget/ImageButton;
if-nez v0, :done
instance-of v0, p0, Landroid/widget/EditText;
:done
return v0'
		'setClickable(Z)V': 'add-int/lit8 v0, p1, 1\niput v0, p0, Landroid/view/View;->vinixClickable:I\nreturn-void'
		'isPressed()Z': 'iget-boolean v0, p0, Landroid/view/View;->pressed:Z\nreturn v0'
		'dispatchTouchEvent(Landroid/view/MotionEvent;)Z': '
invoke-virtual {p0}, Landroid/view/View;->isEnabled()Z
move-result v0
if-eqz v0, :touch
iget-object v0, p0, Landroid/view/View;->on_touch_listener:Landroid/view/View$OnTouchListener;
if-eqz v0, :touch
invoke-interface {v0, p0, p1}, Landroid/view/View$OnTouchListener;->onTouch(Landroid/view/View;Landroid/view/MotionEvent;)Z
move-result v0
if-nez v0, :done
:touch
invoke-virtual {p0, p1}, Landroid/view/View;->onTouchEvent(Landroid/view/MotionEvent;)Z
move-result v0
:done
return v0'
		'onTouchEvent(Landroid/view/MotionEvent;)Z': '
invoke-virtual {p0}, Landroid/view/View;->isClickable()Z
move-result v0
if-eqz v0, :done
invoke-virtual {p0}, Landroid/view/View;->isEnabled()Z
move-result v1
if-eqz v1, :clear
invoke-virtual {p1}, Landroid/view/MotionEvent;->getActionMasked()I
move-result v1
if-eqz v1, :down
const/4 v2, 1
if-eq v1, v2, :up
const/4 v2, 3
if-eq v1, v2, :clear
const/4 v2, 2
if-ne v1, v2, :done
invoke-virtual {p0}, Landroid/view/View;->getContext()Landroid/content/Context;
move-result-object v1
invoke-static {v1}, Landroid/view/ViewConfiguration;->get(Landroid/content/Context;)Landroid/view/ViewConfiguration;
move-result-object v1
invoke-virtual {v1}, Landroid/view/ViewConfiguration;->getScaledTouchSlop()I
move-result v1
int-to-float v1, v1
invoke-direct {p0, p1, v1}, Landroid/view/View;->vinixTouchInside(Landroid/view/MotionEvent;F)Z
move-result v1
if-nez v1, :done
goto :clear
:down
const/4 v1, 1
invoke-virtual {p0, v1}, Landroid/view/View;->setPressed(Z)V
instance-of v1, p0, Landroid/widget/EditText;
if-eqz v1, :done
invoke-virtual {p0}, Landroid/view/View;->requestFocus()Z
goto :done
:up
invoke-virtual {p0}, Landroid/view/View;->isPressed()Z
move-result v1
if-eqz v1, :clear
const/4 v1, 0
invoke-direct {p0, p1, v1}, Landroid/view/View;->vinixTouchInside(Landroid/view/MotionEvent;F)Z
move-result v1
if-eqz v1, :clear
invoke-virtual {p0}, Landroid/view/View;->performClick()Z
:clear
const/4 v1, 0
invoke-virtual {p0, v1}, Landroid/view/View;->setPressed(Z)V
:done
return v0'
	} {
		view = framework_replace_method(view, signature, touch_method('public ' + signature, body))!
	}
	view += touch_method('private vinixTouchInside(Landroid/view/MotionEvent;F)Z', '
invoke-virtual {p1}, Landroid/view/MotionEvent;->getX()F
move-result v0
invoke-virtual {p1}, Landroid/view/MotionEvent;->getY()F
move-result v1
neg-float v2, p2
cmpg-float v3, v0, v2
if-ltz v3, :outside
cmpg-float v3, v1, v2
if-ltz v3, :outside
invoke-virtual {p0}, Landroid/view/View;->getWidth()I
move-result v2
int-to-float v2, v2
add-float/2addr v2, p2
cmpl-float v3, v0, v2
if-gez v3, :outside
invoke-virtual {p0}, Landroid/view/View;->getHeight()I
move-result v2
int-to-float v2, v2
add-float/2addr v2, p2
cmpl-float v3, v1, v2
if-gez v3, :outside
const/4 v0, 1
return v0
:outside
const/4 v0, 0
return v0')
	// Registering a listener makes an otherwise passive view clickable.
	assignment := 'iput-object p1, p0, Landroid/view/View;->on_click_listener:Landroid/view/View$OnClickListener;'
	if view.count(assignment) != 1 { return error('unexpected View click listener setter') }
	view = view.replace(assignment, assignment + '\nconst/4 v0, 1\ninvoke-virtual {p0, v0}, Landroid/view/View;->setClickable(Z)V')
	os.write_file(path, view)!
	group_path := smali + '/android/view/ViewGroup.smali'
	mut group := os.read_file(group_path)! + '\n.field private vinixTouchTarget:Landroid/view/View;\n'
	group = framework_replace_method(group, 'dispatchTouchEvent(Landroid/view/MotionEvent;)Z', touch_method('public dispatchTouchEvent(Landroid/view/MotionEvent;)Z', '
invoke-virtual {p1}, Landroid/view/MotionEvent;->getActionMasked()I
move-result v0
iget-object v1, p0, Landroid/view/ViewGroup;->vinixTouchTarget:Landroid/view/View;
if-nez v0, :intercept
if-eqz v1, :reset
const/4 v2, 3
invoke-direct {p0, v1, p1, v2}, Landroid/view/ViewGroup;->vinixDispatchChild(Landroid/view/View;Landroid/view/MotionEvent;I)Z
:reset
const/4 v1, 0
iput-object v1, p0, Landroid/view/ViewGroup;->vinixTouchTarget:Landroid/view/View;
iput-boolean v1, p0, Landroid/view/View;->disallowIntercept:Z
:intercept
const/4 v2, 0
iget-boolean v3, p0, Landroid/view/View;->disallowIntercept:Z
if-nez v3, :captured
if-eqz v0, :ask
if-eqz v1, :self
:ask
invoke-virtual {p0, p1}, Landroid/view/View;->onInterceptTouchEvent(Landroid/view/MotionEvent;)Z
move-result v2
:captured
if-eqz v1, :find
invoke-virtual {v1}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v3
if-ne v3, p0, :cancel
if-nez v2, :cancel
invoke-virtual {p1}, Landroid/view/MotionEvent;->getAction()I
move-result v3
invoke-direct {p0, v1, p1, v3}, Landroid/view/ViewGroup;->vinixDispatchChild(Landroid/view/View;Landroid/view/MotionEvent;I)Z
move-result v4
goto :finish
:cancel
const/4 v3, 3
invoke-direct {p0, v1, p1, v3}, Landroid/view/ViewGroup;->vinixDispatchChild(Landroid/view/View;Landroid/view/MotionEvent;I)Z
const/4 v3, 0
iput-object v3, p0, Landroid/view/ViewGroup;->vinixTouchTarget:Landroid/view/View;
goto :self
:find
if-nez v0, :self
if-nez v2, :self
invoke-virtual {p1}, Landroid/view/MotionEvent;->getX()F
move-result v5
invoke-virtual {p0}, Landroid/view/View;->getScrollX()I
move-result v3
int-to-float v3, v3
add-float/2addr v5, v3
invoke-virtual {p1}, Landroid/view/MotionEvent;->getY()F
move-result v6
invoke-virtual {p0}, Landroid/view/View;->getScrollY()I
move-result v3
int-to-float v3, v3
add-float/2addr v6, v3
invoke-virtual {p0}, Landroid/view/ViewGroup;->getChildCount()I
move-result v7
:next
add-int/lit8 v7, v7, -1
if-ltz v7, :self
invoke-virtual {p0, v7}, Landroid/view/ViewGroup;->getChildAt(I)Landroid/view/View;
move-result-object v1
if-eqz v1, :next
invoke-virtual {v1}, Landroid/view/View;->getVisibility()I
move-result v3
if-nez v3, :next
invoke-virtual {v1}, Landroid/view/View;->getLeft()I
move-result v3
int-to-float v3, v3
cmpg-float v3, v5, v3
if-ltz v3, :next
invoke-virtual {v1}, Landroid/view/View;->getTop()I
move-result v3
int-to-float v3, v3
cmpg-float v3, v6, v3
if-ltz v3, :next
invoke-virtual {v1}, Landroid/view/View;->getRight()I
move-result v3
int-to-float v3, v3
cmpl-float v3, v5, v3
if-gez v3, :next
invoke-virtual {v1}, Landroid/view/View;->getBottom()I
move-result v3
int-to-float v3, v3
cmpl-float v3, v6, v3
if-gez v3, :next
const/4 v3, 0
invoke-direct {p0, v1, p1, v3}, Landroid/view/ViewGroup;->vinixDispatchChild(Landroid/view/View;Landroid/view/MotionEvent;I)Z
move-result v4
if-eqz v4, :next
iput-object v1, p0, Landroid/view/ViewGroup;->vinixTouchTarget:Landroid/view/View;
goto :finish
:self
invoke-super {p0, p1}, Landroid/view/View;->dispatchTouchEvent(Landroid/view/MotionEvent;)Z
move-result v4
:finish
const/4 v3, 1
if-eq v0, v3, :clear
const/4 v3, 3
if-ne v0, v3, :done
:clear
const/4 v3, 0
iput-object v3, p0, Landroid/view/ViewGroup;->vinixTouchTarget:Landroid/view/View;
iput-boolean v3, p0, Landroid/view/View;->disallowIntercept:Z
:done
return v4'))!
	group += touch_method('private vinixDispatchChild(Landroid/view/View;Landroid/view/MotionEvent;I)Z', '
invoke-static {p2}, Landroid/view/MotionEvent;->obtain(Landroid/view/MotionEvent;)Landroid/view/MotionEvent;
move-result-object v0
invoke-virtual {v0, p3}, Landroid/view/MotionEvent;->setAction(I)V
invoke-virtual {p0}, Landroid/view/View;->getScrollX()I
move-result v1
invoke-virtual {p1}, Landroid/view/View;->getLeft()I
move-result v2
sub-int/2addr v1, v2
int-to-float v1, v1
invoke-virtual {p0}, Landroid/view/View;->getScrollY()I
move-result v2
invoke-virtual {p1}, Landroid/view/View;->getTop()I
move-result v3
sub-int/2addr v2, v3
int-to-float v2, v2
invoke-virtual {v0, v1, v2}, Landroid/view/MotionEvent;->offsetLocation(FF)V
invoke-virtual {p1, v0}, Landroid/view/View;->dispatchTouchEvent(Landroid/view/MotionEvent;)Z
move-result v1
invoke-virtual {v0}, Landroid/view/MotionEvent;->recycle()V
return v1')
	os.write_file(group_path, group)!
	framework_motion_down_time(smali)!
}

fn framework_motion_down_time(smali string) ! {
	path := smali + '/android/view/MotionEvent.smali'
	mut text := os.read_file(path)! + '\n.field public vinixDownTime:J\n'
	text = framework_replace_method(text, 'getDownTime()J', touch_method('public final getDownTime()J', '
iget-wide v0, p0, Landroid/view/MotionEvent;->vinixDownTime:J
return-wide v0'))!
	// Native WS pointer events have no gesture classifier. Android defines
	// CLASSIFICATION_NONE for these ordinary, unclassified event streams.
	text = framework_replace_method(text, 'getClassification()I', touch_method('public getClassification()I', '
const/4 v0, 0
return v0'))!
	// Every public obtain overload with downTime as its first argument must
	// store it, including reused instances from the provider's event pool.
	mut parts := text.split('.method ')
	for i := 1; i < parts.len; i++ {
		declaration := parts[i].all_before('\n')
		mut body := parts[i]
		if declaration.starts_with('public static obtain(JJ') {
			for line in body.split_into_lines() {
				if !line.trim_space().starts_with('return-object ') { continue }
				result := line.trim_space().all_after('return-object ')
				if result !in ['v0', 'v2'] { return error('unexpected MotionEvent factory result') }
				// Some overloads have more than 16 registers. iput-wide only
				// encodes four-bit registers, so copy downTime to dead locals.
				body = body.replace(line, 'move-wide/from16 v4, p0\niput-wide v4, ' + result + ', Landroid/view/MotionEvent;->vinixDownTime:J\n' + line)
			}
		} else if declaration == 'public static obtain(Landroid/view/MotionEvent;)Landroid/view/MotionEvent;' {
			if body.count('return-object v1') != 1 { return error('unexpected MotionEvent copy constructor') }
			body = body.replace('return-object v1', 'iget-wide v2, p0, Landroid/view/MotionEvent;->vinixDownTime:J\niput-wide v2, v1, Landroid/view/MotionEvent;->vinixDownTime:J\nreturn-object v1')
		}
		parts[i] = body
	}
	os.write_file(path, parts.join('.method '))!
}
