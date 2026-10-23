// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_child_order_probe(dir string) ! {
	mut group := '.class public Lorg/vinix/bootstrap/OrderGroup;\n.super Landroid/widget/FrameLayout;\n.implements Landroid/view/ViewGroup$OnHierarchyChangeListener;\n.field public requests:I\n.field public invalidations:I\n.field public hierarchy:I\n'
	group += method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\ninvoke-virtual {p0, p0}, Landroid/view/ViewGroup;->setOnHierarchyChangeListener(Landroid/view/ViewGroup$OnHierarchyChangeListener;)V\nreturn-void')
	for signature, field in {
		'requestLayout()V':                                            'requests'
		'invalidate()V':                                               'invalidations'
		'onViewAdded(Landroid/view/View;)V':                           'hierarchy'
		'onViewRemoved(Landroid/view/View;)V':                         'hierarchy'
		'onChildViewAdded(Landroid/view/View;Landroid/view/View;)V':   'hierarchy'
		'onChildViewRemoved(Landroid/view/View;Landroid/view/View;)V': 'hierarchy'
	} {
		group += method('public ' + signature, 'iget v0, p0, Lorg/vinix/bootstrap/OrderGroup;->${field}:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/OrderGroup;->${field}:I\n' + if field == 'hierarchy' {
			''
		} else {
			'invoke-super {p0}, Landroid/widget/FrameLayout;->${signature}\n'
		} + 'return-void')
	}
	os.write_file(dir + '/OrderGroup.smali', group)!
	mut leaf := '.class public Lorg/vinix/bootstrap/OrderLeaf;\n.super Lorg/vinix/bootstrap/TouchLeaf;\n.field public attached:I\n.field public detached:I\n'
	leaf += method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Lorg/vinix/bootstrap/TouchLeaf;-><init>(Landroid/content/Context;)V\nreturn-void')
	for callback, field in {
		'Attached': 'attached'
		'Detached': 'detached'
	} {
		leaf += method('protected on${callback}ToWindow()V'.replace('DetachedTo', 'DetachedFrom'), 'iget v0, p0, Lorg/vinix/bootstrap/OrderLeaf;->${field}:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/OrderLeaf;->${field}:I\nreturn-void')
	}
	os.write_file(dir + '/OrderLeaf.smali', leaf)!
	mut check := '
new-instance v0, Lorg/vinix/bootstrap/OrderGroup;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/OrderGroup;-><init>(Landroid/content/Context;)V
new-instance v4, Landroid/widget/FrameLayout$LayoutParams;
const/16 v5, 32
invoke-direct {v4, v5, v5}, Landroid/widget/FrameLayout$LayoutParams;-><init>(II)V
const/4 v6, 0
invoke-virtual {v0, v6, v6, v5, v5}, Landroid/view/View;->layout(IIII)V
'
	for i, color in ['0xffff0000', '0xff00ff00', '0xff0000ff'] {
		reg := i + 1
		check += 'new-instance v${reg}, Lorg/vinix/bootstrap/OrderLeaf;\ninvoke-direct {v${reg}, p0}, Lorg/vinix/bootstrap/OrderLeaf;-><init>(Landroid/content/Context;)V\ninvoke-virtual {v0, v${reg}, v4}, Landroid/view/ViewGroup;->addView(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V\ninvoke-virtual {v${reg}, v6, v6, v5, v5}, Landroid/view/View;->layout(IIII)V\nconst v7, ${color}\ninvoke-virtual {v${reg}, v7}, Landroid/view/View;->setBackgroundColor(I)V\n'
	}
	check += '
new-instance v5, Landroid/os/Binder;
invoke-direct {v5}, Landroid/os/Binder;-><init>()V
invoke-virtual {v0, v5}, Landroid/view/View;->vinixAttachToWindow(Landroid/os/IBinder;)V
iput v6, v0, Lorg/vinix/bootstrap/OrderGroup;->hierarchy:I
'
	// Three overlapping views expose both forward paint order and reverse hit
	// testing. The already-last case must still schedule layout and redraw.
	for phase, order in [[1, 2, 3], [2, 3, 1], [3, 1, 2], [3, 1, 2]] {
		if phase > 0 {
			check += 'iget v6, v0, Lorg/vinix/bootstrap/OrderGroup;->requests:I\niget v7, v0, Lorg/vinix/bootstrap/OrderGroup;->invalidations:I\n'
			check += if phase == 1 {
				'invoke-virtual {v1}, Landroid/view/View;->bringToFront()V\n'
			} else {
				'invoke-virtual {v0, v2}, Landroid/view/ViewGroup;->bringChildToFront(Landroid/view/View;)V\n'
			}
			for reg, field in {
				'v6': 'requests'
				'v7': 'invalidations'
			} {
				check += 'iget v8, v0, Lorg/vinix/bootstrap/OrderGroup;->${field}:I\nif-le v8, ${reg}, :bad\n'
			}
		}
		for index, reg in order {
			check += 'const/4 v6, ${index}\ninvoke-virtual {v0, v6}, Landroid/view/ViewGroup;->getChildAt(I)Landroid/view/View;\nmove-result-object v6\nif-ne v6, v${reg}, :bad\n'
		}
		for reg in 1 .. 4 {
			check += 'invoke-static {v${reg}, v0, v4, v5}, Lorg/vinix/bootstrap/ChildOrderProbe;->preserved(Lorg/vinix/bootstrap/OrderLeaf;Landroid/view/ViewGroup;Landroid/view/ViewGroup$LayoutParams;Landroid/os/IBinder;)V\nconst/4 v6, 0\niput v6, v${reg}, Lorg/vinix/bootstrap/TouchLeaf;->clicks:I\n'
		}
		color := ['0xffff0000', '0xff00ff00', '0xff0000ff'][order[2] - 1]
		check += 'const v6, ${color}\ninvoke-static {v0, v6}, Lorg/vinix/bootstrap/ChildOrderProbe;->pixels(Landroid/view/View;I)V\n'
		for action in [0, 1] {
			check += 'const/4 v6, ${action}\nconst/16 v7, 10\ninvoke-static {v0, v6, v7, v7}, Lorg/vinix/bootstrap/TouchProbe;->send(Landroid/view/View;III)Z\n'
		}
		for reg in 1 .. 4 {
			expect := if reg == order[2] { 1 } else { 0 }
			check += 'iget v6, v${reg}, Lorg/vinix/bootstrap/TouchLeaf;->clicks:I\nconst/4 v7, ${expect}\nif-ne v6, v7, :bad\n'
		}
	}
	// A child owned by another group and an orphan leave this group untouched.
	check += '
