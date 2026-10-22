// SPDX-License-Identifier: GPL-2.0-or-later
// Generate public test certificates. Private keys stay in the build directory.
module main

import os

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn main() {
	assert os.args.len == 3, 'WORK_DIR OUTPUT_DIR'
	work, out := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	os.mkdir_all(work)!
	os.mkdir_all(out)!
	ca := 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid,issuer\n'
	os.write_file(work + '/ca.ext', ca)!
	os.write_file(work + '/leaf.ext', 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=DNS:localhost\n')!
	for name in ['root', 'other', 'wrong', 'intermediate', 'leaf'] {
		cn := if name == 'wrong' { 'root' } else { name }
		checked(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=Vinix fixture ${cn}', '-keyout', work + '/${name}.key', '-out', work + '/${name}.csr'])
		if name in ['root', 'other', 'wrong'] {
			checked(['openssl', 'x509', '-req', '-in', work + '/${name}.csr', '-signkey', work + '/${name}.key', '-set_serial', '1', '-days', '7300', '-extfile', work + '/ca.ext', '-out', work + '/${name}.pem'])
		} else {
			issuer := if name == 'leaf' { 'intermediate' } else { 'root' }
			checked(['openssl', 'x509', '-req', '-in', work + '/${name}.csr', '-CA', work + '/${issuer}.pem', '-CAkey', work + '/${issuer}.key', '-set_serial', '2', '-days', '7300', '-extfile', work + '/' + if name == 'leaf' { 'leaf.ext' } else { 'ca.ext' }, '-out', work + '/${name}.pem'])
		}
	}
	checked(['openssl', 'x509', '-req', '-in', work + '/root.csr', '-CA', work + '/other.pem', '-CAkey', work + '/other.key', '-set_serial', '3', '-days', '7300', '-extfile', work + '/ca.ext', '-out', work + '/cross.pem'])
	for name in ['root', 'wrong', 'intermediate', 'leaf', 'cross'] {
		checked(['openssl', 'x509', '-in', work + '/${name}.pem', '-outform', 'DER', '-out', out + '/${name}.der'])
	}
	mut corrupt := os.read_bytes(out + '/leaf.der')!
	corrupt[corrupt.len - 1] ^= 1
	os.write_file_array(out + '/corrupt.der', corrupt)!
	checked(['openssl', 'verify', '-trusted', work + '/root.pem', '-untrusted', work + '/intermediate.pem', work + '/leaf.pem'])
	println('Generated public cross-signed chain and negative cases: ${out}')
}
