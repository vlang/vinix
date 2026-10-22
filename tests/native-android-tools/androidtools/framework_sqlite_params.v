// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// OpenParams is an immutable snapshot. Reuse the existing SQLite engine and
// its flag, cursor factory and corruption-handler paths rather than a new DB.
fn framework_sqlite_params(smali string) ! {
	params := 'Landroid/database/sqlite/SQLiteDatabase$OpenParams;'
	builder := 'Landroid/database/sqlite/SQLiteDatabase$OpenParams$Builder;'
	fields := {'OpenFlags': 'I', 'CursorFactory': 'Landroid/database/sqlite/SQLiteDatabase$CursorFactory;',
		'ErrorHandler': 'Landroid/database/DatabaseErrorHandler;'}
	mut value := '.class public final ' + params + '\n.super Ljava/lang/Object;\n'
	mut build := '.class public final ' + builder + '\n.super Ljava/lang/Object;\n'
	mut snapshot := '.method constructor <init>(' + builder + ')V\n.locals 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\n'
	mut copy := '.method public constructor <init>(' + params + ')V\n.locals 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\n'
	for name, kind in fields {
		op := if kind == 'I' { '' } else { '-object' }
		value += '.field final m' + name + ':' + kind + '\n'
		build += '.field m' + name + ':' + kind + '\n'
		snapshot += 'iget' + op + ' v0, p1, ' + builder + '->m' + name + ':' + kind + '\niput' + op + ' v0, p0, ' + params + '->m' + name + ':' + kind + '\n'
		copy += 'iget' + op + ' v0, p1, ' + params + '->m' + name + ':' + kind + '\niput' + op + ' v0, p0, ' + builder + '->m' + name + ':' + kind + '\n'
		value += '.method public get' + name + '()' + kind + '\n.locals 1\niget' + op + ' v0, p0, ' + params + '->m' + name + ':' + kind + '\nreturn' + op + ' v0\n.end method\n'
		build += '.method public set' + name + '(' + kind + ')' + builder + '\n.locals 0\niput' + op + ' p1, p0, ' + builder + '->m' + name + ':' + kind + '\nreturn-object p0\n.end method\n'
	}
	value += snapshot + 'return-void\n.end method\n' +
		'.method public toBuilder()' + builder + '\n.locals 1\nnew-instance v0, ' + builder + '\ninvoke-direct {v0, p0}, ' + builder + '-><init>(' + params + ')V\nreturn-object v0\n.end method\n'
	build += copy + 'return-void\n.end method\n' +
		'.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
		'.method public build()' + params + '\n.locals 1\nnew-instance v0, ' + params + '\ninvoke-direct {v0, p0}, ' + params + '-><init>(' + builder + ')V\nreturn-object v0\n.end method\n'
	for operation in ['add', 'remove'] {
		build += '.method public ' + operation + 'OpenFlags(I)' + builder + '\n.locals 1\niget v0, p0, ' + builder + '->mOpenFlags:I\n' +
			if operation == 'add' { 'or-int/2addr v0, p1\n' } else { 'not-int p1, p1\nand-int/2addr v0, p1\n' } +
			'iput v0, p0, ' + builder + '->mOpenFlags:I\nreturn-object p0\n.end method\n'
	}
	build += '.method public isWriteAheadLoggingEnabled()Z\n.locals 2\niget v0, p0, ' + builder + '->mOpenFlags:I\nconst/high16 v1, 0x20000000\nand-int/2addr v0, v1\nif-eqz v0, :done\nconst/4 v0, 1\n:done\nreturn v0\n.end method\n' +
		'.method public setWriteAheadLoggingEnabled(Z)V\n.locals 1\nconst/high16 v0, 0x20000000\nif-eqz p1, :off\ninvoke-virtual {p0, v0}, ' + builder + '->addOpenFlags(I)' + builder + '\nreturn-void\n:off\ninvoke-virtual {p0, v0}, ' + builder + '->removeOpenFlags(I)' + builder + '\nreturn-void\n.end method\n'
	os.write_file(smali + '/android/database/sqlite/SQLiteDatabase$OpenParams.smali', value)!
	os.write_file(smali + '/android/database/sqlite/SQLiteDatabase$OpenParams$Builder.smali', build)!
	path := smali + '/android/database/sqlite/SQLiteDatabase.smali'
	mut db := os.read_file(path)!
	db = framework_replace_method(db, 'openDatabase(Ljava/lang/String;' + params + ')Landroid/database/sqlite/SQLiteDatabase;',
		'.method public static openDatabase(Ljava/lang/String;' + params + ')Landroid/database/sqlite/SQLiteDatabase;\n.locals 3\n' +
		'iget-object v0, p1, ' + params + '->mCursorFactory:Landroid/database/sqlite/SQLiteDatabase$CursorFactory;\n' +
		'iget v1, p1, ' + params + '->mOpenFlags:I\niget-object v2, p1, ' + params + '->mErrorHandler:Landroid/database/DatabaseErrorHandler;\n' +
		'invoke-static {p0, v0, v1, v2}, Landroid/database/sqlite/SQLiteDatabase;->openDatabase(Ljava/lang/String;Landroid/database/sqlite/SQLiteDatabase$CursorFactory;ILandroid/database/DatabaseErrorHandler;)Landroid/database/sqlite/SQLiteDatabase;\nmove-result-object v0\nreturn-object v0\n.end method')!
	db = framework_replace_method(db, 'openDatabase(Ljava/io/File;' + params + ')Landroid/database/sqlite/SQLiteDatabase;',
		'.method public static openDatabase(Ljava/io/File;' + params + ')Landroid/database/sqlite/SQLiteDatabase;\n.locals 1\ninvoke-virtual {p0}, Ljava/io/File;->getPath()Ljava/lang/String;\nmove-result-object v0\n' +
		'invoke-static {v0, p1}, Landroid/database/sqlite/SQLiteDatabase;->openDatabase(Ljava/lang/String;' + params + ')Landroid/database/sqlite/SQLiteDatabase;\nmove-result-object v0\nreturn-object v0\n.end method')!
	os.write_file(path, db)!
}
