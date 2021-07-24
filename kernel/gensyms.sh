#!/usr/bin/env bash

set -e -o pipefail

TMP1=$(mktemp)
TMP2=$(mktemp)
TMP3=$(mktemp)

$1 -t "$2" | sed '/\bd\b/d' | sort > "$TMP1"
grep "\.text" < "$TMP1" | cut -d' ' -f1 > "$TMP2"
grep "\.text" < "$TMP1" | awk 'NF{ print $NF }' > "$TMP3"

cat <<EOF
#include <stdint.h>

struct symbol {
	uint64_t address;
	char *string;
};

__attribute__((section(".symbol_table")))
struct symbol symbol_table[] = {
EOF

paste -d'$' "$TMP2" "$TMP3" | sed "s/^/    {0x/g;s/\\\$/, \"/g;s/\$/\"},/g"

cat <<EOF
    {0xffffffffffffffff, ""}
};

struct symbol *get_symbol_table(void) {
    return symbol_table;
}
EOF

rm "$TMP1" "$TMP2" "$TMP3"
