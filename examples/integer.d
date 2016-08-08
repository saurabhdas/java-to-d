module integer;

import jni_d;

shared static this()
{
    import std.stdio;
    if (!jvmIsRunning)
        jvmInit();
        
    writeln("Constructing a java.lang.Integer from an int");
    import java.lang.JInteger;
    auto i1 = new JInteger(42);

    writeln("Constructing a java.lang.Integer from an string");
    import java.lang.JString;
    auto i2 = new JInteger(new JString("43"));

    writeln("Printing these integers");
    import java.lang.JSystem;
    JSystem.jout.println(i1);
    JSystem.jout.println(i2);

    writeln("MIN_VALUE = ", JInteger.MIN_VALUE);
    writeln("MAX_VALUE = ", JInteger.MAX_VALUE);
    writeln("max(42,2) = ", JInteger.max(42, 2));
    writeln("min(42,2) = ", JInteger.min(42, 2));
    writeln("sum(42,2) = ", JInteger.sum(42, 2));
}

shared static ~this()
{
    if (jvmIsRunning)
    {
        // To destroy the GC, we need to ensure that all JNI linked objects are destroyed
        import core.memory;
        GC.collect();

        jvmDestroy();
    }
}
