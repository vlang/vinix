// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Delay Bundle values until the caller has selected their application loader.
// Independent Parcel snapshots also retain Binder references after input recycle.
pub fn framework_bundle_parcel(smali string) ! {
	base_path := smali + '/android/os/BaseBundle.smali'
	bundle_path := smali + '/android/os/Bundle.smali'
	parcel_path := smali + '/android/os/Parcel.smali'
	creator_path := smali + '/android/os/VinixBundleCreator.smali'
	interface_path := smali + '/android/os/Parcelable$ClassLoaderCreator.smali'
	mut base := os.read_file(base_path)!
	mut bundle := os.read_file(bundle_path)!
	mut parcel := os.read_file(parcel_path)!
	mut loader_interface := os.read_file(interface_path)!
	if base.contains('vinixParcelledData') || bundle.contains('vinixReadFromParcel')
		|| bundle.contains('.field public static final CREATOR:')
		|| os.exists(creator_path) || os.is_link(creator_path)
		|| !parcel.contains('vinixBinders:Landroid/util/SparseArray;')
		|| base.count('.field mMap:Landroid/util/ArrayMap;') != 1
		|| !loader_interface.contains('.implements Landroid/os/Parcelable$Creator;')
		|| loader_interface.contains('.method') {
		return error('unmodified Bundle and Binder-aware Parcel required')
	}
	if bundle_parcel_method(base, '.method public constructor <init>()V\n')!.count('->mMap:') != 1
		|| bundle_parcel_method(parcel, '.method public readBundle(Ljava/lang/ClassLoader;)Landroid/os/Bundle;\n')!.count('->readValue(') != 1
		|| bundle_parcel_method(parcel, '.method public writeBundle(Landroid/os/Bundle;)V\n')!.count('->writeMap(') != 1
		|| bundle_parcel_method(bundle, '.method public readFromParcel(Landroid/os/Parcel;)V\n')!.count('->readMap(') != 1 {
		return error('unexpected original Bundle parcel contract')
	}
	parcel = bundle_parcel_binder_values(parcel)!
	copy_signature := '.method public constructor <init>(Landroid/os/Bundle;)V\n'
	copy_constructor := bundle_parcel_method(bundle, copy_signature)!
	copy_map := '    new-instance v0, Landroid/util/ArrayMap;\n\n    iget-object v1, p1, Landroid/os/Bundle;->mMap:Landroid/util/ArrayMap;\n\n    invoke-direct {v0, v1}, Landroid/util/ArrayMap;-><init>(Landroid/util/ArrayMap;)V\n\n    iput-object v0, p0, Landroid/os/Bundle;->mMap:Landroid/util/ArrayMap;'
	if copy_constructor.count(copy_map) != 1 { return error('unexpected Bundle copy constructor') }
	// Validate all map reads before replacing special methods. Constructors and
	// putAll can read another Bundle, so a method-entry check is insufficient.
	_ = bundle_parcel_maps(base, 20)!
	_ = bundle_parcel_maps(bundle, 58)!
	bundle = bundle.replace(copy_constructor, copy_constructor.replace(copy_map,
		'    invoke-virtual {p0, p1}, Landroid/os/BaseBundle;->vinixCopyFrom(Landroid/os/BaseBundle;)V'))
	clear_signature := '.method public clear()V\n'
	clear := bundle_parcel_method(bundle, clear_signature)!
	clear_map := '    iget-object v0, p0, Landroid/os/Bundle;->mMap:Landroid/util/ArrayMap;\n\n    invoke-virtual {v0}, Landroid/util/ArrayMap;->clear()V'
	if clear.count(clear_map) != 1 { return error('unexpected Bundle clear') }
	bundle = bundle.replace(clear, clear.replace(clear_map,
		'    invoke-virtual {p0}, Landroid/os/BaseBundle;->vinixClear()V'))
	bundle = bundle_parcel_replace(bundle, '.method public readFromParcel(Landroid/os/Parcel;)V\n', '.locals 1
invoke-static {p1}, Landroid/os/BaseBundle;->vinixReadLength(Landroid/os/Parcel;)I
move-result v0
invoke-virtual {p0, p1, v0}, Landroid/os/BaseBundle;->vinixReadFromParcel(Landroid/os/Parcel;I)V
return-void')!
	bundle = bundle_parcel_replace(bundle, '.method public isParcelled()Z\n', '.locals 1
invoke-virtual {p0}, Landroid/os/BaseBundle;->vinixIsParcelled()Z
move-result v0
return v0')!
	bundle = bundle_parcel_replace(bundle, '.method public declared-synchronized toString()Ljava/lang/String;\n', '.locals 2
invoke-virtual {p0}, Landroid/os/BaseBundle;->vinixIsParcelled()Z
move-result v0
if-eqz v0, :decoded
const-string v0, "Bundle[parcelled]"
return-object v0
:decoded
new-instance v0, Ljava/lang/StringBuilder;
const-string v1, "Bundle["
invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
iget-object v1, p0, Landroid/os/Bundle;->mMap:Landroid/util/ArrayMap;
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;
const-string v1, "]"
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v0
return-object v0')!
	base = bundle_parcel_maps(base, 20)!
	bundle = bundle_parcel_maps(bundle, 55)!
	base += bundle_parcel_base_methods()
	for signature in ['.method final declared-synchronized vinixGetMap()Landroid/util/ArrayMap;\n',
		'.method final declared-synchronized vinixReadFromParcel(Landroid/os/Parcel;I)V\n',
		'.method final declared-synchronized vinixWriteToParcel(Landroid/os/Parcel;)V\n',
		'.method final declared-synchronized vinixClear()V\n',
		'.method final declared-synchronized vinixIsParcelled()Z\n'] {
		base = bundle_parcel_lock(base, signature)!
	}
	bundle = bundle_parcel_lock(bundle, '.method public declared-synchronized toString()Ljava/lang/String;\n')!
	bundle += '\n.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n
.method public writeToParcel(Landroid/os/Parcel;I)V
.locals 0
invoke-virtual {p0, p1}, Landroid/os/BaseBundle;->vinixWriteToParcel(Landroid/os/Parcel;)V
return-void
.end method

.method vinixClassLoader()Ljava/lang/ClassLoader;
.locals 1
iget-object v0, p0, Landroid/os/Bundle;->mClassLoader:Ljava/lang/ClassLoader;
return-object v0
.end method
'
	clinit := bundle_parcel_method(bundle, '.method static constructor <clinit>()V\n')!
	if clinit.count('    return-void') != 1 { return error('unexpected Bundle initializer') }
	bundle = bundle.replace(clinit, clinit.replace('    return-void',
		'    new-instance v0, Landroid/os/VinixBundleCreator;\n    invoke-direct {v0}, Landroid/os/VinixBundleCreator;-><init>()V\n    sput-object v0, Landroid/os/Bundle;->CREATOR:Landroid/os/Parcelable$Creator;\n    return-void'))
	parcel = bundle_parcel_replace(parcel, '.method public readBundle()Landroid/os/Bundle;\n', '.locals 1
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/os/Parcel;->readBundle(Ljava/lang/ClassLoader;)Landroid/os/Bundle;
move-result-object v0
return-object v0')!
	parcel = bundle_parcel_replace(parcel, '.method public readBundle(Ljava/lang/ClassLoader;)Landroid/os/Bundle;\n', '.locals 2
invoke-static {p0}, Landroid/os/BaseBundle;->vinixReadLength(Landroid/os/Parcel;)I
move-result v0
const/4 v1, -1
if-ne v0, v1, :present
const/4 v0, 0
return-object v0
:present
new-instance v1, Landroid/os/Bundle;
invoke-direct {v1}, Landroid/os/Bundle;-><init>()V
if-eqz p1, :read
invoke-virtual {v1, p1}, Landroid/os/Bundle;->setClassLoader(Ljava/lang/ClassLoader;)V
:read
invoke-virtual {v1, p0, v0}, Landroid/os/BaseBundle;->vinixReadFromParcel(Landroid/os/Parcel;I)V
return-object v1')!
	parcel = bundle_parcel_replace(parcel, '.method public writeBundle(Landroid/os/Bundle;)V\n', '.locals 1
if-nez p1, :present
const/4 v0, -1
invoke-virtual {p0, v0}, Landroid/os/Parcel;->writeInt(I)V
return-void
:present
invoke-virtual {p1, p0}, Landroid/os/BaseBundle;->vinixWriteToParcel(Landroid/os/Parcel;)V
return-void')!
	parcel = bundle_parcel_replace(parcel, '.method public readParcelable(Ljava/lang/ClassLoader;)Landroid/os/Parcelable;\n', '.locals 3
invoke-virtual {p0}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v0
if-nez v0, :present
const/4 v0, 0
return-object v0
:present
move-object v1, p1
if-nez v1, :loader
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v1
:loader
:try_start
const/4 v2, 0
invoke-static {v0, v2, v1}, Ljava/lang/Class;->forName(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;
move-result-object v1
const-class v2, Landroid/os/Parcelable;
invoke-virtual {v2, v1}, Ljava/lang/Class;->isAssignableFrom(Ljava/lang/Class;)Z
move-result v2
if-eqz v2, :bad
const-string v2, "CREATOR"
invoke-virtual {v1, v2}, Ljava/lang/Class;->getField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/reflect/Field;->getModifiers()I
move-result v2
and-int/lit8 v2, v2, 8
if-eqz v2, :bad
const/4 v2, 0
invoke-virtual {v1, v2}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v1
instance-of v2, v1, Landroid/os/Parcelable$Creator;
if-eqz v2, :bad
check-cast v1, Landroid/os/Parcelable$Creator;
:try_end
.catch Ljava/lang/ReflectiveOperationException; {:try_start .. :try_end} :reflection
instance-of v2, v1, Landroid/os/Parcelable$ClassLoaderCreator;
if-eqz v2, :ordinary
check-cast v1, Landroid/os/Parcelable$ClassLoaderCreator;
invoke-interface {v1, p0, p1}, Landroid/os/Parcelable$ClassLoaderCreator;->createFromParcel(Landroid/os/Parcel;Ljava/lang/ClassLoader;)Ljava/lang/Object;
move-result-object v0
goto :result
:ordinary
invoke-interface {v1, p0}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v0
:result
check-cast v0, Landroid/os/Parcelable;
return-object v0
:reflection
move-exception v0
new-instance v1, Landroid/os/BadParcelableException;
invoke-direct {v1}, Landroid/os/BadParcelableException;-><init>()V
invoke-virtual {v1, v0}, Ljava/lang/Throwable;->initCause(Ljava/lang/Throwable;)Ljava/lang/Throwable;
throw v1
:bad
new-instance v0, Landroid/os/BadParcelableException;
invoke-direct {v0}, Landroid/os/BadParcelableException;-><init>()V
throw v0')!
	// No files change until every source and destination guard has passed.
	os.write_file(base_path, base)!
	bundle += framework_account_interaction_bundle_accessor()
	os.write_file(bundle_path, bundle)!
	os.write_file(parcel_path, parcel)!
	loader_interface += '\n.method public abstract createFromParcel(Landroid/os/Parcel;Ljava/lang/ClassLoader;)Ljava/lang/Object;\n.end method\n'
	os.write_file(interface_path, loader_interface)!
	os.write_file(creator_path, bundle_parcel_creator())!
}

fn bundle_parcel_method(text string, signature string) !string {
	if text.count(signature) != 1 { return error('missing or duplicate Bundle method: ' + signature) }
	start := text.index(signature) or { return error('missing Bundle method') }
	end := text[start..].index('.end method') or { return error('unterminated Bundle method') }
	return text[start..start + end + '.end method'.len]
}

fn bundle_parcel_replace(text string, signature string, body string) !string {
	original := bundle_parcel_method(text, signature)!
	return text.replace(original, signature + body + '\n.end method')
}

// Value containers must use the same reference table as direct Binder writes.
// The original tag emitted no reference and its reader invented a new Binder.
fn bundle_parcel_binder_values(text string) !string {
	read := bundle_parcel_method(text, '.method public readValue(Ljava/lang/ClassLoader;)Ljava/lang/Object;\n')!
	write := bundle_parcel_method(text, '.method public writeValue(Ljava/lang/Object;)V\n')!
	old_read := '    new-instance v0, Landroid/os/Binder;\n\n    invoke-direct {v0}, Landroid/os/Binder;-><init>()V'
	old_write := '    instance-of v0, p1, Landroid/os/Binder;

    if-eqz v0, :cond_16e

    const/16 v0, 0x15

    invoke-virtual {p0, v0}, Landroid/os/Parcel;->writeInt(I)V

    goto/16 :goto_6'
	if read.count(old_read) != 1 || write.count(old_write) != 1 {
		return error('unexpected original Parcel Binder value branch')
	}
	new_read := '    invoke-virtual {p0}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;\n\n    move-result-object v0'
	new_write := '    instance-of v0, p1, Landroid/os/IBinder;

    if-eqz v0, :cond_16e

    const/16 v0, 0x15

    invoke-virtual {p0, v0}, Landroid/os/Parcel;->writeInt(I)V

    check-cast p1, Landroid/os/IBinder;

    invoke-virtual {p0, p1}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V

    goto/16 :goto_6'
	return text.replace(read, read.replace(old_read, new_read)).replace(write,
		write.replace(old_write, new_write))
}

// ACC_DECLARED_SYNCHRONIZED is reflection metadata in DEX. Non-native methods
// need explicit monitor instructions, including an exceptional unlock path.
fn bundle_parcel_lock(text string, signature string) !string {
	original := bundle_parcel_method(text, signature)!
	lines := original.split('\n')
	if lines.len < 4 || !lines[1].starts_with('.locals ') || lines[1] == '.locals 0' {
		return error('Bundle lock requires an exception register')
	}
	mut output := [lines[0], lines[1], 'monitor-enter p0', ':vinix_lock_start']
	mut return_instruction := ''
	for line in lines[2..lines.len - 1] {
		if line.starts_with('return') {
			if return_instruction != '' && return_instruction != line {
				return error('inconsistent Bundle lock returns')
			}
			return_instruction = line
			output << 'goto :vinix_unlock'
		} else { output << line }
	}
	if return_instruction == '' { return error('Bundle lock requires a return') }
	output << [':vinix_lock_end', '.catchall {:vinix_lock_start .. :vinix_lock_end} :vinix_lock_failed',
		':vinix_unlock', 'monitor-exit p0', return_instruction, ':vinix_lock_failed',
		'move-exception v0', 'monitor-exit p0', 'throw v0', '.end method']
	return text.replace(original, output.join('\n'))
}

fn bundle_parcel_maps(text string, expected int) !string {
	mut lines := []string{}
	mut count := 0
	for line in text.split('\n') {
		trimmed := line.trim_space()
		if trimmed.starts_with('iget-object ') && trimmed.contains(';->mMap:Landroid/util/ArrayMap;') {
			parts := trimmed['iget-object '.len..].split(', ')
			if parts.len != 3 || parts[2] !in ['Landroid/os/BaseBundle;->mMap:Landroid/util/ArrayMap;', 'Landroid/os/Bundle;->mMap:Landroid/util/ArrayMap;', 'Landroid/os/PersistableBundle;->mMap:Landroid/util/ArrayMap;'] {
				return error('unrecognized Bundle map read')
			}
			lines << '    invoke-virtual {' + parts[1] + '}, Landroid/os/BaseBundle;->vinixGetMap()Landroid/util/ArrayMap;'
			lines << '    move-result-object ' + parts[0]
			count++
		} else { lines << line }
	}
	if count != expected { return error('unexpected Bundle map read count: ' + count.str() + ', expected ' + expected.str()) }
	return lines.join('\n')
}

fn bundle_parcel_creator() string {
	return '.class public final Landroid/os/VinixBundleCreator;
.super Ljava/lang/Object;
.implements Landroid/os/Parcelable$ClassLoaderCreator;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
.locals 1
const/4 v0, 0
invoke-virtual {p0, p1, v0}, Landroid/os/VinixBundleCreator;->createFromParcel(Landroid/os/Parcel;Ljava/lang/ClassLoader;)Ljava/lang/Object;
move-result-object v0
return-object v0
.end method
.method public createFromParcel(Landroid/os/Parcel;Ljava/lang/ClassLoader;)Ljava/lang/Object;
.locals 1
new-instance v0, Landroid/os/Bundle;
invoke-direct {v0}, Landroid/os/Bundle;-><init>()V
if-eqz p2, :read
invoke-virtual {v0, p2}, Landroid/os/Bundle;->setClassLoader(Ljava/lang/ClassLoader;)V
:read
invoke-virtual {v0, p1}, Landroid/os/Bundle;->readFromParcel(Landroid/os/Parcel;)V
return-object v0
.end method
.method public newArray(I)[Ljava/lang/Object;
.locals 1
new-array v0, p1, [Landroid/os/Bundle;
return-object v0
.end method
'
}

fn bundle_parcel_base_methods() string {
	return '\n.field private vinixParcelledData:Landroid/os/Parcel;

.method vinixClassLoader()Ljava/lang/ClassLoader;
.locals 1
const/4 v0, 0
return-object v0
.end method

.method final declared-synchronized vinixGetMap()Landroid/util/ArrayMap;
.locals 3
iget-object v0, p0, Landroid/os/BaseBundle;->vinixParcelledData:Landroid/os/Parcel;
if-eqz v0, :done
new-instance v1, Landroid/util/ArrayMap;
invoke-direct {v1}, Landroid/util/ArrayMap;-><init>()V
const/4 v2, 0
invoke-virtual {v0, v2}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v0}, Landroid/os/Parcel;->dataSize()I
move-result v2
if-eqz v2, :decoded
invoke-virtual {p0}, Landroid/os/BaseBundle;->vinixClassLoader()Ljava/lang/ClassLoader;
move-result-object v2
invoke-virtual {v0, v1, v2}, Landroid/os/Parcel;->readMap(Ljava/util/Map;Ljava/lang/ClassLoader;)V
invoke-virtual {v0}, Landroid/os/Parcel;->dataAvail()I
move-result v2
if-eqz v2, :decoded
new-instance v2, Landroid/os/BadParcelableException;
invoke-direct {v2}, Landroid/os/BadParcelableException;-><init>()V
throw v2
:decoded
iput-object v1, p0, Landroid/os/BaseBundle;->mMap:Landroid/util/ArrayMap;
const/4 v2, 0
iput-object v2, p0, Landroid/os/BaseBundle;->vinixParcelledData:Landroid/os/Parcel;
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
:done
iget-object v0, p0, Landroid/os/BaseBundle;->mMap:Landroid/util/ArrayMap;
return-object v0
.end method

.method static vinixReadLength(Landroid/os/Parcel;)I
.locals 2
invoke-virtual {p0}, Landroid/os/Parcel;->dataAvail()I
move-result v0
const/4 v1, 4
if-lt v0, v1, :bad
invoke-virtual {p0}, Landroid/os/Parcel;->readInt()I
move-result v0
return v0
:bad
new-instance v0, Landroid/os/BadParcelableException;
invoke-direct {v0}, Landroid/os/BadParcelableException;-><init>()V
throw v0
.end method

.method final declared-synchronized vinixReadFromParcel(Landroid/os/Parcel;I)V
.locals 3
if-ltz p2, :bad
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
if-eqz p2, :replace
# Validate by subtraction to avoid an overflowing offset + length.
const/4 v2, 4
if-lt p2, v2, :bad_copy
invoke-virtual {p1}, Landroid/os/Parcel;->dataAvail()I
move-result v1
const/4 v2, 4
if-lt v1, v2, :bad_copy
sub-int/2addr v1, v2
if-gt p2, v1, :bad_copy
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v1
const v2, 0x4c444e42
if-ne v1, v2, :bad_copy
invoke-virtual {p1}, Landroid/os/Parcel;->dataPosition()I
move-result v1
invoke-virtual {v0, p1, v1, p2}, Landroid/os/Parcel;->appendFrom(Landroid/os/Parcel;II)V
add-int v1, v1, p2
invoke-virtual {p1, v1}, Landroid/os/Parcel;->setDataPosition(I)V
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
:replace
iget-object v1, p0, Landroid/os/BaseBundle;->vinixParcelledData:Landroid/os/Parcel;
if-eqz v1, :store
invoke-virtual {v1}, Landroid/os/Parcel;->recycle()V
:store
iput-object v0, p0, Landroid/os/BaseBundle;->vinixParcelledData:Landroid/os/Parcel;
new-instance v1, Landroid/util/ArrayMap;
invoke-direct {v1}, Landroid/util/ArrayMap;-><init>()V
iput-object v1, p0, Landroid/os/BaseBundle;->mMap:Landroid/util/ArrayMap;
return-void
:bad_copy
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
:bad
new-instance v0, Landroid/os/BadParcelableException;
invoke-direct {v0}, Landroid/os/BadParcelableException;-><init>()V
throw v0
.end method

.method final vinixCopyFrom(Landroid/os/BaseBundle;)V
.locals 4
# Destination is unpublished. Lock the source against decode/recycle.
monitor-enter p1
:try_start
iget-object v0, p1, Landroid/os/BaseBundle;->vinixParcelledData:Landroid/os/Parcel;
if-eqz v0, :map
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v1
const/4 v2, 0
invoke-virtual {v0}, Landroid/os/Parcel;->dataSize()I
move-result v3
invoke-virtual {v1, v0, v2, v3}, Landroid/os/Parcel;->appendFrom(Landroid/os/Parcel;II)V
invoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V
iput-object v1, p0, Landroid/os/BaseBundle;->vinixParcelledData:Landroid/os/Parcel;
goto :done
:map
new-instance v0, Landroid/util/ArrayMap;
iget-object v1, p1, Landroid/os/BaseBundle;->mMap:Landroid/util/ArrayMap;
invoke-direct {v0, v1}, Landroid/util/ArrayMap;-><init>(Landroid/util/ArrayMap;)V
iput-object v0, p0, Landroid/os/BaseBundle;->mMap:Landroid/util/ArrayMap;
:done
:try_end
.catchall {:try_start .. :try_end} :failed
monitor-exit p1
return-void
:failed
move-exception v0
monitor-exit p1
throw v0
.end method

.method final declared-synchronized vinixWriteToParcel(Landroid/os/Parcel;)V
.locals 4
iget-object v0, p0, Landroid/os/BaseBundle;->vinixParcelledData:Landroid/os/Parcel;
if-eqz v0, :map
invoke-virtual {v0}, Landroid/os/Parcel;->dataSize()I
move-result v1
invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V
if-eqz v1, :done
const v2, 0x4c444e42
invoke-virtual {p1, v2}, Landroid/os/Parcel;->writeInt(I)V
const/4 v2, 0
invoke-virtual {p1, v0, v2, v1}, Landroid/os/Parcel;->appendFrom(Landroid/os/Parcel;II)V
return-void
:map
iget-object v0, p0, Landroid/os/BaseBundle;->mMap:Landroid/util/ArrayMap;
invoke-virtual {v0}, Landroid/util/ArrayMap;->size()I
move-result v1
if-nez v1, :nonempty
const/4 v1, 0
invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V
return-void
:nonempty
invoke-virtual {p1}, Landroid/os/Parcel;->dataPosition()I
move-result v1
const/4 v2, -1
invoke-virtual {p1, v2}, Landroid/os/Parcel;->writeInt(I)V
const v2, 0x4c444e42
invoke-virtual {p1, v2}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {p1}, Landroid/os/Parcel;->dataPosition()I
move-result v2
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeMap(Ljava/util/Map;)V
invoke-virtual {p1}, Landroid/os/Parcel;->dataPosition()I
move-result v3
sub-int v2, v3, v2
invoke-virtual {p1, v1}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {p1, v2}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {p1, v3}, Landroid/os/Parcel;->setDataPosition(I)V
:done
return-void
.end method

.method final declared-synchronized vinixClear()V
.locals 1
iget-object v0, p0, Landroid/os/BaseBundle;->vinixParcelledData:Landroid/os/Parcel;
if-eqz v0, :clear
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
const/4 v0, 0
iput-object v0, p0, Landroid/os/BaseBundle;->vinixParcelledData:Landroid/os/Parcel;
:clear
iget-object v0, p0, Landroid/os/BaseBundle;->mMap:Landroid/util/ArrayMap;
invoke-virtual {v0}, Landroid/util/ArrayMap;->clear()V
return-void
.end method

.method final declared-synchronized vinixIsParcelled()Z
.locals 1
iget-object v0, p0, Landroid/os/BaseBundle;->vinixParcelledData:Landroid/os/Parcel;
if-eqz v0, :no
const/4 v0, 1
return v0
:no
const/4 v0, 0
return v0
.end method
'
}
