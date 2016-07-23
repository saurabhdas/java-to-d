module detail.jgrammar;

import std.string, std.algorithm, std.array, std.typecons;
import pegged.grammar;

private:
enum javapGrammar = `
J:
    Body                    < Heading Declaration "{" Definition* "}"
    Heading                 < "Compiled from \"" Name ".java\""
    Declaration             < (ClassDeclaration / InterfaceDeclaration)
    Definition              < JavaSignature ("Signature:"/"descriptor:") JniSignature Code?

    InterfaceDeclaration    < Modifier* "interface" ClassName Extends?
    ClassDeclaration        < Modifier* "class" ClassName Extends? Implements?

    JavaSignature           < (Constructor / Method / Member) ";"
    JniSignature            < ("(" JniType* ")")? JniType

    Member                  < Modifier* ClassName Name
    Constructor             < Modifier* ClassName ArgsList Throws?
    Method                  < Modifier* TemplateRestrict? ClassName Name ArgsList Throws?

    ClassName               < OnlyClassName Template? Array?
    
    Template                < '<' (ClassName / Wildcard) (Extends / Supers)* (',' (ClassName / Wildcard) (Extends / Supers)*)* '>'
    TemplateRestrict        < '<' ClassName ("extends" PathOrClassName)? (',' ClassName ("extends" PathOrClassName)?)* '>'
    Extends                 < "extends" ClassName (',' ClassName)*
    Implements              < "implements" ClassName (',' ClassName)*
    Supers                  < "super" ClassName (',' ClassName)*
    Throws                  < "throws" ClassName (',' ClassName)*
    
    JniType                 <- '['* ([ZBCSIJFDV] / 'L' PathName ';')
    Modifier                <- "final" / "static" / "abstract" / "native" / "synchronized" / "public"
    PathName                <- Name ([/$] Name)*
    PathOrClassName         <- Name ([./$] Name)* Template? #('<' ClassName '>')?
    ArgsList                < "(" (ClassName (',' ClassName)*)? "..."? ")"
    OnlyClassName           < Name ([.$] Name)*
    Wildcard                <- '?'
    Array                   <- "[]"+
    Name                    <- identifier

    Code                    <- :endOfLine? '    '? 'Code:' :endOfLine ('    ' (!endOfLine .)+ :endOfLine)+
`;

public:

mixin(grammar(javapGrammar));

unittest
{
    assert(J.Heading("Compiled from \"Object.java\"").successful);
    assert(J.Heading("Compiled from \"Class.java\"").successful);
    assert(!J.Heading("Compiled from \"abc.Class.java\"").successful);

    assert(J.PathOrClassName("java.lang.Comparable<? super U>").successful);
    assert(J.TemplateRestrict("<U extends java.lang.Comparable<? super U>>").successful);
    assert(J.TemplateRestrict("<T, U>").successful);

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
    assert(J.JavaSignature("public <U extends java.lang.Comparable<? super U>> java.util.Comparator<T> thenComparing(java.util.function.Function<? super T, ? extends U>);").successful);
    assert(J.JavaSignature("public static <T, U> java.util.Comparator<T> comparing(java.util.function.Function<? super T, ? extends U>, java.util.Comparator<? super U>);").successful);
    
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

    assert(J.Code(`    Code:
       0: aload_0
       1: invokespecial #1                  // Method java/lang/Object."<init>":()V
       4: return

`).successful);

    import std.file;
    assert(J(readText("test_cases/java_lang_Comparable.javap")).successful);
    assert(J(readText("test_cases/my_example_InterfaceExtends.javap")).successful);
    assert(J(readText("test_cases/java_lang_Number.javap")).successful);
    assert(J(readText("test_cases/java_lang_Object.javap")).successful);
    assert(J(readText("test_cases/java_lang_Integer.javap")).successful);
    assert(J(readText("test_cases/java_lang_Class.javap")).successful);
    assert(J(readText("test_cases/java_lang_reflect_Method.javap")).successful);
    assert(J(readText("test_cases/java_io_InputStream.javap")).successful);
    assert(J(readText("test_cases/java_nio_charset_Charset.javap")).successful);
    assert(J(readText("test_cases/java_util_Locale.javap")).successful);
    assert(J(readText("test_cases/java_util_Locale_Category.javap")).successful);
    assert(J(readText("test_cases/java_lang_AbstractStringBuilder.javap")).successful);
    assert(J(readText("test_cases/java_lang_Enum.javap")).successful);
    assert(J(readText("test_cases/java_lang_Thread.javap")).successful);
    assert(J(readText("test_cases/java_io_Serializable.javap")).successful);
}
