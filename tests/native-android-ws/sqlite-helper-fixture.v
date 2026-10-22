// SPDX-License-Identifier: GPL-2.0-or-later
// Signed guest regression for SQLiteOpenHelper's idle connection policy.
module main

import os

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	tools, java, signer := os.args[3], os.args[4], os.args[5]
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	cls := 'Lorg/vinix/bootstrap/Main;'
	helper := 'Lorg/vinix/bootstrap/Probe;'
	db := 'Landroid/database/sqlite/SQLiteDatabase;'
	base := 'Landroid/database/sqlite/SQLiteOpenHelper;'
	failure := ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "SQLite helper contract failed"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0\n'
	mut body := ''
	for mode in ['default', 'file', 'memory', 'disabled', 'zero'] {
		body += if mode == 'memory' { 'const/4 v0, 0\n' } else {
			'const-string v0, "helper-${mode}.db"\ninvoke-virtual {p0, v0}, Landroid/content/Context;->deleteDatabase(Ljava/lang/String;)Z\n'
		}
		body += 'new-instance v6, ${helper}\ninvoke-direct {v6, p0, v0}, ${helper}-><init>(Landroid/content/Context;Ljava/lang/String;)V\n'
		// Invalid input must leave the previous timeout intact.
		body += 'const-wide/16 v0, -1\n:negative_${mode}\ninvoke-virtual {v6, v0, v1}, ${base}->setIdleConnectionTimeout(J)V\n:negative_end_${mode}\ngoto :bad\n.catch Ljava/lang/IllegalArgumentException; {:negative_${mode} .. :negative_end_${mode}} :negative_ok_${mode}\n:negative_ok_${mode}\nmove-exception v0\n'
		if mode != 'default' {
			timeout := if mode == 'disabled' { '0x7fffffffffffffffL' } else if mode == 'zero' { '0' } else { '200' }
			body += 'const-wide v0, ${timeout}\ninvoke-virtual {v6, v0, v1}, ${base}->setIdleConnectionTimeout(J)V\n'
		}
		body += 'invoke-virtual {v6}, ${base}->getWritableDatabase()${db}\nmove-result-object v7\ninvoke-static {v7}, ${cls}->checkData(${db})V\n'
		for n, timeout in [i64(10), i64(-1)] {
			body += 'const-wide/16 v0, ${timeout}\n:open_${mode}_${n}\ninvoke-virtual {v6, v0, v1}, ${base}->setIdleConnectionTimeout(J)V\n:open_end_${mode}_${n}\ngoto :bad\n.catch Ljava/lang/IllegalStateException; {:open_${mode}_${n} .. :open_end_${mode}_${n}} :open_ok_${mode}_${n}\n:open_ok_${mode}_${n}\nmove-exception v0\n'
		}
		// A held transaction must survive beyond the configured deadline.
		body += 'invoke-virtual {v7}, ${db}->beginTransaction()V\nconst-wide/16 v0, 400\ninvoke-static {v0, v1}, Ljava/lang/Thread;->sleep(J)V\ninvoke-static {v7}, ${cls}->checkData(${db})V\ninvoke-virtual {v7}, ${db}->setTransactionSuccessful()V\ninvoke-virtual {v7}, ${db}->endTransaction()V\nconst-string v0, "mConnectionPoolLocked"\ninvoke-static {v7, v0}, ${cls}->readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;\nmove-result-object v5\n'
		if mode in ['file', 'zero'] {
			body += 'const/16 v4, 100\n:poll_${mode}\nconst-string v0, "mAvailablePrimaryConnection"\ninvoke-static {v5, v0}, ${cls}->readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;\nmove-result-object v0\nif-eqz v0, :evicted_${mode}\nconst-wide/16 v0, 50\ninvoke-static {v0, v1}, Ljava/lang/Thread;->sleep(J)V\nadd-int/lit8 v4, v4, -1\nif-nez v4, :poll_${mode}\ngoto :bad\n:evicted_${mode}\n'
		} else {
			body += 'const-wide/16 v0, 400\ninvoke-static {v0, v1}, Ljava/lang/Thread;->sleep(J)V\nconst-string v0, "mAvailablePrimaryConnection"\ninvoke-static {v5, v0}, ${cls}->readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;\nmove-result-object v0\nif-eqz v0, :bad\n'
		}
		body += 'invoke-static {v7}, ${cls}->checkData(${db})V\ninvoke-virtual {v6}, ${base}->close()V\nconst-wide/16 v0, 0\ninvoke-virtual {v6, v0, v1}, ${base}->setIdleConnectionTimeout(J)V\ninvoke-virtual {v6}, ${base}->getReadableDatabase()${db}\nmove-result-object v7\ninvoke-static {v7}, ${cls}->checkData(${db})V\ninvoke-virtual {v6}, ${base}->close()V\n'
	}
	os.write_file(root + '/Main.smali', '.class public ${cls}
.super Landroid/app/Activity;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method public onCreate(Landroid/os/Bundle;)V
.locals 8
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
${body}
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "SQLITE-HELPER-PASS negative open-guard active-transaction disk-eviction persistent-reopen default-disabled unlimited memory zero closed-reconfigure"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "SQLite helper idle connection checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
${failure}.end method
.method private static checkData(${db})V
.locals 4
const-string v0, "SELECT value FROM probe"
const/4 v1, 0
invoke-virtual {p0, v0, v1}, ${db}->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;
move-result-object v0
invoke-interface {v0}, Landroid/database/Cursor;->moveToFirst()Z
move-result v1
if-eqz v1, :bad
const/4 v1, 0
invoke-interface {v0, v1}, Landroid/database/Cursor;->getInt(I)I
move-result v1
const/16 v2, 42
if-ne v1, v2, :bad
invoke-interface {v0}, Landroid/database/Cursor;->close()V
return-void
${failure}.end method
.method private static readField(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
.locals 2
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
invoke-virtual {v0, p1}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/AccessibleObject;->setAccessible(Z)V
invoke-virtual {v0, p0}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
return-object v0
.end method
')!
	os.write_file(root + '/Probe.smali', '.class public ${helper}
.super ${base}
.method public constructor <init>(Landroid/content/Context;Ljava/lang/String;)V
.locals 5
move-object v0, p0
move-object v1, p1
move-object v2, p2
const/4 v3, 0
const/4 v4, 1
invoke-direct/range {v0 .. v4}, ${base}-><init>(Landroid/content/Context;Ljava/lang/String;Landroid/database/sqlite/SQLiteDatabase$CursorFactory;I)V
return-void
.end method
.method public onCreate(${db})V
.locals 1
const-string v0, "CREATE TABLE probe(value INTEGER)"
invoke-virtual {p1, v0}, ${db}->execSQL(Ljava/lang/String;)V
const-string v0, "INSERT INTO probe VALUES(42)"
invoke-virtual {p1, v0}, ${db}->execSQL(Ljava/lang/String;)V
return-void
.end method
.method public onUpgrade(${db}II)V
.locals 2
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "unexpected upgrade"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
')!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
	}
	dex := out + '/classes.dex'
	if os.exists(dex) { os.rm(dex)! }
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', dex])
	assert os.is_file(dex)
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('SQLITE-HELPER-APK ' + out + '/probe.apk')
}
