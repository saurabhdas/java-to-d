﻿module detail.ast_module;

import std.conv : to;

import pegged.peg;
import detail.ast_base;
import detail.ast_d_helpers;

@safe:

ISerializeToD parseModule(SymbolTable st, in ParseTree pTree, in JName expectedName)
{
    log("Creating Module '", expectedName.extract, "'");

    auto fromFileName = pTree.shallowFindOnlyOne("J.Body").shallowFindOnlyOne("J.Heading").shallowFindOnlyOne("J.Name").matches.join;
    enforce(fromFileName == expectedName.extract.split('$')[0].split('.')[$-1]);

    auto pDeclaration = pTree.shallowFindOnlyOne("J.Body").shallowFindOnlyOne("J.Declaration");
    auto pInner = pDeclaration.shallowFindOneOf(["J.InterfaceDeclaration", "J.ClassDeclaration"]);
    auto pDefinitions = pTree.shallowFindOnlyOne("J.Body").shallowFindMany("J.Definition");

    if (pInner.name == "J.InterfaceDeclaration")
    {
        return new JInterface(st, pInner, pDefinitions, expectedName);
    }
    else if (pInner.name == "J.ClassDeclaration")
    {
        return new JClass(st, pInner, pDefinitions, expectedName);
    }

    assert(false);
}

class JInterface : ISerializeToD
{
    JName name;
    JName[] extends;
    JName parent;

    ISerializeToD[] definitions;

    SymbolTable st;

    this(SymbolTable st_, in ParseTree pDeclaration, in ParseTree[] pDefinitions, in JName expectedName)
    {
        string eName = expectedName.extract;

        st = st_;
        log("Creating Interface '", eName, "'");
        st.table[expectedName] = this;

        if (eName.indexOf('$') >= 0)
        {
            // This is a nested interface, and has a parent
            parent = JName(eName[0 .. eName.replace("$", ".").lastIndexOf('.')]);
            st.ensureSymbol(parent);
        }

        foreach (mod; pDeclaration.shallowFindMany("J.Modifier"))
        {
            switch (mod.matches.join)
            {
                default:
                    throw new Exception("Unknown modifier in definition '" ~ mod.matches.join ~ "'");
                case "public":
                    break;
            }
        }

        name = parseJName(st, pDeclaration.shallowFindOnlyOne("J.ClassName"));
        enforce(name == expectedName);
        
        auto pExtends = pDeclaration.shallowFindMaxOne("J.Extends");
        if (pExtends != ParseTree.init)
        {
            extends = pExtends.shallowFindMany("J.ClassName")
                .map!(a => parseJName(st, a)).array;
        }

        definitions = parseDefinitions(st, pDefinitions, name);
    }

    JName[] allPrecursors() const
    {
        return sort(extends.dup ~ extends.map!(a => cast(const JInterface)st.table.get(a, null)).map!(a => a.allPrecursors).join).uniq.array;
    }

    DName serializeName() const
    {
        return convClassName(name);
    }

    DName importName() const
    {
        if (parent == JName.init)
            return convModuleName(name);
        else
            return st.table.get(parent, null).importName;
    }

    bool serializeFull(ref Appender!string app, ref Appender!(DName[]) imports, in uint tabDepth) const
    {
        app.put(tabs(tabDepth));
        if (parent != JName.init)
            app.put("static ");     // In java, all nested interfaces are static
        app.put("interface ");
        app.put(convClassName(name).extract.split('.')[$-1]);
        if (extends.length > 0)
        {
            app.put(" : ");
            app.put(extends.map!(a => convClassName(a).extract).join(", "));
            imports.put(extends.map!(a => st.table.get(a, null).importName));
        }
        app.put('\n');

        app.put(tabs(tabDepth));
        app.put("{\n");

        foreach(def; definitions)
            def.serializeFull(app, imports, tabDepth+1);

        foreach(nes; findNested(st, name))
            nes.serializeFull(app, imports, tabDepth+1);

        app.put(tabs(tabDepth));
        app.put("}\n");

        return (parent == JName.init);
    }
}

class JClass : ISerializeToD
{
    bool isFinal, isStatic, isAbstract, isSynchronized;

    JName name;
    JName extends;
    JName[] implements;
    JName parent;

    ISerializeToD[] definitions;

    SymbolTable st;

    this(SymbolTable st_, JName name_)
    {
        st = st_;
        name = name_;
        st.table[name] = this;
    }

