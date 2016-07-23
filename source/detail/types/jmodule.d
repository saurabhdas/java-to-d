module detail.types.jmodule;

import std.conv : to;

import pegged.peg;
import detail.types.base;

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

    ISerializeToD[] definitions;

    this(SymbolTable st, in ParseTree pDeclaration, in ParseTree[] pDefinitions, in JName expectedName)
    {
        log("Creating Interface '", expectedName.extract, "'");
        st.table[expectedName] = this;

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

    void serializeToD(ref Appender!string app) const
    {
    }
}

class JClass : ISerializeToD
{
    bool isFinal, isStatic, isAbstract, isSynchronized;

    JName name;
    JName extends;
    JName[] implements;

    ISerializeToD[] definitions;

    this(SymbolTable st, in ParseTree pDeclaration, in ParseTree[] pDefinitions, in JName expectedName)
    {
        log("Creating Class '", expectedName.extract, "'");
        st.table[expectedName] = this;

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
    
    void serializeToD(ref Appender!string app) const
    {
    }
}

JName parseJName(SymbolTable st, in ParseTree pTree)
{
    // Currently we discard the generic args portion
    auto n1 = pTree.shallowFindOnlyOne("J.OnlyClassName").matches.join;
    auto pArray = pTree.shallowFindMaxOne("J.Array");
    if (pArray != ParseTree.init)
    {
        auto arrayDepth = pArray.matches.length;
        import std.range;
        n1 ~= "[]".repeat.take(arrayDepth).array.join;
    }

    log("Parsed JName '", n1, "'");

    auto jn = JName(n1);
    st.ensureSymbol(jn);
    return jn;
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
    return null;
}

class JMember : ISerializeToD
{
    bool isFinal, isStatic;
    JName name;
    JName type;
    JniSig jniSig;

    this(SymbolTable st, in ParseTree pMe, in JName parent, in JniSig jniSig_, in bool hasCode_)
    {
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

    void serializeToD(ref Appender!string app) const
    {
    }
}

class JConstructor : ISerializeToD
{
    JName name;
    JName[] args;
    JniSig jniSig;
    bool hasCode;

    this(SymbolTable st, in ParseTree pMe, in JName parent, in JniSig jniSig_, in bool hasCode_)
    {
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
    
    void serializeToD(ref Appender!string app) const
    {
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

    this(SymbolTable st, in ParseTree pMe, in JName parent, in JniSig jniSig_, in bool hasCode_)
    {
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
    
    void serializeToD(ref Appender!string app) const
    {
    }

    bool isOverride() const
    {
        // TODO
        return false;
    }
}
