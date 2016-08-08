module app;

import std.string, std.algorithm, std.array, std.typecons;
import std.stdio;

import pegged.peg;

import detail.ast_resolver;
import detail.dmodule_writer;

void main(string[] args)
{
    import std.getopt;
    
    string[] javaClassNames;
    string[] javaClassPaths;
    string outputDirectory = "output/";
    
    auto helpInfo = getopt(
        args, std.getopt.config.caseSensitive, std.getopt.config.bundling, std.getopt.config.passThrough,
        "classpath|c", "Specify where to find user class files", &javaClassPaths,
        "outdir|o", "Output directory for generated D modules", &outputDirectory,
        );

    javaClassNames = args[1 .. $];

    if (helpInfo.helpWanted || javaClassNames.length == 0)
    {
        defaultGetoptPrinter("java-to-d <options> <classes>", helpInfo.options);
        return;
    }

    /* Copy jni_d files */
    auto executablePath = args[0].split("/")[0 .. $-1].join("/");
    import std.file;
    mkdirRecurse(outputDirectory ~ "/jni_d/");
    copy(executablePath ~ "/jni.d", outputDirectory ~ "/jni_d/jni.d");
    copy(executablePath ~ "/java_root.d", outputDirectory ~ "/jni_d/java_root.d");
    copy(executablePath ~ "/support.d", outputDirectory ~ "/jni_d/support.d");
    copy(executablePath ~ "/package.d", outputDirectory ~ "/jni_d/package.d");

    auto st = new SymbolTable;
    javaClassNames.each!(a => st.ensureSymbol(JName(a)));
    
    resolveAll(st, javaClassPaths);
    fixAllInheritedImplements(st);

    auto n = writeAll(st, outputDirectory);

    writeln("Finished writing ", n, " in classes.");
}

