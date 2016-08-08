module jni_d;

static import jni_d.support;
static import jni_d.java_root;

alias jvmIsRunning = jni_d.support.jvmIsRunning;
alias jvmInit = jni_d.support.jvmInit;
alias jvmDestroy = jni_d.support.jvmDestroy;

alias JavaArray = jni_d.java_root.JavaArray;

alias JavaDerivesFrom = jni_d.java_root.JavaDerivesFrom;
