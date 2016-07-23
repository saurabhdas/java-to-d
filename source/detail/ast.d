module detail.ast;

import detail.types.base;
import detail.types.resolver;

@safe:

unittest
{
    log("Running unittest 'ast'");

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
}
