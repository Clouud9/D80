module tests;
import zemu;

import std.file;
import std.process;
import std.algorithm;
import std.stdio;
import std.path;

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
    
}