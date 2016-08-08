module jni_d.java_root;

import jni_d.jni;
import jni_d.support;

interface JavaRootInterface
{
    jobject _jniObjectPtr();
}

class JavaRootObject : Object, JavaRootInterface
{
    private jobject _jniObjectPtrValue;

    final jobject _jniObjectPtr()
    {
        return _jniObjectPtrValue;
    }

    protected this(jobject ptr)
    {
        _jniObjectPtrValue = ptr;
    }

    ~this()
    {
        destroyObject(_jniObjectPtr);
    }
}

class JavaRootThrowable : Throwable, JavaRootInterface
{
    private jobject _jniObjectPtrValue;
    
    final jobject _jniObjectPtr()
    {
        return _jniObjectPtrValue;
    }

    protected this(jobject ptr)
    {
        _jniObjectPtrValue = ptr;
        super("TODO");
    }

    ~this()
    {
        destroyObject(_jniObjectPtr);
    }
}

class JavaArray(T) : JavaRootObject
{
    this(jobject ptr)
    {
        super(ptr);
        assert(false, "Not implement yet :(");
    }

    enum _javaPrecursors = ["java.lang.JObject.JObject"];
}

// Does T1 derive from T2?
template JavaDerivesFrom(T1, T2)
{
    static if (is(T1 == class) && is(T2 == class) && is(T1 : JavaRootInterface) && is(T1 : JavaRootInterface))
    {
        import std.algorithm;
        import std.traits;

        enum AsStr1 = fullyQualifiedName!T1;
        enum AsStr2 = fullyQualifiedName!T2;

        static if (AsStr1 == AsStr2 || T1._javaPrecursors.canFind(AsStr2))
            enum JavaDerivesFrom = true;
        else
            enum JavaDerivesFrom = false;
    }
    else
    {
        enum JavaDerivesFrom = false;
    }
}

template CheckCall(PassedType, ArgType, OtherArgTypes...)
{
    static if (JavaDerivesFrom!(PassedType, ArgType))
    {
        static if (OtherArgTypes.length > 0)
        {
            alias ConsiderOne = OtherArgTypes[0];
            static if (JavaDerivesFrom!(PassedType, ConsiderOne) && JavaDerivesFrom!(ConsiderOne, ArgType))
            {
                enum CheckCall = false;
            }
            else
            {
                enum CheckCall = CheckCall!(PassedType, ArgType, OtherArgTypes[1 .. $]);
            }
        }
        else
        {
            enum CheckCall = true;
        }
    }
    else
    {
        enum CheckCall = false;
    }
}

