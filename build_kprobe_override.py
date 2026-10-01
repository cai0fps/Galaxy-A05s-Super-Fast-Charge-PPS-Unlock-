import struct
import capstone

def build_kprobe_override():
    with open('test_sig.ko', 'rb') as f:
        data = bytearray(f.read())

    e_shoff = struct.unpack('<Q', data[40:48])[0]
    e_shentsize = struct.unpack('<H', data[58:60])[0]
    e_shnum = struct.unpack('<H', data[60:62])[0]
    e_shstrndx = struct.unpack('<H', data[62:64])[0]

    sections = [struct.unpack('<IIQQQQIIQQ', data[e_shoff+i*e_shentsize:e_shoff+(i+1)*e_shentsize]) for i in range(e_shnum)]
    shstr = sections[e_shstrndx]
    shstr_tab = data[shstr[4]:shstr[4]+shstr[5]]

    symtab = [s for s in sections if s[1] == 2][0]
    strtab = sections[symtab[6]]

    # 1. Update module name in .gnu.linkonce.this_module (sec 38, off 0x24580)
    new_name = b"pps_kp_override\x00"
    name_pos = 0x24580 + 24
    data[name_pos : name_pos + len(new_name)] = new_name
    print("1. Updated module name to pps_kp_override")

    # 2. In __versions: zero out i2c_register_driver and i2c_del_driver
    data[0x25a40 : 0x25a40 + 64] = b"\x00" * 64
    data[0x25680 : 0x25680 + 64] = b"\x00" * 64
    print("2. Zeroed out i2c_register_driver and i2c_del_driver in __versions")

    # 3. In .strtab: write register_kprobe and unregister_kprobe at unused string
    # file_str_off = 0x3936be, st_name = 0x3305
    data[0x3936be : 0x3936be + 16] = b"register_kprobe\x00"
    data[0x3936be + 16 : 0x3936be + 34] = b"unregister_kprobe\x00"
    # Point symbol 783 to register_kprobe (st_name 0x3305)
    # Point symbol 812 to unregister_kprobe (st_name 0x3315)
    sym783_off = symtab[4] + 783 * 24
    data[sym783_off : sym783_off + 4] = struct.pack('<I', 0x3305)
    sym812_off = symtab[4] + 812 * 24
    data[sym812_off : sym812_off + 4] = struct.pack('<I', 0x3315)
    print("3. Configured symbols 783 (register_kprobe) and 812 (unregister_kprobe)")

    # 4. In .text: bypass CFI in __cfi_check (file offset 0x4000)
    data[0x4000 : 0x4004] = struct.pack('<I', 0xd65f03c0) # ret
    print("4. Patched __cfi_check at 0x4000 with ret (CFI bypass)")

    # 5. Pre-handlers in .text (FASE 3B: Dynamic Universal APDO current negotiation)
    # pre_handler1 at aw35615_tcpc_init (sec 5 off 0x1100 -> file off 0x5100)
    h1_insns = [
        0xd503233f, # 0x00: paciasp
        0xf9401022, # 0x04: ldr x2, [x1, #32] (regs->regs[4], announced max_current)
        0x711f405f, # 0x08: cmp w2, #2000 (is announced current >= 2000?)
        0x54000062, # 0x0c: b.hs 0x18 (if >= 2000, don't modify)
        0xb9008002, # 0x10: str w2, [x0, #128] (save real announced current to [kp1 + 0x80])
        0x5280fa02, # 0x14: mov w2, #2000 (elevate to 2000 to pass OEM check)
        0xf9001022, # 0x18: str x2, [x1, #32] (regs->regs[4] = 2000)
        0x2a1f03e0, # 0x1c: mov w0, wzr (return 0)
        0xd50323bf, # 0x20: autiasp
        0xd65f03c0  # 0x24: ret
    ]
    raw1 = b''.join(struct.pack('<I', w) for w in h1_insns)
    data[0x5100 : 0x5100 + len(raw1)] = raw1
    data[0x5100 + len(raw1) : 0x5144] = struct.pack('<7I', *([0xd503201f]*7))

    # pre_handler2 at aw35615_tcpc_deinit (sec 5 off 0x12dc -> file off 0x52dc)
    h2_insns = [
        0xd503233f, # 0x00: paciasp
        0xd1020003, # 0x04: sub x3, x0, #128 (&kp1 + 0x80)
        0xb9400062, # 0x08: ldr w2, [x3] (load saved announced current)
        0x711f405f, # 0x0c: cmp w2, #2000 (is saved current >= 2000?)
        0x54000042, # 0x10: b.hs 0x18 (keep OEM w3 = 2000)
        0xf9000c22, # 0x14: str x2, [x1, #24] (regs->regs[3] = saved current < 2000)
        0x2a1f03e0, # 0x18: mov w0, wzr (return 0)
        0xd50323bf, # 0x1c: autiasp
        0xd65f03c0  # 0x20: ret
    ]
    raw2 = b''.join(struct.pack('<I', w) for w in h2_insns)
    data[0x52dc : 0x52dc + len(raw2)] = raw2
    data[0x52dc + len(raw2) : 0x5320] = struct.pack('<8I', *([0xd503201f]*8))
    print("5. Installed dynamic pre_handler1 and pre_handler2 in .text")

    # 5.1 Zero out Section 9 (.rela.text.__cfi_check_fail) relocations targeting pre_handlers
    sec9_off = sections[9][4]
    sec9_size = sections[9][5]
    zeroed_relas = 0
    for idx in range(sec9_size // 24):
        entry_off = sec9_off + idx * 24
        r_offset, r_info, r_addend = struct.unpack('<QQq', data[entry_off:entry_off+24])
        if (0x1100 <= r_offset < 0x1144) or (0x12dc <= r_offset < 0x1320):
            data[entry_off : entry_off + 24] = b"\x00" * 24
            zeroed_relas += 1
    print(f"5.1 Zeroed out {zeroed_relas} relocations in Section 9 (.rela.text.__cfi_check_fail)")

    # 6. Allocate struct kprobe in .data (sec 3, file off 0x60)
    # Write symbol_name string "usbpd_pd_contact\x00" at .data offset 0x5e0 (file off 0x640)
    sym_name = b"usbpd_pd_contact\x00"
    data[0x640 : 0x640 + len(sym_name)] = sym_name

    # Zero out 0x600..0x800 in .data (file off 0x660..0x860)
    data[0x660 : 0x860] = b"\x00" * 512
    # Initialize detected_current at .data offset 0x680 (file off 0x6e0) with 2000
    data[0x6e0 : 0x6e4] = struct.pack('<I', 2000)
    # kp1 is at .data offset 0x600.
    # kp1.addr = NULL (offset 0x28 -> 0)
    # kp1.symbol_name will be relocated to .data + 0x5e0 (offset 0x30)
    # kp1.offset = 0x250 (offset 0x38, file off 0x60 + 0x638 = 0x698)
    data[0x698 : 0x69c] = struct.pack('<I', 0x250)

    # kp2 is at .data offset 0x700.
    # kp2.addr = NULL (offset 0x28 -> 0)
    # kp2.symbol_name will be relocated to .data + 0x5e0 (offset 0x30)
    # kp2.offset = 0x2b0 (offset 0x38, file off 0x60 + 0x738 = 0x798)
    data[0x798 : 0x79c] = struct.pack('<I', 0x2b0)
    print("6. Configured kp1 (symbol_name=usbpd_pd_contact, offset=0x250) and kp2 (symbol_name=usbpd_pd_contact, offset=0x2b0) in .data")

    # 7. Relocations in Section 20 (.rela.data.aw35615_driver, file off 0x46448)
    sec20_off = 0x46448
    # R_AARCH64_ABS64 = 257
    r_info_data = (734 << 32) | 257 # sym 734: Section 3 .data
    r_info_text = (736 << 32) | 257 # sym 736: Section 5 .text

    # Rela 0: kp1.symbol_name at .data offset 0x630 -> .data + 0x5e0
    data[sec20_off + 0*24 : sec20_off + 1*24] = struct.pack('<QQq', 0x630, r_info_data, 0x5e0)
    # Rela 1: kp1.pre_handler at .data offset 0x640 -> aw35615_tcpc_init (.text + 0x1100)
    data[sec20_off + 1*24 : sec20_off + 2*24] = struct.pack('<QQq', 0x640, r_info_text, 0x1100)
    # Rela 2: kp2.symbol_name at .data offset 0x730 -> .data + 0x5e0
    data[sec20_off + 2*24 : sec20_off + 3*24] = struct.pack('<QQq', 0x730, r_info_data, 0x5e0)
    # Rela 3: kp2.pre_handler at .data offset 0x740 -> aw35615_tcpc_deinit (.text + 0x12dc)
    data[sec20_off + 3*24 : sec20_off + 4*24] = struct.pack('<QQq', 0x740, r_info_text, 0x12dc)

    # Zero out remaining 154 entries
    data[sec20_off + 4*24 : sec20_off + 158 * 24] = b"\x00" * (154 * 24)
    # Update Section 20 header sh_size to 4 * 24 = 96
    sec20_sh_off = e_shoff + 20 * e_shentsize
    data[sec20_sh_off + 32 : sec20_sh_off + 40] = struct.pack('<Q', 96)
    print("7. Configured Section 20 relocations for symbol_name and pre_handler")

    # 8. Assemble init_module (sec 10, file off 0x24354)
    init_insns = [
        0xd503233f, # 0x00: paciasp
        0xf800865e, # 0x04: str x30, [x18], #8
        0xa9be53f3, # 0x08: stp x19, x20, [sp, #-32]!
        0xa9017bfd, # 0x0c: stp x29, x30, [sp, #16]
        0x910043fd, # 0x10: add x29, sp, #16
        0x90000013, # 0x14: adrp x19, kp1 (Rela 0: sym 734 .data, addend 0x600)
        0x91000273, # 0x18: add x19, x19, :lo12:kp1 (Rela 1: sym 734 .data, addend 0x600)
        0xaa1303e0, # 0x1c: mov x0, x19 (&kp1)
        0x94000000, # 0x20: bl register_kprobe (Rela 2: sym 783)
        0x91040260, # 0x24: add x0, x19, #256 (&kp2)
        0x94000000, # 0x28: bl register_kprobe (Rela 3: sym 783)
        0x2a1f03e0, # 0x2c: mov w0, wzr
        0xa9417bfd, # 0x30: ldp x29, x30, [sp, #16]
        0xa8c253f3, # 0x34: ldp x19, x20, [sp], #32
        0xf85f8e5e, # 0x38: ldr x30, [x18, #-8]!
        0xd50323bf, # 0x3c: autiasp
        0xd65f03c0  # 0x40: ret
    ]
    init_code = b"".join(struct.pack('<I', w) for w in init_insns)
    init_file_off = 0x24354
    data[init_file_off : init_file_off + len(init_code)] = init_code

    # cleanup_module at 0x24398
    exit_insns = [
        0x2a1f03e0, # mov w0, wzr
        0xd65f03c0  # ret
    ]
    exit_code = b"".join(struct.pack('<I', w) for w in exit_insns)
    exit_file_off = init_file_off + len(init_code)
    data[exit_file_off : exit_file_off + len(exit_code)] = exit_code

    # Update Sec 10 (.init.text) and Sec 12 (.exit.text) headers
    sec10_sh_off = e_shoff + 10 * e_shentsize
    data[sec10_sh_off + 24 : sec10_sh_off + 32] = struct.pack('<Q', init_file_off)
    data[sec10_sh_off + 32 : sec10_sh_off + 40] = struct.pack('<Q', len(init_code))

    sec12_sh_off = e_shoff + 12 * e_shentsize
    data[sec12_sh_off + 24 : sec12_sh_off + 32] = struct.pack('<Q', exit_file_off)
    data[sec12_sh_off + 32 : sec12_sh_off + 40] = struct.pack('<Q', len(exit_code))

    # Sec 13 (.rela.exit.text): size = 0
    sec13_sh_off = e_shoff + 13 * e_shentsize
    data[sec13_sh_off + 32 : sec13_sh_off + 40] = struct.pack('<Q', 0)
    print(f"8. Wrote init_module ({len(init_code)} B) and cleanup_module ({len(exit_code)} B)")

    # 9. Relocations in Section 11 (.rela.init.text, file off 0x462c8)
    sec11_off = 0x462c8
    # R_AARCH64_ADR_PREL_PG_HI21 = 275
    # R_AARCH64_ADD_ABS_LO12_NC = 277
    # R_AARCH64_CALL26 = 283
    # Rela 0: adrp x19, kp1 (.data + 0x600, sym 734)
    data[sec11_off + 0*24 : sec11_off + 0*24 + 24] = struct.pack('<QQq', 0x14, (734 << 32) | 275, 0x600)
    # Rela 1: add x19, x19, :lo12:kp1 (.data + 0x600, sym 734)
    data[sec11_off + 1*24 : sec11_off + 1*24 + 24] = struct.pack('<QQq', 0x18, (734 << 32) | 277, 0x600)
    # Rela 2: bl register_kprobe (sym 783)
    data[sec11_off + 2*24 : sec11_off + 2*24 + 24] = struct.pack('<QQq', 0x20, (783 << 32) | 283, 0)
    # Rela 3: bl register_kprobe (sym 783)
    data[sec11_off + 3*24 : sec11_off + 3*24 + 24] = struct.pack('<QQq', 0x28, (783 << 32) | 283, 0)
    # Rela 4: NONE
    data[sec11_off + 4*24 : sec11_off + 4*24 + 24] = struct.pack('<QQq', 0, 0, 0)
    # Update Section 11 header sh_size to 4 * 24 = 96
    sec11_sh_off = e_shoff + 11 * e_shentsize
    data[sec11_sh_off + 32 : sec11_sh_off + 40] = struct.pack('<Q', 4 * 24)
    print("9. Configured Section 11 relocations for init_module")

    # 10. Update symtab entries for init_module and cleanup_module
    for i in range(symtab[5] // 24):
        off = symtab[4] + i * 24
        st_name = struct.unpack('<I', data[off:off+4])[0]
        str_off = strtab[4] + st_name
        name = data[str_off : data.find(b'\x00', str_off)].decode('ascii', errors='ignore')
        if name == 'init_module':
            data[off + 6 : off + 8] = struct.pack('<H', 10)
            data[off + 8 : off + 16] = struct.pack('<Q', 0)
            data[off + 16 : off + 24] = struct.pack('<Q', len(init_code))
        elif name == 'cleanup_module':
            data[off + 6 : off + 8] = struct.pack('<H', 12)
            data[off + 8 : off + 16] = struct.pack('<Q', 0)
            data[off + 16 : off + 24] = struct.pack('<Q', len(exit_code))
    print("10. Updated symtab entries for init_module and cleanup_module")

    out_file = 'pps_kprobe_override.ko'
    with open(out_file, 'wb') as f:
        f.write(data)
    print(f"SUCCESS: Generated {out_file} ({len(data)} bytes)!")

if __name__ == '__main__':
    build_kprobe_override()
