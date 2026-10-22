// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn work_method(signature string, body string) string {
	return '\n.method ' + signature + '\n.locals 8\n' + body + '\n.end method\n'
}

fn work_creator(smali string, class string) ! {
	owner := 'Landroid/os/' + class + ';'
	creator := 'Landroid/os/' + class + '$VinixCreator;'
	os.write_file(smali + '/android/os/' + class + '$VinixCreator.smali',
		'.class public final ' + creator + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n' +
		work_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		work_method('public newArray(I)[Ljava/lang/Object;', 'new-array v0, p1, [Landroid/os/' + class + ';\nreturn-object v0') +
		work_method('public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 'new-instance v0, ' + owner + '\ninvoke-direct {v0, p1}, ' + owner + '-><init>(Landroid/os/Parcel;)V\nreturn-object v0'))!
}

// Value-only attribution records. No power accounting or battery attribution
// service is implied. Match Android's sorted UID/name set and ordered chains.
fn framework_work_source(smali string) ! {
	ws := 'Landroid/os/WorkSource;'
	chain := 'Landroid/os/WorkSource$WorkChain;'
	mut source := ''
	for class in ['WorkSource', 'WorkSource$WorkChain'] {
		owner := 'Landroid/os/' + class + ';'
		is_chain := class.contains('$')
		mut text := '.class public ' + if is_chain { 'final ' } else { '' } + owner + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n' +
			'.field private uids:[I\n.field private names:[Ljava/lang/String;\n.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n' +
			work_method('static constructor <clinit>()V', 'new-instance v0, Landroid/os/' + class + '$VinixCreator;\ninvoke-direct {v0}, Landroid/os/' + class + '$VinixCreator;-><init>()V\nsput-object v0, ' + owner + '->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void')
		if !is_chain { text += '.field private chains:Ljava/util/ArrayList;\n' }
		text += work_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nconst/4 v0, 0\nnew-array v1, v0, [I\niput-object v1, p0, ' + owner + '->uids:[I\n' +
			if is_chain { 'new-array v1, v0, [Ljava/lang/String;\niput-object v1, p0, ' + owner + '->names:[Ljava/lang/String;\n' } else { '' } + 'return-void')
		mut copy := if is_chain { '' } else { 'if-eqz p1, :done\n' }
		for field, kind in {'uids': '[I', 'names': '[Ljava/lang/String;'} {
			copy += 'iget-object v0, p1, ' + owner + '->' + field + ':' + kind + '\nif-eqz v0, :' + field + '_null\n' +
				'invoke-virtual {v0}, ' + kind + '->clone()Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ' + kind + '\n' +
				':' + field + '_null\niput-object v0, p0, ' + owner + '->' + field + ':' + kind + '\n'
		}
		if !is_chain {
			copy += 'iget-object v0, p1, ' + ws + '->chains:Ljava/util/ArrayList;\nif-eqz v0, :done\nnew-instance v1, Ljava/util/ArrayList;\ninvoke-direct {v1}, Ljava/util/ArrayList;-><init>()V\n' +
				'iput-object v1, p0, ' + ws + '->chains:Ljava/util/ArrayList;\ninvoke-virtual {v0}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;\nmove-result-object v0\n:copy_chain\n' +
				'invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z\nmove-result v2\nif-eqz v2, :done\ninvoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;\nmove-result-object v2\ncheck-cast v2, ' + chain + '\n' +
				'new-instance v3, ' + chain + '\ninvoke-direct {v3, v2}, ' + chain + '-><init>(' + chain + ')V\ninvoke-virtual {v1, v3}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z\ngoto :copy_chain\n:done\n'
		}
		text += work_method('public constructor <init>(' + owner + ')V', 'invoke-direct {p0}, ' + owner + '-><init>()V\n' + copy + 'return-void')
		text += work_method('public ' + if is_chain { 'getSize' } else { 'size' } + '()I', 'iget-object v0, p0, ' + owner + '->uids:[I\narray-length v0, v0\nreturn v0')
		text += work_method('public getAttributionUid()I', 'iget-object v0, p0, ' + owner + '->uids:[I\narray-length v1, v0\nif-eqz v1, :empty\nconst/4 v1, 0\naget v0, v0, v1\nreturn v0\n:empty\n' +
			if !is_chain { 'iget-object v0, p0, ' + ws + '->chains:Ljava/util/ArrayList;\nif-eqz v0, :none\ninvoke-virtual {v0}, Ljava/util/ArrayList;->isEmpty()Z\nmove-result v1\nif-nez v1, :none\nconst/4 v1, 0\ninvoke-virtual {v0, v1}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ' + chain + '\ninvoke-virtual {v0}, ' + chain + '->getAttributionUid()I\nmove-result v0\nreturn v0\n:none\n' } else { '' } +
			'const/4 v0, -1\nreturn v0')
		text += work_method('public describeContents()I', 'const/4 v0, 0\nreturn v0')
		mut write := 'iget-object v0, p0, ' + owner + '->uids:[I\narray-length v1, v0\ninvoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeIntArray([I)V\n' +
			'iget-object v0, p0, ' + owner + '->names:[Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeStringArray([Ljava/lang/String;)V\n'
		mut read := 'invoke-direct {p0}, ' + owner + '-><init>()V\ninvoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-ltz v0, :invalid\n' +
			'invoke-virtual {p1}, Landroid/os/Parcel;->createIntArray()[I\nmove-result-object v1\nif-nez v1, :uids\nif-nez v0, :invalid\nnew-array v1, v0, [I\n:uids\narray-length v2, v1\nif-lt v2, v0, :invalid\n' +
			'invoke-static {v1, v0}, Ljava/util/Arrays;->copyOf([II)[I\nmove-result-object v1\niput-object v1, p0, ' + owner + '->uids:[I\n' +
			'invoke-virtual {p1}, Landroid/os/Parcel;->createStringArray()[Ljava/lang/String;\nmove-result-object v1\nif-eqz v1, :names\narray-length v2, v1\nif-lt v2, v0, :invalid\ninvoke-static {v1, v0}, Ljava/util/Arrays;->copyOf([Ljava/lang/Object;I)[Ljava/lang/Object;\nmove-result-object v1\ncheck-cast v1, [Ljava/lang/String;\n:names\n' +
			if is_chain { 'if-eqz v1, :invalid\n' } else { '' } + 'iput-object v1, p0, ' + owner + '->names:[Ljava/lang/String;\n'
		if !is_chain {
			write += 'iget-object v0, p0, ' + ws + '->chains:Ljava/util/ArrayList;\nif-eqz v0, :no_chains\ninvoke-virtual {v0}, Ljava/util/ArrayList;->isEmpty()Z\nmove-result v1\nif-eqz v1, :chains\n:no_chains\nconst/4 v0, -1\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\nreturn-void\n:chains\n' +
				'invoke-virtual {v0}, Ljava/util/ArrayList;->size()I\nmove-result v1\ninvoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V\n' +
				'invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V\ninvoke-virtual {v0}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;\nmove-result-object v0\n:next\n' +
				'invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z\nmove-result v1\nif-eqz v1, :done\ninvoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;\nmove-result-object v1\ncheck-cast v1, Landroid/os/Parcelable;\n' +
				'invoke-virtual {p1, v1, p2}, Landroid/os/Parcel;->writeParcelable(Landroid/os/Parcelable;I)V\ngoto :next\n:done\n'
			// Android reads a second list length only for positive chain counts.
			// Canonicalize empty lists above so clearing a source remains readable.
			read += 'invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-lez v0, :done\ninvoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v1\nif-ne v0, v1, :invalid\n' +
				'new-instance v2, Ljava/util/ArrayList;\ninvoke-direct {v2}, Ljava/util/ArrayList;-><init>()V\niput-object v2, p0, ' + ws + '->chains:Ljava/util/ArrayList;\nconst-class v1, ' + chain + '\n' +
				'invoke-virtual {v1}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;\nmove-result-object v1\n:next\nif-eqz v0, :done\ninvoke-virtual {p1, v1}, Landroid/os/Parcel;->readParcelable(Ljava/lang/ClassLoader;)Landroid/os/Parcelable;\nmove-result-object v3\n' +
				'instance-of v4, v3, ' + chain + '\nif-eqz v4, :invalid\ninvoke-virtual {v2, v3}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z\nadd-int/lit8 v0, v0, -1\ngoto :next\n:done\n'
		}
		text += work_method('public writeToParcel(Landroid/os/Parcel;I)V', write + 'return-void') +
			work_method('constructor <init>(Landroid/os/Parcel;)V', read + 'return-void\n:invalid\nnew-instance v0, Landroid/os/BadParcelableException;\nconst-string v1, "invalid work attribution arrays"\ninvoke-direct {v0, v1}, Landroid/os/BadParcelableException;-><init>(Ljava/lang/String;)V\nthrow v0')
		mut compare := 'instance-of v0, p1, ' + owner + '\nif-eqz v0, :different\ncheck-cast p1, ' + owner + '\n'
		for field, kind in {'uids': '[I', 'names': '[Ljava/lang/String;'} {
			compare += 'iget-object v0, p0, ' + owner + '->' + field + ':' + kind + '\niget-object v1, p1, ' + owner + '->' + field + ':' + kind + '\n' +
				if field == 'names' && !is_chain { 'if-eqz v0, :names_done\nif-eqz v1, :names_done\n' } else { '' } +
				'invoke-static {v0, v1}, Ljava/util/Arrays;->equals(' + if kind == '[I' { '[I[I' } else { '[Ljava/lang/Object;[Ljava/lang/Object;' } + ')Z\nmove-result v0\nif-eqz v0, :different\n' +
				if field == 'names' && !is_chain { ':names_done\n' } else { '' }
		}
		if !is_chain {
			text += work_method('public diff(' + ws + ')Z', compare + 'const/4 v0, 0\nreturn v0\n:different\nconst/4 v0, 1\nreturn v0')
			compare += 'iget-object v0, p0, ' + ws + '->chains:Ljava/util/ArrayList;\niget-object v1, p1, ' + ws + '->chains:Ljava/util/ArrayList;\nif-eqz v0, :empty\ninvoke-virtual {v0}, Ljava/util/ArrayList;->isEmpty()Z\nmove-result v2\nif-nez v2, :empty\n' +
				'invoke-virtual {v0, v1}, Ljava/util/ArrayList;->equals(Ljava/lang/Object;)Z\nmove-result v0\nreturn v0\n:empty\nif-eqz v1, :equal\ninvoke-virtual {v1}, Ljava/util/ArrayList;->isEmpty()Z\nmove-result v0\nreturn v0\n:equal\n'
		}
		text += work_method('public equals(Ljava/lang/Object;)Z', compare + 'const/4 v0, 1\nreturn v0\n:different\nconst/4 v0, 0\nreturn v0')
		mut hash := 'iget-object v0, p0, ' + owner + '->uids:[I\ninvoke-static {v0}, Ljava/util/Arrays;->hashCode([I)I\nmove-result v0\n'
		if is_chain {
			hash += 'mul-int/lit8 v0, v0, 31\niget-object v1, p0, ' + owner + '->names:[Ljava/lang/String;\ninvoke-static {v1}, Ljava/util/Arrays;->hashCode([Ljava/lang/Object;)I\nmove-result v1\nadd-int/2addr v0, v1\n'
		} else {
			// diff() ignores names when one side is unnamed. Excluding names keeps
			// equal objects' hashes equal, including that legacy Android case.
			hash += 'iget-object v1, p0, ' + ws + '->chains:Ljava/util/ArrayList;\nif-eqz v1, :done\ninvoke-virtual {v1}, Ljava/util/ArrayList;->isEmpty()Z\nmove-result v2\nif-nez v2, :done\nmul-int/lit8 v0, v0, 31\ninvoke-virtual {v1}, Ljava/util/ArrayList;->hashCode()I\nmove-result v1\nadd-int/2addr v0, v1\n:done\n'
		}
		text += work_method('public hashCode()I', hash + 'return v0')
		text += work_method('public toString()Ljava/lang/String;', 'new-instance v0, Ljava/lang/StringBuilder;\nconst-string v1, "' + class + ' "\ninvoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V\n' +
			'iget-object v1, p0, ' + owner + '->uids:[I\ninvoke-static {v1}, Ljava/util/Arrays;->toString([I)Ljava/lang/String;\nmove-result-object v1\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
			'iget-object v1, p0, ' + owner + '->names:[Ljava/lang/String;\ninvoke-static {v1}, Ljava/util/Arrays;->toString([Ljava/lang/Object;)Ljava/lang/String;\nmove-result-object v1\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
			'invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\nmove-result-object v0\nreturn-object v0')
		if is_chain {
			for field, kind in {'uids': '[I', 'names': '[Ljava/lang/String;'} {
				text += work_method('public get' + if field == 'uids' { 'Uids' } else { 'Tags' } + '()' + kind,
					'iget-object v0, p0, ' + owner + '->' + field + ':' + kind + '\ninvoke-virtual {v0}, ' + kind + '->clone()Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ' + kind + '\nreturn-object v0')
			}
			text += work_method('public getAttributionTag()Ljava/lang/String;', 'iget-object v0, p0, ' + chain + '->names:[Ljava/lang/String;\narray-length v1, v0\nif-eqz v1, :empty\nconst/4 v1, 0\naget-object v0, v0, v1\nreturn-object v0\n:empty\nconst/4 v0, 0\nreturn-object v0')
			text += work_method('public addNode(ILjava/lang/String;)' + chain,
				'iget-object v0, p0, ' + chain + '->uids:[I\narray-length v1, v0\nadd-int/lit8 v2, v1, 1\ninvoke-static {v0, v2}, Ljava/util/Arrays;->copyOf([II)[I\nmove-result-object v0\naput p1, v0, v1\niput-object v0, p0, ' + chain + '->uids:[I\n' +
				'iget-object v0, p0, ' + chain + '->names:[Ljava/lang/String;\ninvoke-static {v0, v2}, Ljava/util/Arrays;->copyOf([Ljava/lang/Object;I)[Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, [Ljava/lang/String;\naput-object p2, v0, v1\niput-object v0, p0, ' + chain + '->names:[Ljava/lang/String;\nreturn-object p0')
			os.write_file(smali + '/android/os/' + class + '.smali', text)!
		} else { source = text }
		work_creator(smali, class)!
	}
	source += work_source_operations(ws, chain)
	os.write_file(smali + '/android/os/WorkSource.smali', source)!
}

fn work_source_operations(ws string, chain string) string {
	mut text := work_method('public clear()V', 'const/4 v0, 0\nnew-array v1, v0, [I\niput-object v1, p0, ' + ws + '->uids:[I\niput-object v0, p0, ' + ws + '->names:[Ljava/lang/String;\niget-object v1, p0, ' + ws + '->chains:Ljava/util/ArrayList;\nif-eqz v1, :done\ninvoke-virtual {v1}, Ljava/util/ArrayList;->clear()V\n:done\nreturn-void') +
		work_method('public isEmpty()Z', 'invoke-virtual {p0}, ' + ws + '->size()I\nmove-result v0\nif-nez v0, :no\niget-object v0, p0, ' + ws + '->chains:Ljava/util/ArrayList;\nif-eqz v0, :yes\ninvoke-virtual {v0}, Ljava/util/ArrayList;->isEmpty()Z\nmove-result v0\nreturn v0\n:yes\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0')
	for name in ['get', 'getUid'] {
		text += work_method('public ' + name + '(I)I', 'iget-object v0, p0, ' + ws + '->uids:[I\naget v0, v0, p1\nreturn v0')
	}
	for name in ['getName', 'getPackageName'] {
		text += work_method('public ' + name + '(I)Ljava/lang/String;', 'iget-object v0, p0, ' + ws + '->names:[Ljava/lang/String;\nif-nez v0, :named\nconst/4 v0, 0\nreturn-object v0\n:named\naget-object v0, v0, p1\nreturn-object v0')
	}
	text += work_method('public getWorkChains()Ljava/util/List;', 'iget-object v0, p0, ' + ws + '->chains:Ljava/util/ArrayList;\nreturn-object v0') +
		work_method('public createWorkChain()' + chain, 'iget-object v0, p0, ' + ws + '->chains:Ljava/util/ArrayList;\nif-nez v0, :make\nnew-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\niput-object v0, p0, ' + ws + '->chains:Ljava/util/ArrayList;\n:make\nnew-instance v1, ' + chain + '\ninvoke-direct {v1}, ' + chain + '-><init>()V\ninvoke-virtual {v0, v1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z\nreturn-object v1')
	for named in [false, true] {
		arg := if named { 'ILjava/lang/String;' } else { 'I' }
		text += work_method('public constructor <init>(' + arg + ')V', 'invoke-direct {p0}, ' + ws + '-><init>()V\ninvoke-virtual {p0, p1' + if named { ', p2' } else { '' } + '}, ' + ws + '->add(' + arg + ')Z\nreturn-void')
		text += work_method('public set(' + arg + ')V', 'invoke-virtual {p0}, ' + ws + '->clear()V\ninvoke-virtual {p0, p1' + if named { ', p2' } else { '' } + '}, ' + ws + '->add(' + arg + ')Z\nreturn-void')
		text += work_method('public add(' + arg + ')Z', if named {
			'invoke-static {p2}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\n'
		} else { 'const/4 v0, 0\n' } + 'invoke-direct {p0, p1, ' + if named { 'p2' } else { 'v0' } + '}, ' + ws + '->insert(ILjava/lang/String;)Z\nmove-result v0\nreturn v0')
	}
	text += work_method('private insert(ILjava/lang/String;)Z', 'iget-object v0, p0, ' + ws + '->uids:[I\narray-length v1, v0\niget-object v2, p0, ' + ws + '->names:[Ljava/lang/String;\nif-eqz v1, :search\nif-eqz p2, :unnamed\nif-eqz v2, :mixed\ngoto :search\n:unnamed\nif-nez v2, :mixed\n:search\nconst/4 v3, 0\n:next\nif-ge v3, v1, :insert\naget v4, v0, v3\nif-gt v4, p1, :insert\nif-lt v4, p1, :advance\nif-eqz p2, :duplicate\naget-object v4, v2, v3\ninvoke-virtual {v4, p2}, Ljava/lang/String;->compareTo(Ljava/lang/String;)I\nmove-result v4\nif-gtz v4, :insert\nif-eqz v4, :duplicate\n:advance\nadd-int/lit8 v3, v3, 1\ngoto :next\n:duplicate\nconst/4 v0, 0\nreturn v0\n:insert\nadd-int/lit8 v4, v1, 1\nnew-array v4, v4, [I\nconst/4 v5, 0\ninvoke-static {v0, v5, v4, v5, v3}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V\naput p1, v4, v3\nadd-int/lit8 v5, v3, 1\nsub-int v6, v1, v3\ninvoke-static {v0, v3, v4, v5, v6}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V\niput-object v4, p0, ' + ws + '->uids:[I\nif-eqz p2, :done\nadd-int/lit8 v4, v1, 1\nnew-array v4, v4, [Ljava/lang/String;\nif-eqz v1, :name\nconst/4 v7, 0\ninvoke-static {v2, v7, v4, v7, v3}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V\ninvoke-static {v2, v3, v4, v5, v6}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V\n:name\naput-object p2, v4, v3\niput-object v4, p0, ' + ws + '->names:[Ljava/lang/String;\n:done\nconst/4 v0, 1\nreturn v0\n:mixed\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "cannot mix named and unnamed work attribution"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0')
	// Copy via the deep-copy constructor, then take ownership of its new arrays.
	text += work_method('public set(' + ws + ')V', 'new-instance v0, ' + ws + '\ninvoke-direct {v0, p1}, ' + ws + '-><init>(' + ws + ')V\niget-object v1, v0, ' + ws + '->uids:[I\niput-object v1, p0, ' + ws + '->uids:[I\niget-object v1, v0, ' + ws + '->names:[Ljava/lang/String;\niput-object v1, p0, ' + ws + '->names:[Ljava/lang/String;\niget-object v1, v0, ' + ws + '->chains:Ljava/util/ArrayList;\niput-object v1, p0, ' + ws + '->chains:Ljava/util/ArrayList;\nreturn-void')
	text += work_method('public withoutNames()' + ws, 'new-instance v0, ' + ws + '\ninvoke-direct {v0, p0}, ' + ws + '-><init>(' + ws + ')V\nconst/4 v1, 0\nnew-array v2, v1, [I\niput-object v2, v0, ' + ws + '->uids:[I\niput-object v1, v0, ' + ws + '->names:[Ljava/lang/String;\niget-object v2, p0, ' + ws + '->uids:[I\nconst/4 v3, 0\n:next\narray-length v4, v2\nif-ge v3, v4, :done\naget v4, v2, v3\ninvoke-virtual {v0, v4}, ' + ws + '->add(I)Z\nadd-int/lit8 v3, v3, 1\ngoto :next\n:done\nreturn-object v0')
	return text
}
