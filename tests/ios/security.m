// SPDX-License-Identifier: GPL-2.0-or-later
// Same public certificates and API calls against Mac Security and Vinix.
#include "security-fixtures.h"
typedef const void *CFTypeRef, *CFDataRef, *CFStringRef, *CFDictionaryRef, *CFErrorRef;
typedef const void *SecCertificateRef, *SecKeyRef;
typedef unsigned long CFTypeID;
__attribute__((objc_root_class))
@interface NSString
- (const char *)UTF8String;
@end
__attribute__((objc_root_class))
@interface NSNumber
- (long)integerValue;
- (unsigned char)boolValue;
@end
extern int puts(const char *), printf(const char *,...), strcmp(const char *,const char *), memcmp(const void *,const void *,unsigned long);
extern void *memcpy(void *,const void *,unsigned long);
extern CFDataRef CFDataCreate(const void *,const unsigned char *,long);
extern long CFDataGetLength(CFDataRef);
extern const unsigned char *CFDataGetBytePtr(CFDataRef);
extern CFTypeRef CFRetain(CFTypeRef);
extern void CFRelease(CFTypeRef);
extern CFTypeID CFGetTypeID(CFTypeRef), CFDataGetTypeID(void), CFStringGetTypeID(void), CFDictionaryGetTypeID(void);
extern unsigned char CFEqual(CFTypeRef,CFTypeRef);
extern unsigned long CFHash(CFTypeRef);
extern CFTypeRef CFDictionaryGetValue(CFDictionaryRef,CFTypeRef);
extern CFTypeID CFErrorGetTypeID(void);
extern long CFErrorGetCode(CFErrorRef);
extern CFStringRef CFErrorGetDomain(CFErrorRef);
extern CFTypeID SecCertificateGetTypeID(void), SecKeyGetTypeID(void);
extern SecCertificateRef SecCertificateCreateWithData(const void *,CFDataRef);
extern CFDataRef SecCertificateCopyData(SecCertificateRef), SecCertificateCopySerialNumberData(SecCertificateRef,CFErrorRef *);
extern CFStringRef SecCertificateCopySubjectSummary(SecCertificateRef);
extern SecKeyRef SecCertificateCopyKey(SecCertificateRef);
extern CFDataRef SecKeyCopyExternalRepresentation(SecKeyRef,CFErrorRef *);
extern CFDictionaryRef SecKeyCopyAttributes(SecKeyRef);
extern const void *const kSecRandomDefault;
extern int SecRandomCopyBytes(const void *,unsigned long,unsigned char *);
#define SECURITY_STRINGS(X) \
 X(kSecAttrAccessGroup,"agrp") X(kSecAttrAccessible,"pdmn") \
 X(kSecAttrAccessibleAfterFirstUnlock,"ck") X(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,"cku") \
 X(kSecAttrAccessibleAlwaysThisDeviceOnly,"dku") X(kSecAttrAccount,"acct") \
 X(kSecAttrApplicationTag,"atag") X(kSecAttrApplicationLabel,"klbl") X(kSecAttrDescription,"desc") \
 X(kSecAttrGeneric,"gena") X(kSecAttrKeySizeInBits,"bsiz") X(kSecAttrKeyType,"type") \
 X(kSecAttrKeyTypeECSECPrimeRandom,"73") X(kSecAttrKeyTypeRSA,"42") X(kSecAttrService,"svce") \
 X(kSecAttrSynchronizable,"sync") X(kSecAttrType,"type") X(kSecClass,"class") \
 X(kSecClassGenericPassword,"genp") X(kSecClassKey,"keys") X(kSecMatchLimit,"m_Limit") \
 X(kSecMatchLimitAll,"m_LimitAll") X(kSecMatchLimitOne,"m_LimitOne") \
 X(kSecReturnAttributes,"r_Attributes") X(kSecReturnData,"r_Data") \
 X(kSecUseAuthenticationUI,"u_AuthUI") X(kSecUseAuthenticationUISkip,"u_AuthUIS") \
 X(kSecUseDataProtectionKeychain,"nleg") X(kSecValueData,"v_Data") \
 X(kSecAttrKeyClass,"kcls") X(kSecAttrKeyClassPublic,"0") \
 X(kSecAttrCanEncrypt,"encr") X(kSecAttrCanDecrypt,"decr") X(kSecAttrCanDerive,"drve") \
 X(kSecAttrCanSign,"sign") X(kSecAttrCanVerify,"vrfy") X(kSecAttrCanWrap,"wrap") \
 X(kSecAttrCanUnwrap,"unwp") X(kSecAttrIsPermanent,"perm") X(kSecAttrIsPrivate,"priv") \
 X(kSecAttrIsModifiable,"modi") X(kSecAttrIsSensitive,"sens") X(kSecAttrWasAlwaysSensitive,"asen") \
 X(kSecAttrIsExtractable,"extr") X(kSecAttrWasNeverExtractable,"next") X(kSecAttrEffectiveKeySize,"esiz")
