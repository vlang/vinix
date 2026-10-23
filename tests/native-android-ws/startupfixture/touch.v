// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn touch_expect(actual string, expected int, label string) string {
	return actual + '\nconst/16 v8, ${expected}\nconst-string v9, "${label}"\ninvoke-static {v7, v8, v9}, Lorg/vinix/bootstrap/TouchProbe;->expect(IILjava/lang/String;)V\n'
}

fn touch_send(action int, x int, y int) string {
	return 'const/4 v3, ${action}\nconst/16 v4, ${x}\nconst/16 v5, ${y}\ninvoke-static {v0, v3, v4, v5}, Lorg/vinix/bootstrap/TouchProbe;->send(Landroid/view/View;III)Z\n'
}

fn install_touch_probe(dir string) ! {
	os.write_file(dir + '/TouchLeaf.smali', '.class public Lorg/vinix/bootstrap/TouchLeaf;\n.super Landroid/view/View;\n.implements Landroid/view/View$OnClickListener;\n' +
		'.field public clicks:I\n.field public actions:I\n.field public disallow:Z\n.field public x:F\n.field public raw:F\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/view/View;-><init>(Landroid/content/Context;)V\ninvoke-virtual {p0, p0}, Landroid/view/View;->setOnClickListener(Landroid/view/View$OnClickListener;)V\nreturn-void') +
		method('public onClick(Landroid/view/View;)V', 'iget v0, p0, Lorg/vinix/bootstrap/TouchLeaf;->clicks:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/TouchLeaf;->clicks:I\nreturn-void') +
		method('public onTouchEvent(Landroid/view/MotionEvent;)Z', '
invoke-virtual {p1}, Landroid/view/MotionEvent;->getClassification()I
move-result v0
const/4 v1, 0
const-string v2, "WS pointer stream must be unclassified"
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/TouchProbe;->expect(IILjava/lang/String;)V
invoke-virtual {p1}, Landroid/view/MotionEvent;->getActionMasked()I
move-result v0
const/4 v1, 1
shl-int/2addr v1, v0
iget v2, p0, Lorg/vinix/bootstrap/TouchLeaf;->actions:I
or-int/2addr v2, v1
iput v2, p0, Lorg/vinix/bootstrap/TouchLeaf;->actions:I
if-nez v0, :coordinates
iget-boolean v0, p0, Lorg/vinix/bootstrap/TouchLeaf;->disallow:Z
if-eqz v0, :coordinates
invoke-virtual {p0}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v0
const/4 v1, 1
invoke-interface {v0, v1}, Landroid/view/ViewParent;->requestDisallowInterceptTouchEvent(Z)V
:coordinates
invoke-virtual {p1}, Landroid/view/MotionEvent;->getX()F
move-result v0
iput v0, p0, Lorg/vinix/bootstrap/TouchLeaf;->x:F
invoke-virtual {p1}, Landroid/view/MotionEvent;->getRawX()F
move-result v0
iput v0, p0, Lorg/vinix/bootstrap/TouchLeaf;->raw:F
invoke-virtual {p1}, Landroid/view/MotionEvent;->getDownTime()J
move-result-wide v0
const-wide/16 v2, 123
cmp-long v0, v0, v2
if-nez v0, :bad
invoke-super {p0, p1}, Landroid/view/View;->onTouchEvent(Landroid/view/MotionEvent;)Z
move-result v0
return v0
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "gesture downTime changed during dispatch"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
	os.write_file(dir + '/TouchGroup.smali', '.class public Lorg/vinix/bootstrap/TouchGroup;\n.super Landroid/widget/FrameLayout;\n.field public intercept:Z\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nreturn-void') +
		method('public onInterceptTouchEvent(Landroid/view/MotionEvent;)Z', '
invoke-virtual {p1}, Landroid/view/MotionEvent;->getActionMasked()I
move-result v0
const/4 v1, 2
if-ne v0, v1, :no
iget-boolean v0, p0, Lorg/vinix/bootstrap/TouchGroup;->intercept:Z
return v0
:no
const/4 v0, 0
return v0'))!
	mut check := '
new-instance v0, Lorg/vinix/bootstrap/TouchGroup;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/TouchGroup;-><init>(Landroid/content/Context;)V
new-instance v1, Lorg/vinix/bootstrap/TouchLeaf;
invoke-direct {v1, p0}, Lorg/vinix/bootstrap/TouchLeaf;-><init>(Landroid/content/Context;)V
new-instance v2, Landroid/view/View;
invoke-direct {v2, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-virtual {v0, v2}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/4 v3, 0
const/16 v4, 100
invoke-virtual {v0, v3, v3, v4, v4}, Landroid/view/View;->layout(IIII)V
invoke-virtual {v2, v3, v3, v4, v4}, Landroid/view/View;->layout(IIII)V
const/16 v3, 20
const/16 v4, 80
invoke-virtual {v1, v3, v3, v4, v4}, Landroid/view/View;->layout(IIII)V
'
	// A passive overlay must not swallow the clickable view underneath it.
	check += touch_send(0, 30, 30) + touch_send(1, 30, 30)
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->clicks:I', 1, 'overlay fall-through click')
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->actions:I', 3, 'down and up delivered')
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->x:F\nfloat-to-int v7, v7', 10, 'child local coordinate')
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->raw:F\nfloat-to-int v7, v7', 30, 'raw coordinate preserved')
	check += 'const/4 v3, 0\niput v3, v1, Lorg/vinix/bootstrap/TouchLeaf;->actions:I\n'
	check += touch_send(0, 30, 30) + touch_send(2, 150, 150) + touch_send(1, 150, 150)
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->actions:I', 7, 'capture outside parent bounds')
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->clicks:I', 1, 'drag outside does not click')
	check += 'const/4 v3, 0\niput v3, v1, Lorg/vinix/bootstrap/TouchLeaf;->actions:I\nconst/4 v3, 1\niput-boolean v3, v0, Lorg/vinix/bootstrap/TouchGroup;->intercept:Z\n'
	check += touch_send(0, 30, 30) + touch_send(2, 35, 35) + touch_send(1, 35, 35)
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->actions:I', 9, 'interception cancels child')
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->clicks:I', 1, 'cancel prevents click')
	check += 'const/4 v3, 0\niput v3, v1, Lorg/vinix/bootstrap/TouchLeaf;->actions:I\nconst/4 v3, 1\niput-boolean v3, v1, Lorg/vinix/bootstrap/TouchLeaf;->disallow:Z\n'
	check += touch_send(0, 30, 30) + touch_send(2, 35, 35) + touch_send(1, 35, 35)
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->actions:I', 7, 'disallow interception')
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->clicks:I', 2, 'captured gesture completes')
	check += 'const/4 v3, 0\niput v3, v1, Lorg/vinix/bootstrap/TouchLeaf;->actions:I\ninvoke-virtual {v1, v3}, Landroid/view/View;->setEnabled(Z)V\n'
	check += touch_send(0, 30, 30) + touch_send(1, 30, 30)
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->clicks:I', 2, 'disabled view does not click')
	// UP without an accepted DOWN must not reach a child or generate a click.
	check += 'const/4 v3, 1\ninvoke-virtual {v1, v3}, Landroid/view/View;->setEnabled(Z)V\nconst/4 v3, 0\niput v3, v1, Lorg/vinix/bootstrap/TouchLeaf;->actions:I\n'
	check += touch_send(0, 5, 5) + touch_send(1, 30, 30)
	check += touch_expect('iget v7, v1, Lorg/vinix/bootstrap/TouchLeaf;->actions:I', 0, 'unowned release ignored')
	// Context click state is independent of ordinary clicks and other views.
	check += touch_expect('invoke-virtual {v1}, Landroid/view/View;->isContextClickable()Z\nmove-result v7', 0, 'default context click state')
	check += 'const/4 v3, 1\ninvoke-virtual {v1, v3}, Landroid/view/View;->setContextClickable(Z)V\n'
	check += touch_expect('invoke-virtual {v1}, Landroid/view/View;->isContextClickable()Z\nmove-result v7', 1, 'enabled context click state')
	check += touch_expect('invoke-virtual {v2}, Landroid/view/View;->isContextClickable()Z\nmove-result v7', 0, 'context click view isolation')
	check += touch_expect('invoke-virtual {v1}, Landroid/view/View;->isClickable()Z\nmove-result v7', 1, 'ordinary click state retained')
	check += 'const/4 v3, 0\ninvoke-virtual {v1, v3}, Landroid/view/View;->setClickable(Z)V\n'
	check += touch_expect('invoke-virtual {v1}, Landroid/view/View;->isContextClickable()Z\nmove-result v7', 1, 'ordinary click flag independence')
	check += 'invoke-virtual {v1, v3}, Landroid/view/View;->setContextClickable(Z)V\n'
	check += touch_expect('invoke-virtual {v1}, Landroid/view/View;->isContextClickable()Z\nmove-result v7', 0, 'disabled context click state')
	check += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-TOUCH-PASS overlay capture coordinates downTime classification interception cancellation disabled context-flags"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
	os.write_file(dir + '/TouchProbe.smali', '.class public Lorg/vinix/bootstrap/TouchProbe;\n.super Ljava/lang/Object;\n' +
		method('public static expect(IILjava/lang/String;)V', 'if-eq p0, p1, :done\nnew-instance v0, Ljava/lang/AssertionError;\ninvoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0\n:done\nreturn-void') +
		method('public static send(Landroid/view/View;III)Z', '
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
invoke-virtual {p0, v0}, Landroid/view/View;->dispatchTouchEvent(Landroid/view/MotionEvent;)Z
move-result v1
invoke-virtual {v0}, Landroid/view/MotionEvent;->recycle()V
return v1') +
		method('public static check(Landroid/content/Context;)V', check))!
}
