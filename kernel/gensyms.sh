#! /bin/sh

set -e

LC_ALL=C
export LC_ALL

TMP0=$(mktemp)

cat >"$TMP0" <<EOF
#! /bin/sh

set -e

set -o pipefail 2>/dev/null
EOF

chmod +x "$TMP0"

"$TMP0" && set -o pipefail

rm "$TMP0"

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

const struct symbol symbol_table[] = {
EOF

paste -d'$' "$TMP2" "$TMP3" | sed "s/^/    {0x/g;s/\\\$/, \"/g;s/\$/\"},/g"

cat <<EOF
    {0xffffffffffffffff, ""}
};

const struct symbol *get_symbol_table(void) {
    return symbol_table;
}
EOF

rm "$TMP1" "$TMP2" "$TMP3"
