module d_module_writer;

import std.string, std.algorithm, std.array, std.typecons, std.range, std.conv, std.regex;

import j_class_info;

string getModuleText(JClassInfo me, string modName, in string[string] rootMap, in JClassInfo*[string] classesByName)
{
    assert(!me.isNested);

    import std.path, std.file;

    auto modMain = getModuleTextInternal(me, "", rootMap, classesByName, false);
    auto wriImpo = sort(modMain.imports.map!(a => a.sanitizeName).array).uniq.filter!(a => a != modName).array;

    return "module " ~ modName.dName(rootMap).split(".")[0 .. $-1].join(".") ~ ";\n\n" ~
        "static import jarray;\n" ~
            wriImpo.map!(a => "static import " ~ a ~ ";\n").join ~ "\n" ~ modMain.core;
}

string dName(string className, in string[string] rootMap)
{
    if (className.split(regex(r"[./$]")).length == 1)
        return className.sanitizeName;
    else
    {
        auto moduleName = rootMap.get(className.replace("$", ".").filter!(a => a != '[' && a != ']').array.to!string, null);
        assert(moduleName !is null, "No class for: '" ~ className ~ "'");
        assert(moduleName.indexOf('$') < 0);
        assert(className.startsWith(moduleName));
        auto ret = moduleName ~ "." ~ moduleName.split(".")[$-1] ~ className[moduleName.length .. $];
        return ret.sanitizeName;
    }
}

string sanitizeName(string name)
{
    if (name.lastIndexOf('[') > 0)
    {
        assert(name[$-2 .. $] == "[]");
        return "jarray.jarray!(" ~ name[0 .. $-2].sanitizeName ~ ")";
    }
    else if (name.canFind("."))
        return name.split(".").map!(a => a.sanitizeName).join(".");
    else if (name.canFind("$"))
        return name.split("$").map!(a => a.sanitizeName).join(".");
    else if (name == "cast" || name == "function" || name == "with" || name == "delete" || name == "toString" || name == "version")
        return "j" ~ name;
    else if (name == "Object" || name == "Throwable")
        return "J" ~ name;
    else
        return name;
}

