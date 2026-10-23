// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_autofill_manager_probe(dir string) ! {
	manager := 'Landroid/view/autofill/AutofillManager;'
	callback := 'Lorg/vinix/bootstrap/AutofillManagerCallback;'
	probe := 'Lorg/vinix/bootstrap/AutofillManagerProbe;'
	os.write_file(dir + '/AutofillManagerCallback.smali', '.class public ${callback}\n.super Landroid/view/autofill/AutofillManager\$AutofillCallback;\n.field public events:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/view/autofill/AutofillManager\$AutofillCallback;-><init>()V\nreturn-void') +
		method('public onAutofillEvent(Landroid/view/View;II)V', 'iget v0, p0, ${callback}->events:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${callback}->events:I\nreturn-void') +
		method('public onAutofillEvent(Landroid/view/View;I)V', 'iget v0, p0, ${callback}->events:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${callback}->events:I\nreturn-void'))!
	os.write_file(dir + '/AutofillManagerProbe.smali', '.class public ${probe}\n.super Ljava/lang/Object;\n' +
		method('public static check(Landroid/content/Context;)V', '
# Match Compose: retrieve the manager through Context, then notify virtual nodes.
const-class v0, ${manager}
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v0
instance-of v1, v0, ${manager}
if-eqz v1, :bad
check-cast v0, ${manager}
new-instance v1, Landroid/view/View;
invoke-direct {v1, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
new-instance v2, Landroid/graphics/Rect;
const/4 v3, 1
const/4 v4, 2
const/4 v5, 3
const/4 v6, 4
invoke-direct {v2, v3, v4, v5, v6}, Landroid/graphics/Rect;-><init>(IIII)V
new-instance v7, ${callback}
invoke-direct {v7}, ${callback}-><init>()V
invoke-virtual {v0, v7}, ${manager}->registerCallback(Landroid/view/autofill/AutofillManager\$AutofillCallback;)V
const/16 v3, 42
const/4 v4, 1
invoke-virtual {v0, v1, v3, v4}, ${manager}->notifyViewVisibilityChanged(Landroid/view/View;IZ)V
invoke-virtual {v0, v1, v3, v2}, ${manager}->notifyViewEntered(Landroid/view/View;ILandroid/graphics/Rect;)V
invoke-static {v4}, Landroid/view/autofill/AutofillValue;->forToggle(Z)Landroid/view/autofill/AutofillValue;
move-result-object v5
invoke-virtual {v0, v1, v3, v5}, ${manager}->notifyValueChanged(Landroid/view/View;ILandroid/view/autofill/AutofillValue;)V
const/4 v4, 0
invoke-static {v4}, Landroid/view/autofill/AutofillValue;->forToggle(Z)Landroid/view/autofill/AutofillValue;
move-result-object v5
invoke-virtual {v0, v1, v3, v5}, ${manager}->notifyValueChanged(Landroid/view/View;ILandroid/view/autofill/AutofillValue;)V
invoke-virtual {v0, v1, v3}, ${manager}->notifyViewExited(Landroid/view/View;I)V
invoke-virtual {v0, v1, v3, v4}, ${manager}->notifyViewVisibilityChanged(Landroid/view/View;IZ)V
# Notifications without an enabled session must not alter bounds or call clients.
iget v3, v7, ${callback}->events:I
if-nez v3, :bad
iget v3, v2, Landroid/graphics/Rect;->left:I
const/4 v4, 1
if-ne v3, v4, :bad
iget v3, v2, Landroid/graphics/Rect;->top:I
const/4 v4, 2
if-ne v3, v4, :bad
iget v3, v2, Landroid/graphics/Rect;->right:I
const/4 v4, 3
if-ne v3, v4, :bad
iget v3, v2, Landroid/graphics/Rect;->bottom:I
const/4 v4, 4
if-ne v3, v4, :bad
invoke-virtual {v0, v7}, ${manager}->unregisterCallback(Landroid/view/autofill/AutofillManager\$AutofillCallback;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-AUTOFILL-MANAGER-PASS context-lookup no-service virtual-visible virtual-hidden enter values-true-false exit no-callback bounds"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "unavailable AutofillManager virtual notification contract"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
