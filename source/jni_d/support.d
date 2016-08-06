module jni_d.support;

import std.conv : to;
import std.string;
import std.meta;
import std.typecons : Tuple;

import jni_d.jni;

bool jvmIsRunning()
{
    assert((_jvm is null) == (_env is null));
    return (_jvm !is null);
}

void jvmInit(string classpath = "")
{
    if(jvmIsRunning)
        throw new Exception("JVM is already running");

    if (!_jvmAllowStart)
        throw new Exception("The JVM can be started only once - cannot be restarted after shutdown");

    JavaVMInitArgs vm_args;
    JavaVMOption[] options = new JavaVMOption[1];
    options[0].optionString = cast(char*) toStringz("-Djava.class.path=" ~ classpath);
    
    vm_args.version_ = JNI_VERSION_1_6;
    vm_args.nOptions = 1;
    vm_args.options = options.ptr;
    vm_args.ignoreUnrecognized = false;
    
    auto res = JNI_CreateJavaVM(&_jvm, cast(void**) &_env, &vm_args);
    if (res < 0)
        throw new Exception("Could not create JVM. Got return value '" ~ res.to!string ~ "' from JNI_CreateJavaVM");

    _jvmAllowStart = false;
}

void jvmDestroy()
{
    assert(jvmIsRunning);

    auto res1 = (*_jvm).DetachCurrentThread(_jvm);
    if (res1 < 0)
        throw new Exception("Could not destroy JVM. Got return value '" ~ res1.to!string ~ "' from DetachCurrentThread");

    auto res2 = (*_jvm).DestroyJavaVM(_jvm);
    if (res2 < 0)
        throw new Exception("Could not destroy JVM. Got return value '" ~ res2.to!string ~ "' from DestroyJavaVM");

    _jvm = null;
    _env = null;
}

// TODO - For ALL calls to JNI, check for exceptions!

jclass findClassWorker(string className)
{
    import std.stdio;
    writeln("loadClass ", name);
    
    assert(jvmIsRunning);
    myClass = (*_env).FindClass(_env, toStringz(className.replace(".", "/")));
    if (myClass is null)
        throw new Exception("Could not load class '" ~ name ~ "'");
    return myClass;
}

jclass findClass(CallingClass)()
{
    static jclass myClass;
    if (myClass !is null)
        return myClass;

    myClass = findClassWorker(CallingClass._jniClassName);
    return myClass;
}

auto findMethodOrFieldWorker(bool isStatic, bool isMethod)(jclass classz, string name, string jniSig)
{
    static if (isStatic)    enum callStr1 = "Static";
    else                    enum callStr1 = "";

    static if (isMethod)    enum callStr2 = "Method";
    else                    enum callStr2 = "Field";

    import std.stdio;
    writeln("load", callStr1, callStr2, " ", name, " : ", jniSig);

    assert(jvmIsRunning);
    assert(classz !is null);

    auto rv = mixin("(*_env).Get" ~ callStr1 ~ callStr2 ~ "ID(_env, classz, toStringz(name), toStringz(jniSig))");

    static if (isMethod)    static assert(is(typeof(rv) == jmethodID));
    else                    static assert(is(typeof(rv) == jfieldID));

    if (rv is null)
        throw new Exception("Could not load '" ~ name ~ "' with signature '" ~ jniSig ~ "'");

    return rv;
}

auto findMethodOrField(CallingClass, bool isStatic, bool isMethod, string name, string jniSig)()
{
    static if (isMethod)    alias StorageType = jmethodID;
    else                    alias StorageType = jfieldID;

    static StorageType myID;
    if (myID !is null)
        return myID;

    jclass myClass = findClass!CallingClass();

    myID = findMethodOrFieldWorker!(isStatic, isMethod)(myClass, name, jniSig);
    return myID;
}

jobject callNewObjectWorker(Args...)(jclass classz, jmethodID methodId, Args args)
{
    import std.stdio;
    writeln("call NewObject");

    assert(classz !is null);
    assert(methodId !is null);
    
    auto rval = (*_env).NewObject(_env, classz, methodId, args);

    if (rval is null)
        throw new Exception("Could not construct object!");

    return rval;
}

jobject callNewObject(CallingClass, string jniSig, Args...)(Args args)
{
    jclass myClass = findClass!CallingClass();
    jmethodID myMethodID = findMethodOrField!(CallingClass, false, true, "<init>", jniSig)();

    return callNewObjectWorker!(ReplaceAll!(bool, ubyte, Args))(myClass, myMethodID, args);
}

ReturnType callMethodWorker(ReturnType, Args...)(jobject obj, jmethodID methodID, Args args)
{
    assert(methodID !is null);
    assert(obj !is null);

    enum callRetType = typeToCallSig!ReturnType;
    
    static if (callRetType == "Void")
    {
        mixin("(*_env).Call" ~ callRetType ~ "Method(_env, obj, methodID, args);");
        return;
    }
    else
    {
        mixin("auto rval = (*_env).Call" ~ callRetType ~ "Method(_env, obj, methodID, args);");
        return returnTypeConv!(callRetType, ReturnType)(rval);
    }
}

