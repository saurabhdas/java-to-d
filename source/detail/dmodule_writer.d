module detail.dmodule_writer;

import detail.ast_resolver;

@safe:

@trusted:
void writeAll(in SymbolTable st, string outputDirectory = ".")
{
    assert(outputDirectory !is null);
    foreach(item; st.table.byKeyValue)
    {
//        if (cast(const JInterface)(item.value) is null && cast(const JClass)(item.value) is null)
//            continue;
//
//        if (cast(const JInterface)(item.value) !is null)
//            if ((cast(const JInterface)(item.value)).parent != JName.init)
//                continue;
//
//        if (cast(const JClass)(item.value) !is null)
//            if ((cast(const JClass)(item.value)).parent != JName.init)
//                continue;

        auto app1 = appender!string;
        auto app2 = appender!(DName[]);
        
        auto proceed = st.table.get(item.key, null).serializeFull(app1, app2, 0);
        if (!proceed)
            continue;

        auto modStringName = convModuleName(item.key).extract;
        auto mText = chain(["module ", modStringName, ";\n"],
            ["static import jni_d;\n", "\n"],
            sort(app2.data.filter!(a => a != DName.init).map!(a => a.extract).filter!(a => a != modStringName).array).uniq.map!(a => "static import " ~ a ~ ";\n").array,
            ["\n", app1.data]).join;

        auto mPath = convModuleName(item.key).extract.replace(".", "/") ~ ".d";

        log("Writing '", convModuleName(item.key).extract, "'");

        import std.file, std.path;
        mkdirRecurse(outputDirectory ~ "/" ~ dirName(mPath));
        write(outputDirectory ~ "/" ~ mPath, mText);
    }
}

@system:

unittest
{
    // FOR NOW:

    log("Running unittest 'dmodule_writer'");

    auto st = new SymbolTable;
    st.ensureSymbol(JName("java.lang.Object"));

    resolveAll(st, []);
    fixAllInheritedImplements(st);
    writeAll(st, "./unittest_run");
}
