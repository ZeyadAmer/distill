//  HotstashJSCore.h
//  Bridging header that forward-declares the JavaScriptCore execution-time-limit
//  C API. These symbols are exported by the JavaScriptCore framework binary but
//  live in the private JSContextRefPrivate.h header, so they are not visible to
//  Swift through the standard module import. Declaring them here lets the
//  sandbox engine impose a hard wall-clock limit that terminates infinite loops.

#import <JavaScriptCore/JavaScriptCore.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef bool (*HotstashJSShouldTerminateCallback)(JSContextRef ctx, void *context);

JS_EXPORT void JSContextGroupSetExecutionTimeLimit(
    JSContextGroupRef group,
    double limit,
    HotstashJSShouldTerminateCallback callback,
    void *context);

JS_EXPORT void JSContextGroupClearExecutionTimeLimit(JSContextGroupRef group);

#ifdef __cplusplus
}
#endif
