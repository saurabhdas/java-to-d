module detail.util;

import std.string, std.algorithm, std.array, std.typecons;
import std.exception;;

@trusted:

void log(Args...)(auto ref Args args)
{
    import std.stdio;
    version(unittest) writeln(args);
}

void logInfo(Args...)(auto ref Args args)
{
    import std.stdio;
    writeln(args);
}

auto deepFindAllFirst(PT)(auto ref PT haystack, in string needle)
{
    if (haystack.name == needle)
        return [haystack];
    else
        return haystack.children.map!(a => deepFindAllFirst(a, needle)).join.array;
}

auto shallowFindOnlyOne(PT)(auto ref PT haystack, in string needle) @trusted
{
    auto f = haystack.children.filter!(a => a.name == needle).array;
    import std.conv;
    enforce(f.length == 1, "Found " ~ to!string(f.length) ~ " elements, expected exactly 1 of '" ~ needle ~ "'");
    return f[0];
}

auto shallowFindMaxOne(PT)(auto ref PT haystack, in string needle)
{
    auto f = haystack.children.filter!(a => a.name == needle).array;
    enforce(f.length == 0 || f.length == 1);
    return (f.length == 0) ? PT.init : f[0];
}

auto shallowFindOneOf(PT)(auto ref PT haystack, in string[] needles)
{
    auto rxs1 = needles.map!(a => haystack.shallowFindMaxOne(a));
    static if (is(PT == class))
        auto rxs2 = rxs1.filter!(a => a !is PT.init).array;
    else
        auto rxs2 = rxs1.filter!(a => a != PT.init).array;
    enforce(rxs2.length == 1);
    return rxs2[0];
}

auto shallowFindMany(PT)(auto ref PT haystack, in string needle)
{
    return haystack.children.filter!(a => a.name == needle).array;
}

auto shallowFindManyOf(PT)(auto ref PT haystack, in string[] needles)
{
    auto rxs1 = needles.map!(a => haystack.shallowFindMany(a)).join;
    static if (is(PT == class))
        auto rxs2 = rxs1.filter!(a => a !is PT.init).array;
    else
        auto rxs2 = rxs1.filter!(a => a != PT.init).array;

    return rxs2;
}

string tabs(in int tabDepth)
{
    import std.range, std.conv;
    return "    ".repeat.take(tabDepth).join.to!string;
}

@trusted:

// Chain is a system function. We blindly trust it here
auto trustedChain(Ranges...)(Ranges rs)
{
    import std.range;
    return chain(rs).array;
}

// Array is a system function. We blindly trust it here
auto trustedArray(Range)(Range r)
{
    import std.array;
    return r.array;
}

// Join is a system function. We blindly trust it here
auto trustedJoin(Range)(Range r)
{
    return r.join;
}

@system:
unittest
{
    class TestNode
    {
        string name;
        TestNode[] children;

        this(string n, TestNode parent)
        {
            name = n;
            if (parent !is null)
                parent.children ~= this;
        }

        override string toString() const { return name; }
    }

    auto n1 = new TestNode("a", null);
    auto n2 = new TestNode("b", n1);
    auto n3 = new TestNode("c", n1);
    auto n4 = new TestNode("b", n2);
    auto n5 = new TestNode("b", n3);
    auto n6 = new TestNode("b", n3);
    auto n7 = new TestNode("d", n4);
    auto n8 = new TestNode("d", n4);
    auto n9 = new TestNode("e", n4);

    import std.stdio;
    assert(n1.deepFindAllFirst("a") == [n1]);
    assert(n1.deepFindAllFirst("b") == [n2, n5, n6]);
    assert(n1.deepFindAllFirst("c") == [n3]);
    assert(n1.deepFindAllFirst("d") == [n7, n8]);
    assert(n1.deepFindAllFirst("e") == [n9]);

    assertThrown(n1.shallowFindOnlyOne("a"));
    assertThrown(n1.shallowFindOnlyOne("d"));
    assert(n1.shallowFindOnlyOne("b") == n2);
    assert(n1.shallowFindOnlyOne("c") == n3);
    assertThrown(n3.shallowFindOnlyOne("b"));

    assert(n1.shallowFindMaxOne("a") is null);
    assert(n1.shallowFindMaxOne("d") is null);
    assert(n1.shallowFindMaxOne("b") == n2);
    assert(n1.shallowFindMaxOne("c") == n3);
    assertThrown(n3.shallowFindMaxOne("b"));

    assertThrown(n1.shallowFindOneOf(["x", "y"]));
    assertThrown(n1.shallowFindOneOf(["b", "c"]));
    assert(n1.shallowFindOneOf(["x", "b"]) == n2);
    assert(n4.shallowFindOneOf(["x", "e", "q"]) == n9);

    assert(n4.shallowFindMany("d") == [n7, n8]);

    assert(n4.shallowFindManyOf(["d", "z"]) == [n7, n8]);
    assert(n4.shallowFindManyOf(["d", "e"]) == [n7, n8, n9]);
}
