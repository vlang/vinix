"""Import compatibility for the native V Apple DeviceTree and power core."""
import struct
from _native_extract import query as _native_query, span


def query(data, operation, **options):
    try:
        return _native_query(data, "adt:" + operation, **options)
    except ValueError as error:
        message = str(error)
        for prefix, kind in (("struct.error: ", struct.error),
                             ("OverflowError: ", OverflowError),
                             ("TypeError: ", TypeError)):
            if message.startswith(prefix):
                raise kind(message.removeprefix(prefix)) from None
        raise


def parse_adt(blob, property_type, node_type):
    def owned_node(record):
        return node_type(
            {name: property_type(span(blob, value), value["flags"])
             for name, value in record["properties"].items()},
            tuple(owned_node(child) for child in record["children"]),
        )
    return owned_node(query(blob, "parse_adt"))


def parse_pmgr_devices(data, device_type):
    return [device_type(**row) for row in query(data, "parse_pmgr_devices")]


def resolve_gate(handle, devices):
    return query(b"", "resolve_gate", handle=handle, devices=[vars(device) for device in devices])


def device_tree_im4p_payload(blob):
    return span(blob, query(blob, "device_tree_im4p_payload"))


def decompress_device_tree(payload, initial_capacity=None):
    result = query(payload, "decompress_device_tree", initial_capacity=initial_capacity)
    return payload if result["unchanged"] else result["data"]


def parse_reg_regions(data, field):
    return [tuple(pair) for pair in query(data, "parse_reg_regions", field=field)]


def direct_branch_targets(function_address, code):
    return set(query(code, "direct_branch_targets", function_address=function_address))


def pc_relative_targets(function_address, code):
    return set(query(code, "pc_relative_targets", function_address=function_address))
