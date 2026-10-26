// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Account is a value, not a stored login. Match the three-String AOSP parcel
// contract (name, type, accessId), preserving the opaque access ID without
// granting account visibility or pretending that an account service exists.
// Reference: frameworks/base/core/java/android/accounts/Account.java,
// blob 76735b6473894ee52cf598ef1caf8e73c4b65826.
fn account_parcel_method(signature string, locals int, body string) string {
 return '\n.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn account_parcel_replace(source string, signature string, replacement string) !string {
 mut start := -1
 mut end := -1
 mut offset := 0
 for line in source.split_into_lines() {
  trimmed := line.trim_space()
  if trimmed.starts_with('.method ') && trimmed.ends_with(' ' + signature) {
   if start >= 0 { return error('duplicate Account method: ' + signature) }
   start = offset
  }
  if start >= 0 && end < 0 && trimmed == '.end method' {
   end = offset + line.len
  }
  offset += line.len + 1
 }
 if start < 0 || end < start { return error('missing Account method: ' + signature) }
 return source[..start] + replacement + source[end..]
}

fn account_parcel_validate(source string) ! {
 if source.count('.class public Landroid/accounts/Account;\n') != 1
  || source.count('.super Ljava/lang/Object;\n') != 1
  || source.count('.implements Landroid/os/Parcelable;\n') != 1 {
  return error('expected Parcelable Account class')
 }
 expected_fields := ['.field public static final CREATOR:Landroid/os/Parcelable\$Creator;',
  '.field public final name:Ljava/lang/String;', '.field public final type:Ljava/lang/String;']
 mut fields := map[string]bool{}
 mut methods := map[string][]string{}
 mut headers := map[string]bool{}
 mut current := ''
 for raw in source.split_into_lines() {
  line := raw.trim_space()
  if line.starts_with('.class ') || line.starts_with('.super ') || line.starts_with('.implements ') {
   if line !in ['.class public Landroid/accounts/Account;', '.super Ljava/lang/Object;',
    '.implements Landroid/os/Parcelable;'] || line in headers {
    return error('unexpected Account class header: ' + line)
   }
   headers[line] = true
  }
  if line.starts_with('.field ') {
   if line !in expected_fields || line in fields { return error('unexpected Account field: ' + line) }
   fields[line] = true
  }
  if line.starts_with('.method ') {
   if current != '' { return error('nested Account method') }
   current = line
   if current in methods { return error('duplicate Account method: ' + line) }
   methods[current] = []string{}
  } else if line == '.end method' {
   if current == '' { return error('unexpected Account method end') }
   current = ''
  } else if current != '' && line != '' && !line.starts_with('#')
   && !line.starts_with('.registers ') && !line.starts_with('.locals ') {
   methods[current] << line
  }
 }
 if current != '' || fields.len != expected_fields.len || methods.len != 2 {
  return error('unexpected Account source shape')
 }
 expected := {
  '.method static constructor <clinit>()V': [
   'const/4 v0, 0x0',
   'sput-object v0, Landroid/accounts/Account;->CREATOR:Landroid/os/Parcelable\$Creator;',
   'return-void',
  ]
  '.method public constructor <init>(Ljava/lang/String;Ljava/lang/String;)V': [
   'invoke-direct {p0}, Ljava/lang/Object;-><init>()V',
   'iput-object p1, p0, Landroid/accounts/Account;->name:Ljava/lang/String;',
   'iput-object p2, p0, Landroid/accounts/Account;->type:Ljava/lang/String;',
   'return-void',
  ]
 }
 for signature, instructions in expected {
  if signature !in methods || methods[signature] != instructions {
   return error('Account stub method differs: ' + signature)
  }
 }
}

fn account_parcel_validation(name string, type_register string, exception string) string {
 return 'if-eqz ${name}, :bad_name\ninvoke-virtual {${name}}, Ljava/lang/String;->length()I\nmove-result v0\nif-eqz v0, :bad_name\n' +
  'if-eqz ${type_register}, :bad_type\ninvoke-virtual {${type_register}}, Ljava/lang/String;->length()I\nmove-result v0\nif-eqz v0, :bad_type\n' +
  'goto :valid\n:bad_name\nnew-instance v0, ${exception}\nconst-string v1, "Account name must not be empty"\n' +
  'invoke-direct {v0, v1}, ${exception}-><init>(Ljava/lang/String;)V\nthrow v0\n' +
  ':bad_type\nnew-instance v0, ${exception}\nconst-string v1, "Account type must not be empty"\n' +
  'invoke-direct {v0, v1}, ${exception}-><init>(Ljava/lang/String;)V\nthrow v0\n:valid\n'
}

