// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_child_states_probe(dir string) ! {
	os.write_file(dir + '/StateGroup.smali', '.class public Lorg/vinix/bootstrap/StateGroup;\n.super Landroid/widget/FrameLayout;\n.field public changes:I\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nreturn-void') +
		method('protected drawableStateChanged()V', 'invoke-super {p0}, Landroid/widget/FrameLayout;->drawableStateChanged()V\niget v0, p0, Lorg/vinix/bootstrap/StateGroup;->changes:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/StateGroup;->changes:I\nreturn-void') +
		method('public create(I)[I', 'invoke-virtual {p0, p1}, Lorg/vinix/bootstrap/StateGroup;->onCreateDrawableState(I)[I\nmove-result-object v0\nreturn-object v0') +
		method('public static merge([I[I)[I', 'invoke-static {p0, p1}, Landroid/view/View;->mergeDrawableStates([I[I)[I\nmove-result-object v0\nreturn-object v0'))!
	os.write_file(dir + '/NullStateView.smali', '.class public Lorg/vinix/bootstrap/NullStateView;\n.super Landroid/view/View;\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/view/View;-><init>(Landroid/content/Context;)V\nreturn-void') +
		method('protected onCreateDrawableState(I)[I', 'const/4 v0, 0\nreturn-object v0'))!
	os.write_file(dir + '/ChildStatesProbe.smali', '.class public Lorg/vinix/bootstrap/ChildStatesProbe;\n.super Ljava/lang/Object;\n' +
		method('private static contains(Landroid/view/View;IZ)V', '
invoke-virtual {p0}, Landroid/view/View;->getDrawableState()[I
move-result-object v0
const/4 v1, 0
const/4 v2, 0
array-length v3, v0
:loop
if-ge v1, v3, :done
aget v4, v0, v1
if-ne v4, p1, :next
const/4 v2, 1
:next
add-int/lit8 v1, v1, 1
goto :loop
:done
if-ne v2, p2, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "ViewGroup drawable-state contents"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		method('private static background(Landroid/content/Context;)V', '
new-instance v0, Lorg/vinix/bootstrap/StateGroup;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/StateGroup;-><init>(Landroid/content/Context;)V
new-instance v1, Landroid/view/View;
invoke-direct {v1, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
new-instance v2, Landroid/graphics/drawable/GradientDrawable;
invoke-direct {v2}, Landroid/graphics/drawable/GradientDrawable;-><init>()V
const/4 v3, 2
new-array v4, v3, [[I
new-array v5, v3, [I
const/4 v3, 1
new-array v6, v3, [I
const/4 v7, 0
const v8, 0x10100a7
aput v8, v6, v7
aput-object v6, v4, v7
new-array v6, v7, [I
aput-object v6, v4, v3
const v8, -0x10000
aput v8, v5, v7
const v8, -0xff0100
aput v8, v5, v3
new-instance v6, Landroid/content/res/ColorStateList;
invoke-direct {v6, v4, v5}, Landroid/content/res/ColorStateList;-><init>([[I[I)V
invoke-virtual {v2, v6}, Landroid/graphics/drawable/GradientDrawable;->setColor(Landroid/content/res/ColorStateList;)V
invoke-virtual {v0, v2}, Landroid/view/View;->setBackground(Landroid/graphics/drawable/Drawable;)V
invoke-virtual {v0, v3}, Landroid/view/ViewGroup;->setAddStatesFromChildren(Z)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const v8, -0xff0100
invoke-static {v2, v8}, Lorg/vinix/bootstrap/DrawableProbe;->pixel(Landroid/graphics/drawable/GradientDrawable;I)V
invoke-virtual {v1, v3}, Landroid/view/View;->setPressed(Z)V
const v8, -0x10000
invoke-static {v2, v8}, Lorg/vinix/bootstrap/DrawableProbe;->pixel(Landroid/graphics/drawable/GradientDrawable;I)V
invoke-virtual {v1, v7}, Landroid/view/View;->setPressed(Z)V
const v8, -0xff0100
invoke-static {v2, v8}, Lorg/vinix/bootstrap/DrawableProbe;->pixel(Landroid/graphics/drawable/GradientDrawable;I)V
invoke-virtual {v1, v3}, Landroid/view/View;->setPressed(Z)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->removeView(Landroid/view/View;)V
invoke-static {v2, v8}, Lorg/vinix/bootstrap/DrawableProbe;->pixel(Landroid/graphics/drawable/GradientDrawable;I)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const v8, -0x10000
invoke-static {v2, v8}, Lorg/vinix/bootstrap/DrawableProbe;->pixel(Landroid/graphics/drawable/GradientDrawable;I)V
invoke-virtual {v0}, Landroid/view/ViewGroup;->removeAllViews()V
const v8, -0xff0100
invoke-static {v2, v8}, Lorg/vinix/bootstrap/DrawableProbe;->pixel(Landroid/graphics/drawable/GradientDrawable;I)V
return-void') +
		method('public static check(Landroid/content/Context;)V', '
new-instance v0, Lorg/vinix/bootstrap/StateGroup;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/StateGroup;-><init>(Landroid/content/Context;)V
new-instance v1, Lorg/vinix/bootstrap/StateGroup;
invoke-direct {v1, p0}, Lorg/vinix/bootstrap/StateGroup;-><init>(Landroid/content/Context;)V
new-instance v2, Landroid/view/View;
invoke-direct {v2, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v0}, Landroid/view/ViewGroup;->addStatesFromChildren()Z
move-result v3
if-nez v3, :bad
invoke-virtual {v0, v2}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/4 v3, 1
const/4 v4, 0
invoke-virtual {v2, v3}, Landroid/view/View;->setPressed(Z)V
const v5, 0x10100a7
invoke-static {v0, v5, v4}, Lorg/vinix/bootstrap/ChildStatesProbe;->contains(Landroid/view/View;IZ)V
iput v4, v0, Lorg/vinix/bootstrap/StateGroup;->changes:I
invoke-virtual {v0, v3}, Landroid/view/ViewGroup;->setAddStatesFromChildren(Z)V
invoke-static {v0, v5, v3}, Lorg/vinix/bootstrap/ChildStatesProbe;->contains(Landroid/view/View;IZ)V
invoke-virtual {v0}, Landroid/view/ViewGroup;->addStatesFromChildren()Z
move-result v6
if-ne v6, v3, :bad
invoke-virtual {v1}, Landroid/view/ViewGroup;->addStatesFromChildren()Z
move-result v6
if-nez v6, :bad
iget v6, v0, Lorg/vinix/bootstrap/StateGroup;->changes:I
if-ne v6, v3, :bad
# Setter always refreshes, including repeated values.
invoke-virtual {v0, v3}, Landroid/view/ViewGroup;->setAddStatesFromChildren(Z)V
iget v6, v0, Lorg/vinix/bootstrap/StateGroup;->changes:I
const/4 v7, 2
if-ne v6, v7, :bad
invoke-virtual {v2, v4}, Landroid/view/View;->setPressed(Z)V
invoke-static {v0, v5, v4}, Lorg/vinix/bootstrap/ChildStatesProbe;->contains(Landroid/view/View;IZ)V
iget v6, v0, Lorg/vinix/bootstrap/StateGroup;->changes:I
const/4 v7, 3
if-ne v6, v7, :bad
# Nested aggregation propagates a real child selection and activation.
invoke-virtual {v1, v0}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-virtual {v1, v3}, Landroid/view/ViewGroup;->setAddStatesFromChildren(Z)V
iput v4, v1, Lorg/vinix/bootstrap/StateGroup;->changes:I
invoke-virtual {v2, v3}, Landroid/view/View;->setSelected(Z)V
const v5, 0x10100a1
invoke-static {v1, v5, v3}, Lorg/vinix/bootstrap/ChildStatesProbe;->contains(Landroid/view/View;IZ)V
iget v6, v1, Lorg/vinix/bootstrap/StateGroup;->changes:I
if-ne v6, v3, :bad
invoke-virtual {v2, v3}, Landroid/view/View;->setActivated(Z)V
const v5, 0x10102fe
invoke-static {v1, v5, v3}, Lorg/vinix/bootstrap/ChildStatesProbe;->contains(Landroid/view/View;IZ)V
# Own enabled state is independent of child aggregation.
invoke-virtual {v2, v4}, Landroid/view/View;->setEnabled(Z)V
const v5, 0x101009e
invoke-static {v2, v5, v4}, Lorg/vinix/bootstrap/ChildStatesProbe;->contains(Landroid/view/View;IZ)V
invoke-static {v0, v5, v3}, Lorg/vinix/bootstrap/ChildStatesProbe;->contains(Landroid/view/View;IZ)V
# Null child states and reserved zero slots remain safe.
new-instance v6, Lorg/vinix/bootstrap/NullStateView;
invoke-direct {v6, p0}, Lorg/vinix/bootstrap/NullStateView;-><init>(Landroid/content/Context;)V
invoke-virtual {v0, v6}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-virtual {v0, v7}, Lorg/vinix/bootstrap/StateGroup;->create(I)[I
move-result-object v6
array-length v8, v6
sub-int/2addr v8, v3
aget v8, v6, v8
if-nez v8, :bad
invoke-virtual {v0, v2}, Landroid/view/ViewGroup;->removeView(Landroid/view/View;)V
const v5, 0x10102fe
invoke-static {v1, v5, v4}, Lorg/vinix/bootstrap/ChildStatesProbe;->contains(Landroid/view/View;IZ)V
invoke-virtual {v0, v4}, Landroid/view/ViewGroup;->setAddStatesFromChildren(Z)V
iput v4, v0, Lorg/vinix/bootstrap/StateGroup;->changes:I
invoke-virtual {v0, v2}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-virtual {v2, v3}, Landroid/view/View;->setPressed(Z)V
iget v6, v0, Lorg/vinix/bootstrap/StateGroup;->changes:I
if-nez v6, :bad
const v5, 0x10100a7
invoke-static {v0, v5, v4}, Lorg/vinix/bootstrap/ChildStatesProbe;->contains(Landroid/view/View;IZ)V
# Merge preserves the original object and appends after the last live entry.
const/4 v5, 4
new-array v5, v5, [I
const/16 v6, 123
aput v6, v5, v4
new-array v7, v3, [I
const/16 v8, 456
aput v8, v7, v4
invoke-static {v5, v7}, Lorg/vinix/bootstrap/StateGroup;->merge([I[I)[I
move-result-object v7
if-ne v7, v5, :bad
aget v7, v5, v4
if-ne v7, v6, :bad
aget v7, v5, v3
if-ne v7, v8, :bad
invoke-static {p0}, Lorg/vinix/bootstrap/ChildStatesProbe;->background(Landroid/content/Context;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-CHILD-STATES-PASS defaults isolation toggles merge nested pressed selected activated enabled refresh null-child reserved removal background-pixels add remove-all"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "ViewGroup child-state contract"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
