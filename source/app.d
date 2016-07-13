module app;

import std.string, std.algorithm, std.array, std.typecons;

// For debugging
import std.stdio;

enum javapGrammar = `
J:
    Body                    < Heading Declaration "{" Definition* "}"
    Heading                 < "Compiled from \"" Name ".java\""
    Declaration             < (ClassDeclaration / InterfaceDeclaration)
    Definition              < JavaSignature "Signature:" JniSignature

    InterfaceDeclaration    < Modifier* "interface" ClassName Extends?
    ClassDeclaration        < Modifier* "class" ClassName ("extends" ClassName)? ("implements" ClassName (',' ClassName)*)?

    JavaSignature           < (Constructor / Method / Member) ";"
    JniSignature            < ("(" JniType* ")")? JniType

    Member                  < Modifier* ClassName Array? Name
    Constructor             < Modifier* ClassName ArgsList ("throws" ClassName (',' ClassName)*)?
    Method                  < Modifier* TemplateRestrict? ClassName Array? Name ArgsList ("throws" ClassName (',' ClassName)*)?
    
    ArgsList                < "(" (ClassName Array? (',' ClassName Array?)*)? "..."? ")"
    Extends                 < "extends" ClassName (',' ClassName)*
    Supers                  < "super" ClassName (',' ClassName)*

    JniType                 <- '['* ([ZBCSIJFDV] / 'L' PathName ';')
    Modifier                <- "final" / "static" / "abstract" / "native" / "synchronized" / "public"
    PathName                <- Name ([/$] Name)* ('<' Name '>')?
    ClassName               < OnlyClassName Template?
    Template                < '<' (ClassName / Wildcard) (Array / Extends / Supers)* (',' (ClassName / Wildcard) (Array / Extends / Supers)*)* '>'
    TemplateRestrict        < '<' ClassName "extends" PathName '>'
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
    assert(J(readText("test_cases/java_lang_Object.javap")).successful);
    assert(J(readText("test_cases/java_lang_Comparable.javap")).successful);
    assert(J(readText("test_cases/java_lang_Number.javap")).successful);
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
    import pegged.grammar;

    ParseTree parseTree;

    @nogc @safe pure nothrow this(ParseTree parseTree_, string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        parseTree = parseTree_;
        super(msg, file, line, next);
    }
}

struct JavaClassInfo
{
    string className;
    string classFullName;
    string classPath;

    bool isClass;
    bool isInterface;

    bool isGeneric;
    string[] genericArgs;
}

import pegged.peg;
auto findAllFirst(in ref ParseTree haystack, in string needle)
{
    if (haystack.name == needle)
        return [haystack];
    else
        return haystack.children.map!(a => findAllFirst(a, needle)).join.array;
}

string[] tmpProcess(ref ParseTree p)
{
    return sort(findAllFirst(p, "J.OnlyClassName").filter!(a => a.matches.length > 1)
        .map!(a => a.matches.join.replace("$", ".")).array).uniq.array;
}

void main(string[] args)
{
    import std.getopt;
    
    string[] javaClassNames;
    string[] javaClassPaths;
    string outputDirectory = "jni_d/";
    
    auto helpInfo = getopt(
        args, std.getopt.config.caseSensitive, std.getopt.config.bundling,
        std.getopt.config.required, "class|c", "Generate modules for these Java classes. Can specify multiple times", &javaClassNames,
        "classpath|p", "Paths used to look up classes. Seperate by ':' or specify multiple times", &javaClassPaths,
        "odir|o", "Output directory for generated D modules. Created if absent", &outputDirectory,
        );
    
    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("jni-d: Java class to D module generator.",
            helpInfo.options);
        return;
    }
    
    import std.string;
    auto javapCmd = ["javap", "-public", "-s"];
    if (javaClassPaths)
    {
        javapCmd ~= "-classpath";
        javapCmd ~= javaClassPaths.join(":");
    }
    
    string[] classesRemaining = javaClassNames;
    string[] classesFinished;
    while(classesRemaining.length > 0)
    {
        auto thisClass = classesRemaining[0];
        writeln("Generating for ", thisClass);
        
        import std.process;
        auto genOut = execute(javapCmd ~ thisClass);
        
        if (genOut.status != 0)
        {
            import std.conv : to;
            throw new Exception("Non-zero return code from 'javap' on invocation: " ~ to!string(javapCmd ~ thisClass));
        }

        import pegged.grammar;
        mixin(grammar(javapGrammar));
        
        auto classTree = J(genOut.output);
        
        if (!classTree.successful)
        {
            writeln("FAILED ON CLASS: ", thisClass);
            writeln(classTree);
            throw new ParseException(classTree, "Could not parse J class successfully");
        }
            
        auto dependentClassNames = tmpProcess(classTree);
        
//        import std.file, std.path;
//        auto modulePath = outputDirectory ~ "/" ~ dirName(res.oName);
//        auto outputFilePath = outputDirectory ~ "/" ~ res.oName;
//        log("Writing output to directory=", modulePath, " file=", outputFilePath);
//        mkdirRecurse(modulePath);
//        write(outputFilePath, res.oText);
        
        auto newDeps = dependentClassNames.filter!(a => !classesRemaining.canFind(a)).filter!(a => !classesFinished.canFind(a)).array;
        writeln("New dependents = ", newDeps);
        
        classesRemaining ~= newDeps;
        
        classesFinished ~= thisClass;
        classesRemaining = classesRemaining[1 .. $];
    }

    writeln("Finished processing: ", classesFinished, " (", classesFinished.length, " in number)");
}