new-instance v1, Landroid/widget/FrameLayout;
invoke-direct {v1, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
new-instance v2, Landroid/view/View;
invoke-direct {v2, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v1, v2}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
new-instance v3, Landroid/view/View;
invoke-direct {v3, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
iget v6, v0, Lorg/vinix/bootstrap/OrderGroup;->requests:I
iget v7, v0, Lorg/vinix/bootstrap/OrderGroup;->invalidations:I
invoke-virtual {v0, v2}, Landroid/view/ViewGroup;->bringChildToFront(Landroid/view/View;)V
invoke-virtual {v0, v3}, Landroid/view/ViewGroup;->bringChildToFront(Landroid/view/View;)V
invoke-virtual {v3}, Landroid/view/View;->bringToFront()V
iget v8, v0, Lorg/vinix/bootstrap/OrderGroup;->requests:I
if-ne v8, v6, :bad
iget v8, v0, Lorg/vinix/bootstrap/OrderGroup;->invalidations:I
if-ne v8, v7, :bad
invoke-virtual {v2}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v8
if-ne v8, v1, :bad
invoke-virtual {v3}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v8
if-nez v8, :bad
iget v8, v0, Lorg/vinix/bootstrap/OrderGroup;->hierarchy:I
if-nez v8, :bad
invoke-virtual {v0}, Landroid/view/ViewGroup;->getChildCount()I
move-result v8
const/4 v9, 3
if-ne v8, v9, :bad
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/view/View;->vinixAttachToWindow(Landroid/os/IBinder;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-CHILD-ORDER-PASS view parent already-top foreign orphan stable-order parent params token attachment hierarchy layout invalidate all-pixels touch"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "child stacking order or preserved hierarchy"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
	os.write_file(dir + '/ChildOrderProbe.smali', '.class public Lorg/vinix/bootstrap/ChildOrderProbe;\n.super Ljava/lang/Object;\n' + method('public static check(Landroid/content/Context;)V', check) +
		method('private static preserved(Lorg/vinix/bootstrap/OrderLeaf;Landroid/view/ViewGroup;Landroid/view/ViewGroup$LayoutParams;Landroid/os/IBinder;)V', '
invoke-virtual {p0}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v0
if-ne v0, p1, :bad
invoke-virtual {p0}, Landroid/view/View;->getLayoutParams()Landroid/view/ViewGroup$LayoutParams;
move-result-object v0
if-ne v0, p2, :bad
invoke-virtual {p0}, Landroid/view/View;->getWindowToken()Landroid/os/IBinder;
move-result-object v0
if-ne v0, p3, :bad
invoke-virtual {p0}, Landroid/view/View;->isAttachedToWindow()Z
move-result v0
if-eqz v0, :bad
iget v0, p0, Lorg/vinix/bootstrap/OrderLeaf;->attached:I
const/4 v1, 1
if-ne v0, v1, :bad
iget v0, p0, Lorg/vinix/bootstrap/OrderLeaf;->detached:I
if-nez v0, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "reordering detached or reparented a view"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') + method('private static pixels(Landroid/view/View;I)V', '
const/16 v0, 32
sget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v0
new-instance v1, Landroid/graphics/Canvas;
invoke-direct {v1, v0}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {p0, v1}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
const/16 v1, 1024
new-array v1, v1, [I
const/4 v2, 0
const/16 v3, 32
const/4 v4, 0
const/4 v5, 0
const/16 v6, 32
const/16 v7, 32
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
invoke-virtual {v0}, Landroid/graphics/Bitmap;->recycle()V
:pixel
aget v4, v1, v2
if-ne v4, p1, :bad
add-int/lit8 v2, v2, 1
const/16 v5, 1024
if-lt v2, v5, :pixel
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "paint order disagrees with child order"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
