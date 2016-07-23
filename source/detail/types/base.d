module detail.types.base;

public import std.string, std.algorithm, std.array, std.typecons;
public import std.exception;
public import std.regex;
public import std.conv : to;
public import detail.jgrammar;
public import detail.util;
import std.typecons;

@safe:

alias JName = Typedef!(string, null, "JName");
alias DName = Typedef!(string, null, "DName");
alias JniSig = Typedef!(string, null, "JniSig");

interface ISerializeToD
{
    void serializeToD(ref Appender!string app) const;
}

class SymbolTable
{
    ISerializeToD[JName] table;
    
    this()
    {
        log("Creating SymbolTable");

        new JIntrinsic(this, JName("boolean"), "jboolean", DName("bool"));
        new JIntrinsic(this, JName("byte"), "jbyte", DName("byte"));
        new JIntrinsic(this, JName("char"), "jchar", DName("char"));
        new JIntrinsic(this, JName("short"), "jshort", DName("short"));
        new JIntrinsic(this, JName("int"), "jint", DName("int"));
        new JIntrinsic(this, JName("long"), "jlong", DName("long"));
        new JIntrinsic(this, JName("float"), "jfloat", DName("float"));
        new JIntrinsic(this, JName("double"), "jdouble", DName("double"));
        new JIntrinsic(this, JName("void"), "jboolean", DName("void"));
    }

    void ensureSymbol(in JName name)
    {
        if (name in table)
            return;

        auto nn = name.extract;
        if (nn.length > 2 && nn[$-2 .. $] == "[]")
        {
            new JArray(this, JName(nn[0 .. $-2]));
        }
        else
        {
            new UnresolvedSymbol(this, name);
            assert(name in table);
        }
    }
}

class UnresolvedSymbol : ISerializeToD
{
    JName name;
    
    this(SymbolTable st, in JName name_)
    {
        log("Creating UnresolvedSymbol '", name_.extract, "'");

        name = name_;
        enforce(name_ !in st.table);
        st.table[name] = this;
    }
    
    void serializeToD(ref Appender!string app) const
    {
        enforce(false, "Unresolved Symbol '" ~ name.extract ~ "'");
    }
}

class JIntrinsic : ISerializeToD
{
    JName javaName;
    string jniName;
    DName dName;
    
    this(SymbolTable st, in JName javaName_, in string jniName_, in DName dName_)
    {
        javaName = javaName_;
        jniName = jniName_;
        dName = dName_;
        
        st.table[javaName] = this;
    }
    
    void serializeToD(ref Appender!string app) const
    {
        app.put(dName.to!string);
    }
}

class JArray : ISerializeToD
{
    JName type;

    // Only ensureType can create this
    private this(SymbolTable st, in JName type_)
    {
        type = type_;
        st.table[JName(type_.extract ~ "[]")] = this;
        st.ensureSymbol(type);
    }

    void serializeToD(ref Appender!string app) const
    {
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

@system:
unittest
{
    log("Running unittest 'base'");

    SymbolTable st = new SymbolTable;
    st.ensureSymbol(JName("java.lang.Whatever[][][]"));
    auto b1 = st.table.get(JName("java.lang.Whatever[][][]"), null);
    assert(b1 !is null);
    auto a1 = cast(JArray)b1;
    assert(a1 !is null);
    assert(a1.type == JName("java.lang.Whatever[][]"));

    auto b2 = st.table.get(a1.type, null);
    assert(b2 !is null);
    auto a2 = cast(JArray)b2;
    assert(a2 !is null);
    assert(a2.type == JName("java.lang.Whatever[]"));

    auto b3 = st.table.get(a2.type, null);
    assert(b3 !is null);
    auto a3 = cast(JArray)b3;
    assert(a3 !is null);
    assert(a3.type == JName("java.lang.Whatever"));

    auto b4 = st.table.get(a3.type, null);
    assert(b4 !is null);
    auto a4 = cast(UnresolvedSymbol)b4;
    assert(a4 !is null);

    assert(JName("java.lang.Something").extract == "java.lang.Something");

    alias TOR = Tuple!(JName, "returnType", JName[], "arguments");
    assert(st.jniReturnType(JniSig("S")) == TOR(JName("short"), null));
    assert(st.jniReturnType(JniSig("[S")) == TOR(JName("short[]"), null));
    assert(st.jniReturnType(JniSig("[[S")) == TOR(JName("short[][]"), null));
    assert(st.jniReturnType(JniSig("(SLjava.lang.Whatever;[Ljava.lang.Yahoo;Z)[[[Ljava.major.Argh;")) ==
        TOR(JName("java.major.Argh[][][]"), [JName("short"), JName("java.lang.Whatever"), JName("java.lang.Yahoo[]"), JName("boolean")]));
}
