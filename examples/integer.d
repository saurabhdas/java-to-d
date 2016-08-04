module integer;

import jni_d.jni_d;

shared static this()
{
    if (!jvmIsRunning)
        jvmInit();
        
    import std.stdio;

    writeln("========================= 1");
    import java.lang.JString;
    auto s1 = JString.valueOf(true);

    writeln("========================= 2");
    import java.lang.JSystem;
    auto a = JSystem.jout;

    writeln("========================= 3");
    writeln(s1._jniGetObjectPtr);
    writeln(a._jniGetObjectPtr);
    writeln(typeof(s1).stringof);
    writeln(typeof(a).stringof);
    a.println(s1);
}

shared static ~this()
{
    if (jvmIsRunning)
        jvmDestroy();
}