    this(SymbolTable st_, in ParseTree pDeclaration, in ParseTree[] pDefinitions, in JName expectedName)
    {
        string eName = expectedName.extract;

        st = st_;
        log("Creating Class '", expectedName.extract, "'");
        st.table[expectedName] = this;

        if (eName.indexOf('$') >= 0)
        {
            // This is a nested class, and has a parent
            parent = JName(eName[0 .. eName.replace("$", ".").lastIndexOf('.')]);
            st.ensureSymbol(parent);
        }

        foreach (mod; pDeclaration.shallowFindMany("J.Modifier"))
        {
            switch (mod.matches.join)
            {
                default:
                    throw new Exception("Unknown modifier in definition '" ~ mod.matches.join ~ "'");
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
        }

        name = parseJName(st, pDeclaration.shallowFindOnlyOne("J.ClassName"));
        log("Testing ", name.extract, " == ", expectedName.extract);
        enforce(name == expectedName);

        auto pExtends = pDeclaration.shallowFindMaxOne("J.Extends");
        if (pExtends != ParseTree.init)
        {
            extends = parseJName(st, pExtends.shallowFindOnlyOne("J.ClassName"));
        }
        else
        {
            extends = (name == JName("java.lang.Object")) ? JName.init : JName("java.lang.Object");
        }
        
        auto pImplements = pDeclaration.shallowFindMaxOne("J.Implements");
        if (pImplements != ParseTree.init)
        {
            implements = pImplements.shallowFindMany("J.ClassName")
                .map!(a => parseJName(st, a)).array;
        }

        definitions = parseDefinitions(st, pDefinitions, name);
    }

    void fixInheritedImplements()
    {
        // There are cases where a subclass imlements the same interfaces as the parent class
        // This is not needed for us

        if (extends == JName.init)
            return;
        
        auto pprecs = (cast(const JClass)st.table.get(extends, null)).allPrecursors;
        implements = implements.filter!(a => !pprecs.canFind(a)).array;
    }

    JName[] allPrecursors() const
    {
        auto l1 = implements.dup ~ implements.map!(a => cast(const JInterface)st.table.get(a, null)).map!(a => a.allPrecursors).join;
        if (extends != JName.init)
            l1 ~= [JName(extends)] ~ (cast(const JClass)st.table.get(extends, null)).allPrecursors;
        return sort(l1).uniq.array;
    }

    DName serializeName() const
    {
        return convClassName(name);
    }

    DName importName() const
    {
        if (parent == JName.init)
            return convModuleName(name);
        else
            return st.table.get(parent, null).importName;
    }

    const(JMethod)[] defenderMethods() const
    {
        // Consider only this class' immediate interfaces. If there's a method in the interface
        // that has code and doesn't have a corresponding method in thie class, then that is a defender method
        // Handling: In the interface, leave it as an unimplemented class. Implement it here by returning it
        // from this method.

        const(JMethod)[] allInterfaceMethods =
            implements
                .map!(a => cast(const JInterface)st.table.get(a, null))
                .map!(a => a.definitions
                    .map!(a => cast(const JMethod)a)
                    .filter!(a => a !is null)
                    .filter!(a => !a.isStatic)
                    .array)
                .trustedJoin;

        const(JMethod)[] allMyMethods =
            definitions
                .map!(a => cast(const JMethod)a)
                .filter!(a => a !is null)
                .filter!(a => !a.isStatic)
                .trustedArray;

        return allInterfaceMethods
            .filter!(x => !allMyMethods.canFind!((a, b) => (a.name == b.name && a.args == b.args))(x)).trustedArray;
    }

    bool serializeFull(ref Appender!string app, ref Appender!(DName[]) imports, in uint tabDepth) const
    {
        app.put(tabs(tabDepth));
        if (isFinal)
            app.put("final ");
        if (isStatic || (parent != JName.init && cast(const JInterface)(st.table.get(parent, null)) !is null))
            app.put("static ");             // An inner class of an interface is always static
        if (isAbstract)
            app.put("abstract ");
        app.put("class ");
        app.put(convClassName(name).extract.split('.')[$-1]);

        auto exim = trustedChain([extends], implements).filter!(a => a != JName.init);
        if (!exim.empty)
        {
            app.put(" : ");
            app.put(exim.map!(a => convClassName(a).extract).join(", "));
            imports.put(exim.map!(a => st.table.get(a, null).importName));
        }
        app.put('\n');
        
        app.put(tabs(tabDepth));
        app.put("{\n");

        foreach(def; definitions)
            def.serializeFull(app, imports, tabDepth+1);

        foreach(nes; findNested(st, name))
            nes.serializeFull(app, imports, tabDepth+1);

        auto dm = defenderMethods();
        if (dm.length > 0)
        {
            log("Defender methods for ", name.extract, ": ", dm.length);
            log(dm.map!(a => a.name));
        }

        foreach(dfm; defenderMethods)
            dfm.serializeFull(app, imports, tabDepth+1);
        
        app.put(tabs(tabDepth));
        app.put("}\n");

        return (parent == JName.init);
    }
}

ISerializeToD[] parseDefinitions(SymbolTable st, in ParseTree[] pDefinitions, in JName parent)
{
    ISerializeToD[] ret;
    foreach(defn; pDefinitions)
    {
        auto jniSig = JniSig(defn.shallowFindOnlyOne("J.JniSignature").matches.join);
        auto hasCode = (defn.shallowFindMaxOne("J.Code") != typeof(defn).init);

        auto javaSig = defn.shallowFindOnlyOne("J.JavaSignature").shallowFindOneOf(["J.Constructor", "J.Method", "J.Member"]);
        if (javaSig.name == "J.Member")
            ret ~= new JMember(st, javaSig, parent, jniSig, hasCode);
        else if (javaSig.name == "J.Constructor")
            ret ~= new JConstructor(st, javaSig, parent, jniSig, hasCode);
        else if (javaSig.name == "J.Method")
            ret ~= new JMethod(st, javaSig, parent, jniSig, hasCode);
        else
            assert(false);
    }
    return ret;
}

class JMember : ISerializeToD
{
    bool isFinal, isStatic;
    JName name;
    JName type;
    JniSig jniSig;
    JName parent;