pub fn framework_account_parcel_source(source string) !string {
 account_parcel_validate(source)!
 cls := 'Landroid/accounts/Account;'
 creator := 'Landroid/accounts/Account\$Creator;'
 mut out := account_parcel_replace(source, '<clinit>()V',
  account_parcel_method('static constructor <clinit>()V', 1,
   'new-instance v0, ${creator}\ninvoke-direct {v0}, ${creator}-><init>()V\n' +
   'sput-object v0, ${cls}->CREATOR:Landroid/os/Parcelable\$Creator;\nreturn-void'))!
 out = account_parcel_replace(out, '<init>(Ljava/lang/String;Ljava/lang/String;)V',
  account_parcel_method('public constructor <init>(Ljava/lang/String;Ljava/lang/String;)V', 1,
   'const/4 v0, 0x0\ninvoke-direct {p0, p1, p2, v0}, ${cls}-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V\nreturn-void'))!
 out += '\n.field private final accessId:Ljava/lang/String;\n'
 out += account_parcel_method('public constructor <init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V', 2,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  account_parcel_validation('p1', 'p2', 'Ljava/lang/IllegalArgumentException;') +
  'iput-object p1, p0, ${cls}->name:Ljava/lang/String;\niput-object p2, p0, ${cls}->type:Ljava/lang/String;\n' +
  'iput-object p3, p0, ${cls}->accessId:Ljava/lang/String;\nreturn-void')
 out += account_parcel_method('public constructor <init>(${cls}Ljava/lang/String;)V', 2,
  'iget-object v0, p1, ${cls}->name:Ljava/lang/String;\niget-object v1, p1, ${cls}->type:Ljava/lang/String;\n' +
  'invoke-direct {p0, v0, v1, p2}, ${cls}-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V\nreturn-void')
 out += account_parcel_method('public constructor <init>(Landroid/os/Parcel;)V', 4,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  'invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v2\n' +
  'invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v3\n' +
  account_parcel_validation('v2', 'v3', 'Landroid/os/BadParcelableException;') +
  'iput-object v2, p0, ${cls}->name:Ljava/lang/String;\niput-object v3, p0, ${cls}->type:Ljava/lang/String;\n' +
  'invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\n' +
  'iput-object v0, p0, ${cls}->accessId:Ljava/lang/String;\nreturn-void')
 out += account_parcel_method('public getAccessId()Ljava/lang/String;', 1,
  'iget-object v0, p0, ${cls}->accessId:Ljava/lang/String;\nreturn-object v0')
 out += account_parcel_method('public describeContents()I', 1, 'const/4 v0, 0x0\nreturn v0')
 out += account_parcel_method('public writeToParcel(Landroid/os/Parcel;I)V', 1,
  'iget-object v0, p0, ${cls}->name:Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n' +
  'iget-object v0, p0, ${cls}->type:Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n' +
  'iget-object v0, p0, ${cls}->accessId:Ljava/lang/String;\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nreturn-void')
 out += account_parcel_method('public equals(Ljava/lang/Object;)Z', 2,
  'if-eq p0, p1, :equal\ninstance-of v0, p1, ${cls}\nif-eqz v0, :different\ncheck-cast p1, ${cls}\n' +
  'iget-object v0, p0, ${cls}->name:Ljava/lang/String;\niget-object v1, p1, ${cls}->name:Ljava/lang/String;\n' +
  'invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :different\n' +
  'iget-object v0, p0, ${cls}->type:Ljava/lang/String;\niget-object v1, p1, ${cls}->type:Ljava/lang/String;\n' +
  'invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nreturn v0\n' +
  ':equal\nconst/4 v0, 0x1\nreturn v0\n:different\nconst/4 v0, 0x0\nreturn v0')
 out += account_parcel_method('public hashCode()I', 2,
  'iget-object v0, p0, ${cls}->name:Ljava/lang/String;\ninvoke-virtual {v0}, Ljava/lang/String;->hashCode()I\nmove-result v0\n' +
  'const/16 v1, 527\nadd-int/2addr v0, v1\nmul-int/lit8 v0, v0, 31\n' +
  'iget-object v1, p0, ${cls}->type:Ljava/lang/String;\ninvoke-virtual {v1}, Ljava/lang/String;->hashCode()I\nmove-result v1\nadd-int/2addr v0, v1\nreturn v0')
 return out
}

pub fn framework_account_parcel_creator_source() string {
 cls := 'Landroid/accounts/Account;'
 creator := 'Landroid/accounts/Account\$Creator;'
 return '.class public final ${creator}\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable\$Creator;\n' +
  account_parcel_method('public constructor <init>()V', 0, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
  account_parcel_method('public createFromParcel(Landroid/os/Parcel;)${cls}', 1,
   'new-instance v0, ${cls}\ninvoke-direct {v0, p1}, ${cls}-><init>(Landroid/os/Parcel;)V\nreturn-object v0') +
  account_parcel_method('public bridge synthetic createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 1,
   'invoke-virtual {p0, p1}, ${creator}->createFromParcel(Landroid/os/Parcel;)${cls}\nmove-result-object v0\nreturn-object v0') +
  account_parcel_method('public newArray(I)[${cls}', 1, 'new-array v0, p1, [${cls}\nreturn-object v0') +
  account_parcel_method('public bridge synthetic newArray(I)[Ljava/lang/Object;', 1,
   'invoke-virtual {p0, p1}, ${creator}->newArray(I)[${cls}\nmove-result-object v0\nreturn-object v0')
}

fn framework_account_parcel(smali string) ! {
 path := smali + '/android/accounts/Account.smali'
 creator := smali + '/android/accounts/Account\$Creator.smali'
 if os.exists(creator) { return error('Account creator already exists') }
 source := framework_account_parcel_source(os.read_file(path)!)!
 os.write_file(path, source)!
 os.write_file(creator, framework_account_parcel_creator_source())!
}
