// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const expected_process = package_name + ':process_packages'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const worker_type = 'Lorg/vinix/bootstrap/Worker;'
const manager_type = 'Landroid/app/ActivityManager;'
const info_type = 'Landroid/app/ActivityManager$RunningAppProcessInfo;'
const pass_marker = 'PROCESS-PACKAGES-PASS public-instance-field default-null actual-self package-not-process fresh-arrays caller-memory-state bounded-worker'
const fail_marker = 'PROCESS-PACKAGES-FAIL'
// The manifest declares a process name different from its package. Assertions
// read the actual parsed ApplicationInfo and native self record; no metadata
// is fabricated or temporarily substituted by the fixture.
const fixture_scope = 'Standalone aarch64 RunningAppProcessInfo public mutable instance String[] pkgList ABI, untouched no-arg default null, direct nullable/empty/array-alias writes, actual native self PID/UID/process name and primary package, manifest-declared process name distinct from package, independent records and fresh arrays across repeated queries, mutation isolation, getMyMemoryState preserving caller-owned pkgList, and a plain daemon worker without a Looper with bounded join/cleanup. This verifies Vinix single-primary-process metadata, not multiprocess enumeration, installed companion liveness, Google task completion, Maps rendering, imagery or authentication. Host receipts qualify source/input closure, DEX roundtrips and signing; ARM execution requires a separate runtime receipt against the pinned SDK/native pair.'

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
return-void') + method('private static different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-ne p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static present(Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-nez p0, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V', 2, '
invoke-virtual {p1, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v1, 1
invoke-static {v0, v1, p2}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('private static merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;', 0, '
if-eqz p0, :secondary
if-eq p0, p1, :primary
invoke-virtual {p0, p1}, Ljava/lang/Throwable;->addSuppressed(Ljava/lang/Throwable;)V
:primary
return-object p0
:secondary
return-object p1') + method('private static arm()V', 3, '
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

fn field_source() string {
	return method('private static field()V', 5, '
const-class v0, ${info_type}
const-string v1, "pkgList"
invoke-virtual {v0, v1}, Ljava/lang/Class;->getField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/reflect/Field;->getDeclaringClass()Ljava/lang/Class;
move-result-object v2
const-string v4, "pkgList must be declared by RunningAppProcessInfo"
invoke-static {v2, v0, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/reflect/Field;->getType()Ljava/lang/Class;
move-result-object v2
const-class v3, [Ljava/lang/String;
const-string v4, "pkgList must have exact String[] field type"
invoke-static {v2, v3, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/reflect/Field;->getModifiers()I
move-result v2
and-int/lit8 v2, v2, 0x19
const/4 v3, 1
const-string v4, "pkgList must be public, instance and mutable"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn identity_source() string {
	return method('private static identity(${info_type}Ljava/lang/String;)V', 3, '
iget v0, p0, ${info_type}->pid:I
invoke-static {}, Landroid/os/Process;->myPid()I
move-result v1
const-string v2, "native self record PID must equal the actual process PID"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
iget v0, p0, ${info_type}->uid:I
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v1
const-string v2, "native self record UID must equal the actual process UID"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
iget-object v0, p0, ${info_type}->processName:Ljava/lang/String;
const-string v2, "native processName must retain actual parsed application process metadata"
invoke-static {v0, p1, v2}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
return-void')
}

fn value_source() string {
	return method('private static valueObject(Ljava/lang/String;)V', 6, '
new-instance v0, ${info_type}
invoke-direct {v0}, ${info_type}-><init>()V
iget-object v1, v0, ${info_type}->pkgList:[Ljava/lang/String;
const/4 v2, 0
const-string v3, "untouched no-arg process info must leave pkgList null"
invoke-static {v1, v2, v3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v0}, ${manager_type}->getMyMemoryState(${info_type})V
iget-object v1, v0, ${info_type}->pkgList:[Ljava/lang/String;
const-string v3, "getMyMemoryState must leave an untouched null pkgList null"
invoke-static {v1, v2, v3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v0, p0}, ${main_type}->identity(${info_type}Ljava/lang/String;)V
new-array v1, v2, [Ljava/lang/String;
iput-object v1, v0, ${info_type}->pkgList:[Ljava/lang/String;
iget-object v3, v0, ${info_type}->pkgList:[Ljava/lang/String;
const-string v4, "direct empty pkgList assignment must retain the caller array"
invoke-static {v3, v1, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
array-length v3, v3
invoke-static {v3, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v3, 1
new-array v1, v3, [Ljava/lang/String;
const-string v4, "caller-owned-process-package"
aput-object v4, v1, v2
iput-object v1, v0, ${info_type}->pkgList:[Ljava/lang/String;
iget-object v3, v0, ${info_type}->pkgList:[Ljava/lang/String;
const-string v5, "direct pkgList assignment must preserve caller array identity"
invoke-static {v3, v1, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v0}, ${manager_type}->getMyMemoryState(${info_type})V
iget-object v3, v0, ${info_type}->pkgList:[Ljava/lang/String;
const-string v5, "getMyMemoryState must preserve the caller-owned pkgList array"
invoke-static {v3, v1, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
aget-object v3, v3, v2
const-string v5, "getMyMemoryState must preserve caller-owned pkgList contents"
invoke-static {v3, v4, v5}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
invoke-static {v0, p0}, ${main_type}->identity(${info_type}Ljava/lang/String;)V
iput-object v2, v0, ${info_type}->pkgList:[Ljava/lang/String;
iget-object v3, v0, ${info_type}->pkgList:[Ljava/lang/String;
const-string v4, "pkgList must remain directly nullable after native memory-state calls"
invoke-static {v3, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void')
}

fn enumeration_source() string {
	return method('private static self(${manager_type}Ljava/lang/String;Ljava/lang/String;)${info_type}', 6, '
invoke-virtual {p0}, ${manager_type}->getRunningAppProcesses()Ljava/util/List;
move-result-object v0
const-string v1, "native enumeration must return its supported primary-process list"
invoke-static {v0, v1}, ${main_type}->present(Ljava/lang/Object;Ljava/lang/String;)V
invoke-interface {v0}, Ljava/util/List;->size()I
move-result v1
const/4 v2, 1
const-string v3, "Vinix self enumeration must contain exactly one primary-process record"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v1, 0
invoke-interface {v0, v1}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v0
const-string v3, "native self process record must be present"
invoke-static {v0, v3}, ${main_type}->present(Ljava/lang/Object;Ljava/lang/String;)V
check-cast v0, ${info_type}
invoke-static {v0, p2}, ${main_type}->identity(${info_type}Ljava/lang/String;)V
iget-object v4, v0, ${info_type}->pkgList:[Ljava/lang/String;
const-string v3, "native enumeration must populate pkgList from primary package metadata"
invoke-static {v4, v3}, ${main_type}->present(Ljava/lang/Object;Ljava/lang/String;)V
array-length v5, v4
const-string v3, "native self pkgList must contain exactly the primary package"
invoke-static {v5, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
aget-object v4, v4, v1
const-string v3, "native pkgList must use the package name rather than the process suffix"
invoke-static {v4, p1, v3}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
return-object v0') + method('public static repeat(${manager_type}Ljava/lang/String;Ljava/lang/String;)V', 7, '
invoke-static {p0, p1, p2}, ${main_type}->self(${manager_type}Ljava/lang/String;Ljava/lang/String;)${info_type}
move-result-object v0
iget-object v1, v0, ${info_type}->pkgList:[Ljava/lang/String;
invoke-static {p0, p1, p2}, ${main_type}->self(${manager_type}Ljava/lang/String;Ljava/lang/String;)${info_type}
move-result-object v2
const-string v6, "each native enumeration must return a distinct self record"
invoke-static {v0, v2, v6}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
iget-object v3, v2, ${info_type}->pkgList:[Ljava/lang/String;
const-string v6, "each native enumeration must return a fresh package array"
invoke-static {v1, v3, v6}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v4, 0
const-string v5, "org.vinix.fixture.mutated"
aput-object v5, v1, v4
aget-object v5, v3, v4
const-string v6, "mutating one result must not alter another returned package array"
invoke-static {v5, p1, v6}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
iput-object v4, v0, ${info_type}->pkgList:[Ljava/lang/String;
invoke-static {p0, p1, p2}, ${main_type}->self(${manager_type}Ljava/lang/String;Ljava/lang/String;)${info_type}
move-result-object v4
const-string v6, "later native enumeration must not reuse the prior self record"
invoke-static {v4, v2, v6}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v6, "later native enumeration must not reuse the first mutated self record"
invoke-static {v4, v0, v6}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
iget-object v5, v4, ${info_type}->pkgList:[Ljava/lang/String;
const-string v6, "later native enumeration must not reuse the prior package array"
invoke-static {v5, v3, v6}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v6, "later native enumeration must not reuse the first mutated package array"
invoke-static {v5, v1, v6}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void')
}

fn worker_source() string {
	return '.class public final ${worker_type}\n.super Ljava/lang/Thread;\n' +
		'.field private final manager:${manager_type}\n.field private final packageName:Ljava/lang/String;\n' +
		'.field private final processName:Ljava/lang/String;\n.field public volatile failure:Ljava/lang/Throwable;\n.field public volatile done:Z\n' +
		method('public constructor <init>(${manager_type}Ljava/lang/String;Ljava/lang/String;)V', 1, '
const-string v0, "process-packages"
invoke-direct {p0, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/String;)V
iput-object p1, p0, ${worker_type}->manager:${manager_type}
iput-object p2, p0, ${worker_type}->packageName:Ljava/lang/String;
iput-object p3, p0, ${worker_type}->processName:Ljava/lang/String;
return-void') + method('public run()V', 3, '
:try_start
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
if-eqz v0, :plain
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "the background process-query worker must have no Looper"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:plain
iget-object v0, p0, ${worker_type}->manager:${manager_type}
iget-object v1, p0, ${worker_type}->packageName:Ljava/lang/String;
iget-object v2, p0, ${worker_type}->processName:Ljava/lang/String;
invoke-static {v0, v1, v2}, ${main_type}->repeat(${manager_type}Ljava/lang/String;Ljava/lang/String;)V
const/4 v0, 1
iput-boolean v0, p0, ${worker_type}->done:Z
:try_end
return-void
:failed
move-exception v0
iput-object v0, p0, ${worker_type}->failure:Ljava/lang/Throwable;
return-void
.catchall {:try_start .. :try_end} :failed')
}

fn cleanup_source() string {
	return method('private static cleanup(${worker_type}Ljava/lang/Throwable;)V', 3, '
if-eqz p0, :result
:stop_start
invoke-virtual {p0}, Ljava/lang/Thread;->isAlive()Z
move-result v0
if-eqz v0, :stop_end
invoke-virtual {p0}, Ljava/lang/Thread;->interrupt()V
const-wide/16 v0, 1000
invoke-virtual {p0, v0, v1}, Ljava/lang/Thread;->join(J)V
invoke-virtual {p0}, Ljava/lang/Thread;->isAlive()Z
move-result v0
if-eqz v0, :stop_end
new-instance v0, Ljava/lang/AssertionError;
const-string v2, "daemon process-query worker must terminate within bounded cleanup"
invoke-direct {v0, v2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
invoke-static {p1, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p1
:stop_end
goto :result
:stop_failed
move-exception v0
invoke-static {p1, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object p1
:result
if-eqz p1, :done
throw p1
:done
return-void
.catchall {:stop_start .. :stop_end} :stop_failed')
}

fn checks_source() string {
	return method('private static checks(Landroid/content/Context;)V', 8, '
const/4 v0, 0
:try_start
invoke-static {}, ${main_type}->arm()V
invoke-static {}, ${main_type}->field()V
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v1
const-string v2, "${package_name}"
const-string v3, "the actual fixture context must retain its package identity"
invoke-static {v1, v2, v3}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v2
iget-object v2, v2, Landroid/content/pm/ApplicationInfo;->processName:Ljava/lang/String;
const-string v3, "${expected_process}"
const-string v4, "the actual parsed application process must retain the declared process suffix"
invoke-static {v2, v3, v4}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
const/4 v4, 0
const-string v5, "package name and declared process name must differ for this regression"
invoke-static {v3, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v2}, ${main_type}->valueObject(Ljava/lang/String;)V
const-string v3, "activity"
invoke-virtual {p0, v3}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v3
check-cast v3, ${manager_type}
const-string v4, "the fixture must use the actual ActivityManager service"
invoke-static {v3, v4}, ${main_type}->present(Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v3, v1, v2}, ${main_type}->repeat(${manager_type}Ljava/lang/String;Ljava/lang/String;)V
new-instance v4, ${worker_type}
invoke-direct {v4, v3, v1, v2}, ${worker_type}-><init>(${manager_type}Ljava/lang/String;Ljava/lang/String;)V
move-object v0, v4
const/4 v4, 1
invoke-virtual {v0, v4}, Ljava/lang/Thread;->setDaemon(Z)V
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
invoke-static {v3, v1, v2}, ${main_type}->repeat(${manager_type}Ljava/lang/String;Ljava/lang/String;)V
const-wide/16 v5, 8000
invoke-virtual {v0, v5, v6}, Ljava/lang/Thread;->join(J)V
invoke-virtual {v0}, Ljava/lang/Thread;->isAlive()Z
move-result v4
const/4 v5, 0
const-string v6, "background native package queries must finish within a bounded join"
invoke-static {v4, v5, v6}, ${main_type}->equal(IILjava/lang/String;)V
iget-object v4, v0, ${worker_type}->failure:Ljava/lang/Throwable;
if-eqz v4, :worker_complete
throw v4
:worker_complete
iget-boolean v4, v0, ${worker_type}->done:Z
const/4 v5, 1
const-string v6, "background worker must finish all native metadata assertions"
invoke-static {v4, v5, v6}, ${main_type}->equal(IILjava/lang/String;)V
:try_end
const/4 v4, 0
invoke-static {v0, v4}, ${main_type}->cleanup(${worker_type}Ljava/lang/Throwable;)V
return-void
:failed
move-exception v4
invoke-static {v0, v4}, ${main_type}->cleanup(${worker_type}Ljava/lang/Throwable;)V
return-void
.catchall {:try_start .. :try_end} :failed')
}

fn fixture_sources() map[string]string {
	return {
		'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
			method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
			helpers_source() + field_source() + identity_source() + value_source() + enumeration_source() + cleanup_source() + checks_source() +
			method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {p0}, ${main_type}->checks(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Process package metadata passed"
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
	assert !source.contains('->setAccessible(') && !source.contains('->getDeclaredField(') &&
		!source.contains('Ljava/lang/System;->setProperty(') && !source.contains('->join()V') &&
		!source.contains('->await()V') && !source.contains('-><init>(Ljava/lang/String;I[Ljava/lang/String;)V'),
		'fixture must use public platform APIs without unbounded waits or a new constructor API'
	if name == 'org/vinix/bootstrap/Worker.smali' {
		assert source.starts_with('.class public final ${worker_type}') && source.contains('.super Ljava/lang/Thread;')
		for reference in ['Ljava/lang/Thread;-><init>(Ljava/lang/String;)V',
			'Landroid/os/Looper;->myLooper()Landroid/os/Looper;',
			'${main_type}->repeat(${manager_type}Ljava/lang/String;Ljava/lang/String;)V',
			'${worker_type}->failure:Ljava/lang/Throwable;', '${worker_type}->done:Z', '.catchall',
			'"the background process-query worker must have no Looper"'] {
			assert source.contains(reference), 'missing actual worker assertion: ' + reference
		}
		assert fixture_method(source, 'run()V').contains('move-exception')
		return
	}
	assert name == 'org/vinix/bootstrap/Main.smali' && source.starts_with('.class public final ${main_type}')
	for reference in ['.super Landroid/app/Activity;', '"pkgList"', 'const-class v3, [Ljava/lang/String;',
		'Ljava/lang/Class;->getField(Ljava/lang/String;)Ljava/lang/reflect/Field;',
		'Ljava/lang/reflect/Field;->getDeclaringClass()Ljava/lang/Class;',
		'Ljava/lang/reflect/Field;->getType()Ljava/lang/Class;', 'Ljava/lang/reflect/Field;->getModifiers()I',
		'and-int/lit8 v2, v2, 0x19', '${info_type}->pkgList:[Ljava/lang/String;',
		'${manager_type}->getMyMemoryState(${info_type})V', '${manager_type}->getRunningAppProcesses()Ljava/util/List;',
		'Landroid/os/Process;->myPid()I', 'Landroid/os/Process;->myUid()I', 'Landroid/os/Process;->is64Bit()Z',
		'Landroid/content/Context;->getPackageName()Ljava/lang/String;',
		'Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;',
		'Landroid/content/pm/ApplicationInfo;->processName:Ljava/lang/String;', '"${expected_process}"',
		'Ljava/lang/Thread;->setDaemon(Z)V', 'Ljava/lang/Thread;->join(J)V', 'Ljava/lang/Thread;->interrupt()V',
		'${worker_type}->failure:Ljava/lang/Throwable;', '${worker_type}->done:Z', '.catchall',
		'"${pass_marker}"', '"${fail_marker}"', '"untouched no-arg process info must leave pkgList null"',
		'"getMyMemoryState must preserve the caller-owned pkgList array"',
		'"native pkgList must use the package name rather than the process suffix"',
		'"each native enumeration must return a fresh package array"',
		'"mutating one result must not alter another returned package array"',
		'"package name and declared process name must differ for this regression"'] {
		assert source.contains(reference), 'missing actual process package assertion: ' + reference
	}
	values := fixture_method(source, 'valueObject(Ljava/lang/String;)V')
	assert values.count('->getMyMemoryState(') == 2, 'both null and caller-owned memory-state cases required'
	assert values.count('iput-object') == 3, 'nullable, empty and caller-array field writes required'
	assert !source.split_into_lines().map(it.trim_space()).any(it.starts_with('iput-object ') &&
		it.contains('Landroid/content/pm/ApplicationInfo;->processName:')),
		'fixture must never spoof application process metadata'
	repeat := fixture_method(source, 'repeat(${manager_type}Ljava/lang/String;Ljava/lang/String;)V')
	assert repeat.count('->self(') == 3 && repeat.contains('aput-object'), 'native array mutation and later-query isolation required'
	assert repeat.count('->different(') == 6, 'fresh self record and package-array assertions required'
}
