// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn text_size_mark(name string) string {
 return 'const-string v9, "TEXT-SIZE-${name}"\ninvoke-static {v9}, Lorg/vinix/bootstrap/TextSizeProbe;->mark(Ljava/lang/String;)V\n'
}

// Constants are independent pixel expectations for density=2, scaledDensity=3,
// xdpi=144. They deliberately do not call applyDimension as their oracle.
fn text_size_pixels(register string, expected string, label string) string {
 return 'const v8, ${expected}\nconst-string v9, "${label}"\ninvoke-static {${register}, v8, v9}, Lorg/vinix/bootstrap/TextSizeProbe;->pixels(Landroid/widget/TextView;FLjava/lang/String;)V\n'
}

pub fn install_text_size_probe(dir string) ! {
 c := 'Lorg/vinix/bootstrap/TextSizeProbe;'
 context := 'Lorg/vinix/bootstrap/TextSizeContext;'
 tracking := 'Lorg/vinix/bootstrap/TextSizeTrackingView;'
 os.write_file(dir + '/TextSizeContext.smali', '.class public ${context}\n.super Landroid/content/ContextWrapper;\n.field private resources:Landroid/content/res/Resources;\n.field private theme:Landroid/content/res/Resources$Theme;\n' +
  method('public constructor <init>(Landroid/content/Context;)V', '
invoke-direct {p0, p1}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V
invoke-virtual {p1}, Landroid/content/Context;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
new-instance v1, Landroid/util/DisplayMetrics;
invoke-direct {v1}, Landroid/util/DisplayMetrics;-><init>()V
new-instance v2, Landroid/content/res/Configuration;
invoke-direct {v2}, Landroid/content/res/Configuration;-><init>()V
new-instance v3, Landroid/content/res/Resources;
invoke-direct {v3, v0, v1, v2}, Landroid/content/res/Resources;-><init>(Landroid/content/res/AssetManager;Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)V
iput-object v3, p0, ${context}->resources:Landroid/content/res/Resources;
invoke-virtual {v3}, Landroid/content/res/Resources;->getDisplayMetrics()Landroid/util/DisplayMetrics;
move-result-object v1
const/high16 v0, 0x40000000
iput v0, v1, Landroid/util/DisplayMetrics;->density:F
const/high16 v0, 0x40400000
iput v0, v1, Landroid/util/DisplayMetrics;->scaledDensity:F
const/high16 v0, 0x43100000
iput v0, v1, Landroid/util/DisplayMetrics;->xdpi:F
const/16 v0, 320
iput v0, v1, Landroid/util/DisplayMetrics;->densityDpi:I
invoke-virtual {v3}, Landroid/content/res/Resources;->newTheme()Landroid/content/res/Resources$Theme;
move-result-object v0
iput-object v0, p0, ${context}->theme:Landroid/content/res/Resources$Theme;
return-void') +
  method('public getResources()Landroid/content/res/Resources;', 'iget-object v0, p0, ${context}->resources:Landroid/content/res/Resources;\nreturn-object v0') +
  method('public getTheme()Landroid/content/res/Resources$Theme;', 'iget-object v0, p0, ${context}->theme:Landroid/content/res/Resources$Theme;\nreturn-object v0'))!
 os.write_file(dir + '/TextSizeTrackingView.smali', '.class public ${tracking}\n.super Landroid/widget/TextView;\n.field public requests:I\n.field public invalidates:I\n.field public calls:I\n.field public unit:I\n.field public argument:F\n' +
  method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nreturn-void') +
  method('public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;)V', 'const/4 v0, 0\ninvoke-direct {p0, p1, p2, v0, v0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\nreturn-void') +
  method('public setTextSize(IF)V', '
iget v0, p0, ${tracking}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${tracking}->calls:I
iput p1, p0, ${tracking}->unit:I
iput p2, p0, ${tracking}->argument:F
invoke-super {p0, p1, p2}, Landroid/widget/TextView;->setTextSize(IF)V
return-void') +
  method('public requestLayout()V', 'iget v0, p0, ${tracking}->requests:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${tracking}->requests:I\ninvoke-super {p0}, Landroid/view/View;->requestLayout()V\nreturn-void') +
  method('public invalidate()V', 'iget v0, p0, ${tracking}->invalidates:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${tracking}->invalidates:I\ninvoke-super {p0}, Landroid/view/View;->invalidate()V\nreturn-void'))!
 os.write_file(dir + '/TextSizeCompoundButton.smali', '.class public Lorg/vinix/bootstrap/TextSizeCompoundButton;\n.super Landroid/widget/CompoundButton;\n' +
  method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/CompoundButton;-><init>(Landroid/content/Context;)V\nreturn-void'))!
 mut source := '.class public ${c}\n.super Ljava/lang/Object;\n'
 source += method('private static mark(Ljava/lang/String;)V', 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\ninvoke-virtual {v0, p0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void')
 source += method('private static fail(Ljava/lang/String;)V', 'new-instance v0, Ljava/lang/AssertionError;\ninvoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0')
 source += method('private static expect(FFLjava/lang/String;)V', '
cmpl-float v0, p0, p0
if-nez v0, :bad
sub-float v0, p0, p1
invoke-static {v0}, Ljava/lang/Math;->abs(F)F
move-result v0
const v1, 0x3c23d70a
cmpl-float v0, v0, v1
if-lez v0, :ok
:bad
invoke-static {p2}, ${c}->fail(Ljava/lang/String;)V
:ok
return-void')
 source += method('private static pixels(Landroid/widget/TextView;FLjava/lang/String;)V', '
invoke-virtual {p0}, Landroid/widget/TextView;->getTextSize()F
move-result v0
invoke-static {v0, p1, p2}, ${c}->expect(FFLjava/lang/String;)V
invoke-virtual {p0}, Landroid/widget/TextView;->getPaint()Landroid/text/TextPaint;
move-result-object v0
invoke-virtual {v0}, Landroid/graphics/Paint;->getTextSize()F
move-result v0
invoke-static {v0, p1, p2}, ${c}->expect(FFLjava/lang/String;)V
return-void')
 mut units := 'invoke-virtual {p0}, Landroid/widget/TextView;->getPaint()Landroid/text/TextPaint;\nmove-result-object v6\n'
 for test in [['0', '0x40f00000', '0x40f00000', 'PX'], ['1', '0x40f00000', '0x41700000', 'DP'],
  ['2', '0x40f00000', '0x41b40000', 'SP'], ['3', '0x41100000', '0x41900000', 'PT'],
  ['4', '0x3e000000', '0x41900000', 'IN'], ['5', '0x404b3333', '0x41900000', 'MM']] {
  units += 'const/4 v0, ${test[0]}\nconst v1, ${test[1]}\ninvoke-virtual {p0, v0, v1}, Landroid/widget/TextView;->setTextSize(IF)V\n' +
   text_size_pixels('p0', test[2], 'text-size ' + test[3] + ' units') +
   'invoke-virtual {p0}, Landroid/widget/TextView;->getPaint()Landroid/text/TextPaint;\nmove-result-object v0\nif-ne v0, v6, :bad\n'
 }
 units += text_size_mark('UNITS-PASS') + 'return-void\n:bad\nconst-string v0, "text-size Paint identity"\ninvoke-static {v0}, ${c}->fail(Ljava/lang/String;)V\nreturn-void'
 source += method('private static units(Landroid/widget/TextView;)V', units)
 source += method('private static settle(Landroid/view/View;)V', '
const/4 v0, 0
invoke-virtual {p0, v0, v0}, Landroid/view/View;->measure(II)V
invoke-virtual {p0}, Landroid/view/View;->getMeasuredWidth()I
move-result v1
invoke-virtual {p0}, Landroid/view/View;->getMeasuredHeight()I
move-result v2
invoke-virtual {p0, v0, v0, v1, v2}, Landroid/view/View;->layout(IIII)V
invoke-virtual {p0}, Landroid/view/View;->isLayoutRequested()Z
move-result v0
if-eqz v0, :ok
const-string v0, "text-size settle layout"
invoke-static {v0}, ${c}->fail(Ljava/lang/String;)V
:ok
return-void')
 // Exercise native WsView measurement twice: once from an ordinary setter and
 // once with an exposed Paint changed to the target size before the setter.
 source += method('private static nativeCycle(${tracking}Z)V', '
const/4 v0, 0
const/high16 v1, 0x41800000
invoke-virtual {p0, v0, v1}, Landroid/widget/TextView;->setTextSize(IF)V
invoke-static {p0}, ${c}->settle(Landroid/view/View;)V
invoke-virtual {p0}, Landroid/view/View;->getMeasuredWidth()I
move-result v3
invoke-virtual {p0}, Landroid/view/View;->getMeasuredHeight()I
move-result v4
invoke-virtual {p0}, Landroid/widget/TextView;->getPaint()Landroid/text/TextPaint;
move-result-object v6
const-string v7, "WWWWWWWW"
invoke-virtual {v6, v7}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v5
const/high16 v1, 0x42000000
if-eqz p1, :ordinary
invoke-virtual {v6, v1}, Landroid/graphics/Paint;->setTextSize(F)V
:ordinary
iput v0, p0, ${tracking}->requests:I
iput v0, p0, ${tracking}->invalidates:I
invoke-virtual {p0, v0, v1}, Landroid/widget/TextView;->setTextSize(IF)V
invoke-virtual {p0}, Landroid/view/View;->isLayoutRequested()Z
move-result v0
if-eqz v0, :bad
iget v0, p0, ${tracking}->requests:I
if-lez v0, :bad
iget v0, p0, ${tracking}->invalidates:I
if-lez v0, :bad
invoke-virtual {v6, v7}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v0
cmpl-float v0, v0, v5
if-lez v0, :bad
invoke-static {p0}, ${c}->settle(Landroid/view/View;)V
invoke-virtual {p0}, Landroid/view/View;->getMeasuredWidth()I
move-result v0
if-le v0, v3, :bad
invoke-virtual {p0}, Landroid/view/View;->getMeasuredHeight()I
move-result v0
if-le v0, v4, :bad
' + text_size_pixels('p0', '0x42000000', 'text-size native pixels') + '
return-void
:bad
const-string v0, "text-size native measurement layout invalidate"
invoke-static {v0}, ${c}->fail(Ljava/lang/String;)V
return-void')
 mut subclasses := ''
 for name in ['android/widget/Button', 'android/widget/EditText', 'org/vinix/bootstrap/TextSizeCompoundButton', 'android/widget/CheckBox', 'android/widget/RadioButton'] {
  subclasses += 'new-instance v0, L${name};\ninvoke-direct {v0, p0}, L${name};-><init>(Landroid/content/Context;)V\nconst v1, 0x40f00000\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setTextSize(F)V\n' +
   text_size_pixels('v0', '0x41b40000', 'text-size subclass SP ' + name) +
   'const/4 v1, 1\nconst v2, 0x40f00000\ninvoke-virtual {v0, v1, v2}, Landroid/widget/TextView;->setTextSize(IF)V\n' +
   text_size_pixels('v0', '0x41700000', 'text-size subclass DP ' + name)
 }
 source += method('private static subclasses(Landroid/content/Context;)V', subclasses + text_size_mark('SUBCLASSES-PASS') + 'return-void')
 source += method('private static xml(Landroid/content/Context;Ljava/lang/String;F)V', '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
const-string v1, "layout"
const-string v2, "org.vinix.bootstrap"
invoke-virtual {v0, p1, v1, v2}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
if-eqz v1, :bad
invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getLayout(I)Landroid/content/res/XmlResourceParser;
move-result-object v0
:next
invoke-interface {v0}, Lorg/xmlpull/v1/XmlPullParser;->next()I
move-result v1
const/4 v2, 1
if-eq v1, v2, :bad
const/4 v2, 2
if-ne v1, v2, :next
invoke-static {v0}, Landroid/util/Xml;->asAttributeSet(Lorg/xmlpull/v1/XmlPullParser;)Landroid/util/AttributeSet;
move-result-object v1
new-instance v2, ${tracking}
invoke-direct {v2, p0, v1}, ${tracking}-><init>(Landroid/content/Context;Landroid/util/AttributeSet;)V
invoke-interface {v0}, Landroid/content/res/XmlResourceParser;->close()V
invoke-static {v2, p2, p1}, ${c}->pixels(Landroid/widget/TextView;FLjava/lang/String;)V
iget v0, v2, ${tracking}->calls:I
if-nez v0, :bad
return-void
:bad
const-string v0, "text-size XML dimension or constructor dispatch"
invoke-static {v0}, ${c}->fail(Ljava/lang/String;)V
return-void')
 source += method('public static check(Landroid/content/Context;)V', text_size_mark('BEGIN') + '
new-instance v0, ${context}
invoke-direct {v0, p0}, ${context}-><init>(Landroid/content/Context;)V
invoke-virtual {v0}, Landroid/content/Context;->getTheme()Landroid/content/res/Resources$Theme;
move-result-object v1
invoke-virtual {v1}, Landroid/content/res/Resources$Theme;->getResources()Landroid/content/res/Resources;
move-result-object v1
invoke-virtual {v0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v2
if-ne v1, v2, :bad
new-instance v1, ${tracking}
invoke-direct {v1, v0}, ${tracking}-><init>(Landroid/content/Context;)V
const/4 v2, 0
iput v2, v1, ${tracking}->calls:I
const v2, 0x40f00000
invoke-virtual {v1, v2}, Landroid/widget/TextView;->setTextSize(F)V
' + text_size_pixels('v1', '0x41b40000', 'text-size SP readback') + '
iget v2, v1, ${tracking}->calls:I
const/4 v3, 1
if-ne v2, v3, :bad
iget v2, v1, ${tracking}->unit:I
const/4 v3, 2
if-ne v2, v3, :bad
iget v2, v1, ${tracking}->argument:F
const v3, 0x40f00000
const-string v4, "text-size F virtual IF argument"
invoke-static {v2, v3, v4}, ${c}->expect(FFLjava/lang/String;)V
' + text_size_mark('SP-PASS') + '
invoke-static {v1}, ${c}->units(Landroid/widget/TextView;)V
const-string v2, "WWWWWWWW"
invoke-virtual {v1, v2}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
const/4 v2, 0
invoke-virtual {v1, v2, v2, v2, v2}, Landroid/view/View;->setPadding(IIII)V
invoke-static {v1, v2}, ${c}->nativeCycle(${tracking}Z)V
' + text_size_mark('NATIVE-LAYOUT-PASS') + '
const/4 v2, 1
invoke-static {v1, v2}, ${c}->nativeCycle(${tracking}Z)V
' + text_size_mark('PAINT-MUTATION-PASS') + '
invoke-static {v0}, ${c}->subclasses(Landroid/content/Context;)V
const-string v1, "text_size_direct"
const/high16 v2, 0x42100000
invoke-static {v0, v1, v2}, ${c}->xml(Landroid/content/Context;Ljava/lang/String;F)V
const-string v1, "text_size_appearance"
invoke-static {v0, v1, v2}, ${c}->xml(Landroid/content/Context;Ljava/lang/String;F)V
const-string v1, "text_size_override"
invoke-static {v0, v1, v2}, ${c}->xml(Landroid/content/Context;Ljava/lang/String;F)V
' + text_size_mark('XML-PASS') + text_size_mark('PASS') + '
return-void
:bad
const-string v0, "text-size context or F virtual IF dispatch"
invoke-static {v0}, ${c}->fail(Ljava/lang/String;)V
return-void')
 os.write_file(dir + '/TextSizeProbe.smali', source)!
}
