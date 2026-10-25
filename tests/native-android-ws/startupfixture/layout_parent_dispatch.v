// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

// A container can consume a descendant request without forwarding it. Repeated
// requests must enter its override even while the child already needs layout.
// The focused runner also executes the 332 callback and measurement-cache probe.
pub fn install_layout_parent_dispatch_probe(dir string) ! {
 v := 'Landroid/view/View;'
 g := 'Landroid/view/ViewGroup;'
 base := 'Lorg/vinix/bootstrap/LayoutRequestParent;'
 c := 'Lorg/vinix/bootstrap/LayoutParentDispatchParent;'
 p := 'Lorg/vinix/bootstrap/LayoutParentDispatchProbe;'
 os.write_file(dir + '/LayoutParentDispatchParent.smali', '.class public ${c}\n.super ${base}\n.field public requests:I\n.field public intercept:Z\n' +
  method('public constructor <init>(Landroid/content/Context;)V', '
invoke-direct {p0, p1}, ${base}-><init>(Landroid/content/Context;)V
const/4 v0, 1
iput-boolean v0, p0, ${base}->measureChild:Z
return-void') +
  method('public requestLayout()V', '
iget v0, p0, ${c}->requests:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${c}->requests:I
iget-boolean v0, p0, ${c}->intercept:Z
if-nez v0, :done
invoke-super {p0}, ${base}->requestLayout()V
:done
return-void'))!
 mut check := '
new-instance v6, ${c}
invoke-direct {v6, p0}, ${c}-><init>(Landroid/content/Context;)V
new-instance v7, ${c}
invoke-direct {v7, p0}, ${c}-><init>(Landroid/content/Context;)V
new-instance v8, ${v}
invoke-direct {v8, p0}, ${v}-><init>(Landroid/content/Context;)V
invoke-virtual {v7, v8}, ${g}->addView(${v})V
invoke-virtual {v6, v7}, ${g}->addView(${v})V
invoke-static {v6}, ${p}->traverse(${v})V
const/4 v0, 0
iput v0, v6, ${c}->requests:I
iput v0, v7, ${c}->requests:I
'
 for target in ['v6', 'v7', 'v8'] {
  check += dispatch_flag_check(p, v, target, 0, 'initial traversal must settle all views')
 }
 check += '
const/4 v0, 1
iput-boolean v0, v7, ${c}->intercept:Z
invoke-virtual {v8}, ${v}->requestLayout()V
const/4 v0, 1
const-string v1, "descendant request bypassed parent override"
invoke-static {v7, v0, v1}, ${p}->count(${c}ILjava/lang/String;)V
const/4 v0, 0
const-string v1, "intercepted request reached the ancestor"
invoke-static {v6, v0, v1}, ${p}->count(${c}ILjava/lang/String;)V
'
 for target in ['v6', 'v7', 'v8'] {
  pending := if target == 'v8' { 1 } else { 0 }
  check += dispatch_flag_check(p, v, target, pending, 'interception changed ancestor pending flags')
 }
 check += '
# The child is already pending; its second request must still be dispatched.
invoke-virtual {v8}, ${v}->requestLayout()V
const/4 v0, 2
const-string v1, "repeated pending-child request skipped parent override"
invoke-static {v7, v0, v1}, ${p}->count(${c}ILjava/lang/String;)V
const/4 v0, 0
const-string v1, "repeated intercepted request reached ancestor"
invoke-static {v6, v0, v1}, ${p}->count(${c}ILjava/lang/String;)V
# Forwarding through super must reach the next virtual parent implementation.
iput-boolean v0, v7, ${c}->intercept:Z
invoke-virtual {v8}, ${v}->requestLayout()V
const/4 v0, 3
const-string v1, "forwarded request skipped intermediate override"
invoke-static {v7, v0, v1}, ${p}->count(${c}ILjava/lang/String;)V
const/4 v0, 1
const-string v1, "forwarded request skipped ancestor override"
invoke-static {v6, v0, v1}, ${p}->count(${c}ILjava/lang/String;)V
'
 for target in ['v6', 'v7', 'v8'] {
  check += dispatch_flag_check(p, v, target, 1, 'forwarded request did not mark the full parent chain')
 }
 check += 'invoke-static {v6}, ${p}->traverse(${v})V\n'
 for target in ['v6', 'v7', 'v8'] {
  check += dispatch_flag_check(p, v, target, 0, 'next measurement did not consume forwarded request')
 }
 check += '
invoke-static {p0}, ${p}->windowRoot(Landroid/content/Context;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-LAYOUT-PARENT-DISPATCH-PASS intercept repeated-pending forward ancestor next-measure window-root"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void'
 os.write_file(dir + '/LayoutParentDispatchProbe.smali', '.class public ${p}\n.super Ljava/lang/Object;\n' +
  method('public static check(Landroid/content/Context;)V', check) +
  method('private static windowRoot(Landroid/content/Context;)V', '
new-instance v6, ${c}
invoke-direct {v6, p0}, ${c}-><init>(Landroid/content/Context;)V
new-instance v7, ${v}
invoke-direct {v7, p0}, ${v}-><init>(Landroid/content/Context;)V
invoke-virtual {v6, v7}, ${g}->addView(${v})V
# Construct the actual private provider parent without its unrelated,
# unsupported WindowManagerImpl.native_addView entry.
const-string v0, "android.view.WindowManagerImpl$WindowViewParent"
invoke-static {v0}, Ljava/lang/Class;->forName(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v8
const/4 v0, 0
new-array v1, v0, [Ljava/lang/Class;
invoke-virtual {v8, v1}, Ljava/lang/Class;->getDeclaredConstructor([Ljava/lang/Class;)Ljava/lang/reflect/Constructor;
move-result-object v9
const/4 v0, 1
invoke-virtual {v9, v0}, Ljava/lang/reflect/Constructor;->setAccessible(Z)V
const/4 v0, 0
new-array v1, v0, [Ljava/lang/Object;
invoke-virtual {v9, v1}, Ljava/lang/reflect/Constructor;->newInstance([Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/view/ViewParent;
iput-object v0, v6, ${v}->parent:Landroid/view/ViewParent;
invoke-virtual {v6}, ${v}->getParent()Landroid/view/ViewParent;
move-result-object v0
if-eqz v0, :bad
invoke-virtual {v0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Class;->getName()Ljava/lang/String;
move-result-object v0
const-string v1, "android.view.WindowManagerImpl$WindowViewParent"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
# Exercise the real non-View parent ABI, including descendant forwarding.
invoke-virtual {v7}, ${v}->requestLayout()V
invoke-virtual {v6}, ${v}->requestLayout()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "window root parent was not installed"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static traverse(${v})V', '
const v0, 0x40000028
const v1, 0x4000001e
invoke-virtual {p0, v0, v1}, ${v}->measure(II)V
const/4 v0, 0
const/16 v1, 40
const/16 v2, 30
invoke-virtual {p0, v0, v0, v1, v2}, ${v}->layout(IIII)V
return-void') +
  method('private static flag(${v}ZLjava/lang/String;)V', '
invoke-virtual {p0}, ${v}->isLayoutRequested()Z
move-result v0
if-ne v0, p1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static count(${c}ILjava/lang/String;)V', '
iget v0, p0, ${c}->requests:I
if-ne v0, p1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}

fn dispatch_flag_check(probe string, view string, target string, pending int, message string) string {
 return 'const/4 v0, ${pending}\nconst-string v1, "${message}"\ninvoke-static {${target}, v0, v1}, ${probe}->flag(${view}ZLjava/lang/String;)V\n'
}
