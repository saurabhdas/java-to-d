module detail.ast_base;

public import std.string, std.algorithm, std.array, std.typecons, std.range;
public import std.exception;
public import std.regex;
public import std.conv : to;
public import detail.util;
import pegged.peg;
import std.typecons;

@safe:

alias JName = Typedef!(string, null, "JName");
alias DName = Typedef!(string, null, "DName");
alias JniSig = Typedef!(string, null, "JniSig");

interface ISerializeToD
{
    DName serializeName() const;
    DName importName() const;

    // serializeFull returns TRUE if a file should be written for this object
    bool serializeFull(ref Appender!string app, ref Appender!(DName[]) imports, in uint tabDepth) const;
}

class SymbolTable
{
    ISerializeToD[JName] table;
    
    this()
    {
        log("Creating SymbolTable");

        new JIntrinsic(this, JName("boolean"), JniSig("jboolean"), DName("bool"));
        new JIntrinsic(this, JName("byte"), JniSig("jbyte"), DName("byte"));
        new JIntrinsic(this, JName("char"), JniSig("jchar"), DName("char"));
        new JIntrinsic(this, JName("short"), JniSig("jshort"), DName("short"));
        new JIntrinsic(this, JName("int"), JniSig("jint"), DName("int"));
        new JIntrinsic(this, JName("long"), JniSig("jlong"), DName("long"));
        new JIntrinsic(this, JName("float"), JniSig("jfloat"), DName("float"));
        new JIntrinsic(this, JName("double"), JniSig("jdouble"), DName("double"));
        new JIntrinsic(this, JName("void"), JniSig("jboolean"), DName("void"));
    }

    void ensureSymbol(in JName name)
    {
        if (name in table)
            return;

        new UnresolvedSymbol(this, name);
        assert(name in table);
    }
}

class UnresolvedSymbol : ISerializeToD
{
    JName name;

    SymbolTable st;

    this(SymbolTable st_, in JName name_)
    {
        st = st_;
        log("Creating UnresolvedSymbol '", name_.extract, "'");

        name = name_;
        enforce(name_ !in st.table);
        st.table[name] = this;
    }

    DName serializeName() const
    {
        import detail.ast_d_helpers;
        return DName("/+ UnresolvedSymbol +/" ~ convClassName(name).extract);
    }

    DName importName() const
    {
        import detail.ast_d_helpers;
        return DName.init;
    }

    bool serializeFull(ref Appender!string app, ref Appender!(DName[]) imports, in uint tabDepth) const
    {
        enforce(false, "Unresolved Symbol '" ~ name.extract ~ "'");
        return false;
    }
}

class JIntrinsic : ISerializeToD
{
    JName javaName;
    JniSig jniName;
    DName dName;

    SymbolTable st;
    
    this(SymbolTable st_, in JName javaName_, in JniSig jniName_, in DName dName_)
    {
        st = st_;
        javaName = javaName_;
        jniName = jniName_;
        dName = dName_;
        
        st.table[javaName] = this;
    }

    DName serializeName() const
    {
        return dName;
    }

    DName importName() const
    {
        return DName.init;
    }

    bool serializeFull(ref Appender!string app, ref Appender!(DName[]) imports, in uint tabDepth) const
    {
        return false;
    }
}

auto extract(T)(T t)
{
    return cast(TypedefType!T)(t);
}

Tuple!(JName, "returnType", JName[], "arguments") jniReturnType(SymbolTable st, in JniSig jni)
{
    JName ret1;
    JName[] ret2;
    auto inner = jni.extract;
    bool isArg = false;
    string currentItem;
    for (long i=0; i<inner.length; ++i)
    {
        switch(inner[i])
        {
            case '(':
                enforce(!isArg, "Could not process JNI Signature '" ~ inner ~ "'");
                isArg = true;
                continue;
            case ')':
                enforce(isArg, "Could not process JNI Signature '" ~ inner ~ "'");
                isArg = false;
                continue;
            case '[':
                currentItem ~= "[]";
                continue;
            case 'Z':
                currentItem = "boolean" ~ currentItem;
                break;
            case 'B':
                currentItem = "byte" ~ currentItem;
                break;
            case 'C':
                currentItem = "char" ~ currentItem;
                break;
            case 'S':
                currentItem = "short" ~ currentItem;
                break;
            case 'I':
                currentItem = "int" ~ currentItem;
                break;
            case 'J':
                currentItem = "long" ~ currentItem;
                break;
            case 'F':
                currentItem = "float" ~ currentItem;
                break;
            case 'D':
                currentItem = "double" ~ currentItem;
                break;
            case 'V':
                currentItem = "void" ~ currentItem;
                break;
            case 'L':
                auto j = indexOf(inner, ';', i);
                assert(j > i);
                currentItem = inner[i+1 .. j].replace("/", ".") ~ currentItem;
                i = j;  // +1 will be added in the loop
                break;
            default:
                throw new Exception("Could not process JNI Signature '" ~ inner ~ "'");
        }
        auto jn = JName(currentItem);
        currentItem = "";
        st.ensureSymbol(jn);
        if (!isArg)
        {
            assert(ret1 == JName.init);
            ret1 = jn;
        }
        else
            ret2 ~= jn;
    }

    return Tuple!(JName, "returnType", JName[], "arguments")(ret1, ret2);
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
    
    auto jn = JName(n1);
    st.ensureSymbol(jn);
    return jn;
}

@system:
unittest
{
    log("Running unittest 'ast_base'");

    assert(JName("java.lang.Something").extract == "java.lang.Something");

    auto st = new SymbolTable;

    alias TOR = Tuple!(JName, "returnType", JName[], "arguments");
    assert(st.jniReturnType(JniSig("S")) == TOR(JName("short"), null));
    assert(st.jniReturnType(JniSig("[S")) == TOR(JName("short[]"), null));
    assert(st.jniReturnType(JniSig("[[S")) == TOR(JName("short[][]"), null));
    assert(st.jniReturnType(JniSig("(SLjava.lang.Whatever;[Ljava.lang.Yahoo;Z)[[[Ljava.major.Argh;")) ==
        TOR(JName("java.major.Argh[][][]"), [JName("short"), JName("java.lang.Whatever"), JName("java.lang.Yahoo[]"), JName("boolean")]));
}
