// SPDX-License-Identifier: GPL-2.0-or-later
module iostls

// Bind the bundled mbedTLS directly: importing net.mbedtls also imports V's
// socket declarations, which conflict with the runner's Darwin ABI adapter.
#include <mbedtls/net_sockets.h>
#include <mbedtls/ssl.h>
#include <mbedtls/entropy.h>
#include <mbedtls/ctr_drbg.h>

@[typedef]
pub struct C.mbedtls_net_context { pub mut: fd i32 }
@[typedef]
pub struct C.mbedtls_ssl_context {}
@[typedef]
pub struct C.mbedtls_ssl_config {}
@[typedef]
pub struct C.mbedtls_x509_crt {}
@[typedef]
pub struct C.mbedtls_x509_crl {}
@[typedef]
pub struct C.mbedtls_ctr_drbg_context {}
@[typedef]
pub struct C.mbedtls_entropy_context {}
@[typedef]
pub struct C.mbedtls_pk_context {}
// The C typedef is a function type whose buffer is const. Keep that exact type
// at the callback boundary; V function pointers cannot express const pointees.
@[typedef]
pub struct C.mbedtls_ssl_send_t {}

pub fn C.mbedtls_ssl_init(&C.mbedtls_ssl_context)
pub fn C.mbedtls_ssl_setup(&C.mbedtls_ssl_context, &C.mbedtls_ssl_config) int
pub fn C.mbedtls_ssl_config_init(&C.mbedtls_ssl_config)
pub fn C.mbedtls_ssl_config_defaults(&C.mbedtls_ssl_config, int, int, int) int
pub fn C.mbedtls_ssl_config_free(&C.mbedtls_ssl_config)
pub fn C.mbedtls_ssl_conf_authmode(&C.mbedtls_ssl_config, int)
pub fn C.mbedtls_ssl_conf_rng(&C.mbedtls_ssl_config, fn (voidptr, &u8, usize) int, voidptr)
pub fn C.mbedtls_ssl_conf_ca_chain(&C.mbedtls_ssl_config, &C.mbedtls_x509_crt, &C.mbedtls_x509_crl)
pub fn C.mbedtls_ssl_set_hostname(&C.mbedtls_ssl_context, &char) int
pub fn C.mbedtls_ssl_set_bio(&C.mbedtls_ssl_context, &C.mbedtls_net_context, &C.mbedtls_ssl_send_t, fn (voidptr, &u8, usize) i32, fn (voidptr, &u8, usize, u32) i32)
pub fn C.mbedtls_ssl_handshake(&C.mbedtls_ssl_context) int
pub fn C.mbedtls_ssl_read(&C.mbedtls_ssl_context, &u8, usize) int
pub fn C.mbedtls_ssl_write(&C.mbedtls_ssl_context, &u8, usize) int
pub fn C.mbedtls_ssl_close_notify(&C.mbedtls_ssl_context) int
pub fn C.mbedtls_ssl_free(&C.mbedtls_ssl_context)
pub fn C.mbedtls_net_recv(voidptr, &u8, usize) i32
pub fn C.mbedtls_x509_crt_init(&C.mbedtls_x509_crt)
pub fn C.mbedtls_x509_crt_parse_file(&C.mbedtls_x509_crt, &char) int
pub fn C.mbedtls_x509_crt_free(&C.mbedtls_x509_crt)
pub fn C.mbedtls_ctr_drbg_init(&C.mbedtls_ctr_drbg_context)
pub fn C.mbedtls_ctr_drbg_seed(&C.mbedtls_ctr_drbg_context, fn (voidptr, &u8, usize) i32, voidptr, &u8, usize) int
pub fn C.mbedtls_ctr_drbg_random(voidptr, &u8, usize) int
pub fn C.mbedtls_ctr_drbg_free(&C.mbedtls_ctr_drbg_context)
pub fn C.mbedtls_entropy_init(&C.mbedtls_entropy_context)
pub fn C.mbedtls_entropy_func(voidptr, &u8, usize) i32
pub fn C.mbedtls_entropy_free(&C.mbedtls_entropy_context)
pub fn C.mbedtls_pk_init(&C.mbedtls_pk_context)
pub fn C.mbedtls_pk_parse_keyfile(&C.mbedtls_pk_context, &char, &char, fn (voidptr, &u8, usize) int, voidptr) int
pub fn C.mbedtls_pk_free(&C.mbedtls_pk_context)
pub fn C.mbedtls_ssl_conf_own_cert(&C.mbedtls_ssl_config, &C.mbedtls_x509_crt, &C.mbedtls_pk_context) int
