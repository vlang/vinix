/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_AUDIT_COLLECTOR_V_H
#define VINIX_AUDIT_COLLECTOR_V_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#define CAPACITY 128
#define SNAPSHOT_BYTES 65536
#define OUTPUT_BYTES (CAPACITY * 1024 + 8192)
struct record { uint64_t v[15]; };
struct snapshot { uint64_t total, retained, dropped; char boot[33]; struct record records[CAPACITY]; };
struct collector {
    char session[33], boot[33]; uint64_t epoch, last, total, dropped; int started;
    struct record pending[CAPACITY]; size_t pending_count;
    struct record observed[CAPACITY]; size_t observed_count;
};
struct output { char bytes[OUTPUT_BYTES]; size_t used; };
struct vka_stat { uint64_t mode, owner, links, device, inode; int regular, directory; };
int vka_stat(int, struct vka_stat *);
size_t vka_path_max(void);
char *vka_token(char *, const char *, char **);
int vka_errno(void);
int vka_is_error(int);
void vka_set_errno(int);
void vka_restore_errno(int);
int vka_open_read(const char *);
int vka_open_root(void);
int vka_open_dir(int, const char *);
int vka_open_log_file(int, const char *, int);
int vka_dup(int);
int vka_lock(int);
int vka_mkdir(int, const char *);
int64_t vka_read(int, void *, size_t);
int64_t vka_write(int, const void *, size_t);
int vka_close(int);
int vka_fsync(int);
uint32_t vka_uid(void);
uint32_t vka_euid(void);
int64_t vka_pid(void);
void vka_umask(void);
int vka_signals(void);
uint64_t vka_wall_ns(void);
int vka_sleep(uint64_t *, uint64_t *);
void vka_usage(void);
void vka_root_required(void);
void vka_perror(const char *);
void vka_collection_error(int);
extern volatile int stopping, reopening;
#ifndef VINIX_V_RUNTIME
int vka_number(const char *, uint64_t *);
int vka_parse_snapshot(char *, struct snapshot *);
int vka_collect(struct collector *, const struct snapshot *, struct output *);
int vka_end_pending(struct output *, const struct collector *, const char *);
int vka_log_stat(int, uint32_t);
int vka_directory_stat(int, uint32_t);
int vka_open_log_at(int, const char *, uint32_t, int);
int vka_open_log(const char *, int);
int vka_append(int, const struct output *, uint32_t);
int vka_read_snapshot(const char *, struct snapshot *);
int vka_main(int, char **);
#endif
#endif