Tuple!(string, "core", string[], "imports") getModuleTextInternal(JClassInfo me, string tabLevel, in string[string] rootMap, in JClassInfo*[string] classesByName, bool isParentAnInterface)
{
    auto app = appender!(string);
    string[] imports = me.getDependents();

    with(app)
    {
        put(tabLevel);

        if (me.isFinal)
            put("final ");
        if (me.isStatic || isParentAnInterface)
            put("static ");
        if (me.isAbstract)
            put("abstract ");

        if (me.isInterface)
            put("interface ");
        else
            put("class ");
        import std.stdio;
        put(me.className.baseName.dName(rootMap).split(".")[$-1]);

        if (me.isInterface && me.interfaceExtends.length > 0)
        {
            put(" : ");
            put(me.interfaceExtends.map!(a => a.baseName.dName(rootMap)).join(", "));
        }
        if (me.isClass && me.className.baseName != "java.lang.Object")
        {
            put(" : ");
            put(me.classExtends.baseName.dName(rootMap));
            if (me.classImplements.length > 0)
            {
                put(", ");
                put(me.classImplements.map!(a => a.baseName.dName(rootMap)).join(", "));
            }
        }

        put("\n");

        put(tabLevel);
        put("{\n");

        foreach(ref memb; me.classMembers)
        {
            put(tabLevel);

            // Getter
            put("    ");
            if (memb.isStatic)
                put("static ");
            put(memb.interpretJniSig.dName(rootMap));
            put(' ');
            put(memb.name.dName(rootMap));
            put("();\n");

            // Setter
            if (!memb.isFinal)
            {
                put("    ");
                if (memb.isStatic)
                    put("Static ");
                put("void ");
                put(memb.name.dName(rootMap));
                put("(");
                put(memb.interpretJniSig.dName(rootMap));
                put(")");
                put(";\n");
            }

            // Whitespace
            put("\n");
        }

        foreach(ref cons; me.classConstructors)
        {
            put(tabLevel);

            put("    this(");
            put(cons.interpretJniSig.enumerate.map!(a => a.value.dName(rootMap) ~ " _arg" ~ to!string(a.index)).join(", "));
            put(")");
            put(";\n");

            // Whitespace
            put("\n");
        }

        // We need to remove bridge methods. D handles them correctly, so we only need to keep the most derived form
        auto signatureList = me.classMethods.dup;
        if (me.classMethods.length >= 2)
        {
            signatureList = signatureList
                .sort!((a, b) => (a.name ~ "@" ~ a.interpretJniSig2) < (b.name ~ "@" ~ b.interpretJniSig2)).array;
            for(int i=0; i<signatureList.length-1; ++i)
            {
                if (signatureList[i].name == signatureList[i+1].name &&
                    signatureList[i].interpretJniSig2 == signatureList[i+1].interpretJniSig2)
                {
                    // We'll keep the most derived class
                    auto ret1 = signatureList[i].interpretJniSig1;
                    auto ret2 = signatureList[i+1].interpretJniSig1;

                    if (signatureList[i].interpretJniSig1[$-2 .. $] == "[]" && signatureList[i+1].interpretJniSig1 == "java.lang.Object")
                    {
                        debug auto asem = signatureList[i+1];
                        signatureList = signatureList[0 .. i+1] ~ signatureList[i+2 .. $];
                        debug assert(signatureList.length <= i+1 || signatureList[i+1] != asem);
                        --i;
                    }
                    else if (signatureList[i+1].interpretJniSig1[$-2 .. $] == "[]" && signatureList[i].interpretJniSig1 == "java.lang.Object")
                    {
                        debug auto asem = signatureList[i+1];
                        signatureList = signatureList[0 .. i] ~ signatureList[i+1 .. $];
                        debug assert(signatureList.length <= i+1 || signatureList[i+1] != asem);
                        --i;
                    }
                    else
                    {
                        auto ci1 = classesByName.get(ret1.replace("$", ".").filter!(a => a != '[' && a != ']').to!string, null);
                        auto ci2 = classesByName.get(ret2.replace("$", ".").filter!(a => a != '[' && a != ']').to!string, null);

                        assert(ci1 !is null);
                        assert(ci2 !is null);

                        if (ci1.derivesFrom(ret2, classesByName))
                        {
                            //                            writeln("    ", ret1, " derives from ", ret2, "\t\tSTD FORM");
                            debug auto asem = signatureList[i+1];
                            signatureList = signatureList[0 .. i+1] ~ signatureList[i+2 .. $];
                            debug assert(signatureList.length <= i+1 || signatureList[i+1] != asem);
                            --i;
                        }
                        else if (ci2.derivesFrom(ret1, classesByName))
                        {
                            //                            writeln("    ", ret2, " derives from ", ret1, "\t\tSTD FORM");
                            debug auto asem = signatureList[i+1];
                            signatureList = signatureList[0 .. i] ~ signatureList[i+1 .. $];
                            debug assert(signatureList.length <= i+1 || signatureList[i+1] != asem);
                            --i;
                        }
                        else
                        {
                            assert(false);
                        }
                    }

                    //                --i;
                }
            }
        }

        foreach(ref meth; signatureList)
        {
            put("    ");
            if (meth.isFinal || (meth.hasCode && me.isInterface))
                put("final ");
            if (meth.isStatic)
                put("static ");
            if (meth.isOverride && !meth.isStatic)
                put("override ");

            put(meth.interpretJniSig1.dName(rootMap));
            put(' ');

            if (meth.hasCode && me.isInterface)
                put ("__jdefault_");
            put(meth.name.sanitizeName);

            put('(');
            put(meth.interpretJniSig2.enumerate.map!(a => a.value.dName(rootMap) ~ " _arg" ~ to!string(a.index)).join(", "));
            put(')');
            
            if (meth.isAbstract)
            {
                put(";");
            }
            else
            {
                // TODO
                put(";");
            }
            put('\n');

            if (!me.hasMethodInExtendedChain(meth, classesByName, false))
            {
            }

            // Whitespace
            put("\n");
        }

        // Add redirects for the default methods
        foreach (ref iface; me.classImplements)
        {
            assert(me.isClass);

            // Find default members
            auto ff = classesByName.get(iface.baseName.replace("$", ".").to!string, null);
            assert(ff !is null, "Could not find class " ~ iface.baseName.replace("$", "."));

            foreach(ref meth; ff.classMethods)
            {
                if (meth.hasCode)
                {
                    // This here is a default method

                    put(tabLevel);
                    
                    put("    ");
                    if (meth.isFinal)
                        put("final ");
                    if (meth.isStatic)
                        put("static ");

                    put("override ");

                    put(meth.interpretJniSig1.dName(rootMap));
                    put(' ');

                    put(meth.name.sanitizeName);
                    put('(');
                    put(meth.interpretJniSig2.enumerate.map!(a => a.value.dName(rootMap) ~ " _arg" ~ to!string(a.index)).join(", "));
                    put(')');

                    put('\n');
                    put(tabLevel);
                    put("    ");
                    put("{\n");

                    put(tabLevel);
                    put("    ");
                    put("    return ");
                    put(iface.baseName.dName(rootMap));
                    put(".__jdefault_");
                    put(meth.name.sanitizeName);
                    put('(');
                    put(meth.interpretJniSig2.enumerate.map!(a => "_arg" ~ to!string(a.index)).join(", "));
                    put(");\n");

                    put(tabLevel);
                    put("    ");
                    put("}\n");

                    // Whitespace
                    put("\n");

                }
            }
        }

        foreach(ref nest; me.nestedClasses)
        {
            auto gmt = getModuleTextInternal(nest, tabLevel ~ "    ", rootMap, classesByName, me.isInterface);
            put(gmt.core);
            imports ~= gmt.imports;
        }

        put(tabLevel);
        put("}\n");
    }

    import std.stdio;
    string mymod = rootMap.get(me.className.baseName.replace("$", ".").filter!(a => a != '[' && a != ']').to!string, null);
    auto reducedImports = imports.map!(a => rootMap.get(a.replace("$", ".").filter!(a => a != '[' && a != ']').to!string, null).to!string).array;
    return tuple!("core", "imports")(app.data, reducedImports);
}

