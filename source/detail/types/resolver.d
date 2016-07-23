module detail.types.resolver;

import detail.types.base;
import detail.types.jmodule;

@trusted private auto doTree(in string genOut)
{
    import detail.jgrammar;
    return J(genOut);
}

@safe:

ISerializeToD attemptResolution(SymbolTable st, UnresolvedSymbol us, in string[] classPaths)
{
    log("Attempting Resolution of symbol '", us.name.extract, "'");
    assert(us.name in st.table);
    assert(cast(UnresolvedSymbol)st.table[us.name] is us);

    auto javapCmd = ["javap", "-public", "-s", "-c"];
    foreach (cp; classPaths)
    {
        javapCmd ~= "-classpath";
        javapCmd ~= cp;
    }

    import std.process;
    auto genOut = execute(javapCmd ~ us.name);

    if (genOut.status != 0)
    {
        import std.conv : to;
        throw new Exception("Non-zero return code from 'javap' on invocation: '" ~ to!string(javapCmd ~ us.name.extract) ~ "'; return code = " ~ to!string(genOut.status));
    }

    auto pTree = doTree(genOut.output);

    if (us.name.to!string.indexOf('$') >= 0)
    {
        // This was a nested class
        // Ensure that the base class is also there
        st.ensureSymbol(JName(us.name.to!string.split('$')[0]));
    }

    auto nguy = parseModule(st, pTree, us.name);
    assert(st.table[us.name] is nguy);
    return nguy;
}
