// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const worker_type = 'Lorg/vinix/bootstrap/Worker;'
const traffic_type = 'Landroid/net/TrafficStats;'
const latch_type = 'Ljava/util/concurrent/CountDownLatch;'
const pass_marker = 'TRAFFIC-STATS-UID-PASS public-static-reflection signed-uid clear-default tag-independent thread-isolation no-inheritance bounded-worker'
const fail_marker = 'TRAFFIC-STATS-UID-FAIL'
// Host receipts qualify the signed fixture; ARM behavior needs a separate run
// against the pinned framework recorded by the delivery/production recipe.
const fixture_scope = 'Standalone aarch64 TrafficStats public static UID reflection with a null receiver, exact signed int retention, default/clear -1, independent tag state, a plain worker constructed while the main UID/tag are set, bounded two-way thread isolation and cleanup, and finally-restored original main UID/tag. Existing per-UID byte counters remain unsupported (-1L). This tests process-local thread metadata; it supplies no kernel/socket traffic accounting, privileged tagging, Google module completion, account, or authentication success. The builder receipt qualifies host source closure, DEX roundtrips and signing; ARM behavior is evidenced separately by a runtime receipt against a pinned framework.'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn helpers_source() string {
	return method('public static equal(IILjava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('public static merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;', 0, '
if-eqz p0, :secondary
if-eq p0, p1, :primary
invoke-virtual {p0, p1}, Ljava/lang/Throwable;->addSuppressed(Ljava/lang/Throwable;)V
:primary
return-object p0
:secondary
return-object p1') + method('public static state(IILjava/lang/String;)V', 1, '
invoke-static {}, ${traffic_type}->getThreadStatsUid()I
move-result v0
invoke-static {v0, p0, p2}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {}, ${traffic_type}->getThreadStatsTag()I
move-result v0
invoke-static {v0, p1, p2}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('public static await(${latch_type}Ljava/lang/String;)V', 5, '
const-wide/16 v0, 8000
sget-object v2, Ljava/util/concurrent/TimeUnit;->MILLISECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {p0, v0, v1, v2}, ${latch_type}->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v3
const/4 v4, 1
invoke-static {v3, v4, p1}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('private static arm()V', 3, '
const-string v0, "os.arch"
invoke-static {v0}, Ljava/lang/System;->getProperty(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "aarch64"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v1, 1
const-string v2, "the fixture must run in the actual aarch64 process"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {}, Landroid/os/Process;->is64Bit()Z
move-result v0
const-string v2, "the actual ARM fixture process must be 64 bit"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn reflection_source() string {
	return method('private static publicStatic(Ljava/lang/String;[Ljava/lang/Class;Ljava/lang/Class;)Ljava/lang/reflect/Method;', 5, '
const-class v0, ${traffic_type}
invoke-virtual {v0, p0, p1}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/reflect/Method;->getDeclaringClass()Ljava/lang/Class;
move-result-object v2
const-string v4, "UID methods must be declared by android.net.TrafficStats"
invoke-static {v2, v0, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v2
const-string v4, "UID methods must retain their exact primitive return types"
invoke-static {v2, p2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v2
and-int/lit8 v2, v2, 0x9
const/16 v3, 0x9
const-string v4, "UID methods must be public static for Cronet reflection"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-object v1') + method('private static shapes()V', 5, '
const/4 v0, 1
new-array v0, v0, [Ljava/lang/Class;
sget-object v1, Ljava/lang/Integer;->TYPE:Ljava/lang/Class;
const/4 v2, 0
aput-object v1, v0, v2
const-string v1, "setThreadStatsUid"
sget-object v3, Ljava/lang/Void;->TYPE:Ljava/lang/Class;
invoke-static {v1, v0, v3}, ${main_type}->publicStatic(Ljava/lang/String;[Ljava/lang/Class;Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v4
sput-object v4, ${main_type}->setUidMethod:Ljava/lang/reflect/Method;
const/4 v0, 0
new-array v0, v0, [Ljava/lang/Class;
const-string v1, "clearThreadStatsUid"
invoke-static {v1, v0, v3}, ${main_type}->publicStatic(Ljava/lang/String;[Ljava/lang/Class;Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v4
sput-object v4, ${main_type}->clearUidMethod:Ljava/lang/reflect/Method;
const-string v1, "getThreadStatsUid"
sget-object v3, Ljava/lang/Integer;->TYPE:Ljava/lang/Class;
invoke-static {v1, v0, v3}, ${main_type}->publicStatic(Ljava/lang/String;[Ljava/lang/Class;Ljava/lang/Class;)Ljava/lang/reflect/Method;
return-void') + method('public static setUid(I)V', 5, '
sget-object v0, ${main_type}->setUidMethod:Ljava/lang/reflect/Method;
const/4 v1, 0
const/4 v2, 1
new-array v2, v2, [Ljava/lang/Object;
invoke-static {p0}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
move-result-object v3
aput-object v3, v2, v1
invoke-virtual {v0, v1, v2}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v3
const-string v4, "public static UID setter invoked with null receiver must return null"
invoke-static {v3, v1, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void') + method('public static clearUid()V', 5, '
sget-object v0, ${main_type}->clearUidMethod:Ljava/lang/reflect/Method;
const/4 v1, 0
new-array v2, v1, [Ljava/lang/Object;
invoke-virtual {v0, v1, v2}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v3
const-string v4, "public static UID clear invoked with null receiver must return null"
invoke-static {v3, v1, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void')
}

fn baseline_source() string {
	mut body := '
invoke-static {}, ${traffic_type}->getThreadStatsUid()I
move-result v0
const/4 v1, -1
const-string v2, "an untouched main thread UID must default to -1"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
const v1, 0x13579
invoke-static {v1}, ${traffic_type}->setThreadStatsTag(I)V
'
	for value in ['-0x80000000', '0x7fffffff', '-0x2', '0x0', '0x2a', '-0x1'] {
		body += '
const v0, ${value}
invoke-static {v0}, ${main_type}->setUid(I)V
const-string v2, "reflection must retain the exact signed UID without changing the tag"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
invoke-static {}, ${main_type}->clearUid()V
const/4 v0, -1
const-string v2, "clear must restore default UID and retain the independent tag"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
'
	}
	body += '
invoke-static {}, ${main_type}->clearUid()V
const/4 v0, -1
const-string v2, "clearing an already cleared UID must retain the -1 default and tag"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
const/16 v0, 42
invoke-static {v0}, ${main_type}->setUid(I)V
invoke-static {}, ${traffic_type}->clearThreadStatsTag()V
const/4 v1, -1
const-string v2, "clearing the tag must leave the UID unchanged"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
const/4 v1, -2
invoke-static {v1}, ${traffic_type}->setThreadStatsTag(I)V
invoke-static {}, ${main_type}->clearUid()V
const/4 v0, -1
const-string v2, "clearing UID must retain a signed tag value"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
const/4 v0, -2
invoke-static {v0}, ${main_type}->setUid(I)V
const/4 v1, 0
invoke-static {v1}, ${traffic_type}->setThreadStatsTag(I)V
const-string v2, "setting a zero tag must leave the signed UID unchanged"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
invoke-static {}, ${traffic_type}->clearThreadStatsTag()V
const/4 v1, -1
const-string v2, "clearing a zero tag must leave a signed UID unchanged"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
invoke-static {}, ${main_type}->clearUid()V
const/4 v0, -1
const-string v2, "UID and tag must both return to independent defaults"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
return-void'
	return method('private static baseline()V', 3, body) + method('private static unsupported(I)V', 5, '
invoke-static {p0}, ${traffic_type}->getUidRxBytes(I)J
move-result-wide v0
const-wide/16 v2, -1
cmp-long v4, v0, v2
const/4 v0, 0
const-string v1, "per-UID RX byte accounting must remain explicitly unsupported (-1L)"
invoke-static {v4, v0, v1}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {p0}, ${traffic_type}->getUidTxBytes(I)J
move-result-wide v0
cmp-long v4, v0, v2
const/4 v0, 0
const-string v1, "per-UID TX byte accounting must remain explicitly unsupported (-1L)"
invoke-static {v4, v0, v1}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn restore_source() string {
	return method('private static restore(IILjava/lang/Throwable;)Ljava/lang/Throwable;', 2, '
:uid_start
const/4 v0, -1
if-ne p0, v0, :uid_set
invoke-static {}, ${traffic_type}->clearThreadStatsUid()V
goto :uid_end
:uid_set
invoke-static {p0}, ${traffic_type}->setThreadStatsUid(I)V
:uid_end
goto :tag_start
:uid_failed
move-exception v0
invoke-static {p2, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p2
:tag_start
const/4 v0, -1
if-ne p1, v0, :tag_set
invoke-static {}, ${traffic_type}->clearThreadStatsTag()V
goto :tag_end
:tag_set
invoke-static {p1}, ${traffic_type}->setThreadStatsTag(I)V
:tag_end
goto :uid_check_start
:tag_failed
move-exception v0
invoke-static {p2, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p2
:uid_check_start
invoke-static {}, ${traffic_type}->getThreadStatsUid()I
move-result v0
const-string v1, "main UID must be restored on success and failure"
invoke-static {v0, p0, v1}, ${main_type}->equal(IILjava/lang/String;)V
:uid_check_end
goto :tag_check_start
:uid_check_failed
move-exception v0
invoke-static {p2, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p2
:tag_check_start
invoke-static {}, ${traffic_type}->getThreadStatsTag()I
move-result v0
const-string v1, "main tag must be restored even if UID restoration fails"
invoke-static {v0, p1, v1}, ${main_type}->equal(IILjava/lang/String;)V
:tag_check_end
goto :done
:tag_check_failed
move-exception v0
invoke-static {p2, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p2
:done
return-object p2
.catchall {:uid_start .. :uid_end} :uid_failed
.catchall {:tag_start .. :tag_end} :tag_failed
.catchall {:uid_check_start .. :uid_check_end} :uid_check_failed
.catchall {:tag_check_start .. :tag_check_end} :tag_check_failed') +
		method('private static stopWorker(${worker_type}Ljava/lang/Throwable;)Ljava/lang/Throwable;', 3, '
if-eqz p0, :done
:release_start
iget-object v0, p0, ${worker_type}->mainChanged:${latch_type}
invoke-virtual {v0}, ${latch_type}->countDown()V
invoke-virtual {p0}, Ljava/lang/Thread;->interrupt()V
:release_end
goto :join_start
:release_failed
move-exception v0
invoke-static {p1, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p1
:join_start
const-wide/16 v0, 1000
invoke-virtual {p0, v0, v1}, Ljava/lang/Thread;->join(J)V
:join_end
goto :alive
:join_failed
move-exception v0
invoke-static {p1, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p1
:alive
invoke-virtual {p0}, Ljava/lang/Thread;->isAlive()Z
move-result v0
if-eqz v0, :done
new-instance v0, Ljava/lang/AssertionError;
const-string v2, "daemon worker must terminate within bounded cleanup"
invoke-direct {v0, v2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
invoke-static {p1, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p1
:done
return-object p1
.catchall {:release_start .. :release_end} :release_failed
.catchall {:join_start .. :join_end} :join_failed') +
		method('private static cleanup(${worker_type}IILjava/lang/Throwable;)V', 1, '
:stop_start
invoke-static {p0, p3}, ${main_type}->stopWorker(${worker_type}Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p3
:stop_end
goto :restore
:stop_failed
move-exception v0
invoke-static {p3, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p3
:restore
invoke-static {p1, p2, p3}, ${main_type}->restore(IILjava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p3
if-eqz p3, :done
throw p3
:done
return-void
.catchall {:stop_start .. :stop_end} :stop_failed')
}

fn worker_source() string {
	return '.class public final ${worker_type}\n.super Ljava/lang/Thread;\n' +
		'.field public final ready:${latch_type}\n.field public final mainChanged:${latch_type}\n' +
		'.field public volatile failure:Ljava/lang/Throwable;\n.field public volatile done:Z\n' +
		method('public constructor <init>()V', 2, '
const-string v0, "traffic-stats-uid"
invoke-direct {p0, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/String;)V
new-instance v0, ${latch_type}
const/4 v1, 1
invoke-direct {v0, v1}, ${latch_type}-><init>(I)V
iput-object v0, p0, ${worker_type}->ready:${latch_type}
new-instance v0, ${latch_type}
invoke-direct {v0, v1}, ${latch_type}-><init>(I)V
iput-object v0, p0, ${worker_type}->mainChanged:${latch_type}
return-void') + method('private finish(Ljava/lang/Throwable;)V', 1, '
:uid_start
invoke-static {}, ${main_type}->clearUid()V
:uid_end
goto :tag_start
:uid_failed
move-exception v0
invoke-static {p1, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p1
:tag_start
invoke-static {}, ${traffic_type}->clearThreadStatsTag()V
:tag_end
goto :publish
:tag_failed
move-exception v0
invoke-static {p1, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p1
:publish
iput-object p1, p0, ${worker_type}->failure:Ljava/lang/Throwable;
if-nez p1, :ready
const/4 v0, 1
iput-boolean v0, p0, ${worker_type}->done:Z
:ready
iget-object v0, p0, ${worker_type}->ready:${latch_type}
invoke-virtual {v0}, ${latch_type}->countDown()V
return-void
.catchall {:uid_start .. :uid_end} :uid_failed
.catchall {:tag_start .. :tag_end} :tag_failed') + method('public run()V', 4, '
:try_start
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
if-eqz v0, :plain
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "the plain worker must run without a Looper"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:plain
const/4 v0, -1
const/4 v1, -1
const-string v2, "worker UID/tag must default to -1 without inheriting either main value"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
const/4 v0, -2
invoke-static {v0}, ${main_type}->setUid(I)V
const v1, 0x2468a
invoke-static {v1}, ${traffic_type}->setThreadStatsTag(I)V
const-string v2, "worker must retain its own signed UID and tag"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
iget-object v2, p0, ${worker_type}->ready:${latch_type}
invoke-virtual {v2}, ${latch_type}->countDown()V
iget-object v2, p0, ${worker_type}->mainChanged:${latch_type}
const-string v3, "worker must observe main changes within its bounded await"
invoke-static {v2, v3}, ${main_type}->await(${latch_type}Ljava/lang/String;)V
const-string v2, "main UID/tag changes must leave the live worker state unchanged"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
invoke-static {}, ${main_type}->clearUid()V
const/4 v0, -1
const-string v2, "worker UID clear must preserve the worker tag"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
const v0, 0x7fffffff
invoke-static {v0}, ${main_type}->setUid(I)V
invoke-static {}, ${traffic_type}->clearThreadStatsTag()V
const/4 v1, -1
const-string v2, "worker tag clear must preserve the worker UID"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
invoke-static {}, ${main_type}->clearUid()V
const/4 v0, -1
const-string v2, "worker UID and tag must both clear independently"
invoke-static {v0, v1, v2}, ${main_type}->state(IILjava/lang/String;)V
:try_end
const/4 v3, 0
invoke-direct {p0, v3}, ${worker_type}->finish(Ljava/lang/Throwable;)V
return-void
:failed
move-exception v3
invoke-direct {p0, v3}, ${worker_type}->finish(Ljava/lang/Throwable;)V
return-void
.catchall {:try_start .. :try_end} :failed')
}

fn checks_source() string {
	mut body := '
invoke-static {}, ${traffic_type}->getThreadStatsUid()I
move-result v0
invoke-static {}, ${traffic_type}->getThreadStatsTag()I
move-result v1
const/4 v2, 0
:try_start
invoke-static {}, ${main_type}->arm()V
invoke-static {}, ${main_type}->shapes()V
invoke-static {}, ${main_type}->baseline()V
const/16 v3, 42
invoke-static {v3}, ${main_type}->setUid(I)V
const v4, 0x13579
invoke-static {v4}, ${traffic_type}->setThreadStatsTag(I)V
new-instance v5, ${worker_type}
invoke-direct {v5}, ${worker_type}-><init>()V
move-object v2, v5
const/4 v3, 1
invoke-virtual {v2, v3}, Ljava/lang/Thread;->setDaemon(Z)V
invoke-virtual {v2}, Ljava/lang/Thread;->start()V
iget-object v3, v2, ${worker_type}->ready:${latch_type}
const-string v4, "worker must establish independent UID/tag state within bounded await"
invoke-static {v3, v4}, ${main_type}->await(${latch_type}Ljava/lang/String;)V
iget-object v3, v2, ${worker_type}->failure:Ljava/lang/Throwable;
if-eqz v3, :ready
throw v3
:ready
const/16 v3, 42
const v4, 0x13579
const-string v5, "worker UID/tag writes must leave the live main state unchanged"
invoke-static {v3, v4, v5}, ${main_type}->state(IILjava/lang/String;)V
const v3, -0x80000000
invoke-static {v3}, ${main_type}->setUid(I)V
const v4, 0x3579b
invoke-static {v4}, ${traffic_type}->setThreadStatsTag(I)V
iget-object v5, v2, ${worker_type}->mainChanged:${latch_type}
invoke-virtual {v5}, ${latch_type}->countDown()V
const-wide/16 v3, 8000
invoke-virtual {v2, v3, v4}, Ljava/lang/Thread;->join(J)V
invoke-virtual {v2}, Ljava/lang/Thread;->isAlive()Z
move-result v3
const/4 v4, 0
const-string v5, "worker must terminate within the bounded join"
invoke-static {v3, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
iget-object v3, v2, ${worker_type}->failure:Ljava/lang/Throwable;
if-eqz v3, :completed
throw v3
:completed
iget-boolean v3, v2, ${worker_type}->done:Z
const/4 v4, 1
const-string v5, "worker must finish every assertion and cleanup without an exception"
invoke-static {v3, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
const v3, -0x80000000
const v4, 0x3579b
const-string v5, "worker UID/tag clears and cleanup must leave main state unchanged"
invoke-static {v3, v4, v5}, ${main_type}->state(IILjava/lang/String;)V
'
	for value in ['-0x80000000', '0x7fffffff', '-0x2', '0x0', '0x2a'] {
		body += 'const v3, ${value}\ninvoke-static {v3}, ${main_type}->unsupported(I)V\n'
	}
	body += '
:try_end
const/4 v3, 0
invoke-static {v2, v0, v1, v3}, ${main_type}->cleanup(${worker_type}IILjava/lang/Throwable;)V
return-void
:failed
move-exception v3
invoke-static {v2, v0, v1, v3}, ${main_type}->cleanup(${worker_type}IILjava/lang/Throwable;)V
return-void
.catchall {:try_start .. :try_end} :failed'
	return method('private static checks()V', 6, body)
}

fn fixture_sources() map[string]string {
	return {
		'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
			'.field private static setUidMethod:Ljava/lang/reflect/Method;\n.field private static clearUidMethod:Ljava/lang/reflect/Method;\n' +
			method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
			helpers_source() + reflection_source() + baseline_source() + restore_source() + checks_source() +
			method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {}, ${main_type}->checks()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "TrafficStats UID reflection and thread isolation passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
:try_end
return-void
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2
.catchall {:try_start .. :try_end} :failed')
		'org/vinix/bootstrap/Worker.smali': worker_source()
	}
}

fn expected_classes() []string {
	return ['org/vinix/bootstrap/Main.smali', 'org/vinix/bootstrap/Worker.smali']
}

fn fixture_method(source string, signature string) string {
	methods := source.split('.method ').filter(it.all_before('\n').ends_with(' ' + signature))
	assert methods.len == 1, 'exactly one fixture method required: ' + signature
	assert methods[0].contains('.end method'), 'unterminated fixture method: ' + signature
	return methods[0].all_after('\n').all_before('.end method')
}

fn verify_source_references(name string, source string) {
	assert !source.contains('Ljava/lang/InheritableThreadLocal;') &&
		!source.contains('->setAccessible(') && !source.contains('->getDeclaredMethod('),
		'fixture must use public platform reflection and plain worker inheritance'
	for reference in ['${traffic_type}->clearThreadStatsTag()V', '${main_type}->setUid(I)V',
		'${main_type}->clearUid()V', '${main_type}->state(IILjava/lang/String;)V', '.catchall', 'Ljava/lang/Throwable;'] {
		assert source.contains(reference), 'missing state/cleanup fixture linkage: ' + reference
	}
	if name == 'org/vinix/bootstrap/Worker.smali' {
		assert source.starts_with('.class public final ${worker_type}') && source.contains('.super Ljava/lang/Thread;')
		for reference in ['Ljava/lang/Thread;-><init>(Ljava/lang/String;)V',
			'Landroid/os/Looper;->myLooper()Landroid/os/Looper;', '${main_type}->await(${latch_type}Ljava/lang/String;)V',
			'${worker_type}->ready:${latch_type}', '${worker_type}->mainChanged:${latch_type}',
			'${worker_type}->failure:Ljava/lang/Throwable;', '${worker_type}->done:Z',
			'${worker_type}->finish(Ljava/lang/Throwable;)V',
			'"worker UID/tag must default to -1 without inheriting either main value"',
			'"main UID/tag changes must leave the live worker state unchanged"',
			'"worker UID clear must preserve the worker tag"', '"worker tag clear must preserve the worker UID"'] {
			assert source.contains(reference), 'missing actual worker assertion: ' + reference
		}
		for signature in ['<init>()V', 'run()V', 'finish(Ljava/lang/Throwable;)V'] {
			assert fixture_method(source, signature).len > 0
		}
		assert !source.contains('->join()V') && !source.contains('->await()V'), 'no unbounded worker waits'
		return
	}
	assert name == 'org/vinix/bootstrap/Main.smali' && source.starts_with('.class public final ${main_type}')
	for reference in ['.super Landroid/app/Activity;', '"setThreadStatsUid"', '"clearThreadStatsUid"',
		'"getThreadStatsUid"', 'Ljava/lang/Integer;->TYPE:Ljava/lang/Class;',
		'Ljava/lang/Void;->TYPE:Ljava/lang/Class;',
		'Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;',
		'Ljava/lang/reflect/Method;->getModifiers()I', 'Ljava/lang/reflect/Method;->getDeclaringClass()Ljava/lang/Class;',
		'Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;',
		'Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;',
		'${traffic_type}->getThreadStatsUid()I', '${traffic_type}->getThreadStatsTag()I',
		'${traffic_type}->setThreadStatsUid(I)V', '${traffic_type}->clearThreadStatsUid()V',
		'${traffic_type}->getUidRxBytes(I)J', '${traffic_type}->getUidTxBytes(I)J',
		'Ljava/lang/Thread;->setDaemon(Z)V', 'Ljava/lang/Thread;->join(J)V', 'Ljava/lang/Thread;->interrupt()V',
		'${latch_type}->await(JLjava/util/concurrent/TimeUnit;)Z',
		'Ljava/util/concurrent/TimeUnit;->MILLISECONDS:Ljava/util/concurrent/TimeUnit;',
		'Landroid/os/Process;->is64Bit()Z', '"aarch64"',
		'${main_type}->restore(IILjava/lang/Throwable;)Ljava/lang/Throwable;',
		'${main_type}->stopWorker(${worker_type}Ljava/lang/Throwable;)Ljava/lang/Throwable;',
		'"${pass_marker}"', '"${fail_marker}"',
		'"public static UID setter invoked with null receiver must return null"',
		'"public static UID clear invoked with null receiver must return null"',
		'"worker UID/tag writes must leave the live main state unchanged"',
		'"worker UID/tag clears and cleanup must leave main state unchanged"',
		'"main UID must be restored on success and failure"',
		'"main tag must be restored even if UID restoration fails"'] {
		assert source.contains(reference), 'missing actual UID fixture assertion: ' + reference
	}
	for signature in ['setUid(I)V', 'clearUid()V'] {
		body := fixture_method(source, signature)
		assert body.contains('const/4 v1, 0\n') || body.contains('const/4 v1, 0x0\n'), 'literal null reflection receiver required'
		assert body.contains('invoke-virtual {v0, v1, v2}, Ljava/lang/reflect/Method;->invoke('), 'invoke must use the literal null receiver'
	}
	baseline := fixture_method(source, 'baseline()V')
	for value in ['-0x80000000', '0x7fffffff', '-0x2', '0x0', '0x2a', '-0x1'] {
		assert baseline.contains('const v0, ${value}\n'), 'missing exact reflected signed UID case: ' + value
	}
	assert fixture_method(source, 'unsupported(I)V').contains('cmp-long'), 'unsupported byte counters require full 64-bit comparison'
	assert !source.contains('Ljava/lang/System;->setProperty(') && !source.contains('Ljava/net/Socket;') &&
		!source.contains('->tagSocket(') && !source.contains('->setThreadStatsUidInternal('),
		'fixture must only exercise thread metadata and unsupported counters'
	assert !source.contains('->join()V') && !source.contains('->await()V'), 'no unbounded main waits'
}
