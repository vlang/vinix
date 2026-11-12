// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import json2
import crypto.sha256

const subscription_source = r'
.method public static forceLayoutProbe(Landroid/content/Context;)V
.locals 6
new-instance v0, Lorg/vinix/bootstrap/TestLayoutTable;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/TestLayoutTable;-><init>(Landroid/content/Context;)V
new-instance v1, Lorg/vinix/bootstrap/TestLayoutView;
invoke-direct {v1, p0}, Lorg/vinix/bootstrap/TestLayoutView;-><init>(Landroid/content/Context;)V
invoke-virtual {v0, v1}, Landroid/widget/TableLayout;->addView(Landroid/view/View;)V
const v2, 0x40000040
invoke-virtual {v1, v2, v2}, Landroid/view/View;->measure(II)V
const/4 v3, 0
iput v3, v0, Lorg/vinix/bootstrap/TestLayoutTable;->requests:I
iput v3, v1, Lorg/vinix/bootstrap/TestLayoutView;->requests:I
invoke-virtual {v1}, Landroid/view/View;->isLayoutRequested()Z
move-result v4
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/view/View;->forceLayout()V
invoke-virtual {v1}, Landroid/view/View;->isLayoutRequested()Z
move-result v4
const/4 v5, 1
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v4, v1, Lorg/vinix/bootstrap/TestLayoutView;->requests:I
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v4, v0, Lorg/vinix/bootstrap/TestLayoutTable;->requests:I
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1, v2, v2}, Landroid/view/View;->measure(II)V
iget v4, v1, Lorg/vinix/bootstrap/TestLayoutView;->measures:I
const/4 v5, 2
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1, v2, v2}, Landroid/view/View;->measure(II)V
iget v4, v1, Lorg/vinix/bootstrap/TestLayoutView;->measures:I
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v4, Lorg/vinix/bootstrap/TestForceLayoutWorker;
invoke-direct {v4, v1}, Lorg/vinix/bootstrap/TestForceLayoutWorker;-><init>(Landroid/view/View;)V
new-instance v5, Ljava/lang/Thread;
invoke-direct {v5, v4}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v5}, Ljava/lang/Thread;->start()V
invoke-virtual {v5}, Ljava/lang/Thread;->join()V
invoke-virtual {v1}, Landroid/view/View;->isLayoutRequested()Z
move-result v4
const/4 v5, 1
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v4, v1, Lorg/vinix/bootstrap/TestLayoutView;->requests:I
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v4, v0, Lorg/vinix/bootstrap/TestLayoutTable;->requests:I
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1, v2, v2}, Landroid/view/View;->measure(II)V
invoke-virtual {v0}, Landroid/widget/TableLayout;->requestLayout()V
iget v4, v0, Lorg/vinix/bootstrap/TestLayoutTable;->requests:I
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v4, v1, Lorg/vinix/bootstrap/TestLayoutView;->requests:I
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/view/View;->isLayoutRequested()Z
move-result v4
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public static serialTlsCache(Landroid/content/Context;)V
.locals 5
:serial_start
invoke-static {}, Landroid/os/Build;->getSerial()Ljava/lang/String;
:serial_end
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:serial_denied
move-exception v0
new-instance v0, Lorg/vinix/bootstrap/TestSslContext;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/TestSslContext;-><init>(Landroid/content/Context;)V
new-instance v1, Landroid/net/SSLSessionCache;
invoke-direct {v1, v0}, Landroid/net/SSLSessionCache;-><init>(Landroid/content/Context;)V
iget v1, v0, Lorg/vinix/bootstrap/TestSslContext;->calls:I
const/4 v2, 1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget-object v1, v0, Lorg/vinix/bootstrap/TestSslContext;->directory:Ljava/io/File;
invoke-virtual {v1}, Ljava/io/File;->isDirectory()Z
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v3, "sslcache"
const/4 v4, 0
invoke-virtual {p0, v3, v4}, Landroid/content/Context;->getDir(Ljava/lang/String;I)Ljava/io/File;
move-result-object v3
invoke-virtual {v1, v3}, Ljava/io/File;->equals(Ljava/lang/Object;)Z
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
:null_cache_start
new-instance v1, Landroid/net/SSLSessionCache;
const/4 v0, 0
invoke-direct {v1, v0}, Landroid/net/SSLSessionCache;-><init>(Landroid/content/Context;)V
:null_cache_end
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:null_cache
move-exception v0
return-void
.catch Ljava/lang/SecurityException; {:serial_start .. :serial_end} :serial_denied
.catch Ljava/lang/NullPointerException; {:null_cache_start .. :null_cache_end} :null_cache
.end method
.method public static optionalStorageStats(Landroid/content/Context;)V
.locals 4
const-class v0, Landroid/app/usage/StorageStatsManager;
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/app/usage/StorageStatsManager;
invoke-static {v1}, Ljava/util/Optional;->ofNullable(Ljava/lang/Object;)Ljava/util/Optional;
move-result-object v1
invoke-virtual {v1}, Ljava/util/Optional;->isPresent()Z
move-result v1
const/4 v2, 0
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Landroid/content/Context;->STORAGE_STATS_SERVICE:Ljava/lang/String;
const-string v1, "storagestats"
invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
const/4 v3, 1
invoke-static {v1, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/app/usage/StorageStatsManager;
if-nez v0, :stats_failed
return-void
:stats_failed
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
.method public static modemIdentifiers(Landroid/content/Context;)V
.locals 5
const-string v0, "phone"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/telephony/TelephonyManager;
const/4 v2, 0
invoke-virtual {v0}, Landroid/telephony/TelephonyManager;->getPhoneCount()I
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/telephony/TelephonyManager;->getImei()Ljava/lang/String;
move-result-object v1
if-nez v1, :modem_failed
invoke-virtual {v0}, Landroid/telephony/TelephonyManager;->getMeid()Ljava/lang/String;
move-result-object v1
if-nez v1, :modem_failed
const/4 v3, -1
:slot
invoke-virtual {v0, v3}, Landroid/telephony/TelephonyManager;->getImei(I)Ljava/lang/String;
move-result-object v1
if-nez v1, :modem_failed
invoke-virtual {v0, v3}, Landroid/telephony/TelephonyManager;->getMeid(I)Ljava/lang/String;
move-result-object v1
if-nez v1, :modem_failed
add-int/lit8 v3, v3, 1
const/4 v4, 2
if-lt v3, v4, :slot
invoke-virtual {p0}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v0
const-string v1, "android.hardware.telephony"
invoke-virtual {v0, v1}, Landroid/content/pm/PackageManager;->hasSystemFeature(Ljava/lang/String;)Z
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
:modem_failed
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
.method public static scheduleProbeJob(Landroid/content/Context;)V
.locals 6
new-instance v0, Landroid/content/ComponentName;
const-string v1, "org.vinix.bootstrap"
const-string v2, "org.vinix.bootstrap.TestJobService"
invoke-direct {v0, v1, v2}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
new-instance v1, Landroid/app/job/JobInfo$Builder;
const v2, 0x1234567
invoke-direct {v1, v2, v0}, Landroid/app/job/JobInfo$Builder;-><init>(ILandroid/content/ComponentName;)V
new-instance v0, Landroid/os/PersistableBundle;
invoke-direct {v0}, Landroid/os/PersistableBundle;-><init>()V
const-string v2, "job-payload"
const/16 v3, 73
invoke-virtual {v0, v2, v3}, Landroid/os/PersistableBundle;->putInt(Ljava/lang/String;I)V
invoke-virtual {v1, v0}, Landroid/app/job/JobInfo$Builder;->setExtras(Landroid/os/PersistableBundle;)Landroid/app/job/JobInfo$Builder;
const-wide/16 v4, 30000
invoke-virtual {v1, v4, v5}, Landroid/app/job/JobInfo$Builder;->setOverrideDeadline(J)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v1}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v1
const-string v0, "jobscheduler"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/app/job/JobScheduler;
invoke-virtual {v0, v1}, Landroid/app/job/JobScheduler;->schedule(Landroid/app/job/JobInfo;)I
move-result v0
const/4 v1, 1
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget v0, Lorg/vinix/bootstrap/TestJobService;->calls:I
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public static jobInstallQueries(Landroid/content/Context;)V
.locals 8
invoke-virtual {p0}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v0
invoke-virtual {v0}, Landroid/content/pm/PackageManager;->getPackageInstaller()Landroid/content/pm/PackageInstaller;
move-result-object v0
invoke-virtual {v0}, Landroid/content/pm/PackageInstaller;->getStagedSessions()Ljava/util/List;
move-result-object v1
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v2
const/4 v3, 0
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v2, "caller-local mutation"
invoke-interface {v1, v2}, Ljava/util/List;->add(Ljava/lang/Object;)Z
invoke-virtual {v0}, Landroid/content/pm/PackageInstaller;->getStagedSessions()Ljava/util/List;
move-result-object v1
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v2
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/content/ComponentName;
const-string v1, "org.vinix.bootstrap"
const-string v2, "org.vinix.bootstrap.MetadataOnlyJob"
invoke-direct {v0, v1, v2}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
new-instance v1, Landroid/app/job/JobInfo$Builder;
const/4 v2, 1
invoke-direct {v1, v2, v0}, Landroid/app/job/JobInfo$Builder;-><init>(ILandroid/content/ComponentName;)V
invoke-virtual {v1}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v4
invoke-virtual {v4}, Landroid/app/job/JobInfo;->getMinLatencyMillis()J
move-result-wide v4
const-wide/16 v6, 0
cmp-long v3, v4, v6
const/4 v2, 0
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v0
invoke-virtual {v0}, Landroid/app/job/JobInfo;->isRequireCharging()Z
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/app/job/JobInfo;->isRequireDeviceIdle()Z
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/app/job/JobInfo;->getNetworkType()I
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/app/job/JobInfo;->getMaxExecutionDelayMillis()J
move-result-wide v4
const-wide/16 v6, 0
cmp-long v3, v4, v6
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-wide v6, 0x200000023L
invoke-virtual {v1, v6, v7}, Landroid/app/job/JobInfo$Builder;->setOverrideDeadline(J)Landroid/app/job/JobInfo$Builder;
const/4 v3, 1
invoke-virtual {v1, v3}, Landroid/app/job/JobInfo$Builder;->setRequiresCharging(Z)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v1, v3}, Landroid/app/job/JobInfo$Builder;->setRequiresDeviceIdle(Z)Landroid/app/job/JobInfo$Builder;
const/4 v3, 2
invoke-virtual {v1, v3}, Landroid/app/job/JobInfo$Builder;->setRequiredNetworkType(I)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v1}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v0
invoke-virtual {v0}, Landroid/app/job/JobInfo;->getMaxExecutionDelayMillis()J
move-result-wide v4
cmp-long v3, v4, v6
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/app/job/JobInfo;->isRequireCharging()Z
move-result v3
const/4 v2, 1
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/app/job/JobInfo;->isRequireDeviceIdle()Z
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/app/job/JobInfo;->getNetworkType()I
move-result v3
const/4 v2, 2
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v2, 0
invoke-virtual {v1, v2}, Landroid/app/job/JobInfo$Builder;->setRequiresCharging(Z)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v1, v2}, Landroid/app/job/JobInfo$Builder;->setRequiresDeviceIdle(Z)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v1, v2}, Landroid/app/job/JobInfo$Builder;->setRequiredNetworkType(I)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v1}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v0
invoke-virtual {v0}, Landroid/app/job/JobInfo;->isRequireCharging()Z
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/app/job/JobInfo;->isRequireDeviceIdle()Z
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/app/job/JobInfo;->getNetworkType()I
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-wide v6, 0x100000011L
invoke-virtual {v1, v6, v7}, Landroid/app/job/JobInfo$Builder;->setMinimumLatency(J)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v1}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v4
invoke-virtual {v4}, Landroid/app/job/JobInfo;->getMinLatencyMillis()J
move-result-wide v4
cmp-long v3, v4, v6
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/content/ComponentName;
const-string v3, "org.vinix.bootstrap"
const-string v4, "org.vinix.bootstrap.MetadataOnlyJob"
invoke-direct {v0, v3, v4}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
new-instance v1, Landroid/app/job/JobInfo$Builder;
const/4 v3, 2
invoke-direct {v1, v3, v0}, Landroid/app/job/JobInfo$Builder;-><init>(ILandroid/content/ComponentName;)V
const-wide/16 v6, 37
invoke-virtual {v1, v6, v7}, Landroid/app/job/JobInfo$Builder;->setMinimumLatency(J)Landroid/app/job/JobInfo$Builder;
invoke-virtual {v1}, Landroid/app/job/JobInfo$Builder;->build()Landroid/app/job/JobInfo;
move-result-object v0
invoke-virtual {v0}, Landroid/app/job/JobInfo;->getMinLatencyMillis()J
move-result-wide v4
cmp-long v3, v4, v6
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public static sharedLibraryCatalog(Landroid/content/Context;)V
.locals 4
invoke-virtual {p0}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v0
invoke-virtual {v0}, Landroid/content/pm/PackageManager;->getSystemSharedLibraryNames()[Ljava/lang/String;
move-result-object v1
array-length v2, v1
const/4 v3, 0
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-static {v1}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
move-result-object v1
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v2
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/content/pm/PackageManager;->getSystemSharedLibraryNames()[Ljava/lang/String;
move-result-object v1
invoke-virtual {v0}, Landroid/content/pm/PackageManager;->getSystemSharedLibraryNames()[Ljava/lang/String;
move-result-object v2
if-eq v1, v2, :catalog_failed
array-length v2, v2
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
:catalog_failed
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
.method public static storageDatabase(Landroid/content/Context;)V
.locals 8
const-string v0, "vinix-storage-probe.db"
invoke-virtual {p0, v0}, Landroid/content/Context;->getDatabasePath(Ljava/lang/String;)Ljava/io/File;
move-result-object v0
const/4 v3, 0
invoke-static {v0, v3}, Landroid/database/sqlite/SQLiteDatabase;->openOrCreateDatabase(Ljava/io/File;Landroid/database/sqlite/SQLiteDatabase$CursorFactory;)Landroid/database/sqlite/SQLiteDatabase;
move-result-object v1
const-string v2, "PRAGMA synchronous=FULL"
invoke-virtual {v1, v2}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
const-string v2, "CREATE TABLE probe(v BLOB NOT NULL)"
invoke-virtual {v1, v2}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
const-string v2, "INSERT INTO probe VALUES (zeroblob(1048576))"
invoke-virtual {v1, v2}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;)V
invoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase;->close()V
invoke-static {v0, v3}, Landroid/database/sqlite/SQLiteDatabase;->openOrCreateDatabase(Ljava/io/File;Landroid/database/sqlite/SQLiteDatabase$CursorFactory;)Landroid/database/sqlite/SQLiteDatabase;
move-result-object v1
const-string v2, "SELECT length(v) FROM probe"
invoke-virtual {v1, v2, v3}, Landroid/database/sqlite/SQLiteDatabase;->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;
move-result-object v4
invoke-interface {v4}, Landroid/database/Cursor;->moveToFirst()Z
move-result v5
const/4 v6, 1
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-interface {v4, v3}, Landroid/database/Cursor;->getInt(I)I
move-result v5
const v7, 0x100000
invoke-static {v5, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-interface {v4}, Landroid/database/Cursor;->moveToNext()Z
move-result v5
invoke-static {v5, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-interface {v4}, Landroid/database/Cursor;->close()V
invoke-virtual {v1}, Landroid/database/sqlite/SQLiteDatabase;->close()V
invoke-virtual {v0}, Ljava/io/File;->length()J
move-result-wide v1
const-wide/32 v4, 0x100000
cmp-long v7, v1, v4
if-lez v7, :storage_failed
invoke-static {v0}, Landroid/database/sqlite/SQLiteDatabase;->deleteDatabase(Ljava/io/File;)Z
move-result v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
:storage_failed
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
.method public static buildAndObserver()V
.locals 6
const-string v0, "ro.build.version.base_os"
const-string v1, ""
invoke-static {v0, v1}, Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
sget-object v1, Landroid/os/Build$VERSION;->BASE_OS:Ljava/lang/String;
invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v2, 1
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-class v0, Landroid/os/Build$VERSION;
const-string v1, "BASE_OS"
invoke-virtual {v0, v1}, Ljava/lang/Class;->getField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Field;->getModifiers()I
move-result v0
and-int/lit8 v0, v0, 0x19
const/16 v1, 0x19
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-class v0, Landroid/content/pm/IPackageDeleteObserver;
invoke-virtual {v0}, Ljava/lang/Class;->isInterface()Z
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Lorg/vinix/bootstrap/TestDeleteObserver;
invoke-direct {v0}, Lorg/vinix/bootstrap/TestDeleteObserver;-><init>()V
invoke-interface {v0}, Landroid/os/IInterface;->asBinder()Landroid/os/IBinder;
move-result-object v1
if-ne v1, v0, :observer_failed
const-string v3, "android.content.pm.IPackageDeleteObserver"
invoke-interface {v1, v3}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;
move-result-object v1
if-ne v1, v0, :observer_failed
const-string v3, "org.vinix.fixture.callback"
const/4 v4, -6
invoke-interface {v0, v3, v4}, Landroid/content/pm/IPackageDeleteObserver;->packageDeleted(Ljava/lang/String;I)V
iget v1, v0, Lorg/vinix/bootstrap/TestDeleteObserver;->calls:I
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v1, v0, Lorg/vinix/bootstrap/TestDeleteObserver;->code:I
invoke-static {v1, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget-object v1, v0, Lorg/vinix/bootstrap/TestDeleteObserver;->name:Ljava/lang/String;
invoke-virtual {v3, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-class v0, Landroid/content/pm/IPackageDataObserver;
invoke-virtual {v0}, Ljava/lang/Class;->isInterface()Z
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Lorg/vinix/bootstrap/TestDataObserver;
invoke-direct {v0}, Lorg/vinix/bootstrap/TestDataObserver;-><init>()V
invoke-interface {v0}, Landroid/os/IInterface;->asBinder()Landroid/os/IBinder;
move-result-object v1
if-ne v1, v0, :observer_failed
const-string v3, "android.content.pm.IPackageDataObserver"
invoke-interface {v1, v3}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;
move-result-object v1
if-ne v1, v0, :observer_failed
const-string v3, "org.vinix.fixture.callback"
const/4 v4, 0
invoke-interface {v0, v3, v4}, Landroid/content/pm/IPackageDataObserver;->onRemoveCompleted(Ljava/lang/String;Z)V
iget v1, v0, Lorg/vinix/bootstrap/TestDataObserver;->calls:I
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget-boolean v1, v0, Lorg/vinix/bootstrap/TestDataObserver;->success:Z
invoke-static {v1, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget-object v1, v0, Lorg/vinix/bootstrap/TestDataObserver;->name:Ljava/lang/String;
invoke-virtual {v3, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
:observer_failed
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
.method public static sandboxMetadata(Landroid/content/Context;)V
.locals 4
new-instance v0, Landroid/content/pm/ApplicationInfo;
invoke-direct {v0}, Landroid/content/pm/ApplicationInfo;-><init>()V
iget v1, v0, Landroid/content/pm/ApplicationInfo;->targetSandboxVersion:I
const/4 v2, 0
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v2, 2
iput v2, v0, Landroid/content/pm/ApplicationInfo;->targetSandboxVersion:I
new-instance v1, Landroid/content/pm/ApplicationInfo;
invoke-direct {v1, v0}, Landroid/content/pm/ApplicationInfo;-><init>(Landroid/content/pm/ApplicationInfo;)V
iget v3, v1, Landroid/content/pm/ApplicationInfo;->targetSandboxVersion:I
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v3, 1
iput v3, v1, Landroid/content/pm/ApplicationInfo;->targetSandboxVersion:I
iget v1, v0, Landroid/content/pm/ApplicationInfo;->targetSandboxVersion:I
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v0
iget v1, v0, Landroid/content/pm/ApplicationInfo;->targetSandboxVersion:I
invoke-static {v1, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "sandbox/literal.apk"
invoke-static {p0, v0, v2}, Lorg/vinix/bootstrap/Main;->sandboxArchive(Landroid/content/Context;Ljava/lang/String;I)V
const-string v0, "sandbox/resource.apk"
invoke-static {p0, v0, v2}, Lorg/vinix/bootstrap/Main;->sandboxArchive(Landroid/content/Context;Ljava/lang/String;I)V
return-void
.end method
.method public static sandboxArchive(Landroid/content/Context;Ljava/lang/String;I)V
.locals 8
invoke-virtual {p0}, Landroid/content/Context;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
invoke-virtual {v0, p1}, Landroid/content/res/AssetManager;->open(Ljava/lang/String;)Ljava/io/InputStream;
move-result-object v0
invoke-virtual {p0}, Landroid/content/Context;->getCacheDir()Ljava/io/File;
move-result-object v1
new-instance v2, Ljava/io/File;
const/16 v3, 0x2f
const/16 v4, 0x5f
invoke-virtual {p1, v3, v4}, Ljava/lang/String;->replace(CC)Ljava/lang/String;
move-result-object v3
invoke-direct {v2, v1, v3}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v1, Ljava/io/FileOutputStream;
invoke-direct {v1, v2}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
const/16 v4, 0x1000
new-array v4, v4, [B
:copy_start
:copy_loop
invoke-virtual {v0, v4}, Ljava/io/InputStream;->read([B)I
move-result v5
if-ltz v5, :copy_done
const/4 v6, 0
invoke-virtual {v1, v4, v6, v5}, Ljava/io/FileOutputStream;->write([BII)V
goto :copy_loop
:copy_done
:copy_end
invoke-virtual {v1}, Ljava/io/FileOutputStream;->close()V
invoke-virtual {v0}, Ljava/io/InputStream;->close()V
invoke-virtual {v2}, Ljava/io/File;->getPath()Ljava/lang/String;
move-result-object v3
new-instance v0, Landroid/content/pm/PackageParser;
invoke-direct {v0, v3}, Landroid/content/pm/PackageParser;-><init>(Ljava/lang/String;)V
new-instance v4, Landroid/util/DisplayMetrics;
invoke-direct {v4}, Landroid/util/DisplayMetrics;-><init>()V
invoke-virtual {v4}, Landroid/util/DisplayMetrics;->setToDefaults()V
const/4 v5, 0
invoke-virtual {v0, v2, v3, v4, v5}, Landroid/content/pm/PackageParser;->parsePackage(Ljava/io/File;Ljava/lang/String;Landroid/util/DisplayMetrics;I)Landroid/content/pm/PackageParser$Package;
move-result-object v0
iget-object v0, v0, Landroid/content/pm/PackageParser$Package;->applicationInfo:Landroid/content/pm/ApplicationInfo;
iget v0, v0, Landroid/content/pm/ApplicationInfo;->targetSandboxVersion:I
invoke-static {v0, p2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Ljava/io/File;->delete()Z
return-void
:copy_failed
move-exception v7
invoke-virtual {v1}, Ljava/io/FileOutputStream;->close()V
invoke-virtual {v0}, Ljava/io/InputStream;->close()V
throw v7
.catchall {:copy_start .. :copy_end} :copy_failed
.end method
.method public static moduleCatalog(Landroid/content/Context;)V
.locals 4
invoke-virtual {p0}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v0
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/content/pm/PackageManager;->getInstalledModules(I)Ljava/util/List;
move-result-object v2
invoke-interface {v2}, Ljava/util/List;->size()I
move-result v3
invoke-static {v3, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v3, "fixture caller mutation"
invoke-interface {v2, v3}, Ljava/util/List;->add(Ljava/lang/Object;)Z
const/high16 v3, 0x20000
invoke-virtual {v0, v3}, Landroid/content/pm/PackageManager;->getInstalledModules(I)Ljava/util/List;
move-result-object v2
invoke-interface {v2}, Ljava/util/List;->size()I
move-result v3
invoke-static {v3, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0, v1}, Landroid/content/pm/PackageManager;->getInstalledModules(I)Ljava/util/List;
move-result-object v2
invoke-interface {v2}, Ljava/util/List;->size()I
move-result v3
invoke-static {v3, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public static userBroadcasts(Landroid/content/Context;)V
.locals 7
new-instance v0, Landroid/os/UserManager;
invoke-direct {v0}, Landroid/os/UserManager;-><init>()V
invoke-virtual {v0}, Landroid/os/UserManager;->isDemoUser()Z
move-result v0
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Lorg/vinix/bootstrap/TestUserBroadcast;
invoke-direct {v0}, Lorg/vinix/bootstrap/TestUserBroadcast;-><init>()V
new-instance v2, Landroid/content/IntentFilter;
const-string v3, "org.vinix.fixture.USER_BROADCAST"
invoke-direct {v2, v3}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V
invoke-virtual {p0, v0, v2}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;
new-instance v2, Landroid/content/Intent;
invoke-direct {v2, v3}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
const-string v3, "payload"
const/16 v4, 0x59
invoke-virtual {v2, v3, v4}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;
invoke-static {}, Landroid/os/Process;->myUserHandle()Landroid/os/UserHandle;
move-result-object v3
invoke-virtual {p0, v2, v3}, Landroid/content/Context;->sendBroadcastAsUser(Landroid/content/Intent;Landroid/os/UserHandle;)V
new-instance v4, Landroid/os/UserHandle;
invoke-virtual {v3}, Landroid/os/UserHandle;->getIdentifier()I
move-result v5
add-int/lit8 v5, v5, 1
invoke-direct {v4, v5}, Landroid/os/UserHandle;-><init>(I)V
:foreign_start
invoke-virtual {p0, v2, v4}, Landroid/content/Context;->sendBroadcastAsUser(Landroid/content/Intent;Landroid/os/UserHandle;)V
:foreign_end
goto :broadcast_failed
:foreign_denied
move-exception v5
new-instance v4, Landroid/os/UserHandle;
const/4 v5, -1
invoke-direct {v4, v5}, Landroid/os/UserHandle;-><init>(I)V
:all_start
invoke-virtual {p0, v2, v4}, Landroid/content/Context;->sendBroadcastAsUser(Landroid/content/Intent;Landroid/os/UserHandle;)V
:all_end
goto :broadcast_failed
:all_denied
move-exception v5
:null_user_start
invoke-virtual {p0, v2, v1}, Landroid/content/Context;->sendBroadcastAsUser(Landroid/content/Intent;Landroid/os/UserHandle;)V
:null_user_end
goto :broadcast_failed
:null_user
move-exception v5
:null_intent_start
invoke-virtual {p0, v1, v3}, Landroid/content/Context;->sendBroadcastAsUser(Landroid/content/Intent;Landroid/os/UserHandle;)V
:null_intent_end
goto :broadcast_failed
:null_intent
move-exception v5
invoke-virtual {p0, v0}, Landroid/content/Context;->unregisterReceiver(Landroid/content/BroadcastReceiver;)V
return-void
:broadcast_failed
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.catch Ljava/lang/SecurityException; {:foreign_start .. :foreign_end} :foreign_denied
.catch Ljava/lang/SecurityException; {:all_start .. :all_end} :all_denied
.catch Ljava/lang/NullPointerException; {:null_user_start .. :null_user_end} :null_user
.catch Ljava/lang/NullPointerException; {:null_intent_start .. :null_intent_end} :null_intent
.end method
.method public static accountPackages(Landroid/content/Context;)V
.locals 8
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v0
const-string v1, "org.vinix.not.owner"
const-string v2, "org.vinix.fixture"
new-instance v3, Lorg/vinix/bootstrap/TestPackageAccounts;
invoke-direct {v3}, Lorg/vinix/bootstrap/TestPackageAccounts;-><init>()V
new-instance v4, Landroid/accounts/Account;
const-string v5, "fixture@example.invalid"
invoke-direct {v4, v5, v2}, Landroid/accounts/Account;-><init>(Ljava/lang/String;Ljava/lang/String;)V
const/4 v5, 1
new-array v6, v5, [Landroid/accounts/Account;
const/4 v7, 0
aput-object v4, v6, v7
iput-object v6, v3, Lorg/vinix/bootstrap/TestPackageAccounts;->snapshot:[Landroid/accounts/Account;
invoke-virtual {v3, v2, v0}, Landroid/accounts/AccountManager;->getAccountsByTypeForPackage(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;
move-result-object v4
array-length v4, v4
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v6, Ljava/lang/SecurityException;
const-string v4, "fixture backend denial"
invoke-direct {v6, v4}, Ljava/lang/SecurityException;-><init>(Ljava/lang/String;)V
iput-object v6, v3, Lorg/vinix/bootstrap/TestPackageAccounts;->denial:Ljava/lang/SecurityException;
invoke-virtual {v3, v2, v1}, Landroid/accounts/AccountManager;->getAccountsByTypeForPackage(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;
move-result-object v4
array-length v4, v4
invoke-static {v4, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
:own_denied_start
invoke-virtual {v3, v2, v0}, Landroid/accounts/AccountManager;->getAccountsByTypeForPackage(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;
:own_denied_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:own_denied
move-exception v4
if-ne v4, v6, :account_package_failed
new-instance v0, Landroid/app/AppOpsManager;
invoke-direct {v0}, Landroid/app/AppOpsManager;-><init>()V
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v2
:native_owner_start
invoke-virtual {v0, v2, v1}, Landroid/app/AppOpsManager;->checkPackage(ILjava/lang/String;)V
:native_owner_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:native_owner_denied
move-exception v4
return-void
:account_package_failed
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
.catch Ljava/lang/SecurityException; {:own_denied_start .. :own_denied_end} :own_denied
.catch Ljava/lang/SecurityException; {:native_owner_start .. :native_owner_end} :native_owner_denied
.end method
.method public static runtimeQueries(Landroid/content/Context;)V
.locals 8
new-instance v0, Landroid/os/UserManager;
invoke-direct {v0}, Landroid/os/UserManager;-><init>()V
invoke-virtual {v0}, Landroid/os/UserManager;->getUserCount()I
move-result v1
const/4 v2, 1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/os/UserManager;->getUserProfiles()Ljava/util/List;
move-result-object v1
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v2, 0
invoke-interface {v1, v2}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/os/UserHandle;
invoke-virtual {v0, v1}, Landroid/os/UserManager;->getSerialNumberForUser(Landroid/os/UserHandle;)J
move-result-wide v3
invoke-virtual {v0, v3, v4}, Landroid/os/UserManager;->getUserForSerialNumber(J)Landroid/os/UserHandle;
move-result-object v5
invoke-virtual {v5}, Landroid/os/UserHandle;->getIdentifier()I
move-result v5
invoke-virtual {v1}, Landroid/os/UserHandle;->getIdentifier()I
move-result v1
invoke-static {v5, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-wide v5, 0x100000000L
add-long v5, v5, v3
invoke-virtual {v0, v5, v6}, Landroid/os/UserManager;->getUserForSerialNumber(J)Landroid/os/UserHandle;
move-result-object v1
if-nez v1, :runtime_failed
const-wide/16 v5, -1
invoke-virtual {v0, v5, v6}, Landroid/os/UserManager;->getUserForSerialNumber(J)Landroid/os/UserHandle;
move-result-object v1
if-nez v1, :runtime_failed
const-wide/16 v5, 1
add-long v5, v5, v3
invoke-virtual {v0, v5, v6}, Landroid/os/UserManager;->getUserForSerialNumber(J)Landroid/os/UserHandle;
move-result-object v1
if-nez v1, :runtime_failed
new-instance v0, Landroid/content/pm/ApplicationInfo;
invoke-direct {v0}, Landroid/content/pm/ApplicationInfo;-><init>()V
invoke-virtual {v0}, Landroid/content/pm/ApplicationInfo;->isInstantApp()Z
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/16 v1, 0x80
iput v1, v0, Landroid/content/pm/ApplicationInfo;->flags:I
const/16 v1, 0x100
iput v1, v0, Landroid/content/pm/ApplicationInfo;->privateFlags:I
invoke-virtual {v0}, Landroid/content/pm/ApplicationInfo;->isInstantApp()Z
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/16 v1, 0x180
iput v1, v0, Landroid/content/pm/ApplicationInfo;->privateFlags:I
new-instance v3, Landroid/content/pm/ApplicationInfo;
invoke-direct {v3, v0}, Landroid/content/pm/ApplicationInfo;-><init>(Landroid/content/pm/ApplicationInfo;)V
iput v2, v0, Landroid/content/pm/ApplicationInfo;->privateFlags:I
invoke-virtual {v3}, Landroid/content/pm/ApplicationInfo;->isInstantApp()Z
move-result v1
const/4 v4, 1
invoke-static {v1, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/content/pm/ApplicationInfo;->isInstantApp()Z
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v0
invoke-virtual {v0}, Landroid/content/pm/ApplicationInfo;->isInstantApp()Z
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Lorg/vinix/bootstrap/TestNetwork;
invoke-direct {v0}, Lorg/vinix/bootstrap/TestNetwork;-><init>()V
const v1, 0x70401
iput v1, v0, Lorg/vinix/bootstrap/TestNetwork;->state:I
new-instance v1, Landroid/net/Network;
const/4 v3, 7
invoke-direct {v1, v3}, Landroid/net/Network;-><init>(I)V
invoke-virtual {v0, v1}, Landroid/net/ConnectivityManager;->getNetworkInfo(Landroid/net/Network;)Landroid/net/NetworkInfo;
move-result-object v3
invoke-virtual {v3}, Landroid/net/NetworkInfo;->getType()I
move-result v3
const/16 v4, 9
invoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0, v2}, Landroid/net/ConnectivityManager;->getNetworkInfo(Landroid/net/Network;)Landroid/net/NetworkInfo;
move-result-object v3
if-nez v3, :runtime_failed
new-instance v3, Landroid/net/Network;
const/16 v4, 8
invoke-direct {v3, v4}, Landroid/net/Network;-><init>(I)V
invoke-virtual {v0, v3}, Landroid/net/ConnectivityManager;->getNetworkInfo(Landroid/net/Network;)Landroid/net/NetworkInfo;
move-result-object v3
if-nez v3, :runtime_failed
const v3, 0x80401
iput v3, v0, Lorg/vinix/bootstrap/TestNetwork;->state:I
invoke-virtual {v0, v1}, Landroid/net/ConnectivityManager;->getNetworkInfo(Landroid/net/Network;)Landroid/net/NetworkInfo;
move-result-object v3
if-nez v3, :runtime_failed
iput v2, v0, Lorg/vinix/bootstrap/TestNetwork;->state:I
invoke-virtual {v0, v1}, Landroid/net/ConnectivityManager;->getNetworkInfo(Landroid/net/Network;)Landroid/net/NetworkInfo;
move-result-object v3
if-nez v3, :runtime_failed
new-instance v0, Landroid/net/ConnectivityManager;
invoke-direct {v0}, Landroid/net/ConnectivityManager;-><init>()V
invoke-virtual {v0}, Landroid/net/ConnectivityManager;->getActiveNetwork()Landroid/net/Network;
move-result-object v1
invoke-virtual {v0, v1}, Landroid/net/ConnectivityManager;->getNetworkInfo(Landroid/net/Network;)Landroid/net/NetworkInfo;
return-void
:runtime_failed
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
.method public static secureLongs(Landroid/content/ContentResolver;)V
.locals 6
const-string v0, "vinix_absent_long"
:secure_strict_start
invoke-static {p0, v0}, Landroid/provider/Settings$Secure;->getLong(Landroid/content/ContentResolver;Ljava/lang/String;)J
:secure_strict_end
new-instance v1, Ljava/lang/AssertionError;
invoke-direct {v1}, Ljava/lang/AssertionError;-><init>()V
throw v1
:secure_missing
move-exception v1
invoke-virtual {v1}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
const/4 v2, 1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-wide v1, 0x1020304050607080L
invoke-static {p0, v0, v1, v2}, Landroid/provider/Settings$Secure;->getLong(Landroid/content/ContentResolver;Ljava/lang/String;J)J
move-result-wide v3
cmp-long v5, v1, v3
const/4 v0, 0
invoke-static {v5, v0}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "advertising_id"
const-wide v1, -0x8000000000000000L
invoke-static {p0, v0, v1, v2}, Landroid/provider/Settings$Secure;->getLong(Landroid/content/ContentResolver;Ljava/lang/String;J)J
move-result-wide v3
cmp-long v5, v1, v3
const/4 v0, 0
invoke-static {v5, v0}, Lorg/vinix/bootstrap/Main;->expect(II)V
:secure_null_start
invoke-static {p0, v0, v1, v2}, Landroid/provider/Settings$Secure;->getLong(Landroid/content/ContentResolver;Ljava/lang/String;J)J
:secure_null_end
new-instance v1, Ljava/lang/AssertionError;
invoke-direct {v1}, Ljava/lang/AssertionError;-><init>()V
throw v1
:secure_null
move-exception v1
return-void
.catch Landroid/provider/Settings$SettingNotFoundException; {:secure_strict_start .. :secure_strict_end} :secure_missing
.catch Ljava/lang/NullPointerException; {:secure_null_start .. :secure_null_end} :secure_null
.end method
.method public static stableDensity()V
.locals 5
sget v0, Landroid/util/DisplayMetrics;->DENSITY_DEVICE:I
sget v1, Landroid/util/DisplayMetrics;->DENSITY_DEVICE_STABLE:I
const/16 v2, 160
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
:density_start
const/16 v2, 240
sput v2, Landroid/util/DisplayMetrics;->DENSITY_DEVICE:I
new-instance v3, Landroid/util/DisplayMetrics;
invoke-direct {v3}, Landroid/util/DisplayMetrics;-><init>()V
iget v4, v3, Landroid/util/DisplayMetrics;->densityDpi:I
invoke-static {v4, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget v4, Landroid/util/DisplayMetrics;->DENSITY_DEVICE_STABLE:I
invoke-static {v4, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/16 v2, 320
iput v2, v3, Landroid/util/DisplayMetrics;->densityDpi:I
sget v4, Landroid/util/DisplayMetrics;->DENSITY_DEVICE_STABLE:I
invoke-static {v4, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
:density_end
sput v0, Landroid/util/DisplayMetrics;->DENSITY_DEVICE:I
return-void
:density_failed
move-exception v1
sput v0, Landroid/util/DisplayMetrics;->DENSITY_DEVICE:I
throw v1
.catchall {:density_start .. :density_end} :density_failed
.end method
.method public static restrictions(Landroid/content/Context;)V
.locals 6
const-string v0, "restrictions"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/content/RestrictionsManager;
const-class v1, Landroid/content/RestrictionsManager;
invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v1
if-ne v0, v1, :failed
if-eqz v0, :failed
invoke-virtual {v0}, Landroid/content/RestrictionsManager;->hasRestrictionsProvider()Z
move-result v1
const/4 v2, 0
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/content/RestrictionsManager;->getApplicationRestrictions()Landroid/os/Bundle;
move-result-object v1
invoke-virtual {v1}, Landroid/os/Bundle;->size()I
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v3, "fixture"
const/4 v4, 1
invoke-virtual {v1, v3, v4}, Landroid/os/Bundle;->putBoolean(Ljava/lang/String;Z)V
invoke-virtual {v0}, Landroid/content/RestrictionsManager;->getApplicationRestrictions()Landroid/os/Bundle;
move-result-object v3
if-eq v1, v3, :failed
invoke-virtual {v3}, Landroid/os/Bundle;->size()I
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v1, "user"
invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/os/UserManager;
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v3
invoke-virtual {v1, v3}, Landroid/os/UserManager;->getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v1
invoke-virtual {v1}, Landroid/os/Bundle;->size()I
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/content/RestrictionsManager;
invoke-direct {v0}, Landroid/content/RestrictionsManager;-><init>()V
invoke-virtual {v0}, Landroid/content/RestrictionsManager;->getApplicationRestrictions()Landroid/os/Bundle;
move-result-object v0
if-nez v0, :failed
return-void
:failed
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
.method public static shortcuts()V
.locals 5
new-instance v0, Landroid/content/pm/ShortcutManager;
invoke-direct {v0}, Landroid/content/pm/ShortcutManager;-><init>()V
invoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;
move-result-object v1
invoke-virtual {v0, v1}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
new-instance v1, Ljava/util/ArrayList;
invoke-direct {v1}, Ljava/util/ArrayList;-><init>()V
const-string v2, "absent-shortcut"
invoke-virtual {v1, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
invoke-virtual {v1, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
invoke-virtual {v0, v1}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
invoke-virtual {v0, v1}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
invoke-virtual {v1}, Ljava/util/ArrayList;->size()I
move-result v2
const/4 v3, 2
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/content/pm/ShortcutManager;->getDynamicShortcuts()Ljava/util/List;
move-result-object v2
invoke-interface {v2}, Ljava/util/List;->size()I
move-result v2
const/4 v3, 0
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
:null_ids_start
invoke-virtual {v0, v3}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
:null_ids_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:null_ids
move-exception v4
invoke-virtual {v1}, Ljava/util/ArrayList;->clear()V
invoke-virtual {v1, v3}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
:null_id_start
invoke-virtual {v0, v1}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
:null_id_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:null_id
move-exception v4
invoke-virtual {v1}, Ljava/util/ArrayList;->clear()V
const-string v2, ""
invoke-virtual {v1, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
:empty_id_start
invoke-virtual {v0, v1}, Landroid/content/pm/ShortcutManager;->removeDynamicShortcuts(Ljava/util/List;)V
:empty_id_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:empty_id
move-exception v4
return-void
.catch Ljava/lang/NullPointerException; {:null_ids_start .. :null_ids_end} :null_ids
.catch Ljava/lang/IllegalArgumentException; {:null_id_start .. :null_id_end} :null_id
.catch Ljava/lang/IllegalArgumentException; {:empty_id_start .. :empty_id_end} :empty_id
.end method
.method public static subscriptions()V
.locals 6
new-instance v0, Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;
invoke-direct {v0}, Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;-><init>()V
invoke-virtual {v0}, Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;->onSubscriptionsChanged()V
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v0
new-instance v1, Lorg/vinix/bootstrap/TestSubscriptions;
invoke-direct {v1, v0}, Lorg/vinix/bootstrap/TestSubscriptions;-><init>(Landroid/os/Looper;)V
new-instance v0, Landroid/telephony/SubscriptionManager;
invoke-direct {v0}, Landroid/telephony/SubscriptionManager;-><init>()V
invoke-virtual {v0, v1}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
invoke-virtual {v0, v1}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
new-instance v2, Lorg/vinix/bootstrap/TestSubscriptionExecutor;
invoke-direct {v2}, Lorg/vinix/bootstrap/TestSubscriptionExecutor;-><init>()V
invoke-virtual {v0, v2, v1}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Ljava/util/concurrent/Executor;Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
invoke-virtual {v0, v1}, Landroid/telephony/SubscriptionManager;->removeOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
invoke-virtual {v0, v1}, Landroid/telephony/SubscriptionManager;->removeOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
const/4 v3, 0
invoke-virtual {v0, v3}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
invoke-virtual {v0, v3}, Landroid/telephony/SubscriptionManager;->removeOnSubscriptionsChangedListener(Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
iget v4, v1, Lorg/vinix/bootstrap/TestSubscriptions;->calls:I
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v4, v2, Lorg/vinix/bootstrap/TestSubscriptionExecutor;->calls:I
const/4 v5, 1
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v4, v1, Lorg/vinix/bootstrap/TestSubscriptions;->failures:I
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Lorg/vinix/bootstrap/TestSubscriptions;->onSubscriptionsChanged()V
iget v4, v1, Lorg/vinix/bootstrap/TestSubscriptions;->calls:I
const/4 v5, 1
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
:null_executor_start
invoke-virtual {v0, v3, v1}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Ljava/util/concurrent/Executor;Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
:null_executor_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:null_executor
move-exception v4
:null_listener_start
invoke-virtual {v0, v2, v3}, Landroid/telephony/SubscriptionManager;->addOnSubscriptionsChangedListener(Ljava/util/concurrent/Executor;Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;)V
:null_listener_end
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:null_listener
move-exception v4
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v2
invoke-direct {v0, v2}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v2, Lorg/vinix/bootstrap/TestSubscriptionFence;
invoke-direct {v2, v1}, Lorg/vinix/bootstrap/TestSubscriptionFence;-><init>(Lorg/vinix/bootstrap/TestSubscriptions;)V
invoke-virtual {v0, v2}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void
.catch Ljava/lang/NullPointerException; {:null_executor_start .. :null_executor_end} :null_executor
.catch Ljava/lang/NullPointerException; {:null_listener_start .. :null_listener_end} :null_listener
.end method
'

fn subscription_fixture(root string) ! {
	os.write_file(root + '/smali/TestSubscriptionFence.smali', r'.class public Lorg/vinix/bootstrap/TestSubscriptionFence;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private final listener:Lorg/vinix/bootstrap/TestSubscriptions;
.method public constructor <init>(Lorg/vinix/bootstrap/TestSubscriptions;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Lorg/vinix/bootstrap/TestSubscriptionFence;->listener:Lorg/vinix/bootstrap/TestSubscriptions;
return-void
.end method
.method public run()V
.locals 3
iget-object v0, p0, Lorg/vinix/bootstrap/TestSubscriptionFence;->listener:Lorg/vinix/bootstrap/TestSubscriptions;
iget v1, v0, Lorg/vinix/bootstrap/TestSubscriptions;->failures:I
const/4 v2, 3
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v1, v0, Lorg/vinix/bootstrap/TestSubscriptions;->calls:I
const/4 v2, 1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget v1, Lorg/vinix/bootstrap/TestUserBroadcast;->calls:I
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget v1, Lorg/vinix/bootstrap/TestJobService;->calls:I
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "CURRENT-API-PASS"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
')!
	os.write_file(root + '/smali/TestSubscriptions.smali', r'.class public Lorg/vinix/bootstrap/TestSubscriptions;
.super Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;
.field public calls:I
.field public failures:I
.method public constructor <init>(Landroid/os/Looper;)V
.locals 0
invoke-direct {p0, p1}, Landroid/telephony/SubscriptionManager$OnSubscriptionsChangedListener;-><init>(Landroid/os/Looper;)V
return-void
.end method
.method public onSubscriptionsChanged()V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestSubscriptions;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestSubscriptions;->calls:I
return-void
.end method
.method public onAddListenerFailed()V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestSubscriptions;->failures:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestSubscriptions;->failures:I
return-void
.end method
')!
	os.write_file(root + '/smali/TestSubscriptionExecutor.smali', r'.class public Lorg/vinix/bootstrap/TestSubscriptionExecutor;
.super Ljava/lang/Object;
.implements Ljava/util/concurrent/Executor;
.field public calls:I
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public execute(Ljava/lang/Runnable;)V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestSubscriptionExecutor;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestSubscriptionExecutor;->calls:I
invoke-interface {p1}, Ljava/lang/Runnable;->run()V
return-void
.end method
')!
}

fn boolean_source() string {
	// Reflect only to seed this isolated test process's existing property map;
	// do not expose a pretend system-wide property setter in the framework.
	mut source := r'
.method public static properties()V
.locals 6
const-class v0, Landroid/os/SystemProperties;
const-string v1, "properties"
invoke-virtual {v0, v1}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->setAccessible(Z)V
const/4 v1, 0
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/util/Properties;
const-string v1, "vinix.fixture.boolean"
'
	for token in ['<missing>', '', 'unknown', 'TRUE', ' true', '1', 'y', 'yes', 'on', 'true', '0', 'n', 'no', 'off', 'false'] {
		if token == '<missing>' {
			source += 'invoke-virtual {v0, v1}, Ljava/util/Properties;->remove(Ljava/lang/Object;)Ljava/lang/Object;\n'
		} else {
			source += 'const-string v2, "${token}"\ninvoke-virtual {v0, v1, v2}, Ljava/util/Properties;->setProperty(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/Object;\n'
		}
		for fallback in [0, 1] {
			expected := if token in ['1', 'y', 'yes', 'on', 'true'] { 1 } else if token in ['0', 'n', 'no', 'off', 'false'] { 0 } else { fallback }
			source += 'const/4 v3, ${fallback}\ninvoke-static {v1, v3}, Landroid/os/SystemProperties;->getBoolean(Ljava/lang/String;Z)Z\nmove-result v4\nconst/4 v5, ${expected}\ninvoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
		}
	}
	source += 'invoke-virtual {v0, v1}, Ljava/util/Properties;->remove(Ljava/lang/Object;)Ljava/lang/Object;\nreturn-void\n.end method\n'
	return source
}

const user_source = r'
.method public static users()V
.locals 6
const/4 v0, 2
new-array v1, v0, [Landroid/os/UserHandle;
invoke-static {v1}, Lorg/vinix/bootstrap/Main;->acceptUsers([Landroid/os/Parcelable;)I
move-result v2
invoke-static {v2, v0}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/os/UserHandle;
const/16 v1, 42
invoke-direct {v0, v1}, Landroid/os/UserHandle;-><init>(I)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const/4 v3, 0
invoke-virtual {v0, v2, v3}, Landroid/os/UserHandle;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v2, v3}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v4, Landroid/os/UserHandle;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v4, v2}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v5
check-cast v5, Landroid/os/UserHandle;
invoke-virtual {v5}, Landroid/os/UserHandle;->getIdentifier()I
move-result v5
invoke-static {v5, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-interface {v4, v1}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v5
instance-of v5, v5, [Landroid/os/UserHandle;
const/4 v4, 1
invoke-static {v5, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
invoke-static {v0, v2}, Landroid/os/UserHandle;->writeToParcel(Landroid/os/UserHandle;Landroid/os/Parcel;)V
invoke-virtual {v2, v3}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-static {v2}, Landroid/os/UserHandle;->readFromParcel(Landroid/os/Parcel;)Landroid/os/UserHandle;
move-result-object v5
invoke-virtual {v5}, Landroid/os/UserHandle;->getIdentifier()I
move-result v5
invoke-static {v5, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const/4 v0, 0
invoke-static {v0, v2}, Landroid/os/UserHandle;->writeToParcel(Landroid/os/UserHandle;Landroid/os/Parcel;)V
invoke-virtual {v2, v3}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-static {v2}, Landroid/os/UserHandle;->readFromParcel(Landroid/os/Parcel;)Landroid/os/UserHandle;
move-result-object v5
if-eqz v5, :null_ok
new-instance v5, Ljava/lang/AssertionError;
invoke-direct {v5}, Ljava/lang/AssertionError;-><init>()V
throw v5
:null_ok
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
return-void
.end method
.method public static acceptUsers([Landroid/os/Parcelable;)I
.locals 1
array-length v0, p0
return v0
.end method
'

const intent_source = r'
.method public static intent()V
.locals 10
new-instance v0, Landroid/content/Intent;
const-string v1, "android.intent.action.MAIN"
invoke-direct {v0, v1}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
new-instance v1, Landroid/content/ComponentName;
const-string v2, "com.example"
const-string v3, "com.example.Main"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v0, v1}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;
invoke-virtual {v0, v2}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "android.intent.category.LAUNCHER"
invoke-virtual {v0, v1}, Landroid/content/Intent;->addCategory(Ljava/lang/String;)Landroid/content/Intent;
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/content/Intent;->toUri(I)Ljava/lang/String;
move-result-object v2
const-string v3, "intent:#Intent;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;package=com.example;component=com.example/.Main;end"
invoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
const/4 v6, 1
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v1, 2
invoke-virtual {v0, v1}, Landroid/content/Intent;->toUri(I)Ljava/lang/String;
move-result-object v2
const-string v3, "android-app://com.example#Intent;category=android.intent.category.LAUNCHER;component=com.example/.Main;end"
invoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v1, "demo+map://host/a%20b?x=1#fragment"
invoke-static {v1}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v1
const-string v2, "text/plain"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setDataAndType(Landroid/net/Uri;Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "s;雪"
const-string v2, "value;=☃"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "count"
const/16 v2, -7
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;
const-string v1, "yes"
invoke-virtual {v0, v1, v6}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Z)Landroid/content/Intent;
const-string v1, "wide"
const-wide v8, 0x1020304050607080L
invoke-virtual {v0, v1, v8, v9}, Landroid/content/Intent;->putExtra(Ljava/lang/String;J)Landroid/content/Intent;
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/content/Intent;->toUri(I)Ljava/lang/String;
move-result-object v2
invoke-static {v2, v1}, Landroid/content/Intent;->parseUri(Ljava/lang/String;I)Landroid/content/Intent;
move-result-object v3
invoke-static {v0, v3}, Lorg/vinix/bootstrap/Main;->sameIntent(Landroid/content/Intent;Landroid/content/Intent;)V
const/4 v1, 2
invoke-virtual {v0, v1}, Landroid/content/Intent;->toUri(I)Ljava/lang/String;
move-result-object v2
invoke-static {v2, v1}, Landroid/content/Intent;->parseUri(Ljava/lang/String;I)Landroid/content/Intent;
move-result-object v3
invoke-static {v0, v3}, Lorg/vinix/bootstrap/Main;->sameIntent(Landroid/content/Intent;Landroid/content/Intent;)V
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
:package_start
invoke-virtual {v0, v1}, Landroid/content/Intent;->toUri(I)Ljava/lang/String;
:package_end
new-instance v2, Ljava/lang/AssertionError;
invoke-direct {v2}, Ljava/lang/AssertionError;-><init>()V
throw v2
.catch Ljava/lang/IllegalArgumentException; {:package_start .. :package_end} :package_expected
:package_expected
move-exception v2
return-void
.end method
.method public static sameIntent(Landroid/content/Intent;Landroid/content/Intent;)V
.locals 6
invoke-virtual {p0}, Landroid/content/Intent;->getDataString()Ljava/lang/String;
move-result-object v0
invoke-virtual {p1}, Landroid/content/Intent;->getDataString()Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v2, 1
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p0}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v0
invoke-virtual {p1}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v1
invoke-virtual {v0, v1}, Landroid/content/ComponentName;->equals(Ljava/lang/Object;)Z
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "s;雪"
invoke-virtual {p1, v0}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "value;=☃"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "count"
const/4 v1, 0
invoke-virtual {p1, v0, v1}, Landroid/content/Intent;->getIntExtra(Ljava/lang/String;I)I
move-result v0
const/16 v1, -7
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "yes"
const/4 v1, 0
invoke-virtual {p1, v0, v1}, Landroid/content/Intent;->getBooleanExtra(Ljava/lang/String;Z)Z
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "wide"
const-wide/16 v4, 0
invoke-virtual {p1, v0, v4, v5}, Landroid/content/Intent;->getLongExtra(Ljava/lang/String;J)J
move-result-wide v4
const-wide v0, 0x1020304050607080L
cmp-long v0, v0, v4
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
'

const main_source = r'.class public Lorg/vinix/bootstrap/Main;
.super Landroid/app/Activity;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method protected onCreate(Landroid/os/Bundle;)V
.locals 2
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->mime()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->parcel()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->accounts()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->intent()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->users()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->properties()V
invoke-virtual {p0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;
move-result-object v0
invoke-static {v0}, Lorg/vinix/bootstrap/Main;->secureLongs(Landroid/content/ContentResolver;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->stableDensity()V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->runtimeQueries(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->accountPackages(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->userBroadcasts(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->moduleCatalog(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->sandboxMetadata(Landroid/content/Context;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->buildAndObserver()V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->storageDatabase(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->sharedLibraryCatalog(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->jobInstallQueries(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->scheduleProbeJob(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->modemIdentifiers(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->optionalStorageStats(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->serialTlsCache(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->forceLayoutProbe(Landroid/content/Context;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->restrictions(Landroid/content/Context;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->subscriptions()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->shortcuts()V
new-instance v0, Landroid/content/pm/ShortcutManager;
invoke-direct {v0}, Landroid/content/pm/ShortcutManager;-><init>()V
invoke-virtual {v0}, Landroid/content/pm/ShortcutManager;->getDynamicShortcuts()Ljava/util/List;
move-result-object v0
invoke-interface {v0}, Ljava/util/List;->size()I
move-result v0
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/telephony/TelephonyManager;
invoke-direct {v0}, Landroid/telephony/TelephonyManager;-><init>()V
invoke-virtual {v0}, Landroid/telephony/TelephonyManager;->isVoiceCapable()Z
move-result v0
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/net/ConnectivityManager;
invoke-direct {v0}, Landroid/net/ConnectivityManager;-><init>()V
invoke-virtual {v0}, Landroid/net/ConnectivityManager;->isTetheringSupported()Z
move-result v0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public static expect(II)V
.locals 1
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:ok
return-void
.end method
.method public static mime()V
.locals 10
new-instance v0, Landroid/content/IntentFilter;
const-string v1, "A"
invoke-direct {v0, v1}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V
const-string v2, "image/*"
invoke-virtual {v0, v2}, Landroid/content/IntentFilter;->addDataType(Ljava/lang/String;)V
invoke-virtual {v0, v2}, Landroid/content/IntentFilter;->addDataType(Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/content/IntentFilter;->countDataTypes()I
move-result v7
const/4 v8, 1
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v2, "image/png"
invoke-virtual {v0, v2}, Landroid/content/IntentFilter;->hasDataType(Ljava/lang/String;)Z
move-result v7
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v3, "content"
const-string v4, "content://test/image"
invoke-static {v4}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v4
const/4 v5, 0
const/4 v6, 0
invoke-virtual/range {v0 .. v6}, Landroid/content/IntentFilter;->match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I
move-result v7
const v8, 0x608000
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v1, "B"
invoke-virtual/range {v0 .. v6}, Landroid/content/IntentFilter;->match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I
move-result v7
const/4 v8, -3
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v1, "A"
const-string v2, "text/plain"
invoke-virtual/range {v0 .. v6}, Landroid/content/IntentFilter;->match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I
move-result v7
const/4 v8, -1
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v2, "image/png"
const-string v3, "https"
invoke-virtual/range {v0 .. v6}, Landroid/content/IntentFilter;->match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I
move-result v7
const/4 v8, -2
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v3, "content"
new-instance v5, Ljava/util/HashSet;
invoke-direct {v5}, Ljava/util/HashSet;-><init>()V
const-string v9, "missing"
invoke-interface {v5, v9}, Ljava/util/Set;->add(Ljava/lang/Object;)Z
invoke-virtual/range {v0 .. v6}, Landroid/content/IntentFilter;->match(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;Ljava/util/Set;Ljava/lang/String;)I
move-result v7
const/4 v8, -4
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
:bad_start
const-string v9, "broken"
invoke-virtual {v0, v9}, Landroid/content/IntentFilter;->addDataType(Ljava/lang/String;)V
:bad_end
new-instance v9, Ljava/lang/AssertionError;
invoke-direct {v9}, Ljava/lang/AssertionError;-><init>()V
throw v9
.catch Landroid/content/IntentFilter$MalformedMimeTypeException; {:bad_start .. :bad_end} :bad_expected
:bad_expected
move-exception v9
invoke-virtual {v0}, Landroid/content/IntentFilter;->countDataTypes()I
move-result v7
const/4 v8, 1
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/content/IntentFilter;
invoke-direct {v0}, Landroid/content/IntentFilter;-><init>()V
const/4 v3, 0
const/4 v4, 0
invoke-virtual {v0, v2, v3, v4}, Landroid/content/IntentFilter;->matchData(Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;)I
move-result v7
const/4 v8, -2
invoke-static {v7, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public static parcel()V
.locals 8
const-string v0, "01234567-89ab-cdef-8123-456789abcdef"
invoke-static {v0}, Landroid/os/ParcelUuid;->fromString(Ljava/lang/String;)Landroid/os/ParcelUuid;
move-result-object v0
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
const/4 v2, 0
invoke-virtual {v0, v1, v2}, Landroid/os/ParcelUuid;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v3, Landroid/os/ParcelUuid;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v3, v1}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v4
invoke-virtual {v0, v4}, Landroid/os/ParcelUuid;->equals(Ljava/lang/Object;)Z
move-result v5
const/4 v6, 1
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-interface {v3, v6}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v4
instance-of v5, v4, [Landroid/os/ParcelUuid;
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
const v0, 0x200404
invoke-virtual {v1, v0}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v3, Landroid/bluetooth/BluetoothClass;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v3, v1}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v4
check-cast v4, Landroid/bluetooth/BluetoothClass;
invoke-virtual {v4}, Landroid/bluetooth/BluetoothClass;->getDeviceClass()I
move-result v5
const/16 v7, 0x404
invoke-static {v5, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
const v7, 0x200000
invoke-virtual {v4, v7}, Landroid/bluetooth/BluetoothClass;->hasService(I)Z
move-result v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
const-string v0, "01:23:45:67:89:AB"
invoke-virtual {v1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V
invoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v3, Landroid/bluetooth/BluetoothDevice;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v3, v1}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v4
check-cast v4, Landroid/bluetooth/BluetoothDevice;
invoke-virtual {v4}, Landroid/bluetooth/BluetoothDevice;->getAddress()Ljava/lang/String;
move-result-object v4
invoke-virtual {v0, v4}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
return-void
.end method
.method public static accounts()V
.locals 8
new-instance v0, Lorg/vinix/bootstrap/TestAccounts;
invoke-direct {v0}, Lorg/vinix/bootstrap/TestAccounts;-><init>()V
const/4 v7, 0
new-array v1, v7, [Landroid/accounts/Account;
iput-object v1, v0, Lorg/vinix/bootstrap/TestAccounts;->snapshot:[Landroid/accounts/Account;
const-string v1, "type"
const/4 v7, 1
new-array v2, v7, [Ljava/lang/String;
const/4 v6, 0
const-string v5, "feature"
aput-object v5, v2, v6
const/4 v3, 0
const/4 v4, 0
invoke-virtual {v0, v1, v2, v3, v4}, Landroid/accounts/AccountManager;->getAccountsByTypeAndFeatures(Ljava/lang/String;[Ljava/lang/String;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;
move-result-object v5
invoke-interface {v5}, Landroid/accounts/AccountManagerFuture;->getResult()Ljava/lang/Object;
move-result-object v5
check-cast v5, [Landroid/accounts/Account;
array-length v5, v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-array v5, v7, [Landroid/accounts/Account;
new-instance v6, Landroid/accounts/Account;
const-string v7, "name"
invoke-direct {v6, v7, v1}, Landroid/accounts/Account;-><init>(Ljava/lang/String;Ljava/lang/String;)V
const/4 v7, 0
aput-object v6, v5, v7
iput-object v5, v0, Lorg/vinix/bootstrap/TestAccounts;->snapshot:[Landroid/accounts/Account;
:features_start
invoke-virtual {v0, v1, v2, v3, v4}, Landroid/accounts/AccountManager;->getAccountsByTypeAndFeatures(Ljava/lang/String;[Ljava/lang/String;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;
move-result-object v5
invoke-interface {v5}, Landroid/accounts/AccountManagerFuture;->getResult()Ljava/lang/Object;
:features_end
new-instance v5, Ljava/lang/AssertionError;
invoke-direct {v5}, Ljava/lang/AssertionError;-><init>()V
throw v5
.catch Landroid/accounts/AuthenticatorException; {:features_start .. :features_end} :unsupported
:unsupported
move-exception v5
const/4 v2, 0
invoke-virtual {v0, v1, v2, v3, v4}, Landroid/accounts/AccountManager;->getAccountsByTypeAndFeatures(Ljava/lang/String;[Ljava/lang/String;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;
move-result-object v5
invoke-interface {v5}, Landroid/accounts/AccountManagerFuture;->getResult()Ljava/lang/Object;
move-result-object v5
check-cast v5, [Landroid/accounts/Account;
array-length v5, v5
const/4 v6, 1
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
'

fn main() {
	if os.args.len == 4 && os.args[1] == '--plan' {
		serial := os.read_file(os.args[2])!
		if serial.len > 8 * 1024 * 1024 || os.exists(os.args[3]) { panic('bounded input and fresh plan required') }
		prefix := 'VINIX-SERVICE-QUERY-RESULTS-1 '
		headers := serial.split_into_lines().filter(it.starts_with(prefix + 'BEGIN '))
		if headers.len != 1 { panic('one complete fixture export required') }
		fields := headers[0].fields()
		if fields.len != 5 || !serial.contains(prefix + 'END ' + fields[2..].join(' ')) { panic('incomplete fixture export') }
		os.write_file(os.args[3], json2.encode({
			'version': json2.Any(2), 'frame_prefix': json2.Any(prefix),
			'serial_sha256': json2.Any(sha256.sum(serial.bytes()).hex()),
			'archive_sha256': json2.Any(fields[2]), 'archive_bytes': json2.Any(fields[3].int()),
			'archive_chunks': json2.Any(fields[4].int()), 'removals': json2.Any([]json2.Any{})
		}, prettify: true))!
		return
	}
	if os.args.len != 3 { panic('usage: current-api-fixture TEMPLATE_FIXTURE FRESH_OUTPUT') }
	base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	if os.exists(root) { panic('fresh output required') }
	os.mkdir_all(root + '/smali')!
	os.write_file(root + '/smali/TestLayoutTable.smali', r'.class public Lorg/vinix/bootstrap/TestLayoutTable;
.super Landroid/widget/TableLayout;
.field public requests:I
.method public constructor <init>(Landroid/content/Context;)V
.locals 0
invoke-direct {p0, p1}, Landroid/widget/TableLayout;-><init>(Landroid/content/Context;)V
return-void
.end method
.method public requestLayout()V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestLayoutTable;->requests:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestLayoutTable;->requests:I
invoke-super {p0}, Landroid/widget/TableLayout;->requestLayout()V
return-void
.end method
')!
	os.write_file(root + '/smali/TestLayoutView.smali', r'.class public Lorg/vinix/bootstrap/TestLayoutView;
.super Landroid/view/View;
.field public requests:I
.field public measures:I
.method public constructor <init>(Landroid/content/Context;)V
.locals 0
invoke-direct {p0, p1}, Landroid/view/View;-><init>(Landroid/content/Context;)V
return-void
.end method
.method public requestLayout()V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestLayoutView;->requests:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestLayoutView;->requests:I
invoke-super {p0}, Landroid/view/View;->requestLayout()V
return-void
.end method
.method protected onMeasure(II)V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestLayoutView;->measures:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestLayoutView;->measures:I
invoke-super {p0, p1, p2}, Landroid/view/View;->onMeasure(II)V
return-void
.end method
')!
	os.write_file(root + '/smali/TestForceLayoutWorker.smali', r'.class public Lorg/vinix/bootstrap/TestForceLayoutWorker;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private view:Landroid/view/View;
.method public constructor <init>(Landroid/view/View;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Lorg/vinix/bootstrap/TestForceLayoutWorker;->view:Landroid/view/View;
return-void
.end method
.method public run()V
.locals 1
iget-object v0, p0, Lorg/vinix/bootstrap/TestForceLayoutWorker;->view:Landroid/view/View;
invoke-virtual {v0}, Landroid/view/View;->forceLayout()V
return-void
.end method
')!
	os.write_file(root + '/smali/TestSslContext.smali', r'.class public Lorg/vinix/bootstrap/TestSslContext;
.super Landroid/content/ContextWrapper;
.field public calls:I
.field public directory:Ljava/io/File;
.method public constructor <init>(Landroid/content/Context;)V
.locals 0
invoke-direct {p0, p1}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V
return-void
.end method
.method public getDir(Ljava/lang/String;I)Ljava/io/File;
.locals 3
const-string v0, "sslcache"
invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v1, 1
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v0, 0
invoke-static {p2, v0}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v0, p0, Lorg/vinix/bootstrap/TestSslContext;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestSslContext;->calls:I
invoke-super {p0, p1, p2}, Landroid/content/ContextWrapper;->getDir(Ljava/lang/String;I)Ljava/io/File;
move-result-object v0
iput-object v0, p0, Lorg/vinix/bootstrap/TestSslContext;->directory:Ljava/io/File;
return-object v0
.end method
')!
	os.write_file(root + '/smali/TestJobService.smali', r'.class public Lorg/vinix/bootstrap/TestJobService;
.super Landroid/app/job/JobService;
.field public static calls:I
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/job/JobService;-><init>()V
return-void
.end method
.method public onStartJob(Landroid/app/job/JobParameters;)Z
.locals 3
invoke-virtual {p1}, Landroid/app/job/JobParameters;->isOverrideDeadlineExpired()Z
move-result v0
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p1}, Landroid/app/job/JobParameters;->getJobId()I
move-result v0
const v1, 0x1234567
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p1}, Landroid/app/job/JobParameters;->getExtras()Landroid/os/PersistableBundle;
move-result-object v0
const-string v1, "job-payload"
invoke-virtual {v0, v1}, Landroid/os/PersistableBundle;->getInt(Ljava/lang/String;)I
move-result v0
const/16 v1, 73
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget v0, Lorg/vinix/bootstrap/TestJobService;->calls:I
add-int/lit8 v0, v0, 1
sput v0, Lorg/vinix/bootstrap/TestJobService;->calls:I
const/4 v1, 1
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v0, 0
return v0
.end method
.method public onStopJob(Landroid/app/job/JobParameters;)Z
.locals 1
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
')!
	os.write_file(root + '/smali/TestDataObserver.smali', r'.class public Lorg/vinix/bootstrap/TestDataObserver;
.super Landroid/os/Binder;
.implements Landroid/content/pm/IPackageDataObserver;
.field public calls:I
.field public success:Z
.field public name:Ljava/lang/String;
.method public constructor <init>()V
.locals 1
invoke-direct {p0}, Landroid/os/Binder;-><init>()V
const-string v0, "android.content.pm.IPackageDataObserver"
invoke-virtual {p0, p0, v0}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V
return-void
.end method
.method public asBinder()Landroid/os/IBinder;
.locals 0
return-object p0
.end method
.method public onRemoveCompleted(Ljava/lang/String;Z)V
.locals 1
iput-object p1, p0, Lorg/vinix/bootstrap/TestDataObserver;->name:Ljava/lang/String;
iput-boolean p2, p0, Lorg/vinix/bootstrap/TestDataObserver;->success:Z
iget v0, p0, Lorg/vinix/bootstrap/TestDataObserver;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestDataObserver;->calls:I
return-void
.end method
')!
	os.write_file(root + '/smali/TestDeleteObserver.smali', r'.class public Lorg/vinix/bootstrap/TestDeleteObserver;
.super Landroid/os/Binder;
.implements Landroid/content/pm/IPackageDeleteObserver;
.field public calls:I
.field public code:I
.field public name:Ljava/lang/String;
.method public constructor <init>()V
.locals 1
invoke-direct {p0}, Landroid/os/Binder;-><init>()V
const-string v0, "android.content.pm.IPackageDeleteObserver"
invoke-virtual {p0, p0, v0}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V
return-void
.end method
.method public asBinder()Landroid/os/IBinder;
.locals 0
return-object p0
.end method
.method public packageDeleted(Ljava/lang/String;I)V
.locals 1
iput-object p1, p0, Lorg/vinix/bootstrap/TestDeleteObserver;->name:Ljava/lang/String;
iput p2, p0, Lorg/vinix/bootstrap/TestDeleteObserver;->code:I
iget v0, p0, Lorg/vinix/bootstrap/TestDeleteObserver;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestDeleteObserver;->calls:I
return-void
.end method
')!
	os.write_file(root + '/smali/TestUserBroadcast.smali', r'.class public Lorg/vinix/bootstrap/TestUserBroadcast;
.super Landroid/content/BroadcastReceiver;
.field public static calls:I
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V
return-void
.end method
.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
.locals 3
const-string v0, "org.vinix.fixture.USER_BROADCAST"
invoke-virtual {p2}, Landroid/content/Intent;->getAction()Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v1, 1
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v0, "payload"
const/4 v1, 0
invoke-virtual {p2, v0, v1}, Landroid/content/Intent;->getIntExtra(Ljava/lang/String;I)I
move-result v0
const/16 v1, 0x59
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget v0, Lorg/vinix/bootstrap/TestUserBroadcast;->calls:I
add-int/lit8 v0, v0, 1
sput v0, Lorg/vinix/bootstrap/TestUserBroadcast;->calls:I
return-void
.end method
')!
	os.write_file(root + '/smali/TestPackageAccounts.smali', r'.class public Lorg/vinix/bootstrap/TestPackageAccounts;
.super Landroid/accounts/AccountManager;
.field public snapshot:[Landroid/accounts/Account;
.field public denial:Ljava/lang/SecurityException;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/accounts/AccountManager;-><init>()V
return-void
.end method
.method public getAccountsByType(Ljava/lang/String;)[Landroid/accounts/Account;
.locals 1
iget-object v0, p0, Lorg/vinix/bootstrap/TestPackageAccounts;->denial:Ljava/lang/SecurityException;
if-eqz v0, :snapshot
throw v0
:snapshot
iget-object v0, p0, Lorg/vinix/bootstrap/TestPackageAccounts;->snapshot:[Landroid/accounts/Account;
return-object v0
.end method
')!
	os.write_file(root + '/smali/TestNetwork.smali', r'.class public Lorg/vinix/bootstrap/TestNetwork;
.super Landroid/net/ConnectivityManager;
.field public state:I
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/net/ConnectivityManager;-><init>()V
return-void
.end method
.method protected nativeGetNetworkState()I
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestNetwork;->state:I
return v0
.end method
')!
	os.write_file(root + '/smali/Main.smali', main_source + intent_source + user_source + boolean_source() + subscription_source)!
	subscription_fixture(root)!
	os.write_file(root + '/smali/TestAccounts.smali', r'.class public Lorg/vinix/bootstrap/TestAccounts;
.super Landroid/accounts/AccountManager;
.field public snapshot:[Landroid/accounts/Account;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/accounts/AccountManager;-><init>()V
return-void
.end method
.method public getAccountsByType(Ljava/lang/String;)[Landroid/accounts/Account;
.locals 1
iget-object v0, p0, Lorg/vinix/bootstrap/TestAccounts;->snapshot:[Landroid/accounts/Account;
return-object v0
.end method
')!
	// Declare the callback service in the APK; scheduling must not rely on an
	// undeclared class even if the current scheduler can instantiate one.
	os.write_file(root + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap" android:versionCode="1"><uses-sdk android:minSdkVersion="28" android:targetSdkVersion="35"/><application android:label="Current API fixture"><activity android:name="org.vinix.bootstrap.Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity><service android:name="org.vinix.bootstrap.TestJobService" android:permission="android.permission.BIND_JOB_SERVICE" android:exported="false"/></application></manifest>')!
	if os.system_args([os.abs_path('build/android-native-ws/aapt2'), 'link', '-I',
		os.abs_path('build/android-framework/opensudoku/overlay/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'),
		'--manifest', root + '/AndroidManifest.xml', '-o', root + '/unsigned.apk']) != 0 {
		panic('fixture manifest link failed')
	}
	sandbox_assets(root)!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	tools := '/Users/alex/code/vinix/build/android-framework/tools'
	signer := '/Users/alex/code/vinix/build/android-native-ws/android-15/lib/apksigner.jar'
	for args in [[java, '-Xmx256m', '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'],
		['/usr/bin/zip', '-q', '-j', root + '/unsigned.apk', root + '/classes.dex'],
		[java, '-Xmx256m', '-jar', signer, 'sign', '--ks', base + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', root + '/probe.apk', root + '/unsigned.apk'],
		[java, '-Xmx256m', '-jar', signer, 'verify', '--verbose', root + '/probe.apk']] {
		if os.system_args(args) != 0 { panic('fixture build failed') }
	}
	println('CURRENT-API-FIXTURE ' + root + '/probe.apk')
}

// Parse metadata-only archives without installing them or starting their code.
fn sandbox_assets(root string) ! {
	aapt := os.abs_path('build/android-native-ws/aapt2')
	resources := os.abs_path('build/android-framework/opensudoku/overlay/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk')
	os.mkdir_all(root + '/assets/sandbox')!
	os.mkdir_all(root + '/metadata-res/values')!
	os.write_file(root + '/metadata-res/values/integers.xml', '<resources><integer name="sandbox_level">2</integer></resources>')!
	if os.system_args([aapt, 'compile', '--dir', root + '/metadata-res', '-o', root + '/metadata-res.zip']) != 0 {
		return error('metadata resource compilation failed')
	}
	for name, value in {'literal': '2', 'resource': '@integer/sandbox_level'} {
		manifest := root + '/metadata-' + name + '.xml'
		os.write_file(manifest, '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.sandboxmetadata" android:targetSandboxVersion="' + value + '"><uses-sdk android:minSdkVersion="28"/><application android:hasCode="false"/></manifest>')!
		if os.system_args([aapt, 'link', '-I', resources, '--manifest', manifest, root + '/metadata-res.zip', '-o', root + '/assets/sandbox/' + name + '.apk']) != 0 {
			return error('metadata archive link failed')
		}
	}
	// zip must retain the assets/ prefix, unlike the classes.dex insertion.
	mut zip := os.new_process('/usr/bin/zip')
	zip.set_work_folder(root)
	zip.set_args(['-q', '-r', root + '/unsigned.apk', 'assets'])
	zip.run()
	zip.wait()
	if zip.code != 0 { return error('metadata assets insertion failed') }
}
