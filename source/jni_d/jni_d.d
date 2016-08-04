module jni_d.jni_d;

static import java.lang.JObject;

private import jni_d.jni;
private import std.conv : to;
private import std.string;
private import std.meta;
private import std.typecons : Tuple;

bool jvmIsRunning()
{
    assert((_jvm is null) == (_env is null));
    return (_jvm !is null);
}

void jvmInit(string classpath = "")
{
    assert(!jvmIsRunning);

    JavaVMInitArgs vm_args;
    JavaVMOption[] options = new JavaVMOption[1];
    options[0].optionString = cast(char*) toStringz("-Djava.class.path=" ~ classpath);
    
    vm_args.version_ = JNI_VERSION_1_6;
    vm_args.nOptions = 1;
    vm_args.options = options.ptr;
    vm_args.ignoreUnrecognized = false;
    
    auto res = JNI_CreateJavaVM(&_jvm, cast(void**) &_env, &vm_args);
    if (res < 0)
        throw new Exception("Could not create JVM. Got return value '" ~ res.to!string ~ "' JNI_CreateJavaVM");
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

struct InternalConstructorInfo
{
    jobject javaPointer;
}

enum JniRegistrationFunction;

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

string helperGetClassNameAsString(jobject obj)
{
    jclass cls = (*_env).GetObjectClass(_env, obj);
    
    // First get the class object
    jmethodID mid = (*_env).GetMethodID(_env, cls, "getClass", "()Ljava/lang/Class;");
    jobject clsObj = (*_env).CallObjectMethod(_env, obj, mid);
    
    // Now get the class object's class descriptor
    cls = (*_env).GetObjectClass(_env, clsObj);
    
    // Find the getName() method on the class object
    mid = (*_env).GetMethodID(_env, cls, "getName", "()Ljava/lang/String;");
    
    // Call the getName() to get a jstring object back
    jstring strObj = (*_env).CallObjectMethod(_env, clsObj, mid);
    
    // Now get the c string from the java jstring object
    const char* str = (*_env).GetStringUTFChars(_env, strObj, null);
    
    // Print the class name
    auto rv = fromStringz(str).idup;
    
    // Release the memory pinned char array
    (*_env).ReleaseStringUTFChars(_env, strObj, str);

    return rv;
}

ReturnType returnTypeConv(string callRetType, ReturnType, T)(T rval)
{
    import std.stdio;
    static if (callRetType == "Object")
    {
        assert(is(T == jobject));
        ReturnType._jniRegisterAll();
        import std.traits;
        static if (!is(ReturnType == class) || !(isNested!ReturnType))
        {
            jclass objectClass = (*_env).GetObjectClass(_env, rval);
            assert(objectClass !is null);
            writeln("Objectclass = ", objectClass);
            auto secretConstructor = _jniKnownClassConstructors.get(objectClass, null);
            if (secretConstructor !is null)
            {
                auto rr = cast(ReturnType)secretConstructor(InternalConstructorInfo(rval));
                assert(rr !is null);
                return rr;
            }
            else
                throw new Exception("jni_d got a class which is not registered. Directly linked classes are automatically registered, but java functions which return derived classes of known classes need to be loaded manually. Fix this by calling '_jniRegisterAll()' on the derived class before this method is invoked. The class returned is: " ~ helperGetClassNameAsString(rval));
        }
        else
        {
            assert(false, "Not implemented yet :(");
        }
    }
    else static if (callRetType == "Boolean")
        return (rval != 0);
    else static if (callRetType == "Char")
        return cast(wchar)rval;
    else
        return rval;
}

// TODO - For ALL calls to JNI, check for exceptions!

jclass loadClass(string name, ConstructorDelegate del)
{
    import std.stdio;
    writeln("loadClass ", name);
    assert(jvmIsRunning);
    jclass cls = (*_env).FindClass(_env, toStringz(name.replace(".", "/")));
    if (cls is null)
        throw new Exception("Could not load class '" ~ name ~ "'");

    if (del !is null)
    {
        writeln("Setting secret constructor for ", name, " cls=", cls);
        _jniKnownClassConstructors[cls] = del;
    }
    return cls;
}

jmethodID loadClassMethod(jclass classz, string methodName, string methodJniSig)
{
    import std.stdio;
    writeln("loadClassMethod ", methodName, " : ", methodJniSig);
    assert(jvmIsRunning);
    assert(classz !is null);
    jmethodID jm = (*_env).GetMethodID(_env, classz, toStringz(methodName), toStringz(methodJniSig));
    if (jm is null)
        throw new Exception("Could not load class method '" ~ methodName ~ "' with signature '" ~ methodJniSig ~ "'");
    return jm;
}

jmethodID loadStaticMethod(jclass classz, string methodName, string methodJniSig)
{
    import std.stdio;
    writeln("loadStaticMethod ", methodName, " : ", methodJniSig);
    assert(jvmIsRunning);
    assert(classz !is null);
    jmethodID jm = (*_env).GetStaticMethodID(_env, classz, toStringz(methodName), toStringz(methodJniSig));
    if (jm is null)
        throw new Exception("Could not load static method '" ~ methodName ~ "' with signature '" ~ methodJniSig ~ "'");
    return jm;
}

jfieldID loadClassField(jclass classz, string fieldName, string fieldJniSig)
{
    import std.stdio;
    writeln("loadClassField ", fieldName, " : ", fieldJniSig);
    assert(jvmIsRunning);
    assert(classz !is null);
    jfieldID jf = (*_env).GetFieldID(_env, classz, toStringz(fieldName), toStringz(fieldJniSig));
    if (jf is null)
        throw new Exception("Could not load class field '" ~ fieldName ~ "' with signature '" ~ fieldJniSig ~ "'");
    return jf;
}

jfieldID loadStaticField(jclass classz, string fieldName, string fieldJniSig)
{
    import std.stdio;
    writeln("loadStaticField ", fieldName, " : ", fieldJniSig);
    assert(jvmIsRunning);
    assert(classz !is null);
    jfieldID jf = (*_env).GetStaticFieldID(_env, classz, toStringz(fieldName), toStringz(fieldJniSig));
    if (jf is null)
        throw new Exception("Could not load static field '" ~ fieldName ~ "' with signature '" ~ fieldJniSig ~ "'");
    return jf;
}

jobject callNewObject(Args...)(jclass classz, jmethodID methodId, Args args)
{
    // Booleans need widening to ubyte
    return callNewObjectProxy!(ReplaceAll!(bool, ubyte, Args))(classz, methodId, args);
}

jobject callNewObjectProxy(Args...)(jclass classz, jmethodID methodId, Args args)
{
    assert(classz !is null);
    assert(methodId !is null);

    auto rval = (*_env).NewObject(_env, classz, methodId, args);
    if (rval is null)
        throw new Exception("Could not construct object!");
    return rval;
}

ReturnType callClassMethod(ReturnType, Args...)(jobject obj, jmethodID methodID, Args args)
{
    // Booleans need widening to ubyte
    return callClassMethodProxy!(ReturnType, ReplaceAll!(bool, ubyte, Args))(obj, methodID, args);
}

ReturnType callClassMethodProxy(ReturnType, Args...)(jobject obj, jmethodID methodID, Args args)
{
    assert(obj !is null);
    assert(methodID !is null);
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

ReturnType callStaticMethod(ReturnType, Args...)(jobject obj, jmethodID methodID, Args args)
{
    // Booleans need widening to ubyte
    return callStaticMethodProxy!(ReturnType, ReplaceAll!(bool, ubyte, Args))(obj, methodID, args);
}

ReturnType callStaticMethodProxy(ReturnType, Args...)(jclass classz, jmethodID methodID, Args args)
{
    assert(classz !is null);
    assert(methodID !is null);
    enum callRetType = typeToCallSig!ReturnType;
    import std.stdio;
    writeln("Calling static method...");

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

ReturnType callClassFieldGet(ReturnType)(jobject obj, jfieldID fieldID)
{
    assert(obj !is null);
    assert(fieldID !is null);
    enum callRetType = typeToCallSig!ReturnType;
    mixin("auto rval = (*_env).Get" ~ callRetType ~ "Field(_env, obj, fieldID);");
    return returnTypeConv!(callRetType, ReturnType)(rval);
}

ReturnType callStaticFieldGet(ReturnType)(jclass classz, jfieldID fieldID)
{
    assert(classz !is null);
    assert(fieldID !is null);
    enum callRetType = typeToCallSig!ReturnType;
    mixin("auto rval = (*_env).GetStatic" ~ callRetType ~ "Field(_env, classz, fieldID);");
    return returnTypeConv!(callRetType, ReturnType)(rval);
}

void callClassFieldSet(T)(jobject obj, jfieldID fieldID, T newValue)
{
    assert(obj !is null);
    assert(fieldID !is null);
    enum callRetType = typeToCallSig!T;
    mixin("(*_env).Set" ~ callRetType ~ "Field(_env, obj, fieldID, newValue);");
}

void callStaticFieldSet(T)(jclass classz, jfieldID fieldID, T newValue)
{
    assert(classz !is null);
    assert(fieldID !is null);
    enum callRetType = typeToCallSig!T;
    mixin("(*_env).SetStatic" ~ callRetType ~ "Field(_env, classz, fieldID, newValue);");
}

private:

__gshared JavaVM* _jvm;
__gshared JNIEnv* _env;

alias ConstructorDelegate = Object function(InternalConstructorInfo);

// TODO
__gshared ConstructorDelegate[jclass] _jniKnownClassConstructors;