#define DECLARE(name,value) extern NSString *const name;
SECURITY_STRINGS(DECLARE)
#define REQUIRE(condition) do { if (!(condition)) { printf("IOS-SECURITY FAIL: line %d: %s\n",__LINE__,#condition); return 1; } } while (0)
static int data_equals(CFDataRef data,const unsigned char *expected,long length) {
 return data && CFGetTypeID(data)==CFDataGetTypeID() && CFDataGetLength(data)==length && !memcmp(CFDataGetBytePtr(data),expected,(unsigned long)length);
}
static int string_equals(CFStringRef string,const char *expected) {
 return string && CFGetTypeID(string)==CFStringGetTypeID() && !strcmp([(NSString *)string UTF8String],expected);
}
static int check_certificate(const unsigned char *bytes,long length,const unsigned char *key_bytes,long key_length,const unsigned char *label,int bits,int is_rsa) {
 unsigned char input[1024];
 REQUIRE(length+1<(long)sizeof input);
 memcpy(input,bytes,(unsigned long)length);input[length]=0xff;
 CFDataRef source=CFDataCreate(0,input,length+1);
 SecCertificateRef cert=SecCertificateCreateWithData(0,source);
 CFRelease(source);
 REQUIRE(cert && CFGetTypeID(cert)==SecCertificateGetTypeID());
 CFDataRef copy=SecCertificateCopyData(cert);
 REQUIRE(data_equals(copy,bytes,length));CFRelease(copy);
 CFStringRef summary=SecCertificateCopySubjectSummary(cert);
 REQUIRE(string_equals(summary,is_rsa?"Vinix Certificate":"Runtime"));CFRelease(summary);
 CFErrorRef error=(CFErrorRef)0x1234;
 CFDataRef serial=SecCertificateCopySerialNumberData(cert,&error);
 unsigned char expected_serial[2]={0,0x80}, ec_serial=3;
 REQUIRE(error==(CFErrorRef)0x1234 && data_equals(serial,is_rsa?expected_serial:&ec_serial,is_rsa?2:1));CFRelease(serial);
 SecKeyRef key=SecCertificateCopyKey(cert);
 REQUIRE(key && CFGetTypeID(key)==SecKeyGetTypeID());
 source=CFDataCreate(0,bytes,length);
 SecCertificateRef duplicate=SecCertificateCreateWithData(0,source);CFRelease(source);
 SecKeyRef duplicate_key=SecCertificateCopyKey(duplicate);
 REQUIRE(CFEqual(cert,duplicate) && CFHash(cert)==CFHash(duplicate));
 REQUIRE(CFEqual(key,duplicate_key));CFRelease(duplicate_key);CFRelease(duplicate);
 CFRelease(cert); // The public key must own its data independently.
 CFDataRef external=SecKeyCopyExternalRepresentation(key,&error);
 REQUIRE(error==(CFErrorRef)0x1234 && data_equals(external,key_bytes,key_length));CFRelease(external);
 CFDictionaryRef attrs=SecKeyCopyAttributes(key);
 CFRelease(key); // Attributes and exported bytes also survive their source.
 REQUIRE(attrs && CFGetTypeID(attrs)==CFDictionaryGetTypeID());
 REQUIRE(string_equals(CFDictionaryGetValue(attrs,kSecClass),"keys"));
 REQUIRE(string_equals(CFDictionaryGetValue(attrs,kSecAttrKeyClass),"0"));
 REQUIRE(string_equals(CFDictionaryGetValue(attrs,kSecAttrKeyType),is_rsa?"42":"73"));
 REQUIRE([(NSNumber *)CFDictionaryGetValue(attrs,kSecAttrKeySizeInBits) integerValue]==bits);
 REQUIRE([(NSNumber *)CFDictionaryGetValue(attrs,kSecAttrEffectiveKeySize) integerValue]==bits);
 REQUIRE([(NSNumber *)CFDictionaryGetValue(attrs,kSecAttrCanVerify) boolValue]);
 REQUIRE(![(NSNumber *)CFDictionaryGetValue(attrs,kSecAttrCanSign) boolValue]);
 REQUIRE(!![(NSNumber *)CFDictionaryGetValue(attrs,kSecAttrCanDecrypt) boolValue]==is_rsa);
 REQUIRE(data_equals(CFDictionaryGetValue(attrs,kSecValueData),key_bytes,key_length));
 REQUIRE(data_equals(CFDictionaryGetValue(attrs,kSecAttrApplicationLabel),label,20));
 CFRelease(attrs);
 return 0;
}
int main(void) { @autoreleasepool {
#define VERIFY(name,value) REQUIRE(string_equals(name,value));
 SECURITY_STRINGS(VERIFY)
 for(int repeat=0;repeat<8;repeat++) {
  REQUIRE(!check_certificate(rsa,sizeof rsa,rsa_key,sizeof rsa_key,rsa_label,1024,1));
  REQUIRE(!check_certificate(ec,sizeof ec,ec_key,sizeof ec_key,ec_label,256,0));
  REQUIRE(!check_certificate(ec384,sizeof ec384,ec384_key,sizeof ec384_key,ec384_label,384,0));
  REQUIRE(!check_certificate(ec521,sizeof ec521,ec521_key,sizeof ec521_key,ec521_label,521,0));
 }
 // Every truncated prefix fails; no out-of-bounds reads or leaked objects.
 for(unsigned long n=0;n<sizeof rsa;n++) {
  CFDataRef data=CFDataCreate(0,rsa,(long)n);
  SecCertificateRef cert=SecCertificateCreateWithData(0,data);CFRelease(data);
  REQUIRE(!cert);
 }
 const unsigned char bad[]={0x30,0x80,0,0}, overlong[]={0x30,0x84,0xff,0xff,0xff,0xff};
 CFDataRef data=CFDataCreate(0,bad,sizeof bad);REQUIRE(!SecCertificateCreateWithData(0,data));CFRelease(data);
 data=CFDataCreate(0,overlong,sizeof overlong);REQUIRE(!SecCertificateCreateWithData(0,data));CFRelease(data);
 // Parsing alone must not turn an off-curve EC point into a public key.
 unsigned char invalid_ec[sizeof ec];memcpy(invalid_ec,ec,sizeof ec);
 unsigned char *point=0;
 for(unsigned long i=0;i+sizeof ec_key<=sizeof ec;i++) {
  if(!memcmp(invalid_ec+i,ec_key,sizeof ec_key)) { point=invalid_ec+i;break; }
 }
 REQUIRE(point);
 for(unsigned long i=1;i<sizeof ec_key;i++)point[i]=0;
 data=CFDataCreate(0,invalid_ec,sizeof invalid_ec);
 SecCertificateRef invalid_key_cert=SecCertificateCreateWithData(0,data);CFRelease(data);
 REQUIRE(invalid_key_cert && !SecCertificateCopyKey(invalid_key_cert));CFRelease(invalid_key_cert);
 CFErrorRef error=0;
 REQUIRE(!SecCertificateCopySerialNumberData(0,&error));
 REQUIRE(error && CFGetTypeID(error)==CFErrorGetTypeID() && CFErrorGetCode(error)==-26275);
 REQUIRE(string_equals(CFErrorGetDomain(error),"NSOSStatusErrorDomain"));
 CFRetain(error);CFRelease(error);CFRelease(error);
 unsigned char random_a[1026]={0},random_b[1024]={0};random_a[0]=17;random_a[1025]=23;
 REQUIRE(kSecRandomDefault==0 && !SecRandomCopyBytes(kSecRandomDefault,0,0));
 REQUIRE(!SecRandomCopyBytes(kSecRandomDefault,1024,random_a+1));
 REQUIRE(!SecRandomCopyBytes(kSecRandomDefault,sizeof random_b,random_b));
 REQUIRE(random_a[0]==17 && random_a[1025]==23 && memcmp(random_a+1,random_b,1024));
 unsigned long nonzero=0;for(unsigned long i=1;i<=1024;i++)nonzero+=random_a[i]!=0;
 REQUIRE(nonzero>900);
 puts("IOS-SECURITY: owned DER certificates, RSA/EC public keys, attributes, decode errors, typed constants and secure random bytes");
 return 0;
} }
