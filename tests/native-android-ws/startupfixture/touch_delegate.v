// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn delegate_expect(actual string, expected int) string {
	return actual + '\nconst/16 v8, ${expected}\ninvoke-static {v7, v8}, Lorg/vinix/bootstrap/TouchDelegateProbe;->expect(II)V\n'
}

fn delegate_send(action int, x int, y int, expected int) string {
	return 'const/16 v6, ${action}\nconst/16 v7, ${x}\nconst/16 v8, ${y}\ninvoke-static {v0, v6, v7, v8}, Lorg/vinix/bootstrap/TouchDelegateProbe;->send(Landroid/view/View;III)Z\nmove-result v7\n' + delegate_expect('', expected)
}

fn delegate_coordinate(field string, expected int) string {
	return 'iget v7, v1, Lorg/vinix/bootstrap/DelegateLeaf;->${field}:F\nconst/16 v8, ${expected}\ninvoke-static {v7, v8}, Lorg/vinix/bootstrap/TouchDelegateProbe;->coordinate(FI)V\n'
}

pub fn install_touch_delegate_probe(dir string) ! {
	p := 'Lorg/vinix/bootstrap/TouchDelegateProbe;'
	leaf := 'Lorg/vinix/bootstrap/DelegateLeaf;'
	override := 'Lorg/vinix/bootstrap/DelegateOverride;'
	view := 'Landroid/view/View;'
	td := 'Landroid/view/TouchDelegate;'
	os.write_file(dir + '/DelegateLeaf.smali', '.class public ${leaf}\n.super ${view}\n.implements Landroid/view/View$OnClickListener;\n.implements Landroid/view/View$OnTouchListener;\n.field public clicks:I\n.field public dispatches:I\n.field public action:I\n.field public x:F\n.field public y:F\n.field public raw:F\n.field public listenerCalls:I\n.field public consume:Z\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, ${view}-><init>(Landroid/content/Context;)V\ninvoke-virtual {p0, p0}, ${view}->setOnClickListener(Landroid/view/View$OnClickListener;)V\nreturn-void') +
		method('public onClick(${view})V', 'iget v0, p0, ${leaf}->clicks:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${leaf}->clicks:I\nreturn-void') +
		method('public onTouch(${view}Landroid/view/MotionEvent;)Z', 'iget v0, p0, ${leaf}->listenerCalls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${leaf}->listenerCalls:I\niget-boolean v0, p0, ${leaf}->consume:Z\nreturn v0') +
		method('public dispatchTouchEvent(Landroid/view/MotionEvent;)Z', '
iget v0, p0, ${leaf}->dispatches:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${leaf}->dispatches:I
invoke-virtual {p1}, Landroid/view/MotionEvent;->getActionMasked()I
move-result v0
iput v0, p0, ${leaf}->action:I
invoke-virtual {p1}, Landroid/view/MotionEvent;->getX()F
move-result v0
iput v0, p0, ${leaf}->x:F
invoke-virtual {p1}, Landroid/view/MotionEvent;->getY()F
move-result v0
iput v0, p0, ${leaf}->y:F
invoke-virtual {p1}, Landroid/view/MotionEvent;->getRawX()F
move-result v0
iput v0, p0, ${leaf}->raw:F
invoke-virtual {p1}, Landroid/view/MotionEvent;->getDownTime()J
move-result-wide v0
const-wide/16 v2, 123
cmp-long v0, v0, v2
if-eqz v0, :dispatch
invoke-static {}, ${p}->fail()V
:dispatch
invoke-super {p0, p1}, ${view}->dispatchTouchEvent(Landroid/view/MotionEvent;)Z
move-result v0
return v0'))!
	os.write_file(dir + '/DelegateOverride.smali', '.class public ${override}\n.super ${td}\n.field public calls:I\n.field public handled:Z\n' +
		method('public constructor <init>(Landroid/graphics/Rect;${view})V', 'invoke-direct {p0, p1, p2}, ${td}-><init>(Landroid/graphics/Rect;${view})V\nreturn-void') +
		method('public onTouchEvent(Landroid/view/MotionEvent;)Z', 'iget v0, p0, ${override}->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${override}->calls:I\niget-boolean v0, p0, ${override}->handled:Z\nreturn v0'))!
	mut text := '.class public ${p}\n.super Ljava/lang/Object;\n'
	text += method('public static fail()V', 'new-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "TouchDelegate identity, ordering or gesture contract"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0')
	text += method('private static expect(II)V', 'if-eq p0, p1, :done\ninvoke-static {}, ${p}->fail()V\n:done\nreturn-void')
	text += method('private static coordinate(FI)V', 'int-to-float v0, p1\ncmpl-float v0, p0, v0\nif-eqz v0, :done\ninvoke-static {}, ${p}->fail()V\n:done\nreturn-void')
	text += method('private static send(${view}III)Z', '
new-instance v0, Landroid/view/MotionEvent;
const/16 v1, 0x1002
move v2, p1
const-wide/16 v3, 456
int-to-float v5, p2
int-to-float v6, p3
move v7, v5
move v8, v6
invoke-direct/range {v0 .. v8}, Landroid/view/MotionEvent;-><init>(IIJFFFF)V
const-wide/16 v1, 123
iput-wide v1, v0, Landroid/view/MotionEvent;->vinixDownTime:J
invoke-virtual {p0, v0}, ${view}->dispatchTouchEvent(Landroid/view/MotionEvent;)Z
move-result v1
invoke-virtual {v0}, Landroid/view/MotionEvent;->recycle()V
return v1')
	// The first new API invocation is the actual Maps getter, for the old run.
	mut identity := '
new-instance v0, ${view}
invoke-direct {v0, p0}, ${view}-><init>(Landroid/content/Context;)V
invoke-virtual {v0}, ${view}->getTouchDelegate()${td}
move-result-object v6
if-nez v6, :bad
new-instance v1, ${leaf}
invoke-direct {v1, p0}, ${leaf}-><init>(Landroid/content/Context;)V
new-instance v5, Landroid/graphics/Rect;
invoke-direct {v5}, Landroid/graphics/Rect;-><init>()V
new-instance v2, ${override}
invoke-direct {v2, v5, v1}, ${override}-><init>(Landroid/graphics/Rect;${view})V
new-instance v3, ${view}
invoke-direct {v3, p0}, ${view}-><init>(Landroid/content/Context;)V
invoke-virtual {v0, v2}, ${view}->setTouchDelegate(${td})V
invoke-virtual {v0}, ${view}->getTouchDelegate()${td}
move-result-object v6
if-ne v6, v2, :bad
invoke-virtual {v3}, ${view}->getTouchDelegate()${td}
move-result-object v6
if-nez v6, :bad
new-instance v4, ${override}
invoke-direct {v4, v5, v1}, ${override}-><init>(Landroid/graphics/Rect;${view})V
invoke-virtual {v0, v4}, ${view}->setTouchDelegate(${td})V
invoke-virtual {v0}, ${view}->getTouchDelegate()${td}
move-result-object v6
if-ne v6, v4, :bad
const/4 v6, 0
invoke-virtual {v0, v6}, ${view}->setTouchDelegate(${td})V
invoke-virtual {v0}, ${view}->getTouchDelegate()${td}
move-result-object v6
if-nez v6, :bad
const-string v6, "TOUCH-DELEGATE-IDENTITY-PASS"
sget-object v7, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v7, v6}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
invoke-static {}, ${p}->fail()V
return-void'
	text += method('private static identity(Landroid/app/Activity;)V', identity)
	mut routing := '
new-instance v0, ${view}
invoke-direct {v0, p0}, ${view}-><init>(Landroid/content/Context;)V
new-instance v1, ${leaf}
invoke-direct {v1, p0}, ${leaf}-><init>(Landroid/content/Context;)V
new-instance v5, Landroid/graphics/Rect;
invoke-direct {v5}, Landroid/graphics/Rect;-><init>()V
new-instance v2, ${override}
invoke-direct {v2, v5, v1}, ${override}-><init>(Landroid/graphics/Rect;${view})V
invoke-virtual {v0, v2}, ${view}->setTouchDelegate(${td})V
'
	// A passive host tries the actual subclass; false falls through, true wins.
	routing += delegate_send(0, 5, 5, 0)
	routing += delegate_expect('iget v7, v2, ${override}->calls:I', 1)
	routing += 'const/4 v6, 1\niput-boolean v6, v2, ${override}->handled:Z\n'
	routing += delegate_send(0, 5, 5, 1)
	routing += delegate_expect('iget v7, v2, ${override}->calls:I', 2)
	// Disabled views never call a delegate, but retain own clickable consumption.
	routing += 'const/4 v6, 0\ninvoke-virtual {v0, v6}, ${view}->setEnabled(Z)V\n'
	routing += delegate_send(0, 5, 5, 0)
	routing += 'const/4 v6, 1\ninvoke-virtual {v0, v6}, ${view}->setClickable(Z)V\n'
	routing += delegate_send(0, 5, 5, 1)
	routing += delegate_expect('iget v7, v2, ${override}->calls:I', 2)
	// An enabled listener runs first; consuming it skips the delegate.
	routing += 'const/4 v6, 1\ninvoke-virtual {v0, v6}, ${view}->setEnabled(Z)V\ninvoke-virtual {v0, v1}, ${view}->setOnTouchListener(Landroid/view/View$OnTouchListener;)V\niput-boolean v6, v1, ${leaf}->consume:Z\n'
	routing += delegate_send(0, 5, 5, 1)
	routing += delegate_expect('iget v7, v2, ${override}->calls:I', 2)
	routing += delegate_expect('iget v7, v1, ${leaf}->listenerCalls:I', 1)
	routing += 'const/4 v6, 0\niput-boolean v6, v1, ${leaf}->consume:Z\n'
	routing += delegate_send(0, 5, 5, 1)
	routing += delegate_expect('iget v7, v2, ${override}->calls:I', 3)
	routing += delegate_expect('iget v7, v1, ${leaf}->listenerCalls:I', 2)
	// A declining delegate leaves the host's ordinary click handling operational.
	routing += 'move-object v0, v1\nconst/4 v6, 0\nconst/16 v7, 20\ninvoke-virtual {v0, v6, v6, v7, v7}, ${view}->layout(IIII)V\ninvoke-virtual {v0, v2}, ${view}->setTouchDelegate(${td})V\niput-boolean v6, v2, ${override}->handled:Z\n'
	routing += delegate_send(0, 5, 5, 1) + delegate_send(1, 5, 5, 1)
	routing += delegate_expect('iget v7, v1, ${leaf}->clicks:I', 1)
	routing += delegate_expect('iget v7, v2, ${override}->calls:I', 5)
	routing += 'const-string v6, "TOUCH-DELEGATE-ROUTING-PASS"\nsget-object v7, Ljava/lang/System;->out:Ljava/io/PrintStream;\ninvoke-virtual {v7, v6}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
	text += method('private static routing(Landroid/app/Activity;)V', routing)
	mut gesture := '
new-instance v0, ${view}
invoke-direct {v0, p0}, ${view}-><init>(Landroid/content/Context;)V
new-instance v1, ${leaf}
invoke-direct {v1, p0}, ${leaf}-><init>(Landroid/content/Context;)V
const/4 v6, 0
const/16 v7, 21
const/16 v8, 11
invoke-virtual {v1, v6, v6, v7, v8}, ${view}->layout(IIII)V
new-instance v5, Landroid/graphics/Rect;
const/16 v6, 10
const/16 v7, 50
invoke-direct {v5, v6, v6, v7, v7}, Landroid/graphics/Rect;-><init>(IIII)V
new-instance v2, ${td}
invoke-direct {v2, v5, v1}, ${td}-><init>(Landroid/graphics/Rect;${view})V
invoke-virtual {v0, v2}, ${view}->setTouchDelegate(${td})V
'
	// Expanded hit bounds dispatch to the child's virtual dispatch method, centered
	// using integer halves even for odd sizes. Raw coordinates and time survive.
	gesture += delegate_send(0, 15, 15, 1)
	gesture += delegate_expect('iget v7, v1, ${leaf}->dispatches:I', 1)
	gesture += delegate_coordinate('x', 10)
	gesture += delegate_coordinate('y', 5)
	gesture += delegate_coordinate('raw', 15)
	gesture += delegate_send(1, 15, 15, 1)
	gesture += delegate_expect('iget v7, v1, ${leaf}->clicks:I', 1)
	// Right/bottom are exclusive; an uncaptured UP cannot create a new gesture.
	gesture += delegate_send(0, 50, 20, 0) + delegate_send(1, 20, 20, 0)
	gesture += delegate_expect('iget v7, v1, ${leaf}->dispatches:I', 2)
	// Capture is retained outside bounds but within slop.
	gesture += 'invoke-static {p0}, Landroid/view/ViewConfiguration;->get(Landroid/content/Context;)Landroid/view/ViewConfiguration;\nmove-result-object v3\ninvoke-virtual {v3}, Landroid/view/ViewConfiguration;->getScaledTouchSlop()I\nmove-result v3\n'
	gesture += delegate_send(0, 15, 15, 1)
	gesture += 'const/4 v6, 2\nconst/16 v7, 49\nadd-int/2addr v7, v3\nconst/16 v8, 20\ninvoke-static {v0, v6, v7, v8}, ${p}->send(${view}III)Z\nmove-result v7\nconst/4 v8, 1\ninvoke-static {v7, v8}, ${p}->expect(II)V\n'
	gesture += delegate_coordinate('x', 10)
	// Moving outside slop sends -2*slop and clears the child's pressed state.
	gesture += delegate_send(2, 10000, 10000, 1)
	gesture += 'iget v7, v1, ${leaf}->x:F\nfloat-to-int v7, v7\nmul-int/lit8 v8, v3, -2\ninvoke-static {v7, v8}, ${p}->expect(II)V\n'
	gesture += delegate_send(1, 10000, 10000, 1)
	gesture += delegate_expect('iget v7, v1, ${leaf}->clicks:I', 1)
	// CANCEL is forwarded once and resets capture, including later MOVE and UP.
	gesture += delegate_send(0, 15, 15, 1) + delegate_send(3, 10000, 10000, 1)
	gesture += delegate_expect('iget v7, v1, ${leaf}->action:I', 3)
	gesture += delegate_expect('iget v7, v1, ${leaf}->dispatches:I', 8)
	gesture += delegate_send(2, 15, 15, 0) + delegate_send(1, 15, 15, 0)
	gesture += delegate_expect('iget v7, v1, ${leaf}->dispatches:I', 8)
	// The base delegate returns its target's actual result, including false.
	gesture += 'const/4 v6, 0\ninvoke-virtual {v1, v6}, ${view}->setClickable(Z)V\n'
	gesture += delegate_send(0, 15, 15, 0)
	gesture += delegate_expect('iget v7, v1, ${leaf}->dispatches:I', 9)
	gesture += 'const-string v6, "TOUCH-DELEGATE-GESTURE-PASS"\nsget-object v7, Ljava/lang/System;->out:Ljava/io/PrintStream;\ninvoke-virtual {v7, v6}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
	text += method('private static gesture(Landroid/app/Activity;)V', gesture)
	text += method('public static check(Landroid/app/Activity;)V', 'invoke-static {p0}, ${p}->identity(Landroid/app/Activity;)V\ninvoke-static {p0}, ${p}->routing(Landroid/app/Activity;)V\ninvoke-static {p0}, ${p}->gesture(Landroid/app/Activity;)V\nconst-string v0, "TOUCH-DELEGATE-PASS"\nsget-object v1, Ljava/lang/System;->out:Ljava/io/PrintStream;\ninvoke-virtual {v1, v0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void')
	os.write_file(dir + '/TouchDelegateProbe.smali', text)!
}
