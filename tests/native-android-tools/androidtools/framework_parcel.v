// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Local object references belong to the Parcel, not its byte representation.
// Keep ATL's existing primitive encoding; this is not the kernel Binder ABI.
fn framework_parcel_binders(smali string) ! {
	path := smali + '/android/os/Parcel.smali'
	mut text := os.read_file(path)!
	// SafeParcel writers use int presence markers, including nonzero object
	// sizes rather than just 1. A byte boolean consumes only part of the marker.
	for signature in ['createTypedArray(Landroid/os/Parcelable$Creator;)[Ljava/lang/Object;',
		'createTypedArrayList(Landroid/os/Parcelable$Creator;)Ljava/util/ArrayList;',
		'readTypedArray([Ljava/lang/Object;Landroid/os/Parcelable$Creator;)V',
		'readTypedList(Ljava/util/List;Landroid/os/Parcelable$Creator;)V',
		'writeTypedArray([Landroid/os/Parcelable;I)V', 'writeTypedList(Ljava/util/List;)V'] {
		start := text.index('.method public ' + signature + '\n') or { return error('missing Parcel method: ' + signature) }
		end := start + (text[start..].index('.end method') or { return error('unterminated Parcel method') })
		body := text[start..end]
		old := if signature.starts_with('write') { '->writeBoolean(Z)V' } else { '->readBoolean()Z' }
		new := if signature.starts_with('write') { '->writeInt(I)V' } else { '->readInt()I' }
		if body.count(old) != 1 { return error('unexpected Parcel typed marker: ' + signature) }
		text = text[..start] + body.replace(old, new) + text[end..]
	}
	text += '\n.field private vinixBinders:Landroid/util/SparseArray;\n'
	methods := {
		'readStrongBinder()Landroid/os/IBinder;': '.locals 3
iget v0, p0, Landroid/os/Parcel;->pos:I
invoke-virtual {p0}, Landroid/os/Parcel;->readInt()I
move-result v1
if-nez v1, :absent
iget-object v1, p0, Landroid/os/Parcel;->vinixBinders:Landroid/util/SparseArray;
if-eqz v1, :absent
invoke-virtual {v1, v0}, Landroid/util/SparseArray;->get(I)Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/os/IBinder;
return-object v2
:absent
const/4 v2, 0
return-object v2'
		'writeStrongBinder(Landroid/os/IBinder;)V': '.locals 3
iget v0, p0, Landroid/os/Parcel;->pos:I
const/4 v1, -1
if-eqz p1, :write
const/4 v1, 0
:write
invoke-virtual {p0, v1}, Landroid/os/Parcel;->writeInt(I)V
if-eqz p1, :done
iget-object v1, p0, Landroid/os/Parcel;->vinixBinders:Landroid/util/SparseArray;
if-nez v1, :put
new-instance v1, Landroid/util/SparseArray;
invoke-direct {v1}, Landroid/util/SparseArray;-><init>()V
iput-object v1, p0, Landroid/os/Parcel;->vinixBinders:Landroid/util/SparseArray;
:put
invoke-virtual {v1, v0, p1}, Landroid/util/SparseArray;->put(ILjava/lang/Object;)V
:done
return-void'
		'writeStrongInterface(Landroid/os/IInterface;)V': '.locals 1
const/4 v0, 0
if-eqz p1, :write
invoke-interface {p1}, Landroid/os/IInterface;->asBinder()Landroid/os/IBinder;
move-result-object v0
:write
invoke-virtual {p0, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V
return-void'
		'appendFrom(Landroid/os/Parcel;II)V': '.locals 9
if-ltz p2, :bad
if-ltz p3, :bad
iget v0, p1, Landroid/os/Parcel;->size:I
if-gt p2, v0, :bad
sub-int/2addr v0, p2
if-gt p3, v0, :bad
add-int v0, p2, p3
iget-object v1, p1, Landroid/os/Parcel;->data:[B
invoke-static {v1, p2, v0}, Ljava/util/Arrays;->copyOfRange([BII)[B
move-result-object v1
iget-object v2, p1, Landroid/os/Parcel;->vinixBinders:Landroid/util/SparseArray;
if-eqz v2, :copy
invoke-virtual {v2}, Landroid/util/SparseArray;->clone()Landroid/util/SparseArray;
move-result-object v2
:copy
iget v3, p0, Landroid/os/Parcel;->pos:I
const/4 v4, 0
:bytes
if-ge v4, p3, :objects
aget-byte v5, v1, v4
invoke-virtual {p0, v5}, Landroid/os/Parcel;->writeByte(B)V
add-int/lit8 v4, v4, 1
goto :bytes
:objects
if-eqz v2, :done
invoke-virtual {v2}, Landroid/util/SparseArray;->size()I
move-result v4
:next
add-int/lit8 v4, v4, -1
if-ltz v4, :done
invoke-virtual {v2, v4}, Landroid/util/SparseArray;->keyAt(I)I
move-result v5
if-lt v5, p2, :next
add-int/lit8 v6, v5, 4
if-gt v6, v0, :next
sub-int/2addr v5, p2
add-int/2addr v5, v3
iget-object v6, p0, Landroid/os/Parcel;->vinixBinders:Landroid/util/SparseArray;
if-nez v6, :put
new-instance v6, Landroid/util/SparseArray;
invoke-direct {v6}, Landroid/util/SparseArray;-><init>()V
iput-object v6, p0, Landroid/os/Parcel;->vinixBinders:Landroid/util/SparseArray;
:put
invoke-virtual {v2, v4}, Landroid/util/SparseArray;->valueAt(I)Ljava/lang/Object;
move-result-object v7
invoke-virtual {v6, v5, v7}, Landroid/util/SparseArray;->put(ILjava/lang/Object;)V
goto :next
:bad
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Parcel append range outside source data"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:done
return-void'
		'marshall()[B': '.locals 2
iget-object v0, p0, Landroid/os/Parcel;->vinixBinders:Landroid/util/SparseArray;
if-eqz v0, :bytes
invoke-virtual {v0}, Landroid/util/SparseArray;->size()I
move-result v0
if-eqz v0, :bytes
new-instance v0, Ljava/lang/RuntimeException;
const-string v1, "Cannot marshall a Parcel containing Binder objects"
invoke-direct {v0, v1}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;)V
throw v0
:bytes
iget-object v0, p0, Landroid/os/Parcel;->data:[B
iget v1, p0, Landroid/os/Parcel;->size:I
invoke-static {v0, v1}, Ljava/util/Arrays;->copyOf([BI)[B
move-result-object v0
return-object v0'
		'recycle()V': '.locals 1
const/4 v0, 0
iput-object v0, p0, Landroid/os/Parcel;->vinixBinders:Landroid/util/SparseArray;
iput v0, p0, Landroid/os/Parcel;->pos:I
iput v0, p0, Landroid/os/Parcel;->size:I
new-array v0, v0, [B
iput-object v0, p0, Landroid/os/Parcel;->data:[B
return-void'
		'setDataSize(I)V': '.locals 2
if-ltz p1, :bad
invoke-virtual {p0, p1}, Landroid/os/Parcel;->setDataCapacity(I)V
const v0, 0x7fffffff
invoke-direct {p0, p1, v0}, Landroid/os/Parcel;->vinixRemoveBinders(II)V
iput p1, p0, Landroid/os/Parcel;->size:I
iget v0, p0, Landroid/os/Parcel;->pos:I
if-le v0, p1, :done
iput p1, p0, Landroid/os/Parcel;->pos:I
:done
return-void
:bad
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Negative Parcel data size"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0'
	}
	for signature, body in methods {
		text = framework_replace_method(text, signature, '.method public ' + signature + '\n' + body + '\n.end method')!
	}
	// Every primitive write ultimately writes bytes. Remove any object whose
	// marker is touched, even when a write changes only part of that marker.
	for record in [
		['writeByte(B)V', '    .registers 5', '    .registers 5\n    iget v0, p0, Landroid/os/Parcel;->pos:I\n    add-int/lit8 v1, v0, 1\n    invoke-direct {p0, v0, v1}, Landroid/os/Parcel;->vinixRemoveBinders(II)V'],
		['unmarshall([BII)V', '    .registers 5', '    .registers 5\n    const/4 v0, 0\n    iput-object v0, p0, Landroid/os/Parcel;->vinixBinders:Landroid/util/SparseArray;'],
	] {
		start := text.index('.method public ' + record[0] + '\n') or { return error('missing Parcel method: ' + record[0]) }
		end := start + (text[start..].index('.end method') or { return error('unterminated Parcel method') })
		body := text[start..end]
		if body.count(record[1]) != 1 { return error('unexpected Parcel method registers: ' + record[0]) }
		text = text[..start] + body.replace(record[1], record[2]) + text[end..]
	}
	text += '
.method private vinixRemoveBinders(II)V
.locals 4
iget-object v0, p0, Landroid/os/Parcel;->vinixBinders:Landroid/util/SparseArray;
if-eqz v0, :done
invoke-virtual {v0}, Landroid/util/SparseArray;->size()I
move-result v1
:next
add-int/lit8 v1, v1, -1
if-ltz v1, :done
invoke-virtual {v0, v1}, Landroid/util/SparseArray;->keyAt(I)I
move-result v2
if-ge v2, p2, :next
add-int/lit8 v3, v2, 4
if-le v3, p1, :next
invoke-virtual {v0, v1}, Landroid/util/SparseArray;->removeAt(I)V
goto :next
:done
return-void
.end method
'
	os.write_file(path, text)!
}
