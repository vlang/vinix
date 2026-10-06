// Declaration-only actual Android Translation Layer and androidfw ABI.
#ifndef VINIX_ATL_CONFIGURATION_V_ABI_H
#define VINIX_ATL_CONFIGURATION_V_ABI_H
#define _LARGEFILE64_SOURCE 1
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <androidfw/androidfw_c_api.h>
typedef void AConfiguration;
extern AConfiguration *AConfiguration_new(void);
extern void AConfiguration_delete(AConfiguration *);
extern void AConfiguration_fromAssetManager(AConfiguration *, struct AssetManager *);
extern void AConfiguration_copy(AConfiguration *, AConfiguration *);
extern int32_t AConfiguration_diff(AConfiguration *, AConfiguration *);
extern int32_t AConfiguration_match(AConfiguration *, AConfiguration *);
extern int32_t AConfiguration_getDensity(AConfiguration *);
extern int32_t AConfiguration_getScreenWidthDp(AConfiguration *);
extern int32_t AConfiguration_getScreenHeightDp(AConfiguration *);
extern int32_t AConfiguration_getSmallestScreenWidthDp(AConfiguration *);
extern int32_t AConfiguration_getSdkVersion(AConfiguration *);
extern int32_t AConfiguration_getScreenSize(AConfiguration *);
extern int32_t AConfiguration_getNavHidden(AConfiguration *);
extern void AConfiguration_getLanguage(AConfiguration *, char *);
extern void AConfiguration_getCountry(AConfiguration *, char *);
extern void AConfiguration_setOrientation(AConfiguration *, int32_t);
#endif
