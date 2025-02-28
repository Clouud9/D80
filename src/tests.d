module tests;
import zemu;

import std.file;
import std.process;
import std.algorithm;
import std.stdio;
import std.path;
import std.array;
import std.format;

void compileTests() {
    auto testFiles = dirEntries(getcwd() ~ "\\Tests\\Sources\\", SpanMode.shallow)
                     .filter!(e => e.name.endsWith(".asm"))
                     .map!(e => e.name);

    foreach (testFile; testFiles) {
        string withoutExt = testFile.baseName.stripExtension;

        writeln("Compiling ", testFile, " with sjasmplus...");
        auto result = execute(["sjasmplus", testFile, "--raw=" ~ getcwd() ~ "\\Tests\\Bins\\" ~ withoutExt ~ ".bin"]);

        if (result.status != 0) {
            writeln("Error compiling ", testFile, ":");
            writeln(result.output);
            writeln(result.status);
        } else {
            // writeln(testFile, " compiled successfully.");
        }
    }
}

uint runTest(Registers *regs, int cycles, string test) {
    return 0;
}

string getExecutionResults(Zemu emul) {
    Appender!string app;
    app.formattedWrite("A:  %02X\n", emul.regs.A);
    app.formattedWrite("F:  %02X\n", emul.regs.F);
    app.formattedWrite("B:  %02X\n", emul.regs.B);
    app.formattedWrite("C:  %02X\n", emul.regs.C);
    app.formattedWrite("D:  %02X\n", emul.regs.D);
    app.formattedWrite("E:  %02X\n", emul.regs.E);
    app.formattedWrite("H:  %02X\n", emul.regs.H);
    app.formattedWrite("L:  %02X\n", emul.regs.L);
    app.formattedWrite("I:  %02X\n", emul.regs.I);
    app.formattedWrite("R:  %02X\n", emul.regs.R);
    app.formattedWrite("A': %02X\n", emul.regs.AP);
    app.formattedWrite("F': %02X\n", emul.regs.FP);
    app.formattedWrite("B': %02X\n", emul.regs.BP);
    app.formattedWrite("C': %02X\n", emul.regs.CP);
    app.formattedWrite("D': %02X\n", emul.regs.DP);
    app.formattedWrite("E': %02X\n", emul.regs.EP);
    app.formattedWrite("IFF1: %02X\n", emul.regs.iff1);
    app.formattedWrite("IFF2: %02X\n", emul.regs.iff2);
    app.formattedWrite("IM: %02X\n", 0);
    app.formattedWrite("Hidden 16-Bit Math: %02X\n", 0);
    app.formattedWrite("IX: %04X\n", emul.regs.IX);
    app.formattedWrite("IY: %04X\n", emul.regs.IY);
    app.formattedWrite("PC: %04X\n", emul.regs.PC);
    app.formattedWrite("SP: %04X\n", emul.regs.SP);
    app.formattedWrite("Ran %d cycles\n", emul.T);
    return app.toString;
}