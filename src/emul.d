module emul;

import zemu;
import std.format: format;
import std.string, std.array;
import std.algorithm, std.file; 
import std.regex, std.stdio;
import std.traits, std.range;
import mmu;

Zemu emul;
Registers *regs;
ubyte *ram;
ubyte *ports;
int *cycleCount;
bool contLoop = true;
enum Mode {Main, Misc, Bit, IX, IX_Bit, IY, IY_Bit}

// TODO: Must refactor this into controller.d, so that I can use the CPU/Controller as a library
// TODO: Can change lddr and similar vars by just calling ldd and only incrementing the PC when BC = 0 (and also adding proper T vals)
unittest {
    import tests;
    compileTests();

    auto mem = new MMU();
    emul = new Zemu(&mem.read_ram, 
                    &mem.read_ram_16, 
                    &mem.write_ram, 
                    &mem.write_ram_16, 
                    &mem.load, 
                    &mem.dump,
                    mem.ram,
                    mem.ports);

    regs = &emul.regs;
}

void main(string[] args) {
    /*
    ubyte num = 0x7D; 
    string hexStr = format("%02X", num); 
    writeln("The hexadecimal representation is: ", hexStr);
    auto regex = regex(oneOp[3]);
    auto match = matchFirst(format("%02X", num), regex);
    if (match) {
        writeln("MATCH");
    } else writeln("NO MATCH");
    */

    emul = new Zemu();
    regs = &emul.regs;
    ram = cast(ubyte*) &emul.ram;
    ports = cast(ubyte*) &emul.ports;
    cycleCount = &emul.T;

    z80_init();
    // MMU mmu = new MMU();
    // mmu.read_ram(cast(ushort)0x06);
    if (args.length == 1) {
        writeln("No argument provided");
        return;
    }

    emul.z80_mem_load(args[1]);
    int cycles = z80_execute(1024);
    printInfo(cycles);
}

void printInfo(int cyc) {
    writefln("A:  %02X", regs.A);
    writefln("F:  %02X", regs.F);
    writefln("B:  %02X", regs.B);
    writefln("C:  %02X", regs.C);
    writefln("D:  %02X", regs.D);
    writefln("E:  %02X", regs.E);
    writefln("H:  %02X", regs.H);
    writefln("L:  %02X", regs.L);
    writefln("I:  %02X", regs.I);
    writefln("R:  %02X", regs.R);
    writefln("A': %02X", regs.AP);
    writefln("F': %02X", regs.FP);
    writefln("B': %02X", regs.BP);
    writefln("C': %02X", regs.CP);
    writefln("D': %02X", regs.DP);
    writefln("E': %02X", regs.EP);
    writefln("IFF1: %02X", regs.iff1);
    writefln("IFF2: %02X", regs.iff2);
    writefln("IM: %02X", 0);
    writefln("Hidden 16-Bit Math: %02X", 0);
    writefln("IX: %04X", regs.IX);
    writefln("IY: %04X", regs.IY);
    writefln("PC: %04X", regs.PC);
    writefln("SP: %04X", regs.SP);
    writefln("Ran %d cycles", cyc);
    emul.z80_mem_dump("dump.bin");
}

ubyte getY(ubyte opcode) {
    return (opcode & 0b00111000) >> 3;
}

ubyte getZ(ubyte opcode) {
    return (opcode & 0b00000111);
}

ubyte getP(ubyte opcode) {
    return (opcode & 0b00110000) >> 4;
}

Register r_table(ubyte r) {
    switch (r) {
        case 0: return Register.B;
        case 1: return Register.C;
        case 2: return Register.D;
        case 3: return Register.E;
        case 4: return Register.H;
        case 5: return Register.L;
        case 7: return Register.A;
        default: assert(0);
    }
}

Register r_table(ubyte r, Mode mode) {
    assert(mode == Mode.IX || mode == Mode.IY || mode == Mode.IX_Bit || mode == Mode.IY_Bit);
    switch (r) {
        case 0: return Register.B;
        case 1: return Register.C;
        case 2: return Register.D;
        case 3: return Register.E;
        case 4: return (mode == Mode.IX || mode == Mode.IX_Bit) ? Register.IXH : Register.IYH;
        case 5: return (mode == Mode.IX || mode == Mode.IX_Bit) ? Register.IXL : Register.IYL;
        case 7: return Register.A;
        default: assert(0);
    }
}

Register ss_table(ubyte ss) {
    switch (ss) {
        case 0: return Register.BC;
        case 1: return Register.DE;
        case 2: return Register.HL;
        case 3: return Register.SP;
        default: assert(0);
    }
}

Register pp_table(ubyte pp) {
    switch (pp) {
        case 0: return Register.BC;
        case 1: return Register.DE;
        case 2: return Register.IX;
        case 3: return Register.SP;
        default: assert(0);
    }
}

Register rr_table(ubyte rr) {
    switch (rr) {
        case 0: return Register.BC;
        case 1: return Register.DE;
        case 2: return Register.IY;
        case 3: return Register.SP;
        default: assert(0);
    }
}

Register qq_table(ubyte qq) {
    switch (qq) {
        case 0: return Register.BC;
        case 1: return Register.DE;
        case 2: return Register.HL;
        case 3: return Register.AF;
        default: assert(0);
    }
}