ReturnType callMethod(CallingClass, ReturnType, string name, string jniSig, Args...)(jobject obj, Args args)
{
    jmethodID myMethodID = findMethodOrField!(CallingClass, false, true, name, jniSig)();

    return callMethodWorker!(ReturnType, ReplaceAll!(bool, ubyte, Args))(obj, myMethodID, args);
}

ReturnType callStaticMethodWorker(ReturnType, Args...)(jclass classz, jmethodID methodID, Args args)
{
    assert(methodID !is null);
    assert(classz !is null);
    
    enum callRetType = typeToCallSig!ReturnType;
    
    static if (callRetType == "Void")
    {
        mixin("(*_env).CallStatic" ~ callRetType ~ "Method(_env, classz, methodID, args);");
        return;
    }
    else
    {
        mixin("auto rval = (*_env).CallStatic" ~ callRetType ~ "Method(_env, classz, methodID, args);");
        return returnTypeConv!(callRetType, ReturnType)(rval);
    }
}

ReturnType callStaticMethod(CallingClass, ReturnType, string name, string jniSig, Args...)(Args args)
{
    jclass myClass = findClass!CallingClass();
    jmethodID myMethodID = findMethodOrField!(CallingClass, false, true, name, jniSig)();
    
    return callStaticMethodWorker!(ReturnType, ReplaceAll!(bool, ubyte, Args))(myClass, myMethodID, args);
}

ReturnType callGetField(CallingClass, ReturnType, string name, string jniSig)(jobject obj)
{
    assert(obj !is null);
    auto myFieldID = findMethodOrField!(CallingClass, false, false, name, jniSig)();

    enum callRetType = typeToCallSig!ReturnType;
    mixin("auto rval = (*_env).Get" ~ callRetType ~ "Field(_env, obj, myFieldID);");
    return returnTypeConv!(callRetType, ReturnType)(rval);
}

ReturnType callGetStaticField(CallingClass, ReturnType, string name, string jniSig)()
{
    jclass myClass = findClass!CallingClass();
    jmethodID myFieldID = findMethodOrField!(CallingClass, true, false, name, jniSig)();

    enum callRetType = typeToCallSig!ReturnType;
    mixin("auto rval = (*_env).GetStatic" ~ callRetType ~ "Field(_env, myClass, myFieldID);");
    return returnTypeConv!(callRetType, ReturnType)(rval);
}

void callSetField(CallingClass, ArgType, string name, string jniSig)(jobject obj, ArgType newValue)
{
    assert(obj !is null);
    auto myFieldID = findMethodOrField!(CallingClass, false, false, name, jniSig)();

    enum callRetType = typeToCallSig!ArgType;
    mixin("(*_env).Set" ~ callRetType ~ "Field(_env, obj, myFieldID, newValue);");
}

void callSetStaticField(CallingClass, ArgType, string name, string jniSig)(ArgType newValue)
{
    jclass myClass = findClass!CallingClass();
    jmethodID myFieldID = findMethodOrField!(CallingClass, true, false, name, jniSig)();

    enum callRetType = typeToCallSig!T;
    mixin("(*_env).SetStatic" ~ callRetType ~ "Field(_env, myClass, myFieldID, newValue);");
}

void destroyObject(jobject obj)
{
    (*_env).DeleteLocalRef(_env, obj);
}

private:

string typeToCallSig(ReturnType)() nothrow
{
    static if       (ReturnType.stringof == "bool")         return "Boolean";
    else static if  (ReturnType.stringof == "byte")         return "Byte";
    else static if  (ReturnType.stringof == "wchar")        return "Char";
    else static if  (ReturnType.stringof == "short")        return "Short";
    else static if  (ReturnType.stringof == "int")          return "Int";
    else static if  (ReturnType.stringof == "long")         return "Long";
    else static if  (ReturnType.stringof == "float")        return "Float";
    else static if  (ReturnType.stringof == "double")       return "Double";
    else static if  (ReturnType.stringof == "void")         return "Void";
    else                                                    return "Object";
}

ReturnType returnTypeConv(string callRetType, ReturnType, T)(T rval)
{
    import std.stdio;
    static if (callRetType == "Object")
    {
        assert(is(T == jobject));
        import std.traits;
        static if (!isNested!ReturnType)
            return new ReturnType(rval);
        else
            assert(false, "Not implemented yet :(");
    }
    else static if (callRetType == "Boolean")
        return (rval != 0);
    else static if (callRetType == "Char")
        return cast(wchar)rval;
    else
        return rval;
}

private:

__gshared JavaVM* _jvm;
__gshared JNIEnv* _env;
__gshared bool _jvmAllowStart = true;
