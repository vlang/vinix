#!/usr/bin/env bash

set -e -o pipefail

TMP1=$(mktemp)
TMP2=$(mktemp)
TMP3=$(mktemp)

$1 -t "$2" | sed '/\bd\b/d' | sort > "$TMP1"
grep "\.text" < "$TMP1" | cut -d' ' -f1 > "$TMP2"
grep "\.text" < "$TMP1" | awk 'NF{ print $NF }' > "$TMP3"

cat <<EOF
module trace

struct Symbol {
	address u64
	name    string
}

const symbol_table = [
EOF

paste -d'$' "$TMP2" "$TMP3" | sed 's/^/	Symbol{0x/g' | sed "s/\$/'},/g" | sed "s/\\\$/, '/g"

cat <<EOF
	Symbol{0xffffffffffffffff, ''}
]
EOF

rm "$TMP1" "$TMP2" "$TMP3"