CC cc_table(ubyte cc) {
    switch (cc) {
        case 0: return CC.NZ;
        case 1: return CC.Z;
        case 2: return CC.NC;
        case 3: return CC.C;
        case 4: return CC.PO;
        case 5: return CC.PE;
        case 6: return CC.P;
        case 7: return CC.M;
        default: assert(0);
    }
}

int z80_execute(int cycles) {
    contLoop = true;
    *cycleCount = 0;
    while (*cycleCount < cycles && contLoop) {
        Mode mode = getMode();
        ubyte op = getOpcode(mode);
        
        switch (mode) {
            case Mode.Main:   mainTable(op); break;
            case Mode.Misc:   miscTable(op); break;
            case Mode.Bit:    bitTable(op); break;
            case Mode.IX:     // Fall-through
            case Mode.IY:     xyTable(op, mode); break;
            case Mode.IX_Bit: // Fall-through
            case Mode.IY_Bit: xyBitTable(op, mode); break;
            default: assert(0);
        }
    }
    
    return *cycleCount;
}

Mode getMode() {
    if (ram[regs.PC] == 0xDD && ram[regs.PC + 1] == 0xCB) {return Mode.IX_Bit; } 
    else if (ram[regs.PC] == 0xFD && ram[regs.PC + 1] == 0xCB) { return Mode.IY_Bit; } 
    else if (ram[regs.PC] == 0xED) { return Mode.Misc; } 
    else if (ram[regs.PC] == 0xCB) { return Mode.Bit; } 
    else if (ram[regs.PC] == 0xDD) { return Mode.IX; }
    else if (ram[regs.PC] == 0xFD) { return Mode.IY; }
    else return Mode.Main;
    assert(0);
}

void T(int i) {
    *cycleCount += i;
}

// TODO
void z80_init() {
    regs.IX = 0xffff;
    regs.IY = 0xffff;
    emul.setFlagCond(zemu.Flag.Z, true);
}

ubyte getOpcode(Mode mode) {
    switch (mode) {
        case Mode.IX_Bit: 
        case Mode.IY_Bit: 
            emul.incrementR(3); // Change to 2, 3 used for lsebald tests
            return ram[regs.PC + 3];
        
        case Mode.IX: 
        case Mode.IY:
        case Mode.Bit: 
        case Mode.Misc: 
            emul.incrementR(2);
            return ram[regs.PC + 1];

        case Mode.Main: 
            emul.incrementR(1);
            return ram[regs.PC];
        default: assert(0);
    }
}

