module detail.ast_d_helpers;

public import detail.util;
import detail.ast_base;

@safe:

string[] tabooWords()
{
    return ["cast", "function", "with", "delete", "toString", "version", "in", "out", "body", "is"];
}

private auto convRegularName(in string n)
{
    enforce(n.indexOf('.') == -1);
    enforce(n.indexOf('/') == -1);
    enforce(n.indexOf('$') == -1);

    if (tabooWords.canFind(n))
        return 'j' ~ n;
    else
        return n;
}

DName convRegularName(in JName jn)
{
    return DName(convRegularName(jn.extract));
}

DName convModuleName(in JName jn)
{
    auto n = jn.extract;

    auto part1 = n.split('$')[0].split('.')[0 .. $-1].map!(a => a.convRegularName).join('.');
    auto part2 = 'J' ~ n.split('$')[0].split('.')[$-1];
    
    return DName(part1 ~ '.' ~ part2);
}

DName convClassName(in JName jn)
{
    auto n = jn.extract;

//    // Yet another hack. Gah. So UGLY.
//    auto indexOfBracked = n.indexOf('[');
//    auto arrayBit = (indexOfBracked == -1) ? "" : n[indexOfBracked .. $];
//    auto nameBit = n[0 .. $-arrayBit.length];
//    if (okList.canFind(nameBit))
//    {
//        if (nameBit == "boolean")       return DName("bool" ~ arrayBit);
//        else if (nameBit == "char")     return DName("wchar" ~ arrayBit);
//        else                            return DName(n);
//    }
    
    auto part1 = n.split('$')[0].split('.')[0 .. $-1].map!(a => a.convRegularName).join('.');
    auto part2 = 'J' ~ n.split('$')[0].split('.')[$-1];
    auto part3 = n.split('$')[1 .. $].map!(a => 'J' ~ a).join('.');
    
    enforce(part3.indexOf('$') == -1);
    
    auto res = part1 ~ '.' ~ part2 ~ '.' ~ part2;
    if (part3.length > 0)
        res ~= '.' ~ part3;
    
    return DName(res);
}

DName mangleName(in DName functionName, in JniSig jniSig)
{
    return DName(functionName.extract ~ "_" ~ jniSig.extract.replace(".", "_1").replace("/", "_2").replace("(", "_3").replace(")", "_4").replace(";", "_5").replace("$", "_6").replace("[", "_7"));
}

private string[] okList = ["boolean", "byte", "char", "short", "int", "long", "float", "double"];

auto mapHelper(A)(in SymbolTable st, A a)
{
    auto jj = a[3].map!(b => st.table.get(b, null).serializeName.extract).join(", ");
    if (jj.length > 0)
        return "jni_d.java_root.CheckCall!(" ~ join(["T" ~ a[0].to!string, a[2].extract, jj], ", ") ~ ")";
    else
        return "jni_d.java_root.CheckCall!(" ~ join(["T" ~ a[0].to!string, a[2].extract], ", ") ~ ")";
}

string makeArgs(in SymbolTable st, in JName[] args)
{
    import std.range;
    import std.stdio;

    cheatingParameters.each!(a => assert(a.length == args.length));
    auto cheatingParametersDup = cheatingParameters.dup.filter!(a => a != args).map!(a => a.dup).array;
    JName[][] cheatingCrossed = cheatingParametersDup.transposed.map!(a => a.array).array;
    assert(cheatingCrossed.length == args.length || cheatingCrossed.length == 0);
    if (cheatingCrossed.length == 0)
        cheatingCrossed.length = args.length;
    cheatingCrossed.each!(a => assert(a.length == cheatingParametersDup.length || a.length == 0));

    string[] dArgs = args.map!(a => st.table.get(a, null).serializeName.extract).array;

    string templateBit, argsBit, conditionBit;

    bool[] isArgObject = args.map!(a => !okList.canFind(a.extract)).array;
    templateBit = isArgObject.enumerate.map!(a => (a.value) ? "T" ~ a.index.to!string : "").filter!(a => a != "").join(", ");
    argsBit = zip(iota(0, args.length), isArgObject, dArgs).map!(a => (a[1] ? "T" ~ a[0].to!string : a[2].extract) ~ " _arg" ~ a[0].to!string).join(", ");

    conditionBit =
        zip(iota(0, args.length), isArgObject, dArgs, cheatingCrossed)
            .filter!(a => a[1])
            .map!(a => mapHelper(st, a))
            .join(" && ");

    if (conditionBit.length == 0)
        return format("(%s)", argsBit);
    else
        return format("(%s)(%s) if (%s)", templateBit, argsBit, conditionBit);
}

const(JName)[][] cheatingParameters;

string insertObjectPtr(in JName arg)
{
    if (okList.canFind(arg.extract))
        return "";
    else
        return "._jniObjectPtr";
}

@system:

unittest
{
    log("Running unittest 'ast_d_helpers'");

    assert(convRegularName("function") == "jfunction");
    assert(convRegularName("version") == "jversion");
    assert(convRegularName("apple") == "apple");

    assertThrown(convRegularName("java.lang.Object"));
    assertThrown(convRegularName("Thread$State"));

    assert(convModuleName(JName("java.lang.Object")) == DName("java.lang.JObject"));
    assert(convModuleName(JName("java.lang.Thread$State")) == DName("java.lang.JThread"));
    assert(convModuleName(JName("java.lang.Thread$State$Cap")) == DName("java.lang.JThread"));

    assert(convClassName(JName("java.lang.Object")) == DName("java.lang.JObject.JObject"));
    assert(convClassName(JName("java.lang.Thread$State")) == DName("java.lang.JThread.JThread.JState"));
    assert(convClassName(JName("java.lang.Thread$State$Cap")) == DName("java.lang.JThread.JThread.JState.JCap"));

    assert(mangleName(DName("func"), JniSig("(II)V")) == "func__II_V");
    assert(mangleName(DName("func"), JniSig("(Ljava.lang.Thread$State$Cap;)V")) == "func__Ljava_lang_Thread_State_Cap__V");
}