unittest
{
    import std.file;
    import pegged.grammar;
    import jgrammar;
    mixin(grammar(javapGrammar));

    auto e1 = JClassInfo(J(readText("test_cases/java_util_Locale.javap")));
    auto e2 = JClassInfo(J(readText("test_cases/java_util_Locale_Category.javap")));

    string[string] rootMap;
    rootMap["java.util.Locale"] = "java.util.Locale";
    rootMap["java.util.Locale.Category"] = "java.util.Locale";
    rootMap["java.lang.Object"] = "java.lang.Object";
    rootMap["java.lang.Cloneable"] = "java.lang.Cloneable";
    rootMap["java.io.Serializable"] = "java.io.Serializable";
    rootMap["java.lang.String"] = "java.lang.String";
    rootMap["java.util.Set"] = "java.util.Set";
    rootMap["java.lang.Enum"] = "java.lang.Enum";
    rootMap["java.util.List"] = "java.util.List";
    rootMap["java.util.Collection"] = "java.util.Collection";
    rootMap["java.util.Locale.FilteringMode"] = "java.util.Locale.FilteringMode";

    JClassInfo*[string] classesByName;
    classesByName["java.lang.Cloneable"] = new JClassInfo;
    classesByName["java.io.Serializable"] = new JClassInfo;

    auto x = doNesting([e2, e1]);
    auto y = getModuleText(x, "java.util.Locale", rootMap, classesByName);

    // Can't really unittest this since it generates a big-ass string.
}