    SymbolTable st;

    this(SymbolTable st_, in ParseTree pMe, in JName parent_, in JniSig jniSig_, in bool hasCode_)
    {
        st = st_;
        parent = parent_;
        name = JName(pMe.shallowFindOnlyOne("J.Name").matches.join);
        log("Creating Member '", parent.extract, " > ", name.extract, "'");

        foreach (mod; pMe.shallowFindMany("J.Modifier"))
        {
            switch (mod.matches.join)
            {
                default:
                    throw new Exception("Unknown modifier in definition '" ~ mod.matches.join ~ "'");
                case "public":
                    break;
                case "final":
                    isFinal = true;
                    break;
                case "static":
                    isStatic = true;
                    break;
            }
        }

        jniSig = jniSig_;
        enforce(!hasCode_, "Member is not allowed to have code!");

        auto jrt = st.jniReturnType(jniSig);
        type = jrt.returnType;
        assert(jrt.arguments.length == 0);
    }

    DName serializeName() const
    {
        enforce(false, "Class Member '" ~ name.extract ~ "'");
        return DName.init;
    }

    DName importName() const
    {
        enforce(false, "Class Member '" ~ name.extract ~ "'");
        return DName.init;
    }

    bool serializeFull(ref Appender!string app, ref Appender!(DName[]) imports, in uint tabDepth) const
    {
        // Getter
        app.put(tabs(tabDepth));
        app.put("final ");              // Member getter and putter always have to be final - they cannot be overridden
        if (isStatic)
            app.put("static ");
        app.put(st.table.get(type, null).serializeName.extract);
        app.put(' ');
        app.put(convRegularName(name).extract);
        app.put("()");
        if (!isStatic)
            app.put(" const");

        // TODO
        app.put(";");

        app.put("\n");

        // Putter
        if (!isFinal)
        {
            app.put(tabs(tabDepth));
            app.put("final ");              // Member getter and putter always have to be final - they cannot be overridden
            if (isStatic)
                app.put("static ");
            app.put("void");
            app.put(' ');
            app.put(convRegularName(name).extract);
            app.put("(");
            app.put(st.table.get(type, null).serializeName.extract);
            app.put("_arg0) const");
            
            // TODO
            app.put(";");
            
            app.put("\n");
        }

        // Imports
        auto sym1 = st.table.get(type, null);
        if (cast(const JInterface)sym1 !is null || cast(const JClass)sym1 !is null)
            imports.put(st.table.get(type, null).importName);

        return false;
    }
}

class JConstructor : ISerializeToD
{
    JName name;
    JName[] args;
    JniSig jniSig;
    bool hasCode;
    JName parent;

    SymbolTable st;

