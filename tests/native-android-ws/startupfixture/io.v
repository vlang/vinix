// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_io_probe(dir string) ! {
 install_stream_probe(dir)!
 os.write_file(dir + '/TrafficWorker.smali', '.class public Lorg/vinix/bootstrap/TrafficWorker;\n.super Ljava/lang/Thread;\n.field public passed:Z\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Thread;-><init>()V\nreturn-void') +
  method('public run()V', '
invoke-static {}, Landroid/net/TrafficStats;->getThreadStatsTag()I
move-result v0
const/4 v1, -1
if-ne v0, v1, :done
const/16 v0, 77
invoke-static {v0}, Landroid/net/TrafficStats;->setThreadStatsTag(I)V
invoke-static {}, Landroid/net/TrafficStats;->getThreadStatsTag()I
move-result v1
if-ne v0, v1, :done
const/4 v0, 1
iput-boolean v0, p0, Lorg/vinix/bootstrap/TrafficWorker;->passed:Z
:done
return-void'))!
 os.write_file(dir + '/IoProbe.smali', '.class public Lorg/vinix/bootstrap/IoProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check(Landroid/content/Context;)V', '
invoke-static {p0}, Lorg/vinix/bootstrap/IoProbe;->atomic(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/IoProbe;->assetDescriptors(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/StreamProbe;->check(Landroid/content/Context;)V
invoke-static {}, Lorg/vinix/bootstrap/IoProbe;->traffic()V
return-void') +
  method('private static assetDescriptors(Landroid/content/Context;)V', '
invoke-virtual {p0}, Landroid/content/Context;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
const-string v1, "probe.txt"
invoke-virtual {v0, v1}, Landroid/content/res/AssetManager;->openFd(Ljava/lang/String;)Landroid/content/res/AssetFileDescriptor;
move-result-object v2
invoke-virtual {v2}, Landroid/content/res/AssetFileDescriptor;->getLength()J
move-result-wide v3
const-wide/16 v5, 15
cmp-long v3, v3, v5
if-nez v3, :bad
invoke-virtual {v2}, Landroid/content/res/AssetFileDescriptor;->getStartOffset()J
move-result-wide v3
const-wide/16 v5, 0
cmp-long v3, v3, v5
if-lez v3, :bad
invoke-virtual {v0, v1}, Landroid/content/res/AssetManager;->openFd(Ljava/lang/String;)Landroid/content/res/AssetFileDescriptor;
move-result-object v3
invoke-virtual {v2}, Landroid/content/res/AssetFileDescriptor;->close()V
invoke-virtual {v3}, Landroid/content/res/AssetFileDescriptor;->createInputStream()Ljava/io/FileInputStream;
move-result-object v2
const/16 v3, 32
new-array v3, v3, [B
invoke-virtual {v2, v3}, Ljava/io/FileInputStream;->read([B)I
move-result v4
const/16 v5, 15
if-ne v4, v5, :bad
new-instance v5, Ljava/lang/String;
const/4 v6, 0
const-string v7, "UTF-8"
invoke-direct {v5, v3, v6, v4, v7}, Ljava/lang/String;-><init>([BIILjava/lang/String;)V
const-string v3, "VINIX-ASSET-OK\\n"
invoke-virtual {v5, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v2}, Ljava/io/FileInputStream;->read()I
move-result v3
const/4 v4, -1
if-ne v3, v4, :bad
invoke-virtual {v2}, Ljava/io/FileInputStream;->close()V
:missing_start
const-string v1, "absent-file.bin"
invoke-virtual {v0, v1}, Landroid/content/res/AssetManager;->openFd(Ljava/lang/String;)Landroid/content/res/AssetFileDescriptor;
:missing_end
.catch Ljava/io/FileNotFoundException; {:missing_start .. :missing_end} :missing_ok
goto :bad
:missing_ok
move-exception v1
:compressed_start
const-string v1, "compressed.bin"
invoke-virtual {v0, v1}, Landroid/content/res/AssetManager;->openFd(Ljava/lang/String;)Landroid/content/res/AssetFileDescriptor;
:compressed_end
.catch Ljava/io/FileNotFoundException; {:compressed_start .. :compressed_end} :compressed_ok
goto :bad
:compressed_ok
move-exception v1
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-ASSET-FD-PASS offset length independent-close bounded-read compressed missing"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "APK asset file descriptors"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static traffic()V', '
invoke-static {}, Landroid/net/TrafficStats;->clearThreadStatsTag()V
invoke-static {}, Landroid/net/TrafficStats;->getThreadStatsTag()I
move-result v0
const/4 v1, -1
if-ne v0, v1, :bad
const/16 v0, 42
invoke-static {v0}, Landroid/net/TrafficStats;->setThreadStatsTag(I)V
new-instance v2, Lorg/vinix/bootstrap/TrafficWorker;
invoke-direct {v2}, Lorg/vinix/bootstrap/TrafficWorker;-><init>()V
invoke-virtual {v2}, Ljava/lang/Thread;->start()V
invoke-virtual {v2}, Ljava/lang/Thread;->join()V
iget-boolean v2, v2, Lorg/vinix/bootstrap/TrafficWorker;->passed:Z
if-eqz v2, :bad
invoke-static {}, Landroid/net/TrafficStats;->getThreadStatsTag()I
move-result v2
if-ne v0, v2, :bad
invoke-static {}, Landroid/net/TrafficStats;->clearThreadStatsTag()V
invoke-static {}, Landroid/net/TrafficStats;->clearThreadStatsUid()V
invoke-static {}, Landroid/net/TrafficStats;->getThreadStatsTag()I
move-result v0
if-ne v0, v1, :bad
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v0
const-wide/16 v4, -1
invoke-static {v0}, Landroid/net/TrafficStats;->getUidRxBytes(I)J
move-result-wide v2
cmp-long v6, v2, v4
if-nez v6, :bad
invoke-static {v0}, Landroid/net/TrafficStats;->getUidTxBytes(I)J
move-result-wide v2
cmp-long v6, v2, v4
if-nez v6, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TRAFFIC-PASS thread-isolation clear unsupported-counters"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "traffic tags or unsupported counters"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static atomic(Landroid/content/Context;)V', '
invoke-virtual {p0}, Landroid/content/Context;->getCacheDir()Ljava/io/File;
move-result-object v0
new-instance v1, Ljava/io/File;
const-string v2, "atomic-probe/nested/state"
invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v0, Landroid/util/AtomicFile;
invoke-direct {v0, v1}, Landroid/util/AtomicFile;-><init>(Ljava/io/File;)V
invoke-virtual {v0}, Landroid/util/AtomicFile;->delete()V
invoke-virtual {v0}, Landroid/util/AtomicFile;->getBaseFile()Ljava/io/File;
move-result-object v2
if-ne v1, v2, :bad
invoke-virtual {v0}, Landroid/util/AtomicFile;->startWrite()Ljava/io/FileOutputStream;
move-result-object v2
const/16 v3, 17
invoke-virtual {v2, v3}, Ljava/io/FileOutputStream;->write(I)V
invoke-virtual {v0, v2}, Landroid/util/AtomicFile;->finishWrite(Ljava/io/FileOutputStream;)V
invoke-virtual {v0}, Landroid/util/AtomicFile;->startWrite()Ljava/io/FileOutputStream;
move-result-object v2
const/16 v4, 18
invoke-virtual {v2, v4}, Ljava/io/FileOutputStream;->write(I)V
invoke-virtual {v0, v2}, Landroid/util/AtomicFile;->failWrite(Ljava/io/FileOutputStream;)V
invoke-virtual {v0}, Landroid/util/AtomicFile;->readFully()[B
move-result-object v2
const/4 v4, 0
aget-byte v2, v2, v4
if-ne v2, v3, :bad
invoke-virtual {v0}, Landroid/util/AtomicFile;->startWrite()Ljava/io/FileOutputStream;
move-result-object v2
const/16 v5, 19
invoke-virtual {v2, v5}, Ljava/io/FileOutputStream;->write(I)V
invoke-virtual {v2}, Ljava/io/FileOutputStream;->close()V
new-instance v0, Landroid/util/AtomicFile;
invoke-direct {v0, v1}, Landroid/util/AtomicFile;-><init>(Ljava/io/File;)V
invoke-virtual {v0}, Landroid/util/AtomicFile;->openRead()Ljava/io/FileInputStream;
move-result-object v2
invoke-virtual {v2}, Ljava/io/FileInputStream;->read()I
move-result v5
invoke-virtual {v2}, Ljava/io/FileInputStream;->close()V
if-ne v5, v3, :bad
invoke-virtual {v1}, Ljava/io/File;->getPath()Ljava/lang/String;
move-result-object v5
const-string v6, ".bak"
invoke-virtual {v5, v6}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v5
new-instance v6, Ljava/io/File;
invoke-direct {v6, v5}, Ljava/io/File;-><init>(Ljava/lang/String;)V
invoke-virtual {v1, v6}, Ljava/io/File;->renameTo(Ljava/io/File;)Z
move-result v5
if-eqz v5, :bad
new-instance v2, Ljava/io/FileOutputStream;
invoke-direct {v2, v1}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
const/16 v5, 20
invoke-virtual {v2, v5}, Ljava/io/FileOutputStream;->write(I)V
invoke-virtual {v2}, Ljava/io/FileOutputStream;->close()V
invoke-virtual {v0}, Landroid/util/AtomicFile;->readFully()[B
move-result-object v2
aget-byte v2, v2, v4
if-ne v2, v3, :bad
const/16 v5, 8193
new-array v6, v5, [B
aput-byte v3, v6, v4
const/16 v7, 8192
aput-byte v3, v6, v7
invoke-virtual {v0}, Landroid/util/AtomicFile;->startWrite()Ljava/io/FileOutputStream;
move-result-object v2
invoke-virtual {v2, v6}, Ljava/io/FileOutputStream;->write([B)V
invoke-virtual {v0, v2}, Landroid/util/AtomicFile;->finishWrite(Ljava/io/FileOutputStream;)V
invoke-virtual {v0}, Landroid/util/AtomicFile;->readFully()[B
move-result-object v2
array-length v6, v2
if-ne v6, v5, :bad
aget-byte v6, v2, v4
if-ne v6, v3, :bad
aget-byte v6, v2, v7
if-ne v6, v3, :bad
invoke-virtual {v0}, Landroid/util/AtomicFile;->delete()V
invoke-virtual {v1}, Ljava/io/File;->exists()Z
move-result v1
if-nez v1, :bad
:missing
invoke-virtual {v0}, Landroid/util/AtomicFile;->openRead()Ljava/io/FileInputStream;
:missing_end
.catch Ljava/io/FileNotFoundException; {:missing .. :missing_end} :missing_ok
goto :bad
:missing_ok
move-exception v0
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-ATOMIC-FILE-PASS commit rollback interrupted-write legacy-backup large-read delete missing"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "atomic file transaction"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
