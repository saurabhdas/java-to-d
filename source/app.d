module app;

import std.string, std.algorithm, std.array, std.typecons;

import pegged.peg;

import jgrammar;

// For debugging
import std.stdio;

string[] tmpProcess(in ref ParseTree p)
{
    return sort(deepFindAllFirst(p, "J.OnlyClassName").filter!(a => a.matches.length > 1)
        .map!(a => a.matches.join.replace("$", ".")).array).uniq.array;
}

struct JClassInfo
{
    string fromFileName;

    bool isClass, isInterface;
    bool isFinal, isStatic, isAbstract, isSynchronized;
    bool isNested;

    ClassName className;

    ClassName[] interfaceExtends;

    ClassName classExtends;
    ClassName[] classImplements;

    ClassMember[] classMembers;
    ClassConstructor[] classConstructors;
    ClassMethod[] classMethods;

    this(PT)(in auto ref PT p)
    {
        fromFileName = p.shallowFindOnlyOne("J.Body").shallowFindOnlyOne("J.Heading").shallowFindOnlyOne("J.Name").matches.join;

        auto pDeclaration = p.shallowFindOnlyOne("J.Body").shallowFindOnlyOne("J.Declaration");
        auto pInner = pDeclaration.shallowFindOneOf(["J.InterfaceDeclaration", "J.ClassDeclaration"]);
        className = ClassName(pInner.match.shallowFindOnlyOne("J.ClassName"));
        if (pInner.whichMatch == "J.InterfaceDeclaration")
        {
            isInterface = true;
            foreach (mod; pInner.match.shallowFindMany("J.Modifier")) switch (mod.matches.join)
            {
                default:
                    throw new ParseException(p, "Unknown modifier in definition: " ~ mod.matches.join);
                case "public":
                    break;
            }

            auto pExtends = pInner.match.shallowFindMaxOne("J.Extends");
            if (pExtends != ParseTree.init)
            {
                interfaceExtends = pExtends.shallowFindMany("J.ClassName")
                    .map!(a => ClassName(a)).array;
            }
        }
        else if (pInner.whichMatch == "J.ClassDeclaration")
        {
            isClass = true;
            foreach (mod; pInner.match.shallowFindMany("J.Modifier")) switch (mod.matches.join)
            {
                default:
                    throw new ParseException(p, "Unknown modifier in definition: " ~ mod.matches.join);
                case "public":
                    break;
                case "final":
                    isFinal = true;
                    break;
                case "static":
                    isStatic = true;    // Should be a nested class
                    break;
                case "abstract":
                    isAbstract = true;
                    break;
                case "synchronized":
                    isSynchronized = true;
                    break;
            }

            auto pExtends = pInner.match.shallowFindMaxOne("J.Extends");
            if (pExtends != ParseTree.init)
            {
                classExtends = ClassName(pExtends.shallowFindOnlyOne("J.ClassName"));
            }

            auto pImplements = pInner.match.shallowFindMaxOne("J.Implements");
            if (pImplements != ParseTree.init)
            {
                classImplements = pImplements.shallowFindMany("J.ClassName")
                    .map!(a => ClassName(a)).array;
            }
        }
        else
        {
            assert(false);
        }

        import std.regex;
        if (fromFileName != className.baseName.split(regex("[.$]"))[$-1])
        {
            isNested = true;
            assert(className.baseName.split(regex(".$")).canFind(fromFileName));
        }
        // Check for static class for nestedness
        if (isStatic)
            assert(isNested);
        
        foreach(defn; p.shallowFindOnlyOne("J.Body").shallowFindMany("J.Definition"))
        {
            auto jniSig = defn.shallowFindOnlyOne("J.JniSignature").matches.join;

            auto javaSig = defn.shallowFindOnlyOne("J.JavaSignature").shallowFindOneOf(["J.Constructor", "J.Method", "J.Member"]);
            if (javaSig.whichMatch == "J.Constructor")
            {
                auto cc = ClassConstructor(javaSig.match, jniSig);
                assert(cc.name == className);       // Verify this. Maybe the template part will not match.
                classConstructors ~= cc;
            }
            else if (javaSig.whichMatch == "J.Method")
            {
                classMethods ~= ClassMethod(javaSig.match, jniSig);
            }
            else if (javaSig.whichMatch == "J.Member")
            {
                classMembers ~= ClassMember(javaSig.match, jniSig);
            }
            else
            {
                assert(false);
            }
        }
    }
}

