// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The target has no binary event sink. Its host liblog discards binary records
// while returning a positive length, so it cannot supply this API's backend.
// Preserve observable API28 payload preparation, then report -ENODEV. Earlier
// encoding errors take precedence; nothing is stored, printed or authorized.
pub fn framework_event_log_classes() map[string]string {
	return {
		'android/util/EventLog': '.class public Landroid/util/EventLog;
.super Ljava/lang/Object;

.method public constructor <init>()V
.registers 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method

.method public static writeEvent(II)I
.registers 3
const/16 v0, -0x13
return v0
.end method

.method public static writeEvent(IJ)I
.registers 4
const/16 v0, -0x13
return v0
.end method

.method public static writeEvent(IF)I
.registers 3
const/16 v0, -0x13
return v0
.end method

.method public static writeEvent(ILjava/lang/String;)I
.registers 3
const/16 v0, -0x13
return v0
.end method

.method public static varargs writeEvent(I[Ljava/lang/Object;)I
.registers 10
if-eqz p1, :unavailable
const/4 v0, 0x0
const/4 v1, 0x2
array-length v2, p1
const/16 v3, 0xff
const/16 v7, 0xfe0
:next_item
if-ge v0, v2, :unavailable
if-ge v0, v3, :unavailable
aget-object v4, p1, v0
if-eqz v4, :null_item
instance-of v5, v4, Ljava/lang/String;
if-nez v5, :string_item
instance-of v5, v4, Ljava/lang/Integer;
if-nez v5, :fixed_five
instance-of v5, v4, Ljava/lang/Long;
if-nez v5, :fixed_nine
instance-of v5, v4, Ljava/lang/Float;
if-nez v5, :fixed_five
new-instance v4, Ljava/lang/IllegalArgumentException;
const-string v5, "Invalid payload item type"
invoke-direct {v4, v5}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v4
:fixed_five
const/4 v5, 0x5
goto :fixed_item
:fixed_nine
const/16 v5, 0x9
:fixed_item
add-int v6, v1, v5
if-gt v6, v7, :encoding_error
move v1, v6
goto :advance
:null_item
const/4 v5, 0x4
goto :string_length
:string_item
check-cast v4, Ljava/lang/String;
invoke-static {v4}, Landroid/util/EventLog;->vinixUtf8Length(Ljava/lang/String;)I
move-result v5
:string_length
add-int/lit8 v5, v5, 0x5
add-int v6, v1, v5
if-le v6, v7, :string_accepted
add-int/lit8 v5, v1, 0x5
if-ge v5, v7, :encoding_error
:string_accepted
move v1, v6
:advance
add-int/lit8 v0, v0, 0x1
goto :next_item
:encoding_error
const/4 v0, -0x5
return v0
:unavailable
const/16 v0, -0x13
return v0
.end method

.method private static vinixUtf8Length(Ljava/lang/String;)I
.registers 9
const/4 v0, 0x0
const/4 v1, 0x0
invoke-virtual {p0}, Ljava/lang/String;->length()I
move-result v2
const/16 v4, 0xfe0
:next_character
if-ge v0, v4, :capped
if-ge v1, v2, :done
invoke-virtual {p0, v1}, Ljava/lang/String;->charAt(I)C
move-result v3
if-eqz v3, :two_bytes
const/16 v5, 0x80
if-lt v3, v5, :one_byte
const/16 v5, 0x800
if-lt v3, v5, :two_bytes
const v5, 0xd800
if-lt v3, v5, :three_bytes
const v5, 0xdc00
if-ge v3, v5, :three_bytes
add-int/lit8 v6, v1, 0x1
if-ge v6, v2, :three_bytes
invoke-virtual {p0, v6}, Ljava/lang/String;->charAt(I)C
move-result v7
const v5, 0xdc00
if-lt v7, v5, :three_bytes
const v5, 0xe000
if-ge v7, v5, :three_bytes
add-int/lit8 v0, v0, 0x4
move v1, v6
goto :advance
:three_bytes
add-int/lit8 v0, v0, 0x3
goto :advance
:one_byte
add-int/lit8 v0, v0, 0x1
goto :advance
:two_bytes
add-int/lit8 v0, v0, 0x2
:advance
add-int/lit8 v1, v1, 0x1
goto :next_character
:capped
move v0, v4
:done
return v0
.end method
'
	}
}

pub fn framework_event_log(smali string) ! {
	classes := framework_event_log_classes()
	for name, _ in classes {
		if os.exists(smali + '/' + name + '.smali') || os.is_link(smali + '/' + name + '.smali') {
			return error('EventLog destination must be absent')
		}
	}
	for name, source in classes { os.write_file(smali + '/' + name + '.smali', source)! }
}
