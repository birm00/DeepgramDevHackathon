#import <dispatch/once.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSException.h>
#import "NSMethodSignatureForBlock.m"
#import <PromiseKit/Umbrella.h>
#import <PromiseKit/PromiseKit.h>
#import <string.h>

#ifndef PMKLog
#define PMKLog NSLog
#endif

@interface PMKArray : NSObject {
@public
    id objs[3];
    NSUInteger count;
} @end

@implementation PMKArray

- (id)objectAtIndexedSubscript:(NSUInteger)idx {
    if (count <= idx) {
        return nil;
    }
    return objs[idx];
}

@end

id __PMKArrayWithCount(NSUInteger count, ...) {
    PMKArray *this = [PMKArray new];
    this->count = count;
    va_list args;
    va_start(args, count);
    for (NSUInteger x = 0; x < count; ++x)
        this->objs[x] = va_arg(args, id);
    va_end(args);
    return this;
}


static inline id _PMKCallVariadicBlock(id frock, id result) {
    NSCAssert(frock, @"");

    NSMethodSignature *sig = NSMethodSignatureForBlock(frock);
    const NSUInteger nargs = sig.numberOfArguments;
    const char rtype = sig.methodReturnType[0];

    #define call_block_with_rtype(type) ({^type{ \
        switch (nargs) { \
            case 1: \
                return ((type(^)(void))frock)(); \
            case 2: { \
                const id arg = [result class] == [PMKArray class] ? result[0] : result; \
                return ((type(^)(id))frock)(arg); \
            } \
            case 3: { \
                type (^block)(id, id) = frock; \
                return [result class] == [PMKArray class] \
                    ? block(result[0], result[1]) \
                    : block(result, nil); \
            } \
            case 4: { \
                type (^block)(id, id, id) = frock; \
                return [result class] == [PMKArray class] \
                    ? block(result[0], result[1], result[2]) \
                    : block(result, nil, nil); \
            } \
            default: \
                @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"PromiseKit: The provided block’s argument count is unsupported." userInfo:nil]; \
        }}();})

    switch (rtype) {
        case 'v':
            call_block_with_rtype(void);
            return nil;
        case '@':
            return call_block_with_rtype(id) ?: nil;
        case '*': {
            char *str = call_block_with_rtype(char *);
            return str ? @(str) : nil;
        }
        case 'c': return @(call_block_with_rtype(char));
        case 'i': return @(call_block_with_rtype(int));
        case 's': return @(call_block_with_rtype(short));
        case 'l': return @(call_block_with_rtype(long));
        case 'q': return @(call_block_with_rtype(long long));
        case 'C': return @(call_block_with_rtype(unsigned char));
        case 'I': return @(call_block_with_rtype(unsigned int));
        case 'S': return @(call_block_with_rtype(unsigned short));
        case 'L': return @(call_block_with_rtype(unsigned long));
        case 'Q': return @(call_block_with_rtype(unsigned long long));
        case 'f': return @(call_block_with_rtype(float));
        case 'd': return @(call_block_with_rtype(double));
        case 'B': return @(call_block_with_rtype(_Bool));
        case '^':
            if (strcmp(sig.methodReturnType, "^v") == 0) {
                call_block_with_rtype(void);
                return nil;
            }
            // else fall through!
        default:
            @throw [NSException exceptionWithName:@"PromiseKit" reason:@"PromiseKit: Unsupported method signature." userInfo:nil];
    }
}

static id PMKCallVariadicBlock(id frock, id result) {
    @try {
        return _PMKCallVariadicBlock(frock, result);
    } @catch (id thrown) {
        return PMKProcessUnhandledException(thrown);
    }
}


static dispatch_once_t onceToken;
static NSError *(^PMKUnhandledExceptionHandler)(id);

NSError *PMKProcessUnhandledException(id thrown) {

    dispatch_once(&onceToken, ^{
        PMKUnhandledExceptionHandler = ^id(id reason){
            if ([reason isKindOfClass:[NSError class]])
                return reason;
            if ([reason isKindOfClass:[NSString class]])
                return [NSError errorWithDomain:PMKErrorDomain code:PMKUnexpectedError userInfo:@{NSLocalizedDescriptionKey: reason}];
            return nil;
        };
    });

    id err = PMKUnhandledExceptionHandler(thrown);
    if (!err) {
        NSLog(@"PromiseKit no longer catches *all* exceptions. However you can change this behavior by setting a new PMKProcessUnhandledException handler.");
        @throw thrown;
    }
    return err;
}

void PMKSetUnhandledExceptionHandler(NSError *(^newHandler)(id)) {
    dispatch_once(&onceToken, ^{
        PMKUnhandledExceptionHandler = newHandler;
    });
}
