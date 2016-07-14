module jgrammar;

import std.string, std.algorithm, std.array, std.typecons;

enum javapGrammar = `
J:
    Body                    < Heading Declaration "{" Definition* "}"
    Heading                 < "Compiled from \"" Name ".java\""
    Declaration             < (ClassDeclaration / InterfaceDeclaration)
    Definition              < JavaSignature "Signature:" JniSignature

    InterfaceDeclaration    < Modifier* "interface" ClassName Extends?
    ClassDeclaration        < Modifier* "class" ClassName Extends? Implements?

    JavaSignature           < (Constructor / Method / Member) ";"
    JniSignature            < ("(" JniType* ")")? JniType

    Member                  < Modifier* ClassName Name
    Constructor             < Modifier* ClassName ArgsList Throws?
    Method                  < Modifier* TemplateRestrict? ClassName Name ArgsList Throws?

    ClassName               < OnlyClassName Template? Array?
    
    Template                < '<' (ClassName / Wildcard) (Extends / Supers)* (',' (ClassName / Wildcard) (Extends / Supers)*)* '>'
    TemplateRestrict        < '<' ClassName "extends" PathName '>'
    Extends                 < "extends" ClassName (',' ClassName)*
    Implements              < "implements" ClassName (',' ClassName)*
    Supers                  < "super" ClassName (',' ClassName)*
    Throws                  < "throws" ClassName (',' ClassName)*
    
    JniType                 <- '['* ([ZBCSIJFDV] / 'L' PathName ';')
    Modifier                <- "final" / "static" / "abstract" / "native" / "synchronized" / "public"
    PathName                <- Name ([/$] Name)* ('<' Name '>')?
    ArgsList                < "(" (ClassName (',' ClassName)*)? "..."? ")"
    OnlyClassName           < Name ([.$] Name)*
    Wildcard                <- '?'
    Array                   <- "[]"+
    Name                    <- identifier
`;