ClassName[] processTemplatePart(PT)(in auto ref PT p)
{
    assert(p.name == "J.Template");
    return p.children
        .filter!(a => (a.name == "J.ClassName" || a.name == "J.Wildcard"))
            .map!(a => (a.name == "J.Wildcard") ? ClassName(a.matches.join) : ClassName(a))
            .array;
}

struct ClassName
{
    string baseName;
    ClassName[] genericArgs;
    long arrayDepth;

    this(string onlyBaseName)
    {
        baseName = onlyBaseName;
    }

    this(PT)(in auto ref PT p)
    {
        baseName = p.shallowFindOnlyOne("J.OnlyClassName").matches.join;

        auto pTemplate = p.shallowFindMaxOne("J.Template");
        if (pTemplate != ParseTree.init)
            genericArgs = processTemplatePart(pTemplate);

        auto pArray = p.shallowFindMaxOne("J.Array");
        if (pArray != ParseTree.init)
            arrayDepth = pArray.matches.length;
    }
}

struct ClassMember
{
    bool isFinal, isStatic;

    ClassName type;
    string name;

    string jniSig;

    this(PT)(in auto ref PT p, string sig)
    {
        foreach (mod; p.shallowFindMany("J.Modifier")) switch (mod.matches.join)
        {
            default:
                throw new ParseException(p, "Unknown modifier in definition: " ~ mod.matches.join);
            case "public":
                break;
            case "final":
                isFinal = true;
                break;
            case "static":
                isStatic = true;
                break;
        }

        type = ClassName(p.shallowFindOnlyOne("J.ClassName"));
        name = p.shallowFindOnlyOne("J.Name").matches.join;
        
        jniSig = sig;
    }
}

struct ClassConstructor
{
    ClassName name;
    ClassName[] args;

    string jniSig;

    this(PT)(in auto ref PT p, string sig)
    {
        foreach (mod; p.shallowFindMany("J.Modifier")) switch (mod.matches.join)
        {
            default:
                throw new ParseException(p, "Unknown modifier in definition: " ~ mod.matches.join);
            case "public":
                break;
        }

        name = ClassName(p.shallowFindOnlyOne("J.ClassName"));
        args = p.shallowFindOnlyOne("J.ArgsList").shallowFindMany("J.ClassName").map!(a => ClassName(a)).array;
        
        jniSig = sig;
    }
}

struct ClassMethod
{
    bool isFinal, isStatic, isAbstract, isNative, isSynchronized;

    // Statement is of the form "<A extends B>"
    bool hasTemplateRestrict;
    string templateRestrictA, templateRestrictB;

    ClassName returnType;
    string name;
    ClassName[] args;

    string jniSig;

    this(PT)(in auto ref PT p, string sig)
    {
        foreach (mod; p.shallowFindMany("J.Modifier")) switch (mod.matches.join)
        {
            default:
                throw new ParseException(p, "Unknown modifier in definition: " ~ mod.matches.join);
            case "public":
                break;
            case "final":
                isFinal = true;
                break;
            case "static":
                isStatic = true;
                break;
            case "abstract":
                isAbstract = true;
                break;
            case "native":
                isNative = true;
                break;
            case "synchronized":
                isSynchronized = true;
                break;
        }

        auto pTemplateRestrict = p.shallowFindMaxOne("J.TemplateRestrict");
        if (pTemplateRestrict != ParseTree.init)
        {
            hasTemplateRestrict = true;
            templateRestrictA = pTemplateRestrict.shallowFindOnlyOne("J.ClassName").matches.join;
            templateRestrictB = pTemplateRestrict.shallowFindOnlyOne("J.PathName").matches.join;
        }

        returnType = ClassName(p.shallowFindOnlyOne("J.ClassName"));
        name = p.shallowFindOnlyOne("J.Name").matches.join;
        args = p.shallowFindOnlyOne("J.ArgsList").shallowFindMany("J.ClassName").map!(a => ClassName(a)).array;

        jniSig = sig;
    }
}

unittest
{
    import pegged.grammar;
    mixin(grammar(javapGrammar));

    import std.file;
    {
        auto ret = JClassInfo(J(readText("test_cases/java_lang_Comparable.javap")));
        assert(ret.fromFileName == "Comparable");
        assert(ret.isInterface);
        assert(ret.className.baseName == "java.lang.Comparable");
        assert(ret.className.genericArgs.length == 1);
        assert(ret.className.genericArgs[0].baseName == "T");
        assert(ret.className.arrayDepth == 0);
        assert(ret.interfaceExtends.length == 0);
        assert(ret.classMethods.length == 1);
        assert(ret.classMethods[0].name == "compareTo");
        assert(ret.classMethods[0].returnType.baseName == "int");
        assert(ret.classMethods[0].args.length == 1);
        assert(ret.classMethods[0].jniSig == "(Ljava/lang/Object;)I");
    }

    {
        auto ret = JClassInfo(J(readText("test_cases/my_example_InterfaceExtends.javap")));
        assert(ret.fromFileName == "InterfaceExtends");
        assert(ret.isInterface);
        assert(ret.className.baseName == "InterfaceExtends");
        assert(ret.interfaceExtends.length == 1);
        assert(ret.interfaceExtends[0].baseName == "java.lang.Comparable");
        assert(ret.interfaceExtends[0].genericArgs.length == 1);
        assert(ret.interfaceExtends[0].genericArgs[0].baseName == "T");
        assert(ret.classMethods[0].name == "bigBadCompareTo");
        assert(ret.classMethods[0].returnType.baseName == "int");
        assert(ret.classMethods[0].args.length == 1);
        assert(ret.classMethods[0].jniSig == "([LLjava/lang/Object;)[I");
    }

    {
        auto ret = JClassInfo(J(readText("test_cases/java_lang_Number.javap")));
        assert(ret.fromFileName == "Number");
        assert(ret.isClass);
        assert(ret.className.baseName == "java.lang.Number");
        assert(ret.className.genericArgs.length == 0);
        assert(ret.className.arrayDepth == 0);
        assert(ret.classImplements.length == 1);
        assert(ret.classMethods.length == 6);
        assert(ret.classConstructors.length == 1);
        assert(ret.classConstructors[0].name.baseName == "java.lang.Number");
        assert(ret.classConstructors[0].args.length == 0);
        assert(ret.classConstructors[0].jniSig == "()V");
    }

    {
        auto ret = JClassInfo(J(readText("test_cases/java_lang_Object.javap")));
        assert(ret.fromFileName == "Object");
        assert(ret.className.baseName == "java.lang.Object");
    }

    {
        auto ret = JClassInfo(J(readText("test_cases/java_lang_Integer.javap")));
        assert(ret.fromFileName == "Integer");
        assert(ret.isClass);
        assert(ret.className.baseName == "java.lang.Integer");
        assert(ret.classMembers.length == 4);
    }

    {
        auto ret = JClassInfo(J(readText("test_cases/java_lang_Class.javap")));
        assert(ret.fromFileName == "Class");
        assert(ret.isClass);
        assert(ret.className.baseName == "java.lang.Class");
    }

    {
        JClassInfo(J(readText("test_cases/java_lang_reflect_Method.javap")));
        JClassInfo(J(readText("test_cases/java_io_InputStream.javap")));
        JClassInfo(J(readText("test_cases/java_nio_charset_Chartset.javap")));
        JClassInfo(J(readText("test_cases/java_util_Locale.javap")));
        JClassInfo(J(readText("test_cases/java_lang_AbstractStringBuilder.javap")));
        JClassInfo(J(readText("test_cases/java_lang_Enum.javap")));
        JClassInfo(J(readText("test_cases/java_lang_Thread.javap")));
    }
}

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
    while(classesRemaining.length > 0)
    {
        auto thisClass = classesRemaining[0];
        writeln("Generating for ", thisClass);
        
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
            throw new ParseException(classTree, "Could not parse J class successfully");
        }
        
        auto dependentClassNames = tmpProcess(classTree);
        
        //        import std.file, std.path;
        //        auto modulePath = outputDirectory ~ "/" ~ dirName(res.oName);
        //        auto outputFilePath = outputDirectory ~ "/" ~ res.oName;
        //        log("Writing output to directory=", modulePath, " file=", outputFilePath);
        //        mkdirRecurse(modulePath);
        //        write(outputFilePath, res.oText);
        
        auto newDeps = dependentClassNames.filter!(a => !classesRemaining.canFind(a)).filter!(a => !classesFinished.canFind(a)).array;
        writeln("New dependents = ", newDeps);
        
        classesRemaining ~= newDeps;
        
        classesFinished ~= thisClass;
        classesRemaining = classesRemaining[1 .. $];
    }

    writeln("Finished processing: ", classesFinished, " (", classesFinished.length, " in number)");
}