    this(SymbolTable st_, in ParseTree pMe, in JName parent_, in JniSig jniSig_, in bool hasCode_)
    {
        parent = parent_;
        st = st_;
        name = JName(pMe.shallowFindOnlyOne("J.ClassName").matches.join);
        log("Creating Constructor '", parent.extract, " > ", name.extract, "'");

        enforce(name == parent);
        enforce(name in st.table);

        foreach (mod; pMe.shallowFindMany("J.Modifier"))
        {
            switch (mod.matches.join)
            {
                default:
                    throw new Exception("Unknown modifier in definition '" ~ mod.matches.join ~ "'");
                case "public":
                    break;
            }
        }

        jniSig = jniSig_;
        hasCode = hasCode_;

        auto jrt = st.jniReturnType(jniSig);
        assert(jrt.returnType == JName("void"));
        args = jrt.arguments;
    }

    DName serializeName() const
    {
        enforce(false, "Class Constructor '" ~ name.extract ~ "'");
        return DName.init;
    }

    DName importName() const
    {
        enforce(false, "Class Constructor '" ~ name.extract ~ "'");
        return DName.init;
    }

    bool serializeFull(ref Appender!string app, ref Appender!(DName[]) imports, in uint tabDepth) const
    {
        app.put(tabs(tabDepth));
        app.put("this(");
        app.put(args.enumerate.map!(a => st.table.get(a.value, null).serializeName ~ " _arg" ~ a.index.to!string).join(", "));
        app.put(")\n");

        app.put(tabs(tabDepth));
        app.put("{\n");

        app.put(tabs(tabDepth+1));
        app.put("// TODO");
        app.put("\n");

        app.put(tabs(tabDepth));
        app.put("}\n");

        app.put("\n");

        // Imports
        imports.put(args.map!(a => st.table.get(a, null).importName));

        return false;
    }
}

class JMethod : ISerializeToD
{
    bool isFinal, isStatic, isAbstract, isNative, isSynchronized;
    JName name;
    JName returnType;
    JName[] args;
    JniSig jniSig;
    bool hasCode;
    JName parent;

    SymbolTable st;

