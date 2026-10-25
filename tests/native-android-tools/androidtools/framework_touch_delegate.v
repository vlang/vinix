// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Delegates run before the enabled view's own clickable handling. Keep them in
// Java fields so app subclasses and the collector see the actual objects.
pub fn framework_touch_delegate(smali string) ! {
	view_path := smali + '/android/view/View.smali'
	delegate_path := smali + '/android/view/TouchDelegate.smali'
	mut view := os.read_file(view_path)!
	old_delegate := os.read_file(delegate_path)!
	if view.contains('vinixTouchDelegate:') || view.contains(' getTouchDelegate()') {
		return error('View touch delegate already extended')
	}
	if old_delegate.count('.method ') != 1 || old_delegate.count('<init>(Landroid/graphics/Rect;Landroid/view/View;)V') != 1 || old_delegate.contains('.field ') {
		return error('unexpected TouchDelegate baseline')
	}
	old := 'invoke-virtual {p0}, Landroid/view/View;->isClickable()Z\nmove-result v0\nif-eqz v0, :done\ninvoke-virtual {p0}, Landroid/view/View;->isEnabled()Z\nmove-result v1\nif-eqz v1, :clear'
	if view.count(old) != 1 { return error('unexpected View touch entry') }
	view = view.replace(old, 'invoke-virtual {p0}, Landroid/view/View;->isClickable()Z
move-result v0
invoke-virtual {p0}, Landroid/view/View;->isEnabled()Z
move-result v1
if-eqz v1, :delegate_disabled
iget-object v1, p0, Landroid/view/View;->vinixTouchDelegate:Landroid/view/TouchDelegate;
if-eqz v1, :delegate_fallback
invoke-virtual {v1, p1}, Landroid/view/TouchDelegate;->onTouchEvent(Landroid/view/MotionEvent;)Z
move-result v1
if-eqz v1, :delegate_fallback
const/4 v0, 1
return v0
:delegate_disabled
if-eqz v0, :done
goto :clear
:delegate_fallback
if-eqz v0, :done')
	view += '\n.field private vinixTouchDelegate:Landroid/view/TouchDelegate;\n'
	view = framework_replace_method(view, 'getTouchDelegate()Landroid/view/TouchDelegate;', touch_method('public getTouchDelegate()Landroid/view/TouchDelegate;', 'iget-object v0, p0, Landroid/view/View;->vinixTouchDelegate:Landroid/view/TouchDelegate;\nreturn-object v0'))!
	view = framework_replace_method(view, 'setTouchDelegate(Landroid/view/TouchDelegate;)V', touch_method('public setTouchDelegate(Landroid/view/TouchDelegate;)V', 'iput-object p1, p0, Landroid/view/View;->vinixTouchDelegate:Landroid/view/TouchDelegate;\nreturn-void'))!
	owner := 'Landroid/view/TouchDelegate;'
	mut delegate := '.class public ${owner}\n.super Ljava/lang/Object;\n.field private vinixBounds:Landroid/graphics/Rect;\n.field private vinixSlopBounds:Landroid/graphics/Rect;\n.field private vinixDelegateView:Landroid/view/View;\n.field private vinixSlop:I\n.field private vinixTargeted:Z\n'
	delegate += touch_method('public constructor <init>(Landroid/graphics/Rect;Landroid/view/View;)V', '
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, ${owner}->vinixBounds:Landroid/graphics/Rect;
invoke-virtual {p2}, Landroid/view/View;->getContext()Landroid/content/Context;
move-result-object v0
invoke-static {v0}, Landroid/view/ViewConfiguration;->get(Landroid/content/Context;)Landroid/view/ViewConfiguration;
move-result-object v0
invoke-virtual {v0}, Landroid/view/ViewConfiguration;->getScaledTouchSlop()I
move-result v0
iput v0, p0, ${owner}->vinixSlop:I
neg-int v0, v0
new-instance v1, Landroid/graphics/Rect;
invoke-direct {v1, p1}, Landroid/graphics/Rect;-><init>(Landroid/graphics/Rect;)V
invoke-virtual {v1, v0, v0}, Landroid/graphics/Rect;->inset(II)V
iput-object v1, p0, ${owner}->vinixSlopBounds:Landroid/graphics/Rect;
iput-object p2, p0, ${owner}->vinixDelegateView:Landroid/view/View;
return-void')
	delegate += touch_method('public onTouchEvent(Landroid/view/MotionEvent;)Z', '
invoke-virtual {p1}, Landroid/view/MotionEvent;->getX()F
move-result v0
float-to-int v0, v0
invoke-virtual {p1}, Landroid/view/MotionEvent;->getY()F
move-result v1
float-to-int v1, v1
invoke-virtual {p1}, Landroid/view/MotionEvent;->getActionMasked()I
move-result v2
const/4 v3, 0
const/4 v4, 1
if-eqz v2, :down
const/4 v5, 3
if-eq v2, v5, :cancel
const/4 v5, 1
if-eq v2, v5, :captured
const/4 v5, 2
if-eq v2, v5, :captured
const/4 v5, 5
if-eq v2, v5, :captured
const/4 v5, 6
if-ne v2, v5, :dispatch
:captured
iget-boolean v3, p0, ${owner}->vinixTargeted:Z
if-eqz v3, :dispatch
iget-object v5, p0, ${owner}->vinixSlopBounds:Landroid/graphics/Rect;
invoke-virtual {v5, v0, v1}, Landroid/graphics/Rect;->contains(II)Z
move-result v4
goto :dispatch
:down
iget-object v5, p0, ${owner}->vinixBounds:Landroid/graphics/Rect;
invoke-virtual {v5, v0, v1}, Landroid/graphics/Rect;->contains(II)Z
move-result v3
iput-boolean v3, p0, ${owner}->vinixTargeted:Z
goto :dispatch
:cancel
iget-boolean v3, p0, ${owner}->vinixTargeted:Z
const/4 v5, 0
iput-boolean v5, p0, ${owner}->vinixTargeted:Z
:dispatch
if-eqz v3, :unhandled
iget-object v5, p0, ${owner}->vinixDelegateView:Landroid/view/View;
if-eqz v4, :outside
invoke-virtual {v5}, Landroid/view/View;->getWidth()I
move-result v6
div-int/lit8 v6, v6, 2
int-to-float v6, v6
invoke-virtual {v5}, Landroid/view/View;->getHeight()I
move-result v7
div-int/lit8 v7, v7, 2
int-to-float v7, v7
goto :locate
:outside
iget v6, p0, ${owner}->vinixSlop:I
mul-int/lit8 v6, v6, -2
int-to-float v6, v6
move v7, v6
:locate
invoke-virtual {p1, v6, v7}, Landroid/view/MotionEvent;->setLocation(FF)V
invoke-virtual {v5, p1}, Landroid/view/View;->dispatchTouchEvent(Landroid/view/MotionEvent;)Z
move-result v0
return v0
:unhandled
const/4 v0, 0
return v0')
	// Validate both inputs before writing either class.
	os.write_file(view_path, view)!
	os.write_file(delegate_path, delegate)!
}
