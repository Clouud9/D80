module controller;
import emul;
import zemu;

class Controller {
    Zemu emu;
    ubyte *ram, *ports;
    int *cycleCount;
    bool contLoop = true;
    enum Mode {Main, Misc, Bit, IX, IX_Bit, IY, IY_Bit}
}