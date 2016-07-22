module j_class_info;

import std.string, std.algorithm, std.array, std.typecons;
import pegged.grammar;
import jgrammar;

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

    JClassInfo[] nestedClasses;

    bool derivesFrom(string name, in JClassInfo*[string] classesByName) const
    {
        auto n2 = name.replace("$", ".");
        assert(!name.canFind('['));

        if (n2 == className.baseName.replace("$", "."))
            return true;

        if (isClass)
        {
            foreach(ref i; classImplements)
            {
                auto cx = classesByName.get(i.baseName.replace("$", "."), null);
                assert(cx !is null);
                if (cx.derivesFrom(n2, classesByName))
                    return true;
            }

            if (className.baseName != "java.lang.Object")
            {
                auto cx = classesByName.get(classExtends.baseName.replace("$", "."), null);
                import std.stdio;
                writeln(classExtends.baseName.replace("$", "."));
                assert(cx !is null);
                if (cx.derivesFrom(n2, classesByName))
                    return true;
            }
        }
        else
        {
            foreach(ref i; interfaceExtends)
            {
                auto cx = classesByName.get(i.baseName.replace("$", "."), null);
                assert(cx !is null);
                if (cx.derivesFrom(n2, classesByName))
                    return true;
            }
        }

        return false;
    }

    bool hasMethodInExtendedChain(ClassMethod m, in JClassInfo*[string] know, bool examineMe = false) const
    {
        if (examineMe)
        {
            foreach (cm; classMethods)
            {
                if (cm.name == m.name)
                {
                    if(cm.interpretJniSig2 == m.interpretJniSig2 &&
                        cm.isStatic == m.isStatic)
                    {
                        // It could be that the signatures don't match, but one returns a subclass of the base class
                        // We should assert that one is a base class of the other
                        // But since a function call is defined clearly by the caller's signature
                        // This should be okay
                        return true;
                    }
                }
            }
        }
        if (classExtends != ClassName.init)
        {
            auto ce = know.get(classExtends.baseName, null);
            assert(ce !is null);
            return ce.hasMethodInExtendedChain(m, know, true);
        }
        return false;
    }

    string[] getDependents() const
    {
        import std.range;
        return
            sort(chain(
                    isNested ? [getBaseModule()] : [],
                    interfaceExtends.map!(a => a.baseName.idup),
                    (isInterface || classExtends == ClassName.init) ? [] : [classExtends].map!(a => a.baseName.idup).array,
                    classImplements.map!(a => a.baseName.idup),
                    classMembers.map!(a => a.getDependents()).joiner,
                    classConstructors.map!(a => a.getDependents()).joiner,
                    classMethods.map!(a => a.getDependents()).joiner).array)
                .uniq.array;
    }
    
    string getBaseModule() const
    {
        import std.regex, std.range;
        return className.baseName.split(regex(r"[.$/]")).retro.find(fromFileName).retro.join('.');
    }
    
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
            else
            {
                classExtends = (className.baseName != "java.lang.Object") ? ClassName("java.lang.Object") : ClassName.init;
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
            assert(className.baseName.split(regex("[.$]")).canFind(fromFileName));
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
                assert(cc.name.baseName == className.baseName);
                classConstructors ~= cc;
            }
            else if (javaSig.whichMatch == "J.Method")
            {
                auto hasCode = (defn.shallowFindMaxOne("J.Code") != typeof(defn).init);
                classMethods ~= ClassMethod(javaSig.match, jniSig, hasCode);
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

    void bubbleNested(ref JClassInfo jci)
    {
        assert(jci.className.baseName.startsWith(className.baseName));

        import std.range;
        assert(nestedClasses.filter!(a => a.className.baseName.startsWith(jci.className.baseName)).walkLength == 0);

        import std.array;
        auto nTest = nestedClasses.enumerate.filter!(a => jci.className.baseName.startsWith(a.value.className.baseName)).array;
        assert(nTest.length == 0 || nTest.length == 1);

        if (nTest.length == 0)
        {
            nestedClasses ~= jci;
        }
        else
        {
            nestedClasses[nTest[0].index].bubbleNested(jci);
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

auto extractDependentsFromJniSig(const string jniSig)
{
    import std.regex, std.array;
    auto rgx = regex(r"L[a-zA-Z/$]+;");
    return jniSig.matchAll(rgx).map!(a => a.hit).map!(a => a[1 .. $-1].replace("/", ".")).array;
}

struct ClassMember
{
    bool isFinal, isStatic;
    
    ClassName type;
    string name;
    
    string jniSig;
    
    string[] getDependents() const
    {
        return extractDependentsFromJniSig(jniSig);
    }

    string interpretJniSig() const
    {
        string ret;
        assert(jniSig.length > 0);
        for (long i=0; i<jniSig.length; ++i)
        {
            switch(jniSig[i])
            {
                case '[':
                    ret ~= "[]";
                    break;
                case 'Z':
                    ret = "bool" ~ ret;
                    break;
                case 'B':
                    ret = "ubyte" ~ ret;
                    break;
                case 'C':
                    ret = "char" ~ ret;
                    break;
                case 'S':
                    ret = "short" ~ ret;
                    break;
                case 'I':
                    ret = "int" ~ ret;
                    break;
                case 'J':
                    ret = "long" ~ ret;
                    break;
                case 'F':
                    ret = "float" ~ ret;
                    break;
                case 'D':
                    ret = "double" ~ ret;
                    break;
                case 'L':
                    auto j = indexOf(jniSig, ';', i);
                    assert(j > i);
                    ret = jniSig[i+1 .. j].replace("/", ".").replace("$", ".") ~ ret;
                    i = j;  // +1 will be added in the loop
                    break;
                default:
                    assert(false);
            }
        }
        return ret;
    }
    
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
    
    string[] getDependents() const
    {
        return extractDependentsFromJniSig(jniSig);
    }
    
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

    string[] interpretJniSig() const
    {
        // Signature will be of the form (XYZ)V
        assert(jniSig[0] == '(');
        assert(jniSig[$-2 .. $] == ")V");

        auto ret = appender!(string[]);
        string curret;
        assert(jniSig.length > 0);
        for (long i=1; i<jniSig.indexOf(')'); ++i)
        {
            switch(jniSig[i])
            {
                case '[':
                    curret ~= "[]";
                    break;
                case 'Z':
                    ret.put("bool" ~ curret);
                    curret = "";
                    break;
                case 'B':
                    ret.put("ubyte" ~ curret);
                    curret = "";
                    break;
                case 'C':
                    ret.put("char" ~ curret);
                    curret = "";
                    break;
                case 'S':
                    ret ~= "short" ~ curret;
                    curret = "";
                    break;
                case 'I':
                    ret.put("int" ~ curret);
                    curret = "";
                    break;
                case 'J':
                    ret.put("long" ~ curret);
                    curret = "";
                    break;
                case 'F':
                    ret.put("float" ~ curret);
                    curret = "";
                    break;
                case 'D':
                    ret.put("double" ~ curret);
                    curret = "";
                    break;
                case 'L':
                    auto j = indexOf(jniSig, ';', i);
                    assert(j > i);
                    ret.put(jniSig[i+1 .. j].replace("/", ".").replace("$", ".") ~ curret);
                    curret = "";
                    i = j;  // +1 will be added in the loop
                    break;
                default:
                    assert(false);
            }
        }
        return ret.data;
    }
}

struct ClassMethod
{
    bool isFinal, isStatic, isAbstract, isNative, isSynchronized;
    bool isOverride;
    bool hasCode;
    
    // Statement is of the form "<A extends B>"
    bool hasTemplateRestrict;
    Tuple!(string, "pre", string, "post")[] templateRestricts;
    
    ClassName returnType;
    string name;
    ClassName[] args;
    
    string jniSig;

    string[] getDependents() const
    {
        return extractDependentsFromJniSig(jniSig);
    }

    string interpretJniSig1() const
    {
        string ret;
        assert(jniSig.indexOf(')') > 0);
        for (long i=jniSig.indexOf(')')+1; i<jniSig.length; ++i)
        {
            switch(jniSig[i])
            {
                case '[':
                    ret ~= "[]";
                    break;
                case 'Z':
                    ret = "bool" ~ ret;
                    break;
                case 'B':
                    ret = "ubyte" ~ ret;
                    break;
                case 'C':
                    ret = "char" ~ ret;
                    break;
                case 'S':
                    ret = "short" ~ ret;
                    break;
                case 'I':
                    ret = "int" ~ ret;
                    break;
                case 'J':
                    ret = "long" ~ ret;
                    break;
                case 'F':
                    ret = "float" ~ ret;
                    break;
                case 'D':
                    ret = "double" ~ ret;
                    break;
                case 'V':
                    ret = "void" ~ ret;
                    break;
                case 'L':
                    auto j = indexOf(jniSig, ';', i);
                    assert(j > i);
                    ret = jniSig[i+1 .. j].replace("/", ".").replace("$", ".") ~ ret;
                    i = j;  // +1 will be added in the loop
                    break;
                default:
                    import std.stdio;
                    writeln(jniSig);
                    writeln(jniSig[i]);
                    assert(false);
            }
        }
        return ret;
    }

    string[] interpretJniSig2() const
    {
        // Signature will be of the form (XYZ)...
        assert(jniSig[0] == '(');
        
        auto ret = appender!(string[]);
        string curret;
        assert(jniSig.length > 0);
        for (long i=1; i<jniSig.indexOf(')'); ++i)
        {
            switch(jniSig[i])
            {
                case '[':
                    curret ~= "[]";
                    break;
                case 'Z':
                    ret.put("bool" ~ curret);
                    curret = "";
                    break;
                case 'B':
                    ret.put("ubyte" ~ curret);
                    curret = "";
                    break;
                case 'C':
                    ret.put("char" ~ curret);
                    curret = "";
                    break;
                case 'S':
                    ret ~= "short" ~ curret;
                    curret = "";
                    break;
                case 'I':
                    ret.put("int" ~ curret);
                    curret = "";
                    break;
                case 'J':
                    ret.put("long" ~ curret);
                    curret = "";
                    break;
                case 'F':
                    ret.put("float" ~ curret);
                    curret = "";
                    break;
                case 'D':
                    ret.put("double" ~ curret);
                    curret = "";
                    break;
                case 'L':
                    auto j = indexOf(jniSig, ';', i);
                    assert(j > i);
                    ret.put(jniSig[i+1 .. j].replace("/", ".").replace("$", ".") ~ curret);
                    curret = "";
                    i = j;  // +1 will be added in the loop
                    break;
                default:
                    assert(false);
            }
        }
        return ret.data;
    }

    this(PT)(in auto ref PT p, string sig, bool hasCode_)
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
            for (int i=0; i<pTemplateRestrict.children.length; ++i)
            {
                assert(pTemplateRestrict.children[i].name == "J.ClassName");
                if (pTemplateRestrict.children.length > i+1 && pTemplateRestrict.children[i+1].name == "J.PathOrClassName")
                {
                    templateRestricts ~= tuple!("pre", "post")(pTemplateRestrict.children[i].matches.join, pTemplateRestrict.children[i+1].matches.join);
                    ++i;
                }
                else
                {
                    templateRestricts ~= tuple!("pre", "post")(pTemplateRestrict.children[i].matches.join, "");
                }
            }
        }
        
        returnType = ClassName(p.shallowFindOnlyOne("J.ClassName"));
        name = p.shallowFindOnlyOne("J.Name").matches.join;
        args = p.shallowFindOnlyOne("J.ArgsList").shallowFindMany("J.ClassName").map!(a => ClassName(a)).array;
        
        jniSig = sig;
        hasCode = hasCode_;
    }
}

// This function modifies *some* of the values inside jcs - beacuse deep copy isn't defined for JClassInfo
JClassInfo doNesting(JClassInfo[] jcs)
{
    // Find the base class
    import std.range;

    auto sortedArray = jcs.sort!((a, b) => a.className.baseName < b.className.baseName).array;
    assert(sortedArray.uniq.walkLength == sortedArray.length);
    sortedArray.each!(a => assert(a.className.baseName.startsWith(sortedArray[0].className.baseName)));

    jcs[1 .. $].each!(a => sortedArray[0].bubbleNested(a));

    return sortedArray[0];
}

unittest
{
    import pegged.grammar;
    mixin(grammar(javapGrammar));
    
    {   // Test out the get dependents function
        assert(extractDependentsFromJniSig("(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V") == ["java.lang.String", "java.lang.String", "java.lang.String"]);
        assert(extractDependentsFromJniSig("(Ljava/lang/ThreadGroup;Ljava/lang/Runnable;Ljava/lang/String;J)V") == ["java.lang.ThreadGroup", "java.lang.Runnable", "java.lang.String"]);
    }
    
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
        assert(ret.classMembers.length == 5);
    }
    
    {
        auto ret = JClassInfo(J(readText("test_cases/java_lang_Class.javap")));
        assert(ret.fromFileName == "Class");
        assert(ret.isClass);
        assert(ret.className.baseName == "java.lang.Class");
    }
    
    {
        JClassInfo(J(readText("test_cases/java_io_InputStream.javap")));
        JClassInfo(J(readText("test_cases/java_io_Serializable.javap")));
        JClassInfo(J(readText("test_cases/java_lang_AbstractStringBuilder.javap")));
        JClassInfo(J(readText("test_cases/java_lang_Class.javap")));
        JClassInfo(J(readText("test_cases/java_lang_Comparable.javap")));
        JClassInfo(J(readText("test_cases/java_lang_Enum.javap")));
        JClassInfo(J(readText("test_cases/java_lang_Integer.javap")));
        JClassInfo(J(readText("test_cases/java_lang_Number.javap")));
        JClassInfo(J(readText("test_cases/java_lang_Object.javap")));
        JClassInfo(J(readText("test_cases/java_lang_Thread.javap")));
        JClassInfo(J(readText("test_cases/java_lang_reflect_Method.javap")));
        JClassInfo(J(readText("test_cases/java_nio_charset_Charset.javap")));
        JClassInfo(J(readText("test_cases/java_util_Locale.javap")));
        JClassInfo(J(readText("test_cases/java_util_Locale_Category.javap")));
        JClassInfo(J(readText("test_cases/my_example_InterfaceExtends.javap")));
    }
    
    {
        auto ret = JClassInfo(J(readText("test_cases/java_io_Serializable.javap")));
        assert(ret.getDependents() == []);
    }

    {   // Test the class nesting
        JClassInfo c1, c2, c3, c4, c5, c6, c7;
        c1.className.baseName = "aa.bb.cc.dd";
        c2.className.baseName = "aa.bb.cc";
        c3.className.baseName = "aa.bb.cc.dd.ee";
        c4.className.baseName = "aa.bb.cc.ff";
        c5.className.baseName = "aa.bb.cc.ff.hh";
        c6.className.baseName = "aa.bb.cc.ff.gg.ii";
        c7.className.baseName = "aa.bb.cc.ff.jj";

        auto d1 = doNesting([c1, c2, c3,c4, c5, c6, c7]);

        assert(d1.className.baseName == "aa.bb.cc");
        assert(d1.nestedClasses.length == 2);
        assert(d1.nestedClasses[0].className.baseName == "aa.bb.cc.dd");
        assert(d1.nestedClasses[1].className.baseName == "aa.bb.cc.ff");

        assert(d1.nestedClasses[0].nestedClasses.length == 1);
        assert(d1.nestedClasses[0].nestedClasses[0].className.baseName == "aa.bb.cc.dd.ee");

        assert(d1.nestedClasses[1].nestedClasses.length == 3);
        assert(d1.nestedClasses[1].nestedClasses[0].className.baseName == "aa.bb.cc.ff.gg.ii");
        assert(d1.nestedClasses[1].nestedClasses[1].className.baseName == "aa.bb.cc.ff.hh");
        assert(d1.nestedClasses[1].nestedClasses[2].className.baseName == "aa.bb.cc.ff.jj");
    }

    {   // Test the class nesting with a real class
        auto e1 = JClassInfo(J(readText("test_cases/java_util_Locale.javap")));
        auto e2 = JClassInfo(J(readText("test_cases/java_util_Locale_Category.javap")));
        
        auto x = doNesting([e2, e1]);
        assert(x.className.baseName == "java.util.Locale");
        assert(x.nestedClasses.length == 1);
        assert(x.nestedClasses[0].className.baseName == "java.util.Locale$Category");
    }
}
