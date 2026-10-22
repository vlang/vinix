// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_stream_probe(dir string) ! {
 os.write_file(dir + '/StreamProbe.smali', '.class public Lorg/vinix/bootstrap/StreamProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check(Landroid/content/Context;)V', '
invoke-virtual {p0}, Landroid/content/Context;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
const-string v1, "probe.txt"
const-string v2, "VINIX-ASSET-OK"
invoke-virtual {v2}, Ljava/lang/String;->getBytes()[B
move-result-object v2
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/StreamProbe;->stream(Landroid/content/res/AssetManager;Ljava/lang/String;[B)V
const-string v1, "compressed.bin"
const-string v2, "compressed descriptor probe"
invoke-virtual {v2}, Ljava/lang/String;->getBytes()[B
move-result-object v2
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/StreamProbe;->stream(Landroid/content/res/AssetManager;Ljava/lang/String;[B)V
const-string v1, "stream.xml"
invoke-virtual {v0, v1}, Landroid/content/res/AssetManager;->open(Ljava/lang/String;)Ljava/io/InputStream;
move-result-object v0
invoke-static {}, Landroid/util/Xml;->newPullParser()Lorg/xmlpull/v1/XmlPullParser;
move-result-object v1
const/4 v2, 0
invoke-interface {v1, v0, v2}, Lorg/xmlpull/v1/XmlPullParser;->setInput(Ljava/io/InputStream;Ljava/lang/String;)V
invoke-interface {v1}, Lorg/xmlpull/v1/XmlPullParser;->nextTag()I
move-result v2
const/4 v3, 2
if-ne v2, v3, :bad
invoke-interface {v1}, Lorg/xmlpull/v1/XmlPullParser;->getName()Ljava/lang/String;
move-result-object v2
const-string v3, "stream"
invoke-virtual {v3, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-interface {v1}, Lorg/xmlpull/v1/XmlPullParser;->nextText()Ljava/lang/String;
move-result-object v2
const-string v3, "asset reset"
invoke-virtual {v3, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-interface {v1}, Lorg/xmlpull/v1/XmlPullParser;->next()I
move-result v2
const/4 v3, 1
if-ne v2, v3, :bad
invoke-virtual {v0}, Ljava/io/InputStream;->close()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-ASSET-STREAM-PASS stored compressed mark reset relative-skip bounded-eof xml"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "APK XML asset stream"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static stream(Landroid/content/res/AssetManager;Ljava/lang/String;[B)V', '
invoke-virtual {p0, p1}, Landroid/content/res/AssetManager;->open(Ljava/lang/String;)Ljava/io/InputStream;
move-result-object v0
invoke-virtual {v0}, Ljava/io/InputStream;->markSupported()Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v0}, Ljava/io/InputStream;->available()I
move-result v8
const/16 v1, 32
invoke-virtual {v0, v1}, Ljava/io/InputStream;->mark(I)V
invoke-virtual {v0}, Ljava/io/InputStream;->read()I
invoke-virtual {v0}, Ljava/io/InputStream;->reset()V
invoke-virtual {v0}, Ljava/io/InputStream;->read()I
move-result v2
const/4 v3, 0
aget-byte v3, p2, v3
if-ne v2, v3, :bad
invoke-virtual {v0, v1}, Ljava/io/InputStream;->mark(I)V
invoke-virtual {v0}, Ljava/io/InputStream;->read()I
invoke-virtual {v0}, Ljava/io/InputStream;->reset()V
invoke-virtual {v0}, Ljava/io/InputStream;->read()I
move-result v2
const/4 v3, 1
aget-byte v3, p2, v3
if-ne v2, v3, :bad
const-wide/16 v4, -7
invoke-virtual {v0, v4, v5}, Ljava/io/InputStream;->skip(J)J
move-result-wide v6
const-wide/16 v4, 0
cmp-long v2, v4, v6
if-nez v2, :bad
const-wide/16 v4, 2
invoke-virtual {v0, v4, v5}, Ljava/io/InputStream;->skip(J)J
move-result-wide v6
cmp-long v2, v4, v6
if-nez v2, :bad
invoke-virtual {v0}, Ljava/io/InputStream;->read()I
move-result v2
const/4 v3, 4
aget-byte v3, p2, v3
if-ne v2, v3, :bad
invoke-virtual {v0}, Ljava/io/InputStream;->available()I
move-result v2
add-int/lit8 v8, v8, -5
if-ne v2, v8, :bad
const-wide v4, 0x7fffffffffffffffL
invoke-virtual {v0, v4, v5}, Ljava/io/InputStream;->skip(J)J
move-result-wide v6
int-to-long v4, v8
cmp-long v2, v4, v6
if-nez v2, :bad
invoke-virtual {v0}, Ljava/io/InputStream;->read()I
move-result v2
const/4 v3, -1
if-ne v2, v3, :bad
invoke-virtual {v0}, Ljava/io/InputStream;->reset()V
invoke-virtual {v0}, Ljava/io/InputStream;->read()I
move-result v2
const/4 v3, 1
aget-byte v3, p2, v3
if-ne v2, v3, :bad
invoke-virtual {v0}, Ljava/io/InputStream;->close()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
