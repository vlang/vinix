/* SPDX-License-Identifier: GPL-2.0-or-later
 * Private boot policy. Parse before MMIO; resolve PARTUUIDs after GPT validation.
 */
#ifndef VINIX_APPLE_ANS_POLICY_H
#define VINIX_APPLE_ANS_POLICY_H
struct ans_policy { unsigned flags; uint8_t write_guid[16], root_guid[16]; };
static int a_hex(unsigned char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
static const uint8_t a_guid_order[16] = {3,2,1,0,5,4,7,6,8,9,10,11,12,13,14,15};
static int a_guid_parse(const char *s, size_t n, uint8_t guid[16])
{
    uint8_t out[16] = {0}; unsigned nonzero = 0, byte = 0;
    if (!s || n != 36) return 0;
    for (unsigned i = 0; i < 36;) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (s[i++] != '-') return 0;
        } else {
            int hi = a_hex((unsigned char)s[i++]), lo = a_hex((unsigned char)s[i++]);
            if (hi < 0 || lo < 0 || byte == 16) return 0;
            out[a_guid_order[byte++]] = (uint8_t)((hi << 4) | lo);
            nonzero |= (unsigned)((hi << 4) | lo);
        }
    }
    if (!nonzero) return 0;
    a_copy(guid, out, 16); return 1;
}
static void a_guid_format(const uint8_t guid[16], char out[37])
{
    static const char hex[] = "0123456789abcdef"; unsigned pos = 0;
    for (unsigned i = 0; i < 16; ++i) {
        if (i == 4 || i == 6 || i == 8 || i == 10) out[pos++] = '-';
        out[pos++] = hex[guid[a_guid_order[i]] >> 4];
        out[pos++] = hex[guid[a_guid_order[i]] & 15];
    }
    out[pos] = 0;
}
static int a_space(char c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }
static int a_token(const char *s, size_t n, const char *l, size_t bytes)
{ return n == bytes && a_equal((const uint8_t *)s, (const uint8_t *)l, bytes); }
#define A_TOKEN(s,n,l) a_token((s),(n),(l),sizeof(l)-1)
static int a_prefix(const char *s, size_t n, const char *p, size_t bytes)
{ return n >= bytes && a_equal((const uint8_t *)s, (const uint8_t *)p, bytes); }
#define A_PREFIX(s,n,p) a_prefix((s),(n),(p),sizeof(p)-1)
static int a_parse_policy(const char *s, size_t n, struct ans_policy *out)
{
    struct ans_policy p = {0}; unsigned disabled = 0, write = 0, root = 0, type = 0, mode = 0;
    static const char wp[] = "vinix.ans_rw=PARTUUID=", rp[] = "vinix.root=PARTUUID=";
    if (!out || (!s && n) || n > 16384) return -ANS_CONFIG;
    for (size_t i = 0; i < n;) {
        while (i < n && a_space(s[i])) ++i;
        size_t start = i;
        while (i < n && !a_space(s[i])) { if (!s[i]) return -ANS_CONFIG; ++i; }
        const char *t = s + start; size_t len = i - start;
        if (!len) continue;
        if (A_TOKEN(t,len,"vinix.apple_ans=1")) p.flags |= VINIX_ANS_ENABLE;
        else if (A_TOKEN(t,len,"vinix.apple_ans=0")) disabled = 1;
        else if (A_PREFIX(t,len,"vinix.ans_rw=")) {
            if (write++ || !A_PREFIX(t,len,wp) ||
                !a_guid_parse(t + sizeof(wp)-1, len - (sizeof(wp)-1), p.write_guid)) return -ANS_CONFIG;
            p.flags |= VINIX_ANS_WRITE;
        } else if (A_PREFIX(t,len,"vinix.root=")) {
            if (root++ || !A_PREFIX(t,len,rp) ||
                !a_guid_parse(t + sizeof(rp)-1, len - (sizeof(rp)-1), p.root_guid)) return -ANS_CONFIG;
            p.flags |= VINIX_ANS_ROOT;
        } else if (A_PREFIX(t,len,"vinix.rootfstype=")) {
            if (type++ || !A_TOKEN(t,len,"vinix.rootfstype=ext2")) return -ANS_CONFIG;
        } else if (A_PREFIX(t,len,"vinix.rootmode=")) {
            /* Reject, don't silently downgrade, a requested writable root. */
            if (mode++ || !A_TOKEN(t,len,"vinix.rootmode=ro")) return -ANS_CONFIG;
        } else if (A_TOKEN(t,len,"vinix.rootfallback=initramfs")) {
            if (p.flags & VINIX_ANS_FALLBACK) return -ANS_CONFIG;
            p.flags |= VINIX_ANS_FALLBACK;
        } else if (A_PREFIX(t,len,"vinix.apple_ans=") || A_PREFIX(t,len,"vinix.rootfallback="))
            return -ANS_CONFIG;
    }
    if (disabled) p.flags &= ~VINIX_ANS_ENABLE;
    if ((p.flags & (VINIX_ANS_ROOT | VINIX_ANS_WRITE)) && !(p.flags & VINIX_ANS_ENABLE)) return -ANS_CONFIG;
    if ((type || mode || (p.flags & VINIX_ANS_FALLBACK)) && !(p.flags & VINIX_ANS_ROOT)) return -ANS_CONFIG;
    if ((p.flags & (VINIX_ANS_ROOT | VINIX_ANS_WRITE)) == (VINIX_ANS_ROOT | VINIX_ANS_WRITE) &&
        a_equal(p.root_guid, p.write_guid, 16)) return -ANS_CONFIG;
    *out = p; return 0;
}
static int a_linux_partition(const struct ans_partition *p)
{
    static const uint8_t type[16] = {
        0xaf,0x3d,0xc6,0x0f,0x83,0x84,0x72,0x47,0x8e,0x79,0x3d,0x69,0xd8,0x47,0x7d,0xe4
    };
    return a_equal(p->type_guid, type, 16);
}
static int a_find_guid(struct ans *a, const uint8_t guid[16], unsigned *ns, unsigned *part)
{
    unsigned found = 0;
    for (unsigned i = 0; i < a->nns; ++i)
        for (unsigned j = 0; j < a->ns[i].nparts; ++j)
            if (a_equal(a->ns[i].parts[j].guid, guid, 16)) { *ns = i; *part = j; ++found; }
    return found == 1 ? 0 : -ANS_CONFIG;
}
static int a_apply_policy(struct ans *a, const struct ans_policy *p)
{
    unsigned wn = 0, wp = 0, rn = 0, rp = 0;
    if (!a->live || a->stopping || a->policy_set || !(p->flags & VINIX_ANS_ENABLE)) return -ANS_CONFIG;
    if (p->flags & VINIX_ANS_ROOT) {
        if (a_find_guid(a, p->root_guid, &rn, &rp) || !a_linux_partition(&a->ns[rn].parts[rp])) return -ANS_CONFIG;
    }
    if (p->flags & VINIX_ANS_WRITE) {
        if (a_find_guid(a, p->write_guid, &wn, &wp) || !a->ns[wn].gpt_complete || a->ns[wn].gpt_hybrid ||
            !a_linux_partition(&a->ns[wn].parts[wp]) ||
            (a->ns[wn].parts[wp].attributes & (UINT64_C(1) << 60))) return -ANS_CONFIG;
        if ((p->flags & VINIX_ANS_ROOT) && wn == rn && wp == rp) return -ANS_CONFIG;
    }
    a->policy_set = 1;
    a->root_selected = !!(p->flags & VINIX_ANS_ROOT); a->root_ns = rn; a->root_part = rp;
    a->write_enabled = !!(p->flags & VINIX_ANS_WRITE); a->write_ns = wn; a->write_part = wp;
    if (a->write_enabled) { a->write_start = a->ns[wn].parts[wp].start; a->write_blocks = a->ns[wn].parts[wp].blocks; }
    return 0;
}
#endif
