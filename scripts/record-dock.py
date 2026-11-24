#!/usr/bin/env python3
"""Record window lifecycle traffic for one X11 application and its window manager."""

import ctypes as c
import struct
import sys
import time

ptr, xid, integer = c.c_void_p, c.c_ulong, c.c_int
x11 = c.CDLL('libX11.so.6')
xtst = c.CDLL('libXtst.so.6')


class Range(c.Structure):
    _fields_ = [
        ('requests', c.c_ubyte * 2), ('replies', c.c_ubyte * 2),
        ('extension_requests', c.c_ushort * 3), ('extension_replies', c.c_ushort * 3),
        ('events', c.c_ubyte * 2), ('devices', c.c_ubyte * 2), ('errors', c.c_ubyte * 2),
        ('started', integer), ('died', integer),
    ]


class Packet(c.Structure):
    _fields_ = [
        ('base', xid), ('time', xid), ('sequence', xid), ('category', integer),
        ('swapped', integer), ('data', ptr), ('length', xid),
    ]


Callback = c.CFUNCTYPE(None, ptr, c.POINTER(Packet))


def bind(lib, name, args, result):
    fn = getattr(lib, name)
    fn.argtypes, fn.restype = args, result
    return fn


open_display = bind(x11, 'XOpenDisplay', [c.c_char_p], ptr)
intern = bind(x11, 'XInternAtom', [ptr, c.c_char_p, integer], xid)
sync = bind(x11, 'XSync', [ptr, integer], integer)
query = bind(xtst, 'XRecordQueryVersion', [ptr, c.POINTER(integer), c.POINTER(integer)], integer)
id_mask = bind(xtst, 'XRecordIdBaseMask', [ptr], xid)
alloc = bind(xtst, 'XRecordAllocRange', [], c.POINTER(Range))
create = bind(xtst, 'XRecordCreateContext', [ptr, integer, c.POINTER(xid), integer,
    c.POINTER(c.POINTER(Range)), integer], xid)
enable = bind(xtst, 'XRecordEnableContext', [ptr, xid, Callback, ptr], integer)
free_data = bind(xtst, 'XRecordFreeData', [c.POINTER(Packet)], None)

app, wm = (int(value, 0) for value in sys.argv[1:3])
control = open_display(None)
data = open_display(None)
if not control or not data or not query(control, c.byref(integer()), c.byref(integer())):
    sys.exit('Cannot open X11 RECORD session')

mask = id_mask(control)
app_base, wm_base = app & mask, wm & mask
atoms = {intern(control, name.encode(), 0): name for name in (
    '_NET_WM_WINDOW_TYPE', 'WM_TRANSIENT_FOR', '_XWAYLAND_ALLOW_COMMITS', 'WL_SURFACE_ID',
    '_NET_WM_WINDOW_TYPE_NORMAL', '_NET_WM_WINDOW_TYPE_UTILITY',
    '_KDE_NET_WM_WINDOW_TYPE_OVERRIDE',
)}
watched_properties = {'_NET_WM_WINDOW_TYPE', 'WM_TRANSIENT_FOR', '_XWAYLAND_ALLOW_COMMITS'}
watched_frames = set()


def decode(packet):
    raw = c.string_at(packet.data, min(packet.length * 4, 96))
    if len(raw) < 8:
        return None
    prefix = '>' if packet.swapped else '<'

    def number(fmt, offset):
        return struct.unpack_from(prefix + fmt, raw, offset)[0]

    def u(offset):
        return number('I', offset)

    def flags(bitmask, offset, names):
        return ' '.join(f'{name}={number("i", offset + 4 * (bitmask & ((1 << bit) - 1)).bit_count())}'
                        for bit, name in names if bitmask & (1 << bit))

    override = [(9, 'override_redirect')]
    window = u(4)
    op = raw[0]
    if packet.category == 1:
        if op == 1:
            return (f'Create {window:#x} parent={u(8):#x} '
                    f'{number("H", 16)}x{number("H", 18)}@'
                    f'{number("h", 12)},{number("h", 14)} {flags(u(28), 32, override)}')
        if op == 7:
            if packet.base == wm_base and window & mask == app_base:
                watched_frames.add(u(8))
            return f'Reparent {window:#x} parent={u(8):#x} at={number("h", 12)},{number("h", 14)}'
        if op in (4, 8, 10):
            return f'{ {4: "Destroy", 8: "Map", 10: "Unmap"}[op]} {window:#x}'
        if op == 2:
            values = flags(u(8), 12, override)
            return f'Attributes {window:#x} {values}' if values else None
        if op == 12:
            values = flags(number('H', 8), 12, enumerate(
                ('x', 'y', 'width', 'height', 'border', 'sibling', 'stack')))
            return f'Configure {window:#x} {values}'
        if op == 18 and (window & mask == app_base or packet.base == app_base):
            name = atoms.get(u(8))
            if name in watched_properties and raw[16] == 32:
                values = [u(i) for i in range(24, len(raw), 4)]
                return f'Property {window:#x} {name} ' + ','.join(
                    atoms.get(value, hex(value)) if name == '_NET_WM_WINDOW_TYPE'
                    else hex(value) for value in values)
        return None
    event = op & 0x7f
    window = u(8) if event != 33 else window
    if window & mask != app_base and window not in watched_frames:
        return None
    if event == 16:
        return f'CreateNotify {window:#x} parent={u(4):#x} {number("H", 16)}x{number("H", 18)} override={raw[22]}'
    if event == 19:
        return f'MapNotify {window:#x} event={u(4):#x} override={raw[12]}'
    if event == 21:
        return f'ReparentNotify {window:#x} parent={u(12):#x} event={u(4):#x} override={raw[20]}'
    if event in (17, 18, 20, 22, 23):
        return f'{ {17: "DestroyNotify", 18: "UnmapNotify", 20: "MapRequest", 22: "ConfigureNotify", 23: "ConfigureRequest"}[event]} {window:#x} event/parent={u(4):#x}'
    if event == 33 and atoms.get(u(8)) == 'WL_SURFACE_ID':
        return f'WL_SURFACE_ID {window:#x} surface={u(12)}'
    return None


@Callback
def capture(_, packet_ptr):
    try:
        packet = packet_ptr.contents
        if packet.category == 4:
            print(f'READY app={app:#x} wm={wm:#x}', flush=True)
            return
        if packet.category not in (0, 1):
            return
        line = decode(packet)
        if line:
            tag = 'app' if packet.base == app_base else 'wm'
            direction = 'request' if packet.category == 1 else 'event'
            print(f'{time.time():.3f} {packet.time} {tag} {direction} {packet.sequence}: {line}', flush=True)
    except (struct.error, ValueError) as error:
        print(f'Decode error: {error}', file=sys.stderr, flush=True)
    finally:
        free_data(packet_ptr)


ranges = (c.POINTER(Range) * 3)(alloc(), alloc(), alloc())
ranges[0].contents.requests[:] = 1, 12
ranges[0].contents.events[:] = 16, 23
ranges[1].contents.requests[:] = 18, 18
ranges[2].contents.events[:] = 33, 33
context = create(control, 7, (xid * 2)(app, wm), 2, ranges, len(ranges))
if not context:
    sys.exit('Failed to create X11 RECORD context')
sync(control, 0)
if not enable(data, context, capture, None):
    sys.exit('Failed to enable X11 RECORD context')