    this(SymbolTable st_, in ParseTree pMe, in JName parent_, in JniSig jniSig_, in bool hasCode_)
    {
        parent = parent_;
        st = st_;
        name = JName(pMe.shallowFindOnlyOne("J.Name").matches.join);
        log("Creating Method '", parent.extract, " > ", name.extract, "'");
        
        foreach (mod; pMe.shallowFindMany("J.Modifier"))
        {
            switch (mod.matches.join)
            {
                default:
                    throw new Exception("Unknown modifier in definition '" ~ mod.matches.join ~ "'");
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
        }

        jniSig = jniSig_;
        hasCode = hasCode_;

        auto jrt = st.jniReturnType(jniSig);
        returnType = jrt.returnType;
        args = jrt.arguments;
    }

    bool isOverride() const
    body
    {
        if (isStatic)
            return false;

        auto p1 = st.table.get(parent, null);
        JName[] p2;
        if (cast(const JInterface)p1 !is null)
            p2 = (cast(const JInterface)p1).allPrecursors();
        else if (cast(const JClass)p1 !is null)
            p2 = (cast(const JClass)p1).allPrecursors();
        else
            assert(false);
        foreach(parentName; p2)
        {
            auto p3 = cast(const JClass)(st.table.get(parentName, null));

            if (p3 is null)
                continue;                           // Override methods don't apply if the parent is an Interface
                
            auto wl =
                trustedChain(p3.definitions, p3.defenderMethods)
                    .map!(a => cast(const JMethod)a)
                    .filter!(a => a !is null)
                    .filter!(a => a.name == name)
                    .filter!(a => a.args == args)
                    .filter!(a => a.isStatic == isStatic)
                    .walkLength;

            if (wl > 0)
                return true;
        }

        return false;
    }

    @trusted Tuple!(bool, "isBridgeMethod", bool, "isMoreDerived") isBridgeMethod() const
    {
        auto p1 = st.table.get(parent, null);
        const(JMethod)[] meths;
        if (cast(const JInterface)p1 !is null)
            meths = (cast(const JInterface)p1).definitions.map!(a => cast(const JMethod)a).filter!(a => a !is null).array;
        else if (cast(const JClass)p1 !is null)
            meths = (cast(const JClass)p1).definitions.map!(a => cast(const JMethod)a).filter!(a => a !is null).array;
        else
            assert(false);

        foreach(meth; meths)
        {
            if (meth is this)
                continue;

            if (meth.name != name || meth.args != args)
                continue;

            auto ret1 = st.table.get(returnType, null);
            auto ret2 = st.table.get(meth.returnType, null);

            JName[] prec1, prec2;

            if (cast(const JInterface)ret1 !is null)    prec1 = (cast(const JInterface)ret1).allPrecursors;
            else if (cast(const JClass)ret1 !is null)   prec1 = (cast(const JClass)ret1).allPrecursors;
            else                                        assert(false);

            if (cast(const JInterface)ret2 !is null)    prec2 = (cast(const JInterface)ret2).allPrecursors;
            else if (cast(const JClass)ret2 !is null)   prec2 = (cast(const JClass)ret2).allPrecursors;
            else                                        assert(false);

            if (prec2.canFind(returnType))
            {
                assert(!prec1.canFind(meth.returnType));
                return tuple!("isBridgeMethod", "isMoreDerived")(true, false);
            }
            else if (prec1.canFind(meth.returnType))
            {
                assert(!prec2.canFind(returnType));
                return tuple!("isBridgeMethod", "isMoreDerived")(true, true);
            }
            else
                assert(false);
        }

        return tuple!("isBridgeMethod", "isMoreDerived")(false, false);
    }

    DName serializeName() const
    {
        enforce(false, "Class/Interface Method '" ~ name.extract ~ "'");
        return DName.init;
    }
    
    DName importName() const
    {
        enforce(false, "Class/Interface Method '" ~ name.extract ~ "'");
        return DName.init;
    }

    bool serializeFull(ref Appender!string app, ref Appender!(DName[]) imports, in uint tabDepth) const
    {
        if (isAbstract)
            enforce(!hasCode);

        auto bm = isBridgeMethod;
        if (bm.isBridgeMethod && !bm.isMoreDerived)
            return false;
            
        app.put(tabs(tabDepth));

        if (isFinal)
            app.put("final ");
        if (isStatic)
            app.put("static ");
        if (isAbstract && (cast(const JInterface)st.table.get(parent, null)) is null)
            app.put("abstract ");       // Don't put abstract if parent is an interface
        if (isOverride)
            app.put("override ");

        app.put(st.table.get(returnType, null).serializeName.extract);
        app.put(' ');
        app.put(convRegularName(name).extract);
        app.put("(");
        app.put(args.enumerate.map!(a => st.table.get(a.value, null).serializeName ~ " _arg" ~ a.index.to!string).join(", "));
        app.put(")");
        
        // TODO
        app.put(";");
        
        app.put("\n");

        // Imports
        imports.put(trustedChain(args, [returnType]).map!(a => st.table.get(a, null).importName));

        return false;
    }
}

class JArray : JClass
{
    JName innerType;
    
    // Only ensureType can create this
    this(SymbolTable st_, in JName arrayType)
    {
        super(st_, arrayType);

        enforce(name.extract[$-2 .. $] == "[]");
        innerType = JName(name.extract[0 .. $-2]);
        st.ensureSymbol(innerType);

        extends = JName("java.lang.Object");
        st.ensureSymbol(extends);
    }
    
    override DName serializeName() const
    {
        auto tt = st.table.get(innerType, null);
        assert(tt !is null);
        return DName("jni_d.JavaArray!(" ~ tt.serializeName.extract ~ ")");
    }

    override DName importName() const
    {
        return st.table.get(innerType, null).importName;
    }
    
    override bool serializeFull(ref Appender!string app, ref Appender!(DName[]) imports, in uint tabDepth) const
    {
        return false;
    }
}

@trusted:

const(ISerializeToD)[] findNested(in SymbolTable st, in JName ofWhich)
{
    auto l1 = st.table
        .byValue
            .map!(a => cast(const JInterface)a)
            .filter!(a => a !is null)
            .filter!(a => a.parent == ofWhich)
            .map!(a => cast(const ISerializeToD)a);
    
    auto l2 = st.table
        .byValue
            .map!(a => cast(const JClass)a)
            .filter!(a => a !is null)
            .filter!(a => a.parent == ofWhich)
            .map!(a => cast(const ISerializeToD)a);

    return trustedChain(l1, l2);
}

@system:

unittest
{
    log("Running unittest 'ast_module'");

    SymbolTable st = new SymbolTable;
    auto s1 = new JArray(st, JName("java.lang.Whatever[][][]"));
    assert(s1.innerType == JName("java.lang.Whatever[][]"));
}
