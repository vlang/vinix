// SPDX-License-Identifier: GPL-2.0-or-later
module jobimportantprobe

import os

pub fn install(root string) ! {
	os.write_file(root + '/smali/JobImportantProbe.smali', r'
.class public final Lorg/vinix/bootstrap/JobImportantProbe;
.super Ljava/lang/Object;
.method private static builder(I)Landroid/app/job/JobInfo$Builder;
.locals 3
new-instance v0, Landroid/content/ComponentName;
const-string v1, "org.vinix.bootstrap"
const-string v2, "org.vinix.bootstrap.MetadataOnlyJob"
invoke-direct {v0, v1, v2}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
new-instance v1, Landroid/app/job/JobInfo$Builder;
invoke-direct {v1, p0, v0}, Landroid/app/job/JobInfo$Builder;-><init>(ILandroid/content/ComponentName;)V
return-object v1
.end method
.method private static flag(Landroid/app/job/JobInfo;Z)V
.locals 1
invoke-virtual {p0}, Landroid/app/job/JobInfo;->isImportantWhileForeground()Z
move-result v0
invoke-static {v0, p1}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method private static rejected(Landroid/app/job/JobInfo$Builder;)V
.locals 1
:begin
invoke-virtual {p0}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
:end
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.catch Ljava/lang/IllegalArgumentException; {:begin .. :end} :caught
:caught
move-exception v0
return-void
.end method
.method public static check()V
.locals 8
const/4 v4, 0
const/4 v5, 1
const/16 v6, 73
invoke-static {v6}, Lorg/vinix/bootstrap/JobImportantProbe;->builder(I)Landroid/app/job/JobInfo$Builder;
move-result-object v0
invoke-virtual {v0}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v1
invoke-static {v1, v4}, Lorg/vinix/bootstrap/JobImportantProbe;->flag(Landroid/app/job/JobInfo;Z)V
invoke-virtual {v0, v5}, Landroid/app/job/JobInfo$Builder;->setImportantWhileForeground(Z)Landroid/app/job/JobInfo$Builder;
move-result-object v6
if-ne v6, v0, :bad
invoke-virtual {v0}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v2
invoke-virtual {v0, v4}, Landroid/app/job/JobInfo$Builder;->setImportantWhileForeground(Z)Landroid/app/job/JobInfo$Builder;
move-result-object v6
if-ne v6, v0, :bad
invoke-virtual {v0}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v3
invoke-static {v1, v4}, Lorg/vinix/bootstrap/JobImportantProbe;->flag(Landroid/app/job/JobInfo;Z)V
invoke-static {v2, v5}, Lorg/vinix/bootstrap/JobImportantProbe;->flag(Landroid/app/job/JobInfo;Z)V
invoke-static {v3, v4}, Lorg/vinix/bootstrap/JobImportantProbe;->flag(Landroid/app/job/JobInfo;Z)V
invoke-virtual {v2}, Landroid/app/job/JobInfo;->getId()I
move-result v6
const/16 v7, 73
invoke-static {v6, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Landroid/app/job/JobInfo;->getService()Landroid/content/ComponentName;
move-result-object v6
invoke-virtual {v6}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;
move-result-object v6
const-string v7, "org.vinix.bootstrap.MetadataOnlyJob"
invoke-virtual {v6, v7}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v6
invoke-static {v6, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0, v5}, Landroid/app/job/JobInfo$Builder;->setImportantWhileForeground(Z)Landroid/app/job/JobInfo$Builder;
const-wide/16 v6, 0
invoke-virtual {v0, v6, v7}, Landroid/app/job/JobInfo$Builder;->setMinimumLatency(J)Landroid/app/job/JobInfo$Builder;
invoke-static {v0}, Lorg/vinix/bootstrap/JobImportantProbe;->rejected(Landroid/app/job/JobInfo$Builder;)V
invoke-virtual {v0, v4}, Landroid/app/job/JobInfo$Builder;->setImportantWhileForeground(Z)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v0}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v3
invoke-static {v3, v4}, Lorg/vinix/bootstrap/JobImportantProbe;->flag(Landroid/app/job/JobInfo;Z)V
const-wide v6, 0x100000001L
invoke-virtual {v0, v6, v7}, Landroid/app/job/JobInfo$Builder;->setMinimumLatency(J)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v0, v5}, Landroid/app/job/JobInfo$Builder;->setImportantWhileForeground(Z)Landroid/app/job/JobInfo$Builder;
invoke-static {v0}, Lorg/vinix/bootstrap/JobImportantProbe;->rejected(Landroid/app/job/JobInfo$Builder;)V
invoke-virtual {v0, v4}, Landroid/app/job/JobInfo$Builder;->setImportantWhileForeground(Z)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v0}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v3
invoke-virtual {v3}, Landroid/app/job/JobInfo;->getMinLatencyMillis()J
move-result-wide v6
const-wide v1, 0x100000001L
cmp-long v6, v6, v1
invoke-static {v6, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/16 v6, 74
invoke-static {v6}, Lorg/vinix/bootstrap/JobImportantProbe;->builder(I)Landroid/app/job/JobInfo$Builder;
move-result-object v0
const-wide/16 v6, 0
invoke-virtual {v0, v6, v7}, Landroid/app/job/JobInfo$Builder;->setPeriodic(J)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v0, v5}, Landroid/app/job/JobInfo$Builder;->setImportantWhileForeground(Z)Landroid/app/job/JobInfo$Builder;
invoke-static {v0}, Lorg/vinix/bootstrap/JobImportantProbe;->rejected(Landroid/app/job/JobInfo$Builder;)V
invoke-virtual {v0, v4}, Landroid/app/job/JobInfo$Builder;->setImportantWhileForeground(Z)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v0}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v3
invoke-static {v3, v4}, Lorg/vinix/bootstrap/JobImportantProbe;->flag(Landroid/app/job/JobInfo;Z)V
const/16 v6, 75
invoke-static {v6}, Lorg/vinix/bootstrap/JobImportantProbe;->builder(I)Landroid/app/job/JobInfo$Builder;
move-result-object v0
const-wide v6, 0x100000001L
invoke-virtual {v0, v6, v7}, Landroid/app/job/JobInfo$Builder;->setOverrideDeadline(J)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v0, v5}, Landroid/app/job/JobInfo$Builder;->setImportantWhileForeground(Z)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v0}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v3
invoke-static {v3, v5}, Lorg/vinix/bootstrap/JobImportantProbe;->flag(Landroid/app/job/JobInfo;Z)V
invoke-virtual {v3}, Landroid/app/job/JobInfo;->getMaxExecutionDelayMillis()J
move-result-wide v6
const-wide v1, 0x100000001L
cmp-long v6, v6, v1
invoke-static {v6, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/16 v6, 76
invoke-static {v6}, Lorg/vinix/bootstrap/JobImportantProbe;->builder(I)Landroid/app/job/JobInfo$Builder;
move-result-object v0
invoke-virtual {v0}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v3
invoke-static {v3, v4}, Lorg/vinix/bootstrap/JobImportantProbe;->flag(Landroid/app/job/JobInfo;Z)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "JOB-IMPORTANT-PASS default fluent true false independent-built-metadata zero-positive-delay-rejected periodic-rejected deadline-allowed no-scheduling-grant"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "job importance metadata"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
')!
}
