module app;

import std.string, std.algorithm, std.array, std.typecons;
import std.stdio;

import pegged.peg;

//import j_class_info;
//import d_module_writer;

void main(string[] args)
{
}
//    import std.getopt;
//    
//    string[] javaClassNames;
//    string[] javaClassPaths;
//    string outputDirectory = "jni_d/";
//    
//    auto helpInfo = getopt(
//        args, std.getopt.config.caseSensitive, std.getopt.config.bundling,
//        std.getopt.config.required, "class|c", "Generate modules for these Java classes. Can specify multiple times", &javaClassNames,
//        "classpath|p", "Paths used to look up classes. Seperate by ':' or specify multiple times", &javaClassPaths,
//        "odir|o", "Output directory for generated D modules. Created if absent", &outputDirectory,
//        );
//    
//    if (helpInfo.helpWanted)
//    {
//        defaultGetoptPrinter("jni-d: Java class to D module generator.",
//            helpInfo.options);
//        return;
//    }
//    
//    import std.string;
//    auto javapCmd = ["javap", "-public", "-s", "-c"];
//    if (javaClassPaths)
//    {
//        javapCmd ~= "-classpath";
//        javapCmd ~= javaClassPaths.join(":");
//    }
//    
//    string[] classesRemaining = javaClassNames;
//    string[] classesFinished;
//    JClassInfo[][string] moduleInfo;
//    while(classesRemaining.length > 0)
//    {
//        auto thisClass = classesRemaining[0];
//        //        writeln("Generating for '", thisClass, "'");
//        writeln("Reading: ", thisClass);
//        
//        import std.process;
//        auto genOut = execute(javapCmd ~ thisClass);
//        
//        if (genOut.status != 0)
//        {
//            import std.conv : to;
//            throw new Exception("Non-zero return code from 'javap' on invocation: " ~ to!string(javapCmd ~ thisClass));
//        }
//
//        import pegged.grammar;
//        mixin(grammar(javapGrammar));
//        
//        auto classTree = J(genOut.output);
//        
//        if (!classTree.successful)
//        {
//            writeln("FAILED ON CLASS: ", thisClass);
//            writeln(classTree);
//            throw new ParseException(classTree, "Could not parse J class '" ~ thisClass ~ "'");
//        }
//        
//        auto jClassInfo = JClassInfo(classTree);
//        moduleInfo[jClassInfo.getBaseModule()] ~= jClassInfo;   // Store the class info for writing modules later
//
//        auto newDeps =
//            jClassInfo.getDependents()
//                .filter!(a => !["boolean", "byte", "char", "short", "int", "long", "float", "double", "void"].canFind(a))
//                .filter!(a => !classesRemaining.canFind(a))
//                .filter!(a => !classesFinished.canFind(a))
//                .array;
//        //        writeln("New dependents = ", newDeps);
//        
//        classesRemaining ~= newDeps;
//        
//        classesFinished ~= thisClass;
//        classesRemaining = classesRemaining[1 .. $];
//    }
//
//    import std.stdio;
//
//    // Let's nest it
//    JClassInfo[string] rootClasses;
//    string[string] rootMap;
//    void recurseRootMap(string root, in ref JClassInfo jci)
//    {
//        rootMap[jci.className.baseName.replace("$", ".")] = root;
//        jci.nestedClasses.each!(a => recurseRootMap(root, a));
//    }
//    foreach(modName, ref modInfo; moduleInfo)
//    {
//        rootClasses[modName] = doNesting(modInfo);
//        recurseRootMap(modName, rootClasses[modName]);
//    }
//
//    JClassInfo*[string] classesByName;
//    void recurseNestedClasses(JClassInfo* c)
//    {
//        classesByName[c.className.baseName.replace("$", ".")] = c;
//        foreach(ref cp; c.nestedClasses)
//        {
//            recurseNestedClasses(&cp);
//        }
//    }
//    foreach(ref mostBase; rootClasses)
//    {
//        recurseNestedClasses(&mostBase);
//    }
//    
//    foreach(modInfo; classesByName)
//    {
//        if (!modInfo.isClass)
//            continue;
//
//        // Set the override flags
//        foreach(ref meth; modInfo.classMethods)
//        {
//            if (modInfo.hasMethodInExtendedChain(meth, classesByName))
//                meth.isOverride = true;
//            else
//                meth.isOverride = false;
//        }
//    }
//
//    foreach(modName, mostBase; rootClasses)
//    {
//        import std.file, std.path;
//        auto modText = getModuleText(mostBase, modName, rootMap, classesByName);
//
//        auto outName = modName.sanitizeName.replace(".", "/") ~ ".d";
//        writeln("Writing: ", outName);
//
//        auto modulePath = outputDirectory ~ "/" ~ dirName(outName);
//        auto outputFilePath = outputDirectory ~ "/" ~ outName;
//        mkdirRecurse(modulePath);
//        write(outputFilePath, modText);
//    }
//
//    writeln("Finished writing ", classesFinished.length, " in classes.");
//}
//
