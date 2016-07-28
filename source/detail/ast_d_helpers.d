module detail.ast_d_helpers;

public import detail.util;
import detail.ast_base;

@safe:

string[] tabooWords()
{
    return ["cast", "function", "with", "delete", "toString", "version"];
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
    
    auto part1 = n.split('$')[0].split('.')[0 .. $-1].map!(a => a.convRegularName).join('.');
    auto part2 = 'J' ~ n.split('$')[0].split('.')[$-1];
    auto part3 = n.split('$')[1 .. $].map!(a => 'J' ~ a).join('.');
    
    enforce(part3.indexOf('$') == -1);
    
    auto res = part1 ~ '.' ~ part2 ~ '.' ~ part2;
    if (part3.length > 0)
        res ~= '.' ~ part3;
    
    return DName(res);
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
}
