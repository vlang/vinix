// SPDX-License-Identifier: GPL-2.0-or-later
module main
import cpythonhost
@[export: 'vinix_perf_fixture']
fn entry(operation &char, namespace voidptr, arguments voidptr, syntax voidptr) voidptr {
 return cpythonhost.perf_fixture_entry(operation, namespace, arguments, syntax)
}
