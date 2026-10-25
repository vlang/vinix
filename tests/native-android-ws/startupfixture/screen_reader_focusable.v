// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn screen_reader_mark(name string) string {
 return 'sget-object v8, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v9, "SCREEN-READER-FOCUSABLE-' + name + '"\ninvoke-virtual {v8, v9}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn screen_reader_expect(receiver string, expected int, label string) string {
 return 'const/4 v7, ' + expected.str() + '\nconst-string v9, "' + label + '"\ninvoke-static {' + receiver + ', v7, v9}, Lorg/vinix/bootstrap/ScreenReaderFocusableProbe;->expect(Landroid/view/View;ZLjava/lang/String;)V\n'
}

fn screen_reader_constructor(context string, attrs string, def_attr string, def_res string, expected int, calls int, label string) string {
 return 'new-instance v6, Lorg/vinix/bootstrap/ScreenReaderFocusableView;\ninvoke-direct {v6, ' + context + ', ' + attrs + ', ' + def_attr + ', ' + def_res + '}, Lorg/vinix/bootstrap/ScreenReaderFocusableView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\n' +
  screen_reader_expect('v6', expected, label) + 'iget v7, v6, Lorg/vinix/bootstrap/ScreenReaderFocusableView;->calls:I\nconst/4 v8, ' + calls.str() + '\nif-ne v7, v8, :bad\n'
}

fn screen_reader_resource(name string, kind string, destination string) string {
 return 'const-string v7, "' + name + '"\nconst-string v8, "' + kind + '"\ninvoke-static {p0, v7, v8}, Lorg/vinix/bootstrap/ScreenReaderFocusableProbe;->resource(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)I\nmove-result ' + destination + '\n'
}

