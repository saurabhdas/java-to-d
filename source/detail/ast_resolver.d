module detail.ast_resolver;

public import std.string, std.algorithm, std.array, std.typecons, std.range;

public import detail.ast_base;
public import detail.ast_module;
public import detail.ast_d_helpers;

@trusted private auto doTree(in string genOut)
{
    import detail.java_grammar_parser;
    return J(genOut);
}

@safe:

ISerializeToD attemptResolution(SymbolTable st, UnresolvedSymbol us, in string[] classPaths)
{
    logInfo("Resolving symbol '", us.name.extract, "'");

    assert(us.name in st.table);
    assert(cast(UnresolvedSymbol)st.table[us.name] is us);

    auto nn = us.name.extract;
    if (nn.length > 2 && nn[$-2 .. $] == "[]")
    {
        return new JArray(st, us.name);
    }

    auto javapCmd = ["javap", "-public", "-s", "-c"];
    foreach (cp; classPaths)
    {
        javapCmd ~= "-classpath";
        javapCmd ~= cp;
    }

    import std.process;
    auto genOut = execute(javapCmd ~ us.name.extract);

    if (genOut.status != 0)
    {
        import std.conv : to;
        log(genOut.output);
        throw new Exception("Non-zero return code from 'javap' on invocation: '" ~ to!string(javapCmd ~ us.name.extract) ~ "'; return code = " ~ to!string(genOut.status));
    }

    auto pTree = doTree(genOut.output);

    if (us.name.to!string.indexOf('$') >= 0)
    {
        // This was a nested class
        // Ensure that the base class is also there
        st.ensureSymbol(JName(us.name.extract.split('$')[0]));
    }

    auto nguy = parseModule(st, pTree, us.name);
    assert(st.table[us.name] is nguy);
    return nguy;
}

@trusted:
void resolveAll(SymbolTable st, in string[] classPaths)
{
    auto xr = st.table
        .byValue
            .map!(a => cast(UnresolvedSymbol)a)
            .filter!(a => a !is null)
            .array;                // Freeze the elements - iterators are invalidated when elements are added (?)

    if (xr.length > 0)
    {
        log("Resolving ", xr.length, " items");
        xr.map!(a => attemptResolution(st, a, classPaths)).each;
        resolveAll(st, classPaths);
    }
}

void fixAllInheritedImplements(SymbolTable st)
{
    st.table.byValue.map!(a => cast(JClass)a).filter!(a => a !is null).each!(a => a.fixInheritedImplements());
}

@system:

unittest
{
    log("Running unittest 'ast_resolver'");
    
    SymbolTable st = new SymbolTable;
    
    auto doJn(in JName jn)
    {
        st.ensureSymbol(jn);
        auto us = cast(UnresolvedSymbol)st.table.get(jn, null);
        assert(us !is null);
        auto rs = attemptResolution(st, us, null);
        return rs;
    }
    
    auto rs1 = doJn(JName("java.io.Serializable"));
    auto rs2 = doJn(JName("java.lang.Comparable"));
    auto rs3 = doJn(JName("java.lang.Object"));
    auto rs4 = doJn(JName("java.lang.Thread"));
    auto rs5 = doJn(JName("java.lang.Thread$State"));
}
