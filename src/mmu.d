module mmu;
import device;
import std.file;
import std.exception : ErrnoException, enforce;
import std.stdio;

class MMU {
    enum MAX_MEM = 65_536;
    
    public:
        ubyte[MAX_MEM] ram;
        ubyte[256] ports; // Has 16 bit addresses but typically only uses up to 8, figure out how it 
        Device[256] devices;

        ubyte read_ram(ushort addr) {
            return ram[addr];
        }
        
        ushort read_ram_16(ushort addr) {
            return (cast(ushort)ram[addr]) | ((cast(ushort)ram[addr + 1]) << 8);
        }
        
        void write_ram(ushort addr, ubyte value) {
            ram[addr] = value;
        }
        
        void write_ram_16(ushort addr, ushort value) {
            ram[addr] = cast(ubyte)(value & 0xff);
            ram[addr + 1] = cast(ubyte)(value >> 8);
        }

        void load(string str) {
            try {
                File fp = File(str, "r");
                fp.rawRead(ram);
            } catch (ErrnoException e) {
                assert(false, "Error: " ~ e.msg);
            }
        }

        void dump(string str) {
            try {
                File fp = File(str, "w");
                fp.rawWrite(ram);
            } catch (ErrnoException e) {
                assert(false, "Error: " ~ e.msg);
            }
        }

        // port_in may be 16 bytes
        void port_in(ushort port) {
            
        }
        
        void port_in_16(ushort port) {
            
        }

        void port_out(ushort addr, ubyte val) {
            
        }

        void port_out_16(ushort addr, ushort val) {
            
        }
        
        /* 
         * TODO: Need to implement a way to custom-define port behavior,
         *  and define how devices interact with ports. Then need to
         *  figure out how to implement this in emul.d with the 
         *  switch statement, and zemu.d with the functions.
         *  Must be able to deal with delays.
         *  
         * Global Variable ports is temporary until read and write logic 
         *  is revised (likely will be the same w/ global var ram)
         */
}