pub fn install_screen_reader_focusable_probe(root string) ! {
 owner := 'Lorg/vinix/bootstrap/ScreenReaderFocusableProbe;'
 tracking := 'Lorg/vinix/bootstrap/ScreenReaderFocusableView;'
 // Isolate the initial setter from getter, attr and subclass references.
 os.write_file(root + '/ScreenReaderFocusableEntry.smali', '.class public Lorg/vinix/bootstrap/ScreenReaderFocusableEntry;\n.super Ljava/lang/Object;\n' +
  method('public static check(Landroid/content/Context;)V', screen_reader_mark('BEGIN') + '
new-instance v0, Landroid/view/View;
invoke-direct {v0, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/view/View;->setScreenReaderFocusable(Z)V
' + screen_reader_mark('SETTER-PASS') + '
invoke-static {p0, v0}, ' + owner + '->check(Landroid/content/Context;Landroid/view/View;)V
return-void'))!
 os.write_file(root + '/ScreenReaderFocusableView.smali', '.class public ' + tracking + '\n.super Landroid/view/View;\n.field public calls:I\n' +
  method('public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V', '
invoke-direct {p0, p1, p2, p3, p4}, Landroid/view/View;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V
return-void') + method('public setScreenReaderFocusable(Z)V', '
iget v0, p0, ' + tracking + '->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ' + tracking + '->calls:I
invoke-super {p0, p1}, Landroid/view/View;->setScreenReaderFocusable(Z)V
return-void'))!
 mut source := '.class public ' + owner + '\n.super Ljava/lang/Object;\n' + method('private static fail(Ljava/lang/String;)V', '
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') + method('private static expect(Landroid/view/View;ZLjava/lang/String;)V', '
invoke-virtual {p0}, Landroid/view/View;->isScreenReaderFocusable()Z
move-result v0
if-eq v0, p1, :ok
invoke-static {p2}, ' + owner + '->fail(Ljava/lang/String;)V
:ok
return-void') + method('private static resource(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)I', '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
const-string v1, "org.vinix.bootstrap"
invoke-virtual {v0, p1, p2, v1}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v0
if-nez v0, :ok
const-string v1, "screen reader resource lookup"
invoke-static {v1}, ' + owner + '->fail(Ljava/lang/String;)V
:ok
return v0')
 mut state := screen_reader_expect('p1', 1, 'first setter true')
 for count in 1 .. 5 {
  args := ['Landroid/content/Context;', 'Landroid/util/AttributeSet;', 'I', 'I'][..count].join('')
  registers := ['v0', 'p0', 'v1', 'v2', 'v2'][..count + 1].join(', ')
  state += 'new-instance v0, Landroid/view/View;\nconst/4 v1, 0\nconst/4 v2, 0\ninvoke-direct {' + registers + '}, Landroid/view/View;-><init>(' + args + ')V\n' +
   screen_reader_expect('v0', 0, 'constructor default false')
 }
 state += screen_reader_mark('DEFAULT-PASS')
 for value in [1, 1, 0, 0, 1, 0] {
  state += 'const/4 v1, ' + value.str() + '\ninvoke-virtual {p1, v1}, Landroid/view/View;->setScreenReaderFocusable(Z)V\n' + screen_reader_expect('p1', value, 'toggle and repeat')
 }
 state += screen_reader_mark('STATE-PASS') + '
new-instance v3, Landroid/view/View;
invoke-direct {v3, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
const/4 v1, 0
invoke-virtual {v3, v1}, Landroid/view/View;->setFocusable(Z)V
invoke-virtual {v3}, Landroid/view/View;->isFocusable()Z
move-result v4
if-nez v4, :bad
const/4 v1, 1
invoke-virtual {v3, v1}, Landroid/view/View;->setScreenReaderFocusable(Z)V
invoke-virtual {v3}, Landroid/view/View;->isFocusable()Z
move-result v5
if-ne v4, v5, :bad
' + screen_reader_expect('v3', 1, 'screen reader true while keyboard false') + '
const/4 v1, 1
invoke-virtual {v3, v1}, Landroid/view/View;->setFocusable(Z)V
invoke-virtual {v3}, Landroid/view/View;->isFocusable()Z
move-result v4
if-eqz v4, :bad
const/4 v1, 0
invoke-virtual {v3, v1}, Landroid/view/View;->setScreenReaderFocusable(Z)V
invoke-virtual {v3}, Landroid/view/View;->isFocusable()Z
move-result v5
if-ne v4, v5, :bad
' + screen_reader_expect('v3', 0, 'screen reader false while keyboard true') + screen_reader_mark('KEYBOARD-PASS') + '
new-instance v0, Landroid/view/View;
invoke-direct {v0, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/view/View;->setScreenReaderFocusable(Z)V
' + screen_reader_expect('p1', 0, 'second view does not affect first') + '
new-instance v2, Landroid/view/View;
invoke-direct {v2, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
' + screen_reader_expect('v2', 0, 'new view while another true') + '
const/4 v1, 1
invoke-virtual {p1, v1}, Landroid/view/View;->setScreenReaderFocusable(Z)V
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/view/View;->setScreenReaderFocusable(Z)V
' + screen_reader_expect('p1', 1, 'reset another view independently') + screen_reader_expect('v2', 0, 'third view remains false') + screen_reader_mark('INDEPENDENT-PASS') + '
return-void
:bad
const-string v0, "screen reader and keyboard focus independence"
invoke-static {v0}, ' + owner + '->fail(Ljava/lang/String;)V
return-void'
 source += method('private static state(Landroid/content/Context;Landroid/view/View;)V', state)
 source += method('private static xml(Landroid/content/Context;Ljava/lang/String;ZI)V', '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
const-string v1, "xml"
invoke-static {p0, p1, v1}, ' + owner + '->resource(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getXml(I)Landroid/content/res/XmlResourceParser;
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
const/4 v2, 0
new-instance v6, ' + tracking + '
invoke-direct {v6, p0, v1, v2, v2}, ' + tracking + '-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V
invoke-interface {v0}, Landroid/content/res/XmlResourceParser;->close()V
invoke-static {v6, p2, p1}, ' + owner + '->expect(Landroid/view/View;ZLjava/lang/String;)V
iget v1, v6, ' + tracking + '->calls:I
if-ne v1, p3, :bad
return-void
:bad
const-string v1, "screen reader XML value or constructor virtual dispatch"
invoke-static {v1}, ' + owner + '->fail(Ljava/lang/String;)V
return-void')
 mut xml := 'sget v0, Landroid/R$attr;->screenReaderFocusable:I\nconst v1, 0x01010574\nif-ne v0, v1, :bad\n'
 for row in [['absent', '0', '0'], ['literal_true', '1', '1'], ['literal_false', '0', '1'],
  ['resource_true', '1', '1'], ['resource_false', '0', '1'], ['styled_true', '1', '1'], ['styled_false', '0', '1']] {
  xml += 'const-string v0, "reader_' + row[0] + '"\nconst/4 v1, ' + row[1] + '\nconst/4 v2, ' + row[2] + '\ninvoke-static {p0, v0, v1, v2}, ' + owner + '->xml(Landroid/content/Context;Ljava/lang/String;ZI)V\n'
 }
 xml += screen_reader_mark('XML-PASS') + 'return-void\n:bad\nconst-string v0, "screen reader public attribute ID"\ninvoke-static {v0}, ' + owner + '->fail(Ljava/lang/String;)V\nreturn-void'
 source += method('private static xmlChecks(Landroid/content/Context;)V', xml)
 mut styles := 'const/4 v0, 0\nconst/4 v1, 0\nconst/4 v2, 0\n' +
  screen_reader_constructor('p0', 'v0', 'v1', 'v2', 0, 0, 'absent attr skips constructor override') +
  screen_reader_resource('ReaderTrue', 'style', 'v2') +
  screen_reader_constructor('p0', 'v0', 'v1', 'v2', 1, 1, 'defStyleRes true invokes override once') +
  screen_reader_resource('ReaderFalse', 'style', 'v2') +
  screen_reader_constructor('p0', 'v0', 'v1', 'v2', 0, 1, 'defStyleRes false invokes override once') +
  screen_reader_resource('ReaderTheme', 'style', 'v4') + '
new-instance v3, Landroid/view/ContextThemeWrapper;
invoke-direct {v3, p0, v4}, Landroid/view/ContextThemeWrapper;-><init>(Landroid/content/Context;I)V
' + screen_reader_resource('readerStyle', 'attr', 'v1') +
  screen_reader_constructor('v3', 'v0', 'v1', 'v2', 1, 1, 'theme defStyleAttr takes precedence over defStyleRes') + '
const/4 v1, 0
const/4 v2, 0
' + screen_reader_constructor('v3', 'v0', 'v1', 'v2', 0, 1, 'direct theme false is present') + '
const-string v0, "reader_literal_true"
const/4 v1, 1
invoke-static {v3, v0, v1, v1}, ' + owner + '->xml(Landroid/content/Context;Ljava/lang/String;ZI)V
' + screen_reader_resource('ReaderTrueTheme', 'style', 'v4') + '
new-instance v3, Landroid/view/ContextThemeWrapper;
invoke-direct {v3, p0, v4}, Landroid/view/ContextThemeWrapper;-><init>(Landroid/content/Context;I)V
const-string v0, "reader_literal_false"
const/4 v1, 0
const/4 v2, 1
invoke-static {v3, v0, v1, v2}, ' + owner + '->xml(Landroid/content/Context;Ljava/lang/String;ZI)V
const-string v0, "reader_absent"
const/4 v1, 1
invoke-static {v3, v0, v1, v1}, ' + owner + '->xml(Landroid/content/Context;Ljava/lang/String;ZI)V
' + screen_reader_mark('STYLE-PASS') + '
return-void
:bad
const-string v0, "screen reader style or constructor virtual dispatch"
invoke-static {v0}, ' + owner + '->fail(Ljava/lang/String;)V
return-void'
 source += method('private static styles(Landroid/content/Context;)V', styles) +
  method('public static check(Landroid/content/Context;Landroid/view/View;)V', '
invoke-static {p0, p1}, ' + owner + '->state(Landroid/content/Context;Landroid/view/View;)V
invoke-static {p0}, ' + owner + '->xmlChecks(Landroid/content/Context;)V
invoke-static {p0}, ' + owner + '->styles(Landroid/content/Context;)V
' + screen_reader_mark('PASS') + 'return-void')
 os.write_file(root + '/ScreenReaderFocusableProbe.smali', source)!
}
