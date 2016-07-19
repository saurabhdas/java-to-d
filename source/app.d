module app;

import std.string, std.algorithm, std.array, std.typecons;
import std.stdio;

import pegged.peg;

import jgrammar;
import j_class_info;
import d_module_writer;

void main(string[] args)
{
    import std.getopt;
    
    string[] javaClassNames;
    string[] javaClassPaths;
    string outputDirectory = "jni_d/";
    
    auto helpInfo = getopt(
        args, std.getopt.config.caseSensitive, std.getopt.config.bundling,
        std.getopt.config.required, "class|c", "Generate modules for these Java classes. Can specify multiple times", &javaClassNames,
        "classpath|p", "Paths used to look up classes. Seperate by ':' or specify multiple times", &javaClassPaths,
        "odir|o", "Output directory for generated D modules. Created if absent", &outputDirectory,
        );
    
    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("jni-d: Java class to D module generator.",
            helpInfo.options);
        return;
    }
    
    import std.string;
    auto javapCmd = ["javap", "-public", "-s"];
    if (javaClassPaths)
    {
        javapCmd ~= "-classpath";
        javapCmd ~= javaClassPaths.join(":");
    }
    
    string[] classesRemaining = javaClassNames;
    string[] classesFinished;
    JClassInfo[][string] moduleInfo;
    while(classesRemaining.length > 0)
    {
        auto thisClass = classesRemaining[0];
//        writeln("Generating for '", thisClass, "'");
        writeln(thisClass);
        
        import std.process;
        auto genOut = execute(javapCmd ~ thisClass);
        
        if (genOut.status != 0)
        {
            import std.conv : to;
            throw new Exception("Non-zero return code from 'javap' on invocation: " ~ to!string(javapCmd ~ thisClass));
        }

        import pegged.grammar;
        mixin(grammar(javapGrammar));
        
        auto classTree = J(genOut.output);
        
        if (!classTree.successful)
        {
            writeln("FAILED ON CLASS: ", thisClass);
            writeln(classTree);
            throw new ParseException(classTree, "Could not parse J class '" ~ thisClass ~ "'");
        }
        
        auto jClassInfo = JClassInfo(classTree);
        moduleInfo[jClassInfo.getBaseModule()] ~= jClassInfo;   // Store the class info for writing modules later

        auto newDeps =
            jClassInfo.getDependents()
                .filter!(a => !["boolean", "byte", "char", "short", "int", "long", "float", "double", "void"].canFind(a))
                .filter!(a => !classesRemaining.canFind(a))
                .filter!(a => !classesFinished.canFind(a))
                .array;
//        writeln("New dependents = ", newDeps);
        
        classesRemaining ~= newDeps;
        
        classesFinished ~= thisClass;
        classesRemaining = classesRemaining[1 .. $];
    }

    foreach(modName, modInfo; moduleInfo)
    {
        writeln(modName, " <- ", modInfo);
    }

    //        import std.file, std.path;
    //        auto modulePath = outputDirectory ~ "/" ~ dirName(res.oName);
    //        auto outputFilePath = outputDirectory ~ "/" ~ res.oName;
    //        log("Writing output to directory=", modulePath, " file=", outputFilePath);
    //        mkdirRecurse(modulePath);
    //        write(outputFilePath, res.oText);

    writeln("Finished processing: ", classesFinished, " (", classesFinished.length, " in number)");
}