unittest
{
    import pegged.grammar;
    mixin(grammar(javapGrammar));
    
    assert(J.Heading("Compiled from \"Object.java\"").successful);
    assert(J.Heading("Compiled from \"Class.java\"").successful);
    assert(!J.Heading("Compiled from \"abc.Class.java\"").successful);
    
    assert(J.JavaSignature("public static final int MAX_VALUE;").successful);
    assert(J.JavaSignature("public static final java.lang.String mesaString;").successful);
    assert(J.JavaSignature("public static final Map<Key, Value> withGenerics;").successful);
    
    assert(J.Declaration("public class java.lang.Object").successful);
    assert(J.Declaration("public final class java.lang.Class<T> implements java.io.Serializable, java.lang.reflect.GenericDeclaration, java.lang.reflect.Type, java.lang.reflect.AnnotatedElement").successful);
    assert(J.Declaration("public interface java.lang.Comparable<T>").successful);
    assert(J.Declaration("public final class java.lang.Integer extends java.lang.Number implements java.lang.Comparable<java.lang.Integer>").successful);
    
    assert(J.JavaSignature("public java.lang.Object();").successful);
    assert(J.JavaSignature("public java.lang.Integer(int);").successful);
    assert(J.JavaSignature("public java.lang.Integer(java.lang.String) throws java.lang.NumberFormatException;").successful);
    assert(J.JavaSignature("public boolean equals(java.lang.Object);").successful);
    assert(J.JavaSignature("public final native void notify();").successful);
    assert(J.JavaSignature("public final native void wait(long) throws java.lang.InterruptedException;").successful);
    assert(J.JavaSignature("public final native java.lang.Class<?> getClass();").successful);
    assert(J.JavaSignature("public static java.lang.Class<?> forName(java.lang.String, boolean, java.lang.ClassLoader) throws java.lang.ClassNotFoundException;").successful);
    assert(J.JavaSignature("public T[] getEnumConstants();").successful);
    assert(J.JavaSignature("public java.lang.reflect.TypeVariable<java.lang.Class<T>>[] getTypeParameters();").successful);
    assert(J.JavaSignature("public java.lang.Class<? extends U> asSubclass(java.lang.Class<U>);").successful);
    assert(J.JavaSignature("public <U extends java/lang/Object> java.lang.Class<? extends U> asSubclass(java.lang.Class<U>);").successful);
    assert(J.JavaSignature("public <A extends java/lang/annotation/Annotation> A getAnnotation(java.lang.Class<A>);").successful);
    assert(J.JavaSignature("public static final <A extends java/lang/annotation/Annotation> A getAnnotation(java.lang.Class<A>);").successful);
    assert(J.JavaSignature("public static java.util.SortedMap<java.lang.String, java.nio.charset.Charset> availableCharsets();").successful);
    assert(J.JavaSignature("public static java.util.Locale getDefault(java.util.Locale$Category);").successful);
    
    assert(J.JavaSignature("public static java.util.Map<java.lang.Thread, java.lang.StackTraceElement[]> getAllStackTraces();").successful);
    assert(J.JavaSignature("public static <T extends java/lang/Enum<T>> T valueOf(java.lang.Class<T>, java.lang.String);").successful);
    
    assert(J.JniSignature("I").successful);
    assert(J.JniSignature("()Z").successful);
    assert(J.JniSignature("(JI)V").successful);
    assert(J.JniSignature("()Ljava/lang/String;").successful);
    assert(J.JniSignature("(Ljava/lang/String;)Ljava/lang/Class;").successful);
    assert(J.JniSignature("(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;").successful);
    assert(J.JniSignature("(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;").successful);
    assert(J.JniSignature("()[[Ljava/lang/annotation/Annotation;").successful);
    assert(J.JniSignature("(Ljava/util/Locale$Category;)Ljava/util/Locale;").successful);
    
    import std.file;
    assert(J(readText("test_cases/java_lang_Comparable.javap")).successful);
    assert(J(readText("test_cases/my_example_InterfaceExtends.javap")).successful);
    assert(J(readText("test_cases/java_lang_Number.javap")).successful);
    assert(J(readText("test_cases/java_lang_Object.javap")).successful);
    assert(J(readText("test_cases/java_lang_Integer.javap")).successful);
    assert(J(readText("test_cases/java_lang_Class.javap")).successful);
    assert(J(readText("test_cases/java_lang_reflect_Method.javap")).successful);
    assert(J(readText("test_cases/java_io_InputStream.javap")).successful);
    assert(J(readText("test_cases/java_nio_charset_Chartset.javap")).successful);
    assert(J(readText("test_cases/java_util_Locale.javap")).successful);
    assert(J(readText("test_cases/java_lang_AbstractStringBuilder.javap")).successful);
    assert(J(readText("test_cases/java_lang_Enum.javap")).successful);
    assert(J(readText("test_cases/java_lang_Thread.javap")).successful);
}

class ParseException : Exception
{
    import pegged.peg;
    const ParseTree parseTree;
    
    @nogc @safe pure nothrow this(in ref ParseTree parseTree_, string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        parseTree = parseTree_;
        super(msg, file, line, next);
    }
}

import pegged.peg;
auto deepFindAllFirst(PT)(in auto ref PT haystack, in string needle)
{
    if (haystack.name == needle)
        return [haystack];
    else
        return haystack.children.map!(a => deepFindAllFirst(a, needle)).join.array;
}

auto shallowFindOnlyOne(PT)(in auto ref PT haystack, in string needle)
{
    auto f = haystack.children.filter!(a => a.name == needle).array;
    import std.conv;
    assert(f.length == 1, "Found " ~ to!string(f.length) ~ " elements, expected exactly 1 of '" ~ needle ~ "'");
    return f[0];
}

auto shallowFindMaxOne(PT)(in auto ref PT haystack, in string needle)
{
    auto f = haystack.children.filter!(a => a.name == needle).array;
    assert(f.length == 0 || f.length == 1);
    return (f.length == 0) ? PT.init : f[0];
}

auto shallowFindOneOf(PT)(in auto ref PT haystack, in string[] needles)
{
    auto rxs = needles
        .map!(a => tuple!("whichMatch", "match")(a, haystack.shallowFindMaxOne(a)))
        .filter!(a => a.match != PT.init).array;
    if (rxs.length != 1)
    {
        import std.stdio;
        writeln("ERROR");
        writeln(haystack);
        writeln(needles);
    }
    assert(rxs.length == 1);
    return rxs[0];
}

auto shallowFindMany(PT)(in auto ref PT haystack, in string needle)
{
    return haystack.children.filter!(a => a.name == needle).array;
}