void mainTable(ubyte op) {
    ubyte y = getY(op), z = getZ(op), p = getP(op);

    switch (op) {
        case 0x40: .. case 0x45: case 0x47: // ld r, r'
        case 0x48: .. case 0x4D: case 0x4F:
        case 0x50: .. case 0x55: case 0x57:
        case 0x58: .. case 0x5D: case 0x5F:
        case 0x60: .. case 0x65: case 0x67:
        case 0x68: .. case 0x6D: case 0x6F:
        case 0x78: .. case 0x7D: case 0x7F:
            emul.ld_r_r(r_table(y), r_table(z));
            regs.PC += 1;
            T(4);
            break;

        case 0x04: case 0x14: case 0x24: // inc r
        case 0x0C: case 0x1C: case 0x2C: case 0x3C:
            emul.inc_r(r_table(y));
            regs.PC += 1;
            T(4);
            break;

        case 0x05: case 0x15: case 0x25: // dec r
        case 0x0D: case 0x1D: case 0x2D: case 0x3D: 
            emul.dec_r(r_table(y));
            regs.PC += 1;
            T(4);
            break;

        case 0x03: case 0x13: case 0x23: case 0x33: // inc ss
            emul.inc_rr(ss_table(p));
            regs.PC += 1;
            T(6);
            break;

        case 0x0B: case 0x1B: case 0x2B: case 0x3B: // dec ss
            emul.dec_rr(ss_table(p));
            regs.PC += 1; 
            T(6);
            break;

        case 0x34: // inc (hl)
            emul.inc_addr(regs.HL);
            regs.PC += 1;
            T(11);
            break;

        case 0x35: // dec (hl)
            emul.dec_addr(regs.HL);
            regs.PC += 1;
            T(11);
            break;

        case 0x00: // nop
            emul.nop();
            regs.PC += 1;
            T(4);
            break;
        
        case 0x46: case 0x56: case 0x66: // ld r, (hl)
        case 0x4E: case 0x5E: case 0x6E: case 0x7E:
            emul.ld_r_addr(r_table(y), regs.HL);
            regs.PC += 1;
            T(7);
            break;

        case 0x70: .. case 0x75: case 0x77: // ld (hl), r
            emul.ld_addr_r(regs.HL, r_table(z));
            regs.PC += 1;
            T(7);
            break;

        case 0x80: .. case 0x85: case 0x87: // add a, r
            emul.add_a_r(r_table(z));
            regs.PC += 1;
            T(4);
            break;

        case 0x86: // add a, (hl)
            emul.add_a_addr(regs.HL);
            regs.PC += 1;
            T(7);
            break;

        case 0x88: .. case 0x8D: case 0x8F: // adc a, r
            emul.adc_a_r(r_table(z));
            regs.PC += 1; 
            T(4);
            break;

        case 0x8E: // adc a, (hl)
            emul.adc_a_addr(regs.HL);
            regs.PC += 1;
            T(7);
            break;
        
        case 0x90: .. case 0x95: case 0x97: // sub a, r
            emul.sub_a_r(r_table(z));
            regs.PC += 1;
            T(4);
            break;

        case 0x96: // sub a, (hl)
            emul.sub_a_addr(regs.HL);
            regs.PC += 1; 
            T(7);
            break;

        case 0x98: .. case 0x9D: case 0x9F: // sbc a, r
            emul.sbc_a_r(r_table(z));
            regs.PC += 1;
            T(4);
            break;

        case 0x9E: // sbc a, (hl)
            emul.sbc_a_addr(regs.HL);
            regs.PC += 1;
            T(7);
            break;

        case 0xA0: .. case 0xA5: case 0xA7: // and r
            emul.and_r(r_table(z));
            regs.PC += 1;
            T(4);
            break;

        case 0xA6: // and (hl)
            emul.and_addr(regs.HL);
            regs.PC += 1;
            T(7);
            break;

        case 0xA8: .. case 0xAD: case 0xAF: // xor r
            emul.xor_r(r_table(z));
            regs.PC += 1;
            T(4);
            break;

        case 0xAE: // xor (hl)
            emul.xor_addr(regs.HL);
            regs.PC += 1;
            T(7);
            break;
       
        case 0xB0: .. case 0xB5: case 0xB7: // or r
            emul.or_r(r_table(z));
            regs.PC += 1; 
            T(4);
            break;

        case 0xB6: // or (hl)
            emul.or_addr(regs.HL);
            regs.PC += 1;
            T(7);
            break;

        case 0xB8: .. case 0xBD: case 0xBF: // cp r
            emul.cp_r(r_table(z));
            regs.PC += 1;
            T(4);
            break;

        case 0xBE: // cp (hl)
            emul.cp_addr(regs.HL);
            regs.PC += 1;
            T(7);
            break;
        
        case 0xC5: case 0xD5: case 0xE5: case 0xF5: // push qq
            emul.push_qq(qq_table(p));
            regs.PC += 1;
            T(11);
            break;
        
        case 0xC1: case 0xD1: case 0xE1: case 0xF1: // pop qq
            emul.pop_qq(qq_table(p));
            regs.PC += 1;
            T(11);
            break;

        case 0xD9: // exx
            emul.exx();
            regs.PC += 1;
            T(4);
            break;

        case 0x08: // ex af, af'
            emul.ex_dd_dd(Register.AF, Register.AFP);
            regs.PC += 1;
            T(4);
            break;

        case 0xEB: // ex de, hl
            emul.ex_dd_dd(Register.DE, Register.HL);
            regs.PC += 1;
            T(4);
            break;

        case 0xE3: // ex (sp), hl
            emul.ex_addr_dd(regs.SP, Register.HL);
            regs.PC += 1;
            T(19);
            break;

        case 0xF9: // ld sp, hl
            emul.ld_dd_dd(Register.SP, Register.HL);
            regs.PC += 1;
            T(6);
            break;

        case 0x02: // ld (bc), a
            emul.ld_addr_r(regs.BC, Register.A);
            regs.PC += 1; 
            T(7);
            break; 

        case 0x12: // ld (de), a
            emul.ld_addr_r(regs.DE, Register.A);
            regs.PC += 1;
            T(7);
            break;

        case 0x27: // daa
            emul.daa();
            regs.PC += 1;
            T(4);
            break;
        
        case 0x2F: // cpl
            emul.cpl();
            regs.PC += 1;
            T(4);
            break;
        
        case 0x37: // scf
            emul.scf();
            regs.PC += 1;
            T(4);
            break;

        case 0x3F: // ccf
            emul.ccf();
            regs.PC += 1;
            T(4);
            break;

        case 0x76: // halt
            emul.halt();
            regs.PC += 1;
            T(4);
            // TODO: Temp, remove later
            contLoop = false;
            break;

        case 0xF3: // di
            emul.di();
            regs.PC += 1;
            T(4);
            break;

        case 0xFB: // ei
            emul.ei();
            regs.PC += 1;
            T(4);
            break;
        
        case 0x09: case 0x19: case 0x29: case 0x39: // add hl, ss
            emul.add_rr_rr(Register.HL, ss_table(p));
            regs.PC += 1;
            T(11);
            break;

        case 0x07: // rlca
            emul.rlca();
            regs.PC += 1;
            T(4);
            break;

        case 0x0F: // rrca
            emul.rrca();
            regs.PC += 1;
            T(4);
            break;

        case 0x17: // rla
            emul.rla();
            regs.PC += 1;
            T(4);
            break;

        case 0x1F: // rra
            emul.rra();
            regs.PC += 1;
            T(4);
            break;

        case 0xC9: // ret
            emul.ret();
            T(10);
            break;

        case 0xC0: case 0xD0: case 0xE0: case 0xF0: // ret cc
        case 0xC8: case 0xD8: case 0xE8: case 0xF8: 
            T(emul.ret_cc(cc_table(y)));
            regs.PC += 1;
            break;

        case 0x06: case 0x16: case 0x26: // ld r, n
        case 0x0E: case 0x1E: case 0x2E: case 0x3E:
            emul.ld_r_n(r_table(y), emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(7);
            break;

        case 0x36: // ld (hl), n
            emul.ld_addr_n(regs.HL, emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(10);
            break;

        case 0xC6: // add a, n
            emul.add_a_n(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(7);
            break;

        case 0xCE: // adc a, n
            emul.adc_a_n(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(7);
            break;

        case 0xD6: // sub a, n
            emul.sub_a_n(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(7);
            break;

        case 0xDE: // sbc a, n
            emul.sbc_a_n(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(7);
            break;

        case 0xE6: // and n
            emul.and_n(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(7);
            break;

        case 0xEE: // xor n
            emul.xor_n(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(7);
            break;

        case 0xF6: // or n
            emul.or_n(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(7);
            break;

        case 0xFE: // cp n
            emul.cp_n(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(7);
            break;

        case 0x18: // jr e
            emul.jr_e(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(12);
            break;

        case 0x38: // jr c, e
            T(emul.jr_cc_e(CC.C, emul.z80_mem_read(cast(ushort)(regs.PC + 1))));
            regs.PC += 2;
            break;

        case 0x30: // jr nc, e
            T(emul.jr_cc_e(CC.NC, emul.z80_mem_read(cast(ushort)(regs.PC + 1))));
            regs.PC += 2;
            break;

        case 0x28: // jr z, e
            T(emul.jr_cc_e(CC.Z, emul.z80_mem_read(cast(ushort)(regs.PC + 1))));
            regs.PC += 2;
            break;
        
        case 0x20: // jr nz, e
            T(emul.jr_cc_e(CC.NZ, emul.z80_mem_read(cast(ushort)(regs.PC + 1))));
            regs.PC += 2;
            break;

        case 0x10: // djnz e
            emul.djnz_e(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(13);
            break;
        
        case 0xDB: // in a, (n)
            emul.in_a_n_addr(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(11);
            break;
        
        case 0xD3: // out (n), a
            emul.out_n_addr_a(emul.z80_mem_read(cast(ushort)(regs.PC + 1)));
            regs.PC += 2;
            T(11);
            break;

        case 0x3A: // ld a, (nn)
            emul.ld_r_addr(Register.A, emul.z80_mem_read16(cast(ushort)(regs.PC + 1)));
            regs.PC += 3;
            T(13);
            break;

        case 0x32: // ld (nn), a
            emul.ld_addr_r(emul.z80_mem_read16(cast(ushort)(regs.PC + 1)), Register.A);
            regs.PC += 3;
            T(13);
            break;

        case 0x01: case 0x11: case 0x21: case 0x31: // ld dd, nn
            emul.ld_dd_nn(ss_table(p), emul.z80_mem_read16(cast(ushort)(regs.PC + 1)));
            regs.PC += 3;
            T(10);
            break;

        case 0x2A: // ld hl, (nn)
            emul.ld_dd_nn(Register.HL, emul.z80_mem_read16(cast(ushort)(regs.PC + 1)));
            regs.PC += 3;
            T(16);
            break;

        case 0x22: // ld (nn), hl
            emul.ld_addr_r(emul.z80_mem_read16(cast(ushort)(regs.PC + 1)), Register.HL);
            regs.PC += 3;
            T(16);
            break;

        case 0xC3: // jp nn
            emul.jp_nn(emul.z80_mem_read16(cast(ushort)(regs.PC + 1)));
            // regs.PC += 3;
            T(10);
            break;

        case 0xC2: case 0xD2: case 0xE2: case 0xF2: // jp cc, nn
        case 0xCA: case 0xDA: case 0xEA: case 0xFA:
            emul.jp_cc_nn(cc_table(y), emul.z80_mem_read16(cast(ushort)(regs.PC + 1)));
            regs.PC += 3;
            T(10);
            break;

        case 0xCD: // call nn
            // TODO: Must increment PC before push, but also use data as a base (to get nn). Is this what memptr is for?
            ushort addr = emul.z80_mem_read16(cast(ushort)(regs.PC + 1));
            regs.PC += 3;
            emul.call_nn(addr);
            T(17);
            break;

        case 0xC4: case 0xD4: case 0xE4: case 0xF4: // call cc, nn
        case 0xCC: case 0xDC: case 0xEC: case 0xFC:
            T(emul.call_cc_nn(cc_table(y), emul.z80_mem_read16(cast(ushort)(regs.PC + 1))));
            regs.PC += 3;
            break;
        default: assert(0);
    }
}

void miscTable(ubyte op) {
    ubyte y = getY(op), p = getP(op);

    switch (op) {
        case 0x40: case 0x50: case 0x60: case 0x70: // in section
        case 0x48: case 0x58: case 0x68: case 0x78:
            emul.in_r_C_addr(r_table(y));
            regs.PC += 2;
            T(12);
            break;

        case 0x41: case 0x51: case 0x61: case 0x71: // out section
        case 0x49: case 0x59: case 0x69: case 0x79: 
            emul.out_C_addr_r(r_table(y));
            regs.PC += 2;
            T(12);
            break;            

        case 0x42: case 0x52: case 0x62: case 0x72: // SBC
            emul.sbc_rr_rr(Register.HL, ss_table(p));
            regs.PC += 2;
            T(15);
            break;

        case 0x4A: case 0x5A: case 0x6A: case 0x7A: // ADC
            emul.adc_rr_rr(Register.HL, ss_table(p));
            regs.PC += 2;
            T(15);
            break;

        case 0x43: case 0x53: case 0x63: case 0x73: // ld (nn), dd
            emul.ld_addr_dd(emul.z80_mem_read(cast(ushort)(regs.PC + 2)), ss_table(p));
            regs.PC += 4;
            T(20);
            break;
            
        case 0x4B: case 0x5B: case 0x6B: case 0x7B: // ld dd, (nn)
            emul.ld_dd_addr(ss_table(p), emul.z80_mem_read16(cast(ushort)(regs.PC + 2)));
            regs.PC += 4;
            T(20);
            break;

        case 0x44: // neg
            emul.neg(); 
            regs.PC += 2;
            T(8); 
            break;

        case 0x4D: // reti
            emul.reti();
            // regs.PC += 2;
            T(14);
            break;

        case 0x45: // retn
            emul.retn();
            // regs.PC += 2;
            T(14);
            break;

        case 0x46: // im0
            emul.im_0();
            regs.PC += 2;
            T(8);
            break;

        case 0x56: // im1
            emul.im_1();
            regs.PC += 2;
            T(8);
            break;

        case 0x5E: // im2
            emul.im_2();
            regs.PC += 2;
            T(8);
            break;

        case 0x47: // ld i, a
            emul.ld_r_r(Register.I, Register.A);
            regs.PC += 2;
            T(9);
            break;

        case 0x57: // ld a, i
            emul.ld_r_r(Register.A, Register.I);
            regs.PC += 2;
            T(9);
            break;

        case 0x4F: // ld r, a 
            emul.ld_r_r(Register.R, Register.A);
            regs.PC += 2;
            T(9);
            break;
    
        case 0x5F: // ld a, r
            emul.ld_r_r(Register.A, Register.R);
            regs.PC += 2;
            T(9);
            break;

        case 0x6F: // rld
            emul.rld();
            regs.PC += 2;
            T(18);
            break;

        case 0x67: // rrd
            emul.rrd();
            regs.PC += 2;
            T(18);
            break;

        case 0xA0: // ldi
            emul.ldi();
            regs.PC += 2; 
            T(16);
            break;

        case 0xB0: // ldir
            emul.ldi();
            if (regs.BC != 0) { T(21); }
            else { T(16); regs.PC += 2; }
            break; 

        case 0xA1: // cpi
            emul.cpi();
            regs.PC += 2; 
            T(16);
            break;

        case 0xB1: // cpir
            emul.cpi();
            if (regs.BC != 0) { T(21); }
            else { T(16); regs.PC += 2; }
            break;

        case 0xA2: // ini
            emul.ini();
            regs.PC += 2;
            T(16);
            break;
        case 0xB2: // inir
            emul.ini();
            if (regs.BC != 0) { T(21); }
            else { T(16); regs.PC += 2; }
            break;

        case 0xA3: // outi
            emul.outi();
            regs.PC += 2;
            T(16);
            break;
        case 0xB3: // otir
            emul.outi();
            if (regs.BC != 0) { T(21); }
            else { T(16); regs.PC += 2; }
            break;

        case 0xA8: // ldd
            emul.ldd();
            regs.PC += 2;
            T(16);
            break;

        case 0xB8: // lddr
            emul.ldd();
            if (regs.BC != 0) { T(21); }
            else { T(16); regs.PC += 2; }
            break;
        
        case 0xA9: // cpd
            emul.cpd();
            regs.PC += 2;
            T(16);
            break;

        case 0xB9: // cpdr
            emul.cpd();
            if (regs.BC != 0) { T(21); }
            else { T(16); regs.PC += 2; }
            break;
        
        case 0xAA: // ind
            emul.ind();
            regs.PC += 2;
            T(16);
            break;
        case 0xBA: // indr
            emul.ind();
            if (regs.BC != 0) { T(21); }
            else { T(16); regs.PC += 2; }
            break;

        case 0xAB: // outd
            emul.outd();
            regs.PC += 2;
            T(16);
            break;
        case 0xBB: // otdr
            emul.outd();
            if (regs.BC != 0) { T(21); }
            else { T(16); regs.PC += 2; }
            break;
        default: assert(0);
    }
}

void bitTable(ubyte op) {
    ubyte y = getY(op), z = getZ(op);
    
    switch (op) {
        case 0x00: .. case 0x05: case 0x07: // rlc r
            emul.rlc_r(r_table(z));
            regs.PC += 2;
            T(8);
            break;

        case 0x06: // rlc (hl)
            emul.rlc_addr(regs.HL);
            regs.PC += 2;
            T(15);
            break;

        case 0x08: .. case 0x0D: case 0x0F: // rrc r
            emul.rrc_r(r_table(z));
            regs.PC += 2;
            T(8);
            break;

        case 0x0E: // rrc (hl)
            emul.rrc_addr(regs.HL);
            regs.PC += 2;
            T(15);
            break;

        case 0x10: .. case 0x15: case 0x17: // rl r
            emul.rl_r(r_table(z));
            regs.PC += 2;
            T(8);
            break; 

        case 0x16: // rl (hl)
            emul.rl_addr(regs.HL);
            regs.PC += 2;
            T(15);
            break;

        case 0x18: .. case 0x1D: case 0x1F: // rr r
            emul.rr_r(r_table(z));
            regs.PC += 2;
            T(8);
            break;

        case 0x1E: // rr (hl)
            emul.rr_addr(regs.HL);
            regs.PC += 2;
            T(15); 
            break;

        case 0x20: .. case 0x25: case 0x27: // sla r
            emul.sla_r(r_table(z));
            regs.PC += 2;
            T(8);
            break;

        case 0x26: // sla (hl)
            emul.sla_addr(regs.HL);
            regs.PC += 2;
            T(15);
            break;

        case 0x28: .. case 0x2D: case 0x2F: // sra r
            emul.sra_r(r_table(z));
            regs.PC += 2;
            T(8);
            break;
    
        case 0x2E: // sra (hl)
            emul.sra_addr(regs.HL);
            regs.PC += 2;
            T(15);
            break;

        case 0x30: .. case 0x35: case 0x37: // sll r
            emul.sll_r(r_table(z));
            regs.PC += 2;
            T(8);
            break;

        case 0x36: // sll (hl)
            emul.sll_addr(regs.HL);
            regs.PC += 2;
            T(15);
            break;

        case 0x38: .. case 0x3D: case 0x3F: // srl r
            emul.srl_r(r_table(z));
            regs.PC += 2;
            T(8);
            break;

        case 0x3E: // srl (hl)
            emul.srl_addr(regs.HL);
            regs.PC += 2; 
            T(15);
            break;

        case 0x40: .. case 0x45: case 0x47: // bit b, r
        case 0x48: .. case 0x4D: case 0x4F:
        case 0x50: .. case 0x55: case 0x57:
        case 0x58: .. case 0x5D: case 0x5F: 
        case 0x60: .. case 0x65: case 0x67:
        case 0x68: .. case 0x6D: case 0x6F:
        case 0x70: .. case 0x75: case 0x77:
        case 0x78: .. case 0x7D: case 0x7F:
            emul.bit_b_r(y, r_table(z));
            regs.PC += 2;
            T(8);
            break;

        case 0x46: case 0x4E: // bit b, (hl)
        case 0x56: case 0x5E:
        case 0x66: case 0x6E: 
        case 0x76: case 0x7E:
            emul.bit_b_addr(y, regs.HL);
            regs.PC += 2;
            T(12);
            break; 

        case 0x80: .. case 0x85: case 0x87: // res b, r
        case 0x88: .. case 0x8D: case 0x8F:
        case 0x90: .. case 0x95: case 0x97:
        case 0x98: .. case 0x9D: case 0x9F:
        case 0xA0: .. case 0xA5: case 0xA7:
        case 0xA8: .. case 0xAD: case 0xAF:
        case 0xB0: .. case 0xB5: case 0xB7:
        case 0xB8: .. case 0xBD: case 0xBF:
            emul.res_b_r(y, r_table(z));
            regs.PC += 2;
            T(8);
            break;

        case 0x86: case 0x8E: // res b, (hl)
        case 0x96: case 0x9E: 
        case 0xA6: case 0xAE: 
        case 0xB6: case 0xBE: 
            emul.res_b_addr(y, regs.HL);
            regs.PC += 2;
            T(15);
            break;

        case 0xC0: .. case 0xC5: case 0xC7: // set b, r
        case 0xC8: .. case 0xCD: case 0xCF: 
        case 0xD0: .. case 0xD5: case 0xD7:
        case 0xD8: .. case 0xDD: case 0xDF:
        case 0xE0: .. case 0xE5: case 0xE7:
        case 0xE8: .. case 0xED: case 0xEF:
        case 0xF0: .. case 0xF5: case 0xF7:
        case 0xF8: .. case 0xFD: case 0xFF:
            emul.set_b_r(y, r_table(z));
            regs.PC += 2;
            T(8);
            break;

        case 0xC6: case 0xCE: // set b, (hl)
        case 0xD6: case 0xDE:
        case 0xE6: case 0xEE: 
        case 0xF6: case 0xFE:
            emul.set_b_addr(y, regs.HL);
            regs.PC += 2;
            T(15);
            break;

        default: assert(0);
    }
}

void xyTable(ubyte op, Mode mode) {
    assert(mode == Mode.IX || mode == Mode.IY);

    ubyte y = getY(op), z = getZ(op), p = getP(op);
    ubyte d = emul.z80_mem_read(cast(ushort)(regs.PC + 2));
    ushort xy = (mode == Mode.IX) ? regs.IX : regs.IY;
    ushort xyd = cast(ushort)(xy + d);
    Register regXY = (mode == mode.IX) ? Register.IX : Register.IY;

    switch (op) {
        case 0x04: case 0x14: case 0x24: // inc r
        case 0x0C: case 0x1C: case 0x2C: case 0x3C: 
            emul.inc_r(r_table(y, mode));
            regs.PC += 2;
            T(8);
            break;
        
        case 0x05: case 0x15: case 0x25: // dec r
        case 0x0D: case 0x1D: case 0x2D: case 0x3D:
            emul.dec_r(r_table(y, mode));
            regs.PC += 2;
            T(8);
            break;

        case 0x23: // inc ix
            emul.inc_rr((mode == Mode.IX) ? Register.IX : Register.IY);
            regs.PC += 2;
            T(10);
            break; 

        case 0x2B: // dec ix
            emul.dec_rr((mode == Mode.IX) ? Register.IX : Register.IY);
            regs.PC += 2;
            T(10);
            break;

        case 0x09: case 0x19: case 0x29: case 0x39: // add ix, ss (is this SS?)
            emul.add_rr_rr(Register.IX, pp_table(p));
            regs.PC += 2;
            T(15);
            break;

        case 0x06: case 0x16: case 0x26: // ld r, n
        case 0x0E: case 0x1E: case 0x2E: case 0x3E:
            emul.ld_r_n(r_table(y, mode), emul.z80_mem_read(cast(ushort)(regs.PC + 2)));
            regs.PC += 2; 
            T(11);
            break;

        case 0x40: .. case 0x45: case 0x47: // ld r, r'
        case 0x50: .. case 0x55: case 0x57:
        case 0x60: .. case 0x65: case 0x67:
        case 0x48: .. case 0x4D: case 0x4F:
        case 0x58: .. case 0x5D: case 0x5F: 
        case 0x68: .. case 0x6D: case 0x6F:
        case 0x78: .. case 0x7D: case 0x7F: 
            emul.ld_r_r(r_table(y, mode), r_table(z, mode));
            regs.PC += 2;
            T(8);
            break;

        case 0x46: case 0x56: case 0x66: // ld r, (ix + d)
        case 0x4E: case 0x5E: case 0x6E: case 0x7E:
            emul.ld_r_addr(r_table(y, mode), xyd);
            regs.secretMath = getHigh(xyd);
            regs.PC += 3;
            T(19);
            break;

        case 0x70: .. case 0x75: case 0x77: // ld (ix + d), r
            emul.ld_addr_r(xyd, r_table(z, mode));
            regs.PC += 3;
            T(19);
            break;

        case 0x80: .. case 0x85: case 0x87: // add r
            emul.add_a_r(r_table(z, mode));
            regs.PC += 2;
            T(8);
            break;

        case 0x86: // add (ix + d)
            emul.add_a_addr(xyd);
            regs.PC += 3;
            T(19);
            break;

        case 0x88: .. case 0x8D: case 0x8F: // adc r
            emul.adc_a_r(r_table(z, mode));
            regs.PC += 2;
            T(8);
            break;

        case 0x8E: // adc (ix + d)
            emul.adc_a_addr(xyd);
            regs.PC += 3;
            T(19);
            break;

        case 0x90: .. case 0x95: case 0x97: // sub r
            emul.sub_a_r(r_table(z, mode));
            regs.PC += 2; 
            T(8);
            break;

        case 0x96: // sub (ix + d)
            emul.sub_a_addr(xyd);
            regs.PC += 3;
            T(19);
            break;

        case 0x98: .. case 0x9D: // sbc r
            emul.sbc_a_r(r_table(z, mode));
            regs.PC += 2;
            T(8);
            break;

        case 0x9E: // sbc (ix + d)
            emul.sbc_a_addr(xyd);
            regs.PC += 2;
            T(19);
            break;

        case 0xA0: .. case 0xA5: case 0xA7: // and r
            emul.and_r(r_table(z, mode));
            regs.PC += 2;
            T(8);
            break;

        case 0xA6: // and (ix + d)
            emul.and_addr(xyd);
            regs.PC += 3;
            T(19);
            break;

        case 0xA8: .. case 0xAD: case 0xAF: // xor r
            emul.xor_r(r_table(z, mode));
            regs.PC += 2;
            T(8);
            break;

        case 0xAE: // xor (ix + d)
            emul.xor_addr(xyd);
            regs.PC += 3;
            T(19);
            break;

        case 0xB0: .. case 0xB5: case 0xB7: // or r
            emul.or_r(r_table(z, mode));
            regs.PC += 2;
            T(8);
            break;

        case 0xB6: // or (ix + d)
            emul.or_addr(xyd);
            regs.PC += 3;
            T(19);
            break;

        case 0xB8: .. case 0xBD: case 0xBF: // cp r
            emul.cp_r(r_table(z, mode));
            regs.PC += 2;
            T(8);
            break;

        case 0xBE: // cp (ix + d)
            emul.cp_addr(xyd);
            regs.PC += 3;
            T(19);
            break;
        
        case 0xE1: // pop ix
            emul.pop_qq(regXY);
            regs.PC += 2;
            T(14);
            break;

        case 0xE5: // push ix
            emul.push_qq(regXY);
            regs.PC += 2;
            T(15);
            break;

        case 0xE3: // ex (sp), ix
            emul.ex_addr_dd(regs.SP, regXY);
            regs.PC += 2;
            T(23);
            break;

        case 0xE9: // jp (ix)
            emul.jp_addr(xy);
            regs.PC += 2;
            T(8);
            break;

        case 0xF9: // ld sp, ix
            emul.ld_dd_dd(Register.SP, regXY);
            regs.PC += 2;
            T(10);
            break;

        case 0x21: // ld ix, nn 
            ushort addr = (emul.z80_mem_read16(cast(ushort)(regs.PC + 2)));
            emul.ld_dd_nn(regXY, emul.z80_mem_read16(addr));
            regs.PC += 4;
            T(14);
            break;

        case 0x2A: // ld ix, (nn)
            emul.ld_dd_addr(regXY, emul.z80_mem_read16(cast(ushort)(regs.PC + 2)));
            regs.PC += 4;
            T(20);
            break;

        case 0x22: // ld (nn), ix
            emul.ld_addr_dd(emul.z80_mem_read16(cast(ushort)(regs.PC + 2)), regXY);
            regs.PC += 4;
            T(20);
            break;

        case 0x34: // inc (ix + d) 
            emul.inc_addr(xyd);
            regs.PC += 3;
            T(23);
            break;

        case 0x35: // dec (ix + d)
            emul.dec_addr(xyd);
            regs.PC += 3; 
            T(23);
            break;

        case 0x36: // ld (ix + d), n
            emul.ld_addr_n(xyd, emul.z80_mem_read(cast(ushort)(regs.PC + 3)));
            regs.PC += 4;
            T(19);
            break;

        default: assert(0);
    }
}

void xyBitTable(ubyte op, Mode mode) {
    ubyte y = getY(op), z = getZ(op), p = getP(op);
    ubyte d = emul.z80_mem_read(cast(ushort)(regs.PC + 2));
    ushort xy = (mode == Mode.IX_Bit) ? regs.IX : regs.IY;
    ushort xyd = cast(ushort)(xy + d);

    switch (op) {
        case 0x00: .. case 0x05: case 0x07: // rlc (ix + d), r
            emul.rlc_addr_r(xyd, r_table(z));
            T(23);
            break;

        case 0x06: // rlc (ix + d)
            emul.rlc_addr(xyd);
            T(23);
            break;
        
        case 0x08: .. case 0x0D: case 0x0F: // rrc (ix + d), r
            emul.rrc_addr_r(xyd, r_table(z));
            T(23);
            break;

        case 0x0E: // rrc (ix + d)
            emul.rrc_addr(xyd);
            T(23);
            break;

        case 0x10: .. case 0x15: case 0x17: // rl (ix + d), r
            emul.rl_addr_r(xyd, r_table(z));
            T(23);
            break;

        case 0x16: // rl (ix + d)
            emul.rl_addr(xyd);
            T(23);
            break;

        case 0x18: .. case 0x1D: case 0x1F: // rr (ix + d), r
            emul.rr_addr_r(xyd, r_table(z));
            T(23);
            break;

        case 0x1E: // rr (ix + d)
            emul.rr_addr(xyd);
            T(23);
            break;

        case 0x20: .. case 0x25: case 0x27: // sla (ix + d), r
            emul.sla_addr_r(xyd, r_table(z));
            T(23);
            break;
    
        case 0x26: // sla (ix + d)
            emul.sla_addr(xyd);
            T(23);
            break;

        case 0x28: .. case 0x2D: case 0x2F: // sra (ix + d), r
            emul.sra_addr_r(xyd, r_table(z));
            T(23); 
            break;

        case 0x2E: // sra (ix + d)
            emul.sra_addr(xyd);
            T(23);
            break;

        case 0x30: .. case 0x35: case 0x37: // sll (ix + d), r
            emul.sll_addr_r(xyd, r_table(z));
            T(23);
            break;

        case 0x36: // sll (ix + d)
            emul.sll_addr(xyd);
            T(23);
            break;

        case 0x38: .. case 0x3D: case 0x3F: // srl (ix + d), r
            emul.srl_addr_r(xyd, r_table(z));
            T(23);
            break;

        case 0x3E: // srl (ix + d)
            emul.srl_addr(xyd);
            T(23);
            break;

        case 0x40: .. case 0x7F: // bit b, (ix + d)
            emul.bit_b_addr(y, xyd);
            if (mode == Mode.IX_Bit) {
                ubyte upper = getHigh(xyd);
                emul.setFlagCond(zemu.Flag.X, bit(upper, zemu.Flag.X));
                emul.setFlagCond(zemu.Flag.Y, bit(upper, zemu.Flag.Y));
            }
            T(20);
            break;

        case 0x80: .. case 0x85: case 0x87: // res b, (ix + d), r
        case 0x90: .. case 0x95: case 0x97:
        case 0xA0: .. case 0xA5: case 0xA7:
        case 0xB0: .. case 0xB5: case 0xB7:
        case 0x88: .. case 0x8D: case 0x8F: 
        case 0x98: .. case 0x9D: case 0x9F:
        case 0xA8: .. case 0xAD: case 0xAF:
        case 0xB8: .. case 0xBD: case 0xBF:
            emul.res_b_addr_r(y, xyd, r_table(z));
            T(23);
            break;

        case 0x86: case 0x8E: // res b, (ix + d)
        case 0x96: case 0x9E:
        case 0xA6: case 0xAE:
        case 0xB6: case 0xBE:
            emul.res_b_addr(y, xyd);
            T(23);
            break;

        case 0xC0: .. case 0xC5: case 0xC7: // set b, (ix + d), r
        case 0xD0: .. case 0xD5: case 0xD7:
        case 0xE0: .. case 0xE5: case 0xE7:
        case 0xF0: .. case 0xF5: case 0xF7:
        case 0xC8: .. case 0xCD: case 0xCF:
        case 0xD8: .. case 0xDD: case 0xDF:
        case 0xE8: .. case 0xED: case 0xEF:
        case 0xF8: .. case 0xFD: case 0xFF:
            emul.set_b_addr_r(y, xyd, r_table(z));
            T(23);
            break;

        case 0xC6: case 0xCE: // set b, (ix + d)
        case 0xD6: case 0xDE:
        case 0xE6: case 0xEE:
        case 0xF6: case 0xFE:
            emul.set_b_addr(y, xyd);
            T(23);
            break;

        default: assert(0);
    }

    regs.PC += 4;
}

