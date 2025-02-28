module zemu;

import std.stdio;
import std.file;
import std.bitmanip : BitArray;
import std.exception : ErrnoException, enforce;

template regPair(string HL, string H, string L) {
    const char[] regPair = "
        union {
            struct {
                ubyte " ~ L ~ ";" ~
                "ubyte " ~ H ~ ";" ~
            "}
                ushort " ~ HL ~ ";
        }";
}

struct Registers {
    mixin(regPair!("AF", "A", "F"));
    mixin(regPair!("BC", "B", "C"));
    mixin(regPair!("DE", "D", "E"));
    mixin(regPair!("HL", "H", "L"));
    mixin(regPair!("IX", "IXH", "IXL"));
    mixin(regPair!("IY", "IYH", "IYL"));

    mixin(regPair!("AFP", "AP", "FP"));
    mixin(regPair!("BCP", "BP", "CP"));
    mixin(regPair!("DEP", "DP", "EP"));
    mixin(regPair!("HLP", "HP", "LP"));

    ushort SP, PC;
    ubyte I, R;
    ubyte interruptMode; 
    bool iff1, iff2;
    ubyte secretMath;
}

enum Register { B, C, D, E, H, L, HL, A, 
               IXH, IXL, IX, IYH, IYL, IY, 
               R, I, PC, SP, BC, DE, AF, F,
               AFP, BCP, DEP, HLP }
enum Flag {C = 0, N = 1, PV = 2,  X = 3, H = 4, Y = 5, Z = 6, S = 7} // TODO: Add unused flags and implement their behavior
enum CC {NZ, Z, NC, C, PO, PE, P, M} 

bool bit(ubyte val, int i) {
    return cast(bool)(getBit(val, i));
}

bool bit(ushort val, int i) {
    return cast(bool)(getBit(val, i));
}

ubyte getBit(ubyte b, int i) {
    return cast(ubyte)((b & (0b00000001 << i)) >> i);
}

ushort getBit(ushort b, int i) {
    return cast(ushort)((b & (0b00000001 << i)) >> i);
}

ubyte getHigh(ushort val) {
    return cast(ubyte)((val & 0xFF00) >> 8);
}

class Zemu {
    public:
    
    // TODO: Implement similar to the Z80 emulator I saw in GitHub later on? 
    Registers regs;
    ubyte[65_536] ram;
    ubyte[256] ports;
    int T;
    bool contLoop;

    static this() {
        Registers regs;
    }

    this() {
        _z80_mem_read    = &read_ram_default;
        _z80_mem_read16  = &read_ram_16_default;
        _z80_mem_write   = &write_ram_default;
        _z80_mem_write16 = &write_ram_16_default;
        _z80_mem_load    = &z80_mem_load_default;
        _z80_mem_dump    = &z80_mem_dump_default;
        regs.IX = 0xffff;
        regs.IY = 0xffff;
        setFlagCond(Flag.Z, true);
    }

    // TODO: Add Error Handling
    void z80_mem_load_default(string str) {
        try {
            File fp = File(str, "r");
            fp.rawRead(ram);
        } catch (ErrnoException e) {
            assert(false, "Error: " ~ e.msg);
        }
    }

    void z80_mem_dump_default(string str) {
        try {
            File fp = File(str, "w");
            fp.rawWrite(ram);
        } catch (ErrnoException e) {
            assert(false, "Error: " ~ e.msg);
        }
    }

    void write_ram_default(ushort addr, ubyte val) {
        ram[addr] = val;
    }

    void write_ram_16_default(ushort addr, ushort val) {
        this.ram[addr] = cast(ubyte)(val & 0xff);
        this.ram[addr + 1] = cast(ubyte)(val >> 8);
    }

    ubyte read_ram_default(ushort addr) {
        return ram[addr];
    }

    ushort read_ram_16_default(ushort addr) {
        return (cast(ushort)this.ram[addr]) | ((cast(ushort)this.ram[addr + 1]) << 8);
    }

    // TODO: Add reassignment of ram, ports in this constructor
    this(
        ubyte  delegate(ushort)         read, 
        ushort delegate(ushort)         read16, 
        void   delegate(ushort, ubyte)  write,
        void   delegate(ushort, ushort) write16,
        void   delegate(string)         load,
        void   delegate(string)         dump,
        ubyte[]                         ramArr,
        ubyte[]                         portArr
    ) in {
        assert(read !is null,    "read is null");
        assert(read16 !is null,  "read16 is null");
        assert(write !is null,   "write is null");
        assert(write16 !is null, "write16 is null");
        assert(dump !is null,    "dump is null");
        assert(load !is null,    "load is null");
        assert(ramArr !is null,  "ramArr is null");
        assert(portArr !is null, "portArr is null");
    } do {
        _z80_mem_write     = write;
        _z80_mem_write16   = write16;
        _z80_mem_read      = read;
        _z80_mem_read16    = read16;
        _z80_mem_load      = load;
        _z80_mem_dump      = dump;
        ram                = ramArr;
        ports              = portArr;
        Registers regs;
    }
    
    private {        
        ubyte    delegate(ushort)            _z80_mem_read;
        ushort   delegate(ushort)            _z80_mem_read16;
        void     delegate(ushort, ubyte)     _z80_mem_write;
        void     delegate(ushort, ushort)    _z80_mem_write16;
        void     delegate(string)            _z80_mem_load;
        void     delegate(string)            _z80_mem_dump;
    }
    
    void   z80_mem_write(ushort addr, ubyte value)    => _z80_mem_write(addr, value);
    void   z80_mem_write16(ushort addr, ushort value) => _z80_mem_write16(addr, value);
    ubyte  z80_mem_read(ushort addr)                  => _z80_mem_read(addr);
    ushort z80_mem_read16(ushort addr)                => _z80_mem_read16(addr);
    void   z80_mem_dump(string str)                   => _z80_mem_dump(str);
    void   z80_mem_load(string str)                   => _z80_mem_load(str);

    void test() {
        writeln("\nSub Tests");
        regs.A = 0x16;
        regs.HL = 0x3433;
        z80_mem_write(0x3433, 0x05);
        sbc_a_addr(regs.HL);
        assert(0x10);

        writeln("\nUnrelated Read Test");
        z80_mem_write16(0x50, cast(ushort) 0x5040);
        z80_mem_dump("memory.bin");
        writefln("0x%x", z80_mem_read16(0x50)); // When getting nn, use z80_mem_read so the order is right
    }

    ubyte getRegisterValue(Register r) {
        switch (r) {
            case Register.B: return regs.B; 
            case Register.C: return regs.C;
            case Register.D: return regs.D;
            case Register.E: return regs.E;
            case Register.H: return regs.H;
            case Register.L: return regs.L;
            case Register.A: return regs.A;
            case Register.F: return regs.F;
            case Register.I: return regs.I;
            case Register.R: return regs.R;
            default: break;
        }

        assert(0, "Valid 8 Bit Register Value Not Found");
    }

    ubyte* getRegisterPointer(Register r) {
        switch (r) {
            case Register.B: return &regs.B; 
            case Register.C: return &regs.C;
            case Register.D: return &regs.D;
            case Register.E: return &regs.E;
            case Register.H: return &regs.H;
            case Register.L: return &regs.L;
            case Register.A: return &regs.A;
            case Register.F: return &regs.F;
            case Register.I: return &regs.I;
            case Register.R: return &regs.R;
            default: break;
        }

        assert(0, "Valid 8 Bit Register Pointer Not Found");
    }

    ushort* getRegisterPointer16(Register r) {
        switch (r) {
            case Register.BC: return &regs.BC;
            case Register.DE: return &regs.DE;
            case Register.HL: return &regs.HL;
            case Register.SP: return &regs.SP;
            case Register.IX: return &regs.IX;
            case Register.IY: return &regs.IY;
            case Register.AF: return &regs.AF;
            case Register.AFP: return &regs.AFP;
            case Register.BCP: return &regs.BCP;
            case Register.DEP: return &regs.DEP;
            case Register.HLP: return &regs.HLP;
            default: break;
        }

        assert(0, "Valid 16 Bit Register Pointer Not Found");
    }

    ushort getRegisterValue16(Register r) {
        switch (r) {
            case Register.BC: return regs.BC;
            case Register.DE: return regs.DE;
            case Register.HL: return regs.HL;
            case Register.SP: return regs.SP;
            case Register.IX: return regs.IX;
            case Register.IY: return regs.IY;
            case Register.AF: return regs.AF;
            case Register.AFP: return regs.AFP;
            case Register.BCP: return regs.BCP;
            case Register.DEP: return regs.DEP;
            case Register.HLP: return regs.HLP;
            default: break;
        }

        assert(0, "Valid 16 Bit Register Value Not Found");
    }

    BitArray toBitArray(ubyte num) {
        auto arr = BitArray([]);
        arr.length = 8;

        foreach (i; 0 .. ubyte.sizeof * 8) {
            ubyte mask = cast(ubyte) (0b1 << i);
            ubyte val = num & mask;
            arr[i] = cast(bool) val;
        }

        return arr;
    }

    ubyte toUByte(BitArray arr) {
        ubyte val;
        foreach (i; 0 .. arr.length()) {
            bool bit = arr[i];
            ubyte castBit = cast(ubyte) bit;
            castBit = cast(ubyte) (castBit << i);
            val += castBit;
        }

        return val;
    }

    void setFlagCond(int i, bool cond) {
        BitArray arr = toBitArray(regs.F);
        arr[i] = cond;
        regs.F = toUByte(arr); 
    }

    void setFlagConds(bool sc, bool zc, bool hc, bool pvc, bool nc, bool cc) {
        setFlagCond(Flag.S, sc);
        setFlagCond(Flag.Z, zc);
        setFlagCond(Flag.H, hc);
        setFlagCond(Flag.PV, pvc);
        setFlagCond(Flag.N, nc);
        setFlagCond(Flag.C, cc);
        // TODO: Are the X and Y flags reset always? Assume not for now.
        setFlagCond(Flag.X, false);
        setFlagCond(Flag.Y, false);
    }

    void setFlagConds(bool sc, bool zc, bool hc, bool pvc, bool nc, bool cc, bool xc, bool yc) {
        setFlagConds(
            sc, zc,
            hc, pvc,
            nc, cc
        );
        setFlagCond(Flag.X, xc);
        setFlagCond(Flag.Y, yc);
    }

    bool halfCarryAdd(ubyte first, ubyte second) {
        return (((first & 0x0F) + (second & 0x0F)) & 0x10) == 0x10;
    }

    bool halfCarryAdd(ushort first, ushort second) {
        return (((first & 0x00FF) + (second & 0x00FF)) & 0x0100) == 0x0100;
    }

    bool halfCarrySub(ubyte first, ubyte second) {
        return cast(int) (first & 0x0F) - cast(int) (second & 0x0F) < 0;
    }

    bool halfCarrySub(ushort first, ushort second) {
        return cast(int) (first & 0x0F) - cast(int) (second & 0x0F) < 0;
    }

    // carrySub previously had issues with some cases when it was set up similarly, this may have errors, too
    bool carryAdd(ubyte first, ubyte second) {
        ubyte result = cast(ubyte)(first + second); 
        if (result < first || result < second) return true;
        else return false; 
    }

    // TODO: Can I get away with only doing short versions of this, if bytes get auto-cast (do they get auto-cast?)
    bool carryAdd(ushort first, ushort second) {
        ushort result = cast(ushort)(first + second);
        if (result < first || result < second) return true;
        else return false;
    }

    bool carrySub(ubyte first, ubyte second) {
        ubyte result = cast(ubyte)(first - second);
        if (first < second) return true; 
        else return false;
    }

    bool carrySub(ushort first, ushort second) {
        ushort result = cast(ushort)(first - second);
        if (first < second) return true;
        else return false;
    }

    bool overflowAdd(ubyte first, ubyte second) {
        byte result = cast(byte)(first + second);
        bool bit = cast(bool)(result & 0b10000000);
        if ((cast(byte) first >= 0) && (cast(byte) second >= 0)) {
            if (bit) {
                return true;
            }
        }

        if ((cast(byte) first < 0) && (cast(byte) second < 0)) {
            if (!bit) {
                return true;
            }
        }
        
        return false;
    }

    bool overflowAdd(ushort first, ushort second) {
        short result = cast(short)(first + second);
        bool bit = cast(bool)(result & 0x8000);
        if ((cast(short) first >= 0) && (cast(short) second >= 0)) {
            if (bit) {
                return true;
            }
        }

        if ((cast(short) first < 0) && (cast(short) second < 0)) {
            if (!bit) {
                return true;
            }
        }

        return false;
    }

    ubyte getFlag(int flag) {
        return (regs.F & (0b00000001 << flag)) >> flag;
    }

    ubyte getBit(Register r, int i) {
        return (getRegisterValue(r) & (0b00000001 << i)) >> i;
    }

    ubyte getBit(ubyte b, int i) {
        return (b & (0b00000001 << i)) >> i;
    }

    ushort getBit(ushort b, int i) {
        return cast(ushort)((b & (0b00000001 << i)) >> i);
    }

    bool bit(ubyte val, int i) {
        return cast(bool)(getBit(val, i));
    }

    bool bit(ushort val, int i) {
        return cast(bool)(getBit(val, i));
    }

    // TODO: Increment R
    void incrementR(ubyte val) {
        ubyte bit7 = cast(ubyte)(getBit(regs.R, 7) << 7);
        regs.R = cast(ubyte)((regs.R + val) | bit7);
    }

    void addFlags(ubyte source) {
        ubyte result = cast(ubyte)(source + regs.A);
        setFlagConds(
            negative(result), zero(result),
            halfCarryAdd(regs.A, source), overflowAdd(regs.A, source),
            false, carryAdd(regs.A, source),
            result.bit(Flag.X), result.bit(Flag.Y)
        );
    }

    void addFlags(ushort dest, ushort source) {
        ubyte result = cast(ubyte)(dest + source);
        setFlagConds(
            negative(result), zero(result),
            halfCarryAdd(dest, source), overflowAdd(dest, source),
            false, carryAdd(dest, source),
            result.bit(Flag.X), result.bit(Flag.Y)
        );
    }

    void subFlags(ubyte source) {
        ubyte result = cast(ubyte)(regs.A - source);
        setFlagConds(
            negative(result), zero(result),
            halfCarrySub(regs.A, source), overflowAdd(regs.A, source), // TODO: Should overflow be here? It's not an addition so IDK.
            true, carrySub(regs.A, source),
            result.bit(Flag.X), result.bit(Flag.Y)
        );
    }

    void subFlags(ushort dest, ushort source) {
        ubyte result = cast(ubyte)(dest - source);
        setFlagConds(
            negative(result), zero(result),
            halfCarrySub(dest, source), overflowAdd(dest, source),
            true, carrySub(dest, source),
            result.bit(Flag.X), result.bit(Flag.Y)
        );
    }

    void andFlags(ubyte result) {
        setFlagConds(
            negative(result), zero(result),
            true, parity(result),
            false, false,
            result.bit(Flag.X), result.bit(Flag.Y)
        );
    }

    void orXorFlags(ubyte result) {
        setFlagConds(
            negative(result), zero(result),
            false, parity(result),
            false, false,
            result.bit(Flag.X), result.bit(Flag.Y)
        );
    }

    void incFlags(ubyte dest) {
        ubyte result = cast(bool)(dest + 1);
        setFlagConds(
            negative(dest + 1), zero(dest + 1),
            halfCarryAdd(dest, 1), (dest == 0x7f),
            false, cast(bool) getFlag(Flag.C), // regs.F.bit(Flag.C) could maybe work. Is it worth trying?
            result.bit(Flag.X), result.bit(Flag.Y)
        );
    }

    void decFlags(ubyte dest) {
        ubyte result = cast(ubyte)(dest - 1);
        setFlagConds(
            negative(result), zero(result),
            halfCarrySub(dest, 1), (dest == 0x80),
            true, cast(bool) getFlag(Flag.C),
            result.bit(Flag.X), result.bit(Flag.Y)
        );
    }

    bool parity(ubyte val) {
        bool parity = true;
        foreach (i; 0 .. 8) {
            if (val.bit(i)) {
                parity = !parity;
            }
        }

        return parity;
    }

    bool parity(ushort val) {
        bool parity = true;
        foreach (i; 0 .. 16) {
            if (val.bit(i)) {
                parity = !parity;
            }
        }

        return parity;
    }

    bool negative(ubyte val) {
        return (cast(byte) val < 0);
    }

    bool negative(ushort val) {
        return (cast(short) val < 0);
    }

    bool zero(ubyte val) {
        return val == 0;
    }

    bool zero(ushort val) {
        return val == 0;
    }

    // TODO: Check that these are the proper boolean value for each condition
    bool checkCC(CC cc) {
        switch (cc) {
            case CC.Z:  return getFlag(Flag.N) != 0;
            case CC.NZ: return getFlag(Flag.N) == 0;
            case CC.C:  return getFlag(Flag.C) != 0;
            case CC.NC: return getFlag(Flag.C) == 0;
            case CC.PE: return getFlag(Flag.PV) != 0;
            case CC.PO: return getFlag(Flag.PV) == 0;
            case CC.P:  return getFlag(Flag.S) == 0;
            case CC.M:  return getFlag(Flag.S) != 0;
            default: assert(0);
        }
    }

    void ld_r_r(Register d, Register s) {
        ubyte *dest = getRegisterPointer(d);
        ubyte source = getRegisterValue(s);
        *dest = source;
    }

    void ld_r_n(Register d, ubyte n) {
        ubyte *dest = getRegisterPointer(d);
        *dest = n;
    }

    void ld_r_addr(Register d, ushort addr) {
        ubyte *dest = getRegisterPointer(d);
        ubyte source = z80_mem_read(addr);
        *dest = source;
    }

    void ld_addr_r(ushort addr, Register s) {
        ubyte source = getRegisterValue(s);
        z80_mem_write(addr, source);
    }

    void ld_addr_n(ushort addr, byte n) {
        z80_mem_write(addr, n);
    }

    void ld_dd_nn(Register dd, ushort nn) {
        ushort *dest = getRegisterPointer16(dd);
        *dest = nn;
    }

    void ld_dd_addr(Register dd, ushort addr) {
        ushort *dest = getRegisterPointer16(dd);
        *dest = z80_mem_read16(addr);
    }

    void ld_addr_dd(ushort addr, Register dd) {
        ushort source = getRegisterValue16(dd);
        z80_mem_write16(addr, source);
    }

    void ld_dd_dd(Register dd, Register ss) {
        ushort *dest = getRegisterPointer16(dd);
        ushort source = getRegisterValue16(ss);
        *dest = source;
    }

    void push_qq(Register qq) {
        regs.SP -= 2;
        ushort source = getRegisterValue16(qq);
        z80_mem_write16(regs.SP, source);
    } 

    void push_nn(ushort nn) {
        regs.SP -= 2;
        z80_mem_write16(regs.SP, nn);
    }

    // TODO: Pop into Register DD as provided by an argument?
    ushort pop() {
        ushort value = z80_mem_read16(regs.SP);
        z80_mem_write16(regs.SP, 0);
        regs.SP += 2;
        return value;
    }

    void pop_qq(Register qq) {
        ushort *dest = getRegisterPointer16(qq);
        *dest = pop();
    }

    // Check if this is what Z80 Instructions say w/ the second DD. Same with ex (addr), dd
    // TODO: Should I use a different enum or use asserts in this function (or asserts after?)
    void ex_dd_dd(Register d1, Register d2) {
        ushort *destOne = getRegisterPointer16(d1);
        ushort *destTwo = getRegisterPointer16(d2);
        ushort valOne = getRegisterValue16(d1);
        ushort valTwo = getRegisterValue16(d2);
        
        *destOne = valTwo;
        *destTwo = valOne;
    }

    void ex_addr_dd(ushort addr, Register dd) {
        ushort newDD = z80_mem_read16(addr);
        ushort newAddrVal = getRegisterValue16(dd);

        ushort *ddDest = getRegisterPointer16(dd);
        *ddDest = newDD;

        z80_mem_write16(addr, newAddrVal);
    }

    void exx() {
        ex_dd_dd(Register.BC, Register.BCP);
        ex_dd_dd(Register.DE, Register.DEP);
        ex_dd_dd(Register.HL, Register.HLP);
    }

    void ldi() {
        z80_mem_write(regs.DE, z80_mem_read(regs.HL));
        regs.HL++;
        regs.DE++;
        regs.BC--; // TODO: Is regs.BC - 1 before or after decrementing? For now assume after.

        setFlagCond(Flag.PV, (regs.BC != 0));
        setFlagCond(Flag.H, false);
        setFlagCond(Flag.N, false);
    }

    // TODO: ldir, ldd, lddr, cpi, cpir, cpd, cpdr. Need to wait to test CP versions because Compare needs to be implemented.
    int ldir() {
        int cyc;
        bool afterFirst;
        do {
            ldi();
            T += (regs.BC != 0) ? 21 : 16; 
            cyc += (regs.BC != 0) ? 21 : 16;
            if (afterFirst) { incrementR(2); }
            else afterFirst = true;
        } while (regs.BC != 0);

        return cyc;
    }

    void ldd() {
        z80_mem_write(regs.DE, z80_mem_read(regs.HL));
        regs.DE--;
        regs.HL--;
        regs.BC--;

        setFlagCond(Flag.PV, (regs.BC != 0));
        setFlagCond(Flag.H, false);
        setFlagCond(Flag.N, false);
    }

    int lddr() {
        int cyc;
        bool afterFirst;
        do {
            ldd();
            T += (regs.BC != 0) ? 21 : 16;
            cyc += (regs.BC != 0) ? 21 : 16;
            if (afterFirst) { incrementR(2); }
            else afterFirst = true;
        } while (regs.BC != 0);

        return cyc;
    }

    void cpi() {
        cp_cpid(regs.HL);
        regs.HL++;
        regs.BC--;
    }

    int cpir() {
        int cyc;
        bool afterFirst;
        do {
            cpi();
            T += (regs.BC != 0) ? 21 : 16;
            cyc += (regs.BC != 0) ? 21 : 16;
            if (afterFirst) { incrementR(2); }
            else afterFirst = true;
        } while (regs.BC != 0);

        return cyc;
    }

    void cpd() {
        cp_cpid(regs.HL);
        regs.HL--;
        regs.BC--;
    }

    int cpdr() {
        int cyc;
        bool afterFirst;
        do {
            cpd();
            T += (regs.BC != 0) ? 21 : 16;
            cyc += (regs.BC != 0) ? 21 : 16;
            if (afterFirst) { incrementR(2); }
            else afterFirst = true;
        } while (regs.BC != 0);

        return cyc;
    }

    void cp_cpid(ushort addr) {
        ubyte result = cast(ubyte) (regs.A - z80_mem_read(addr));
        BitArray arr = toBitArray(result);

        setFlagCond(Flag.S, arr[7]);
        setFlagCond(Flag.Z, result == 0);
        setFlagCond(Flag.H, halfCarrySub(regs.A, z80_mem_read(addr)));
        setFlagCond(Flag.PV, regs.BC - 1 != 0);
        setFlagCond(Flag.N, true);
    }

    void add_a_r(Register s) {
        ubyte source = getRegisterValue(s);
        addFlags(source);
        regs.A += source;
    }

    void add_a_n(ubyte n) {
        addFlags(n);
        regs.A += n;
    }

    void add_a_addr(ushort addr) {
        ubyte source = z80_mem_read(addr);
        addFlags(source);
        regs.A += source;
    }

    void adc_a_r(Register r) {
        ubyte source = cast(ubyte)(getRegisterValue(r) + getFlag(Flag.C));
        addFlags(source);
        regs.A += source;
    }

    void adc_a_n(ubyte n) {
        ubyte source = cast(ubyte)(n + getFlag(Flag.C));
        addFlags(source);
        regs.A += source;
    }

    void adc_a_addr(ushort addr) {
        ubyte source = cast(ubyte)(z80_mem_read(addr) + getFlag(Flag.C));
        addFlags(source);
        regs.A += source;
    }

    // TODO: Test below here
    void sub_a_r(Register s) {
        ubyte source = getRegisterValue(s);
        subFlags(source);
        regs.A -= source;
    }

    void sub_a_n(ubyte n) {
        subFlags(n);
        regs.A -= n;
    }

    void sub_a_addr(ushort addr) {
        ubyte source = z80_mem_read(addr);
        subFlags(source);
        regs.A -= source;
    }

    void sbc_a_r(Register s) {
        ubyte source = cast(ubyte)(getRegisterValue(s) + getFlag(Flag.C));
        subFlags(source);
        regs.A -= source;
    }

    void sbc_a_n(ubyte n) {
        ubyte source = cast(ubyte)(n + getFlag(Flag.C));
        subFlags(source);
        regs.A -= source;
    }

    void sbc_a_addr(ushort addr) {
        ubyte source = cast(ubyte)(z80_mem_read(addr) + getFlag(Flag.C));
        subFlags(source);
        regs.A -= source;
    }

    void and_r(Register s) {
        ubyte source = getRegisterValue(s);
        andFlags(regs.A & source);
        regs.A &= source;
    }

    void and_n(ubyte n) {
        andFlags(regs.A & n);
        regs.A &= n;
    }

    void and_addr(ushort addr) {
        ubyte source = z80_mem_read(addr);
        andFlags(regs.A & source);
        regs.A &= source;
    }

    void or_r(Register s) {
        ubyte source = getRegisterValue(s);
        orXorFlags(regs.A | source);
        regs.A |= source;
    }

    void or_n(ubyte n) {
        orXorFlags(regs.A ^ n);
        regs.A |= n;
    }

    void or_addr(ushort addr) {
        ubyte source = z80_mem_read(addr);
        orXorFlags(regs.A | source);
        regs.A |= source;
    }

    void xor_r(Register s) {
        ubyte source = getRegisterValue(s);
        orXorFlags(regs.A ^ source);
        regs.A ^= source;
    }

    void xor_n(ubyte n) {
        orXorFlags(regs.A ^ n);
        regs.A ^= n;
    }

    void xor_addr(ushort addr) {
        ubyte source = z80_mem_read(addr);
        orXorFlags(regs.A ^ source);
        regs.A ^= source;
    }

    void cp_r(Register s) {
        ubyte source = getRegisterValue(s);
        subFlags(source);
    }

    void cp_n(ubyte n) {
        subFlags(n);
    }

    void cp_addr(ushort addr) {
        ubyte source = z80_mem_read(addr);
        subFlags(source);
    }

    void inc_r(Register d) {
        ubyte source = getRegisterValue(d);
        ubyte *dest = getRegisterPointer(d);
        incFlags(source);
        *dest += 1;
    }

    void inc_addr(ushort addr) {
        ubyte source = z80_mem_read(addr);
        incFlags(source);
        z80_mem_write(addr, cast(ubyte)(source + 1));
    }

    void dec_r(Register d) {
        ubyte source = getRegisterValue(d);
        ubyte *dest = getRegisterPointer(d);
        decFlags(source);
        *dest -= 1;
    }

    void dec_addr(ushort addr) {
        ubyte source = z80_mem_read(addr);
        decFlags(source);
        z80_mem_write(addr, cast(ubyte)(source - 1));
    }

    // https://stackoverflow.com/a/57837042 
    // TODO: I have no idea how accurate this is. Test later, and learn what exactly is happening.
    void daa() {
        ubyte upper = (regs.A & 0xf0) >> 4;
        ubyte lower = (regs.A & 0x0f);
        bool setC, upperCond, lowerCond;

        int op;

        if (getFlag(Flag.H) || ((regs.A & 0xf0) > 9)) {
            op++;
        }

        if (getFlag(Flag.C) || regs.A > 0x99) {
            setFlagCond(Flag.C, true);
            op += 2;
        }

        if (getFlag(Flag.N) && !getFlag(Flag.H)) {
            setFlagCond(Flag.H, false);
        } else {
            if (getFlag(Flag.N) && getFlag(Flag.H)) {
                setFlagCond(Flag.H, (regs.A & 0x0F) < 6);
            } else {
                setFlagCond(Flag.H, (regs.A & 0x0f) >= 0x0A);
            }
        }

        switch (op) {
            case 1: regs.A += getFlag(Flag.N) ? 0xfa : 0x06; break;
            case 2: regs.A += getFlag(Flag.N) ? 0xa0 : 0x60; break;
            case 3: regs.A += getFlag(Flag.N) ? 0x9a : 0x66; break;
            default: break;
        }

        setFlagCond(Flag.S, cast(byte) regs.A < 0);
        setFlagCond(Flag.Z, cast(byte) regs.A == 0);
        setFlagCond(Flag.PV, (regs.A % 2) == 0);
    }

    void cpl() {
        auto arr = toBitArray(regs.A);
        arr.flip();
        regs.A = toUByte(arr);
        setFlagCond(Flag.H, true);
        setFlagCond(Flag.N, true);
    }

    void neg() {
        setFlagCond(Flag.S, cast(byte)(0 - regs.A) < 0);
        setFlagCond(Flag.Z, (0 - regs.A) == 0);
        setFlagCond(Flag.H, halfCarrySub(0, regs.A));
        setFlagCond(Flag.PV, regs.A == 0x80);
        setFlagCond(Flag.N, true);
        setFlagCond(Flag.C, regs.A != 0);

        regs.A = cast(ubyte)(0 - regs.A);
    }

    void ccf() {
        ubyte flag = getFlag(Flag.C);
        auto arr = toBitArray(regs.F);
        arr.flip(Flag.C);
        setFlagCond(Flag.H, cast(bool) flag);
        setFlagCond(Flag.N, false);
        setFlagCond(Flag.C, flag == 0);
    }

    void scf() {
        setFlagCond(Flag.H, false);
        setFlagCond(Flag.H, false);
        setFlagCond(Flag.C, true);
        regs.F |= 0b00000001;
    }

    void nop() {
        // Nothing in Z80 Spec, but project says halt does other thing
    }

    void halt() {
        // Halt differs from Z80 Spec, will implement later, like nop
    }

    void di() {
        regs.iff1 = false;
        regs.iff2 = false;
    }

    void ei() {
        regs.iff1 = true;
        regs.iff2 = true;
    }

    void im_0() {
        regs.interruptMode = 0;
        // Restart address thing happens in Z80 Spec
    }

    void im_1() {
        regs.interruptMode = 1;
        // Special thing happens in Z80 Spec
    }

    void im_2() {
        regs.interruptMode = 2;
        // Special thing happens in Z80 Spec
    }

    void add_rr_rr(Register dd, Register ss) {
        ushort *dest = getRegisterPointer16(dd);
        ushort copy = *dest;
        ushort source = getRegisterValue16(ss);
        addFlags(*dest, source);
        *dest += source;

        if (dd == Register.HL) {
            regs.secretMath = getHigh(copy);
        }
    }

    void adc_rr_rr(Register dd, Register ss) {
        ushort *dest = getRegisterPointer16(dd);
        ushort source = cast(ushort)(getRegisterValue16(ss) + getFlag(Flag.C));
        addFlags(*dest, source);
        *dest += source;
    }

    void sub_rr_rr(Register dd, Register ss) {
        ushort *dest = getRegisterPointer16(dd);
        ushort source = getRegisterValue16(ss);
        subFlags(*dest, source);
        *dest -= source;
    }

    void sbc_rr_rr(Register dd, Register ss) {
        ushort *dest = getRegisterPointer16(dd);
        ushort source = cast(ushort)(getRegisterValue16(ss) + getFlag(Flag.C));
        subFlags(*dest, source);
        *dest -= source;
    }

    void inc_rr(Register dd) {
        ushort *dest = getRegisterPointer16(dd);
        *dest += 1;
    }

    void dec_rr(Register dd) {
        ushort *dest = getRegisterPointer16(dd);
        *dest -= 1;
    }

    void rlca() {
        ubyte bit = getBit(Register.A, 7);
        regs.A = cast(ubyte)((regs.A << 1) | bit);
        setFlagCond(Flag.H, false);
        setFlagCond(Flag.N, false);
        setFlagCond(Flag.C, cast(bool) bit);
    }

    void rrca() {
        ubyte bit = getBit(Register.A, 0);
        regs.A = cast(ubyte)((regs.A >> 1) | (bit << 7));
        setFlagCond(Flag.H, false);
        setFlagCond(Flag.N, false);
        setFlagCond(Flag.C, cast(bool) bit);
    }

    void rla() {
        ubyte flag = getFlag(Flag.C);
        ubyte bit = getBit(Register.A, 7);
        regs.A = cast(ubyte)((regs.A << 1) | flag);
        setFlagCond(Flag.H, false);
        setFlagCond(Flag.N, false);
        setFlagCond(Flag.C, cast(bool) bit);
    }

    void rra() {
        ubyte flag = getFlag(Flag.C);
        ubyte bit = getBit(Register.A, 0);
        regs.A = cast(ubyte)((regs.A >> 1) | (flag << 7));
        setFlagCond(Flag.H, false);
        setFlagCond(Flag.N, false);
        setFlagCond(Flag.C, cast(bool) bit);
    }

    void sla_r(Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte bit7 = getBit(r, 7);
        *reg = cast(ubyte)(*reg << 1);

        setFlagConds(
            negative(*reg), zero(*reg),
            false, parity(*reg),
            false, cast(bool) bit7,
            (*reg).bit(Flag.X), (*reg).bit(Flag.Y)
        );
    }

    void sla_addr(ushort addr) {
        ubyte val = z80_mem_read(addr);
        ubyte bit7 = getBit(val, 7);
        val = cast(ubyte)(val << 1);
        z80_mem_write(addr, val);

        setFlagConds(
            negative(val), zero(val),
            false, parity(val),
            false, cast(bool) bit7,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void sla_addr_r(ushort addr, Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte val = z80_mem_read(addr);
        ubyte bit7 = getBit(val, 7);
        val = cast(ubyte)(val << 1);
        *reg = val;

        setFlagConds(
            negative(val), zero(val),
            false, parity(val),
            false, cast(bool) bit7,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void sra_r(Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte bit0 = getBit(r, 0);
        ubyte bit7 = getBit(r, 7);
        *reg = cast(ubyte)((*reg >> 1) | (bit7 << 7));

        setFlagConds(
            negative(*reg), zero(*reg),
            false, parity(*reg),
            false, cast(bool) bit0,
            (*reg).bit(Flag.X), (*reg).bit(Flag.Y)
        );
    }

    void sra_addr(ushort addr) {
        ubyte val = z80_mem_read(addr);
        ubyte bit0 = getBit(val, 0);
        ubyte bit7 = getBit(val, 7);
        val = cast(ubyte)((val >> 1) | (bit7 << 7));
        z80_mem_write(addr, val);

        setFlagConds(
            negative(val), zero(val),
            false, parity(val),
            false, cast(bool) bit0,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void sra_addr_r(ushort addr, Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte val = z80_mem_read(addr);
        ubyte bit0 = getBit(val, 0);
        ubyte bit7 = getBit(val, 7);
        val = cast(ubyte)((val >> 1) | (bit7 << 7));
        *reg = val;

        setFlagConds(
            negative(val), zero(val),
            false, parity(val),
            false, cast(bool) bit0,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void sll_r(Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte bit7 = getBit(r, 7);
        *reg = cast(ubyte)((*reg << 1) + 0b00000001);

        setFlagConds(
            false, zero(*reg),
            false, parity(*reg),
            false, cast(bool) bit7,
            (*reg).bit(Flag.X), (*reg).bit(Flag.Y)
        );
    }

    void sll_addr(ushort addr) {
        ubyte val = z80_mem_read(addr);
        ubyte bit7 = getBit(val, 7);
        val = cast(ubyte)((val << 1) + 0b00000001);
        z80_mem_write(addr, val);

        setFlagConds(
            false, zero(val),
            false, parity(val),
            false, cast(bool) bit7,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void sll_addr_r(ushort addr, Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte val = z80_mem_read(addr);
        ubyte bit7 = getBit(val, 7);
        val = cast(ubyte)((val << 1) + 0b00000001);
        *reg = val;

        setFlagConds(
            false, zero(val),
            false, parity(val),
            false, cast(bool) bit7,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void srl_r(Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte bit0 = getBit(r, 0);
        *reg = cast(ubyte)(*reg >> 1);

        setFlagConds(
            false, zero(*reg),
            false, parity(*reg),
            false, cast(bool) bit0,
            (*reg).bit(Flag.X), (*reg).bit(Flag.Y)
        );
    }

    void srl_addr(ushort addr) {
        ubyte val = z80_mem_read(addr);
        ubyte bit0 = getBit(val, 0);
        val = cast(ubyte)(val >> 1);
        z80_mem_write(addr, val);

        setFlagConds(
            false, zero(val),
            false, parity(val),
            false, cast(bool) bit0,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void srl_addr_r(ushort addr, Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte val = z80_mem_read(addr);
        ubyte bit0 = getBit(val, 0);
        val = cast(ubyte)(val >> 1);
        *reg = val;

        setFlagConds(
            false, zero(val),
            false, parity(val),
            false, cast(bool) bit0,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void rl_r(Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte bit7 = getBit(r, 7);
        ubyte bitC = getBit(regs.F, Flag.C);
        *reg = cast(ubyte)((*reg << 1) | bitC);

        setFlagConds(
            negative(*reg), zero(*reg),
            false, parity(*reg),
            false, cast(bool) bit7,
            bit(*reg, Flag.X), bit(*reg, Flag.Y)
        );
    }

    void rl_addr(ushort addr) {
        ubyte val = z80_mem_read(addr);
        ubyte bit = getBit(val, 7);
        val = cast(ubyte)((val << 1) | bit);
        z80_mem_write(addr, val);

        setFlagConds(
            negative(val), zero(val),
            false, parity(val),
            false, cast(bool) bit,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void rl_addr_r(ushort addr, Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte val = z80_mem_read(addr);
        ubyte bit = getBit(val, 7);
        val = cast(ubyte)((val << 1) | bit);
        *reg = val;

        setFlagConds(
            negative(val), zero(val),
            false, parity(val),
            false, cast(bool) bit,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void rr_r(Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte bit = getBit(r, 0);
        ubyte flag = getFlag(Flag.C);
        *reg = cast(ubyte)((*reg >> 1) | (flag << 7));
        
        setFlagConds(
            negative(*reg), zero(*reg),
            false, parity(*reg),
            false, cast(bool) bit,
            (*reg).bit(Flag.X), (*reg).bit(Flag.Y)
        );
    }

    void rr_addr(ushort addr) {
        ubyte val = z80_mem_read(addr);
        ubyte bit = getBit(val, 0);
        ubyte flag = getFlag(Flag.C);
        val = cast(ubyte)((val >> 1) | (flag << 7));
        z80_mem_write(addr, val);

        setFlagConds(
            cast(byte) val < 0, val == 0, // S, Z
            false, (val % 2) == 0,        // H, PV
            false, cast(bool) bit,        // N, C
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void rr_addr_r(ushort addr, Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte val = z80_mem_read(addr);
        ubyte bit = getBit(val, 0);
        ubyte flag = getFlag(Flag.C);
        val = cast(ubyte)((val >> 1) | (flag << 7));
        *reg = val;

        setFlagConds(
            cast(byte) val < 0, val == 0, // S, Z
            false, (val % 2) == 0,        // H, PV
            false, cast(bool) bit,        // N, C
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void rlc_r(Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte bit = getBit(r, 7);
        *reg = cast(ubyte)((*reg << 1) | bit);

        setFlagConds(
            cast(byte) *reg < 0, *reg == 0,
            false, (*reg % 2) == 0,
            false, cast(bool) bit,
            (*reg).bit(Flag.X), (*reg).bit(Flag.Y)
        );
    }

    void rlc_addr(ushort addr) {
        ubyte val = z80_mem_read(addr);
        ubyte bit = getBit(val, 7);
        val = cast(ubyte)((val << 1) | bit);
        z80_mem_write(addr, val);

        setFlagConds(
            cast(byte) val < 0, val == 0,
            false, (val % 2) == 0,
            false, cast(bool) bit,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void rlc_addr_r(ushort addr, Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte val = z80_mem_read(addr);
        ubyte bit = getBit(val, 7);
        val = cast(ubyte)((val << 1) | bit);
        *reg = val;

        setFlagConds(
            cast(byte) val < 0, val == 0,
            false, (val % 2) == 0,
            false, cast(bool) bit,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void rrc_r(Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte bit = getBit(r, 0);
        *reg = cast(ubyte)((*reg >> 1) | (bit << 7));

        setFlagConds(
            negative(*reg), zero(*reg),
            false, parity(*reg),
            false, cast(bool) bit,
            (*reg).bit(Flag.X), (*reg).bit(Flag.Y)
        );
    }

    void rrc_addr(ushort addr) {
        ubyte val = z80_mem_read(addr);
        ubyte bit = getBit(val, 0);
        val = cast(ubyte)((val >> 1) | (bit << 7));
        z80_mem_write(addr, val);

        setFlagConds(
            negative(val), zero(val),
            false, parity(val),
            false, cast(bool) bit,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void rrc_addr_r(ushort addr, Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte val = z80_mem_read(addr);
        ubyte bit = getBit(val, 0);
        val = cast(ubyte)((val >> 1) | (bit << 7));
        *reg = val;

        setFlagConds(
            negative(val), zero(val),
            false, parity(val),
            false, cast(bool) bit,
            val.bit(Flag.X), val.bit(Flag.Y)
        );
    }

    void rld() {
        ubyte val = z80_mem_read(regs.HL);
        ubyte upperHL = val & 0b11110000;
        ubyte lowerHL = val & 0b00001111;

        ubyte upperA = regs.A & 0b11110000;
        ubyte lowerA = regs.A & 0b00001111;

        ubyte newHL = cast(ubyte)((lowerHL << 4) | lowerA);
        z80_mem_write(regs.HL, newHL);
        regs.A = cast(ubyte)(upperHL >> 4 | upperA);

        // TODO: Negative zero and parity are "after an operation", does this mean check these for every step of this operation?
        setFlagConds(
            negative(regs.A), zero(regs.A),
            false, parity(regs.A),
            false, cast(bool) getFlag(Flag.C),
            regs.A.bit(Flag.X), regs.A.bit(Flag.Y)
        );
    }

    void rrd() {
        ubyte val = z80_mem_read(regs.HL);
        ubyte upperHL = val & 0b11110000;
        ubyte lowerHL = val & 0b00001111;

        ubyte upperA = regs.A & 0b11110000;
        ubyte lowerA = regs.A & 0b00001111;

        ubyte newHL = cast(ubyte)((lowerA << 4) | (upperHL >> 4));
        z80_mem_write(regs.HL, newHL);
        regs.A = cast(ubyte)(upperA | lowerHL);

        setFlagConds(
            negative(regs.A), zero(regs.A),
            false, parity(regs.A),
            false, cast(bool) getFlag(Flag.C),
            regs.A.bit(Flag.X), regs.A.bit(Flag.Y)
        );
    }

    void bit_b_r(int b, Register r) {
        ubyte val = getRegisterValue(r);
        bool test = cast(bool)(val & (0b00000001 << b));

        // TODO: S and PV are "unknown". What does this mean? Same with Bit B addr
        setFlagConds(
            false, test == 0,
            true, false,
            false, cast(bool) getFlag(Flag.C)
        );

        if (b == 3) {
            setFlagCond(Flag.X, test);
        } else if (b == 5) {
            setFlagCond(Flag.Y, test);
        }
    }

    // TODO: Leave Flag Conds alone, needs to be done based on if addr is (ix + d) or (hl)
    void bit_b_addr(int b, ushort addr) {
        byte val = z80_mem_read(addr);
        bool test = cast(bool)(val & (0b00000001 << b));
        
        setFlagConds(
            false, test == 0,
            true, false,
            false, cast(bool) getFlag(Flag.C)
        );
    }

    void set_b_r(int b, Register r) {
        ubyte *reg = getRegisterPointer(r);
        *reg = cast(ubyte)(*reg | (0b00000001 << b));
    }

    void set_b_addr(int b, ushort addr) {
        byte val = z80_mem_read(addr);
        val = cast(ubyte)(val | (0b00000001 << b));
        z80_mem_write(addr, val);
    }

    void set_b_addr_r(int b, ushort addr, Register r) {
        ubyte *reg = getRegisterPointer(r);
        byte val = z80_mem_read(addr);
        val = cast(ubyte)(val | (0b00000001 << b));
        *reg = val;
    }

    void res_b_r(int b, Register r) {
        ubyte *reg = getRegisterPointer(r);
        *reg = cast(ubyte)(*reg ^ (0b00000001 << b));
    }

    void res_b_addr(int b, ushort addr) {
        ubyte val = z80_mem_read(addr);
        val = cast(ubyte)(val ^ (0b00000001 << b));
        z80_mem_write(addr, val);
    }

    void res_b_addr_r(int b, ushort addr, Register r) {
        ubyte *reg = getRegisterPointer(r);
        ubyte val = z80_mem_read(addr);
        val = cast(ubyte)(val ^ (0b00000001 << b));
        *reg = val;
    }

    void jp_nn(ushort nn) {
        regs.PC = nn;
    }

    void jp_cc_nn(CC cc, ushort nn) {
        if (checkCC(cc)) regs.PC = nn;
    }

    // TODO: PC increments by e - 2 (which is just e here), so the PC will increment by 2 when jr instructions are done.
    // TODO: Binary value in the actual instruction will be e - 2, so this automatically adjusts for this. Test if it works properly.
    void jr_e(byte e) {
        regs.PC += e;
        regs.secretMath = getHigh(regs.PC);
    }

    // May change to a function for each applicable condition
    int jr_cc_e(CC cc, byte e) {
        if (checkCC(cc)) { regs.PC += e; return 12; }
        else return 7;
    }

    void jp_addr(ushort addr) {
        regs.PC = z80_mem_read16(addr);
    }

    int djnz_e(ubyte e) {
        regs.B--;
        if (regs.B != 0) {
            regs.PC += e;
            return 13;
        } else return 8;
    }

    void call_nn(ushort addr) {
        push_nn(regs.PC);
        regs.PC = addr;
    }

    int call_cc_nn(CC cc, ushort addr) {
        if (checkCC(cc)) {
            call_nn(addr);
            return 17;
        }

        return 10;
    }

    void ret() {
        regs.PC = pop();
    }

    int ret_cc(CC cc) {
        if (checkCC(cc)) { ret(); return 11; }
        else return 5;
    }

    void reti() {
        ret();
        // TODO: Signal I/O Device that Interrupt done
    }

    void retn() {
        ret();
        // TODO: See description for more info
    }

    // TODO: Check program description
    void rst_p(ushort p) {
        push_nn(regs.PC);
        regs.PC = p;
    }

    /*
     * TODO: Need to potentially emulate pins(?) because regs.A (and other regs)
     *  is supposed to appear at the top section of the address pins
     *  despite this part not being used in this function (I think)
     * 
     * TODO: Also need to implement a way to time input/output operations so that 
     *  input doesn't just take the same value from a port and output doesn't
     *  have any similar unintended behaviors. Mabye locks would be useful.
     *
     * TODO: Some of these flags have had the X and Y flags accounted for. See if the others need to be changed. 
     */
    void in_a_n_addr(ubyte port) {
        ubyte top = regs.A;
        regs.A = ports[port];
    }

    void in_r_C_addr(Register r) {
        ubyte top = regs.B;
        ubyte *reg = getRegisterPointer(r);
        *reg = ports[regs.C];

        setFlagConds(
            negative(*reg), zero(*reg),
            false, parity(*reg),
            false, cast(bool) getFlag(Flag.C),
            (*reg).bit(Flag.X), (*reg).bit(Flag.Y)
        );
    }

    // TODO: Need to implement memptr?
    // TODO: Unsure if this is the correct behavior, document unclear
    void ini() {
        ubyte top = regs.B;
        z80_mem_write(regs.HL, ports[regs.C]);
        regs.B--;
        regs.HL++;

        setFlagConds(
            false, zero(regs.B),
            false, false,
            true, cast(bool) getFlag(Flag.C)
        );
    }

    int inir() {
        int cycCount;
        ubyte top = regs.B;
        bool afterFirst;
        do {
            ini();
            T += (regs.BC != 0) ? 21 : 16;
            cycCount += (regs.B != 0) ? 21 : 16;
            if (afterFirst) { incrementR(2); }
            else afterFirst = true;
        } while (regs.B != 0);

        return cycCount;
    }

    void ind() {
        ubyte top = regs.B;
        z80_mem_write(regs.HL, ports[regs.C]);
        regs.BC--;
        regs.HL--;
        
        setFlagConds(
            false, zero(regs.B),
            false, false,
            true, cast(bool) getFlag(Flag.C)
        );
    }

    int indr() {
        int cycCount;
        ubyte top = regs.B;
        bool afterFirst;
        do {
            ind();
            T += (regs.BC != 0) ? 21 : 16;
            cycCount += (regs.B != 0) ? 21 : 16;
            if (afterFirst) { incrementR(2); }
            else afterFirst = true;
        } while (regs.B != 0);
        return cycCount;
    }

    void out_n_addr_a(ubyte port) {
        ubyte top = regs.A;
        ports[port] = regs.A;
    }

    void out_C_addr_r(Register r) {
        ubyte top = regs.B;
        ports[regs.C] = getRegisterValue(r);
    }

    // TODO: Check for accuracy
    void outi() {
        ubyte top = --regs.B;
        ports[regs.C] = z80_mem_read(regs.HL);
        regs.HL++;

        setFlagConds(
            false, zero(regs.B),
            false, false,
            true, cast(bool) getFlag(Flag.C)
        );
    }

    int otir() {
        int cycCount;
        bool afterFirst;
        do {
            outi();
            T += (regs.BC != 0) ? 21 : 16;
            cycCount += (regs.B != 0) ? 21 : 16;
            if (afterFirst) { incrementR(2); }
            else afterFirst = true;
        } while (regs.B != 0);

        return cycCount;
    }

    void outd() {
        ubyte top = --regs.B;
        ports[regs.C] = z80_mem_read(regs.HL);
        regs.HL--;

        setFlagConds(
            false, zero(regs.B),
            false, false,
            true, cast(bool) getFlag(Flag.C)
        );
    }

    int otdr() {
        int cycCount;
        bool afterFirst;
        do {
            outd();
            T += (regs.BC != 0) ? 21 : 16;
            cycCount += (regs.B != 0) ? 21 : 16;
            if (afterFirst) { incrementR(2); }
            else afterFirst = true;
        } while (regs.BC != 0);

        return cycCount;
    }
}