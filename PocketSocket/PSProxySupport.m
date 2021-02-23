//  Created by Matthias Keiser on 23/02/2021.
//  Copyright © 2021 Zwopple Limited. All rights reserved.

#import "PSProxySupport.h"

NSString *const PSProxyErrorDomain = @"PSProxyErrorDomain";
typedef NS_ENUM(NSUInteger, PSProxyErrorCode) {
    PSProxyErrorCodeNoSystemProxySettings,
    PSProxyErrorCodeMissingPACURL,
    PSProxyErrorCodeNoRunLoopSource,
    PSProxyErrorCodeInvalidPACResult
};

static void ResultCallback(void * client, CFArrayRef proxies, CFErrorRef error);

@implementation PSProxySupport

#if TARGET_OS_OSX

+ (void)applySuitableProxyForURL:(NSURL *)url toStream:(CFReadStreamRef)stream {
    NSError *error = nil;
    NSArray *proxies = [self getProxyListForURL:url error:&error];
    if (!proxies) {
        NSLog(@"failed to get suitable proxies for url: %@. Error: %@", url, error);
        return;
    }

    // Look for the first proxy we can work with (either "none", SOCKS, or HTTPS).
    for (NSDictionary *proxyDict in proxies) {

        // most simple: don't use a proxy at all
        if ([proxyDict[(NSString *)kCFProxyTypeKey] isEqual:(NSString *)kCFProxyTypeNone]) {
            return;
        }

        // next best outcome: use a SOCKS proxy
        if ([proxyDict[(NSString *)kCFProxyTypeKey] isEqual:(NSString *)kCFProxyTypeSOCKS]) {
            Boolean ok = CFReadStreamSetProperty(stream, kCFStreamPropertySOCKSProxy, (__bridge CFTypeRef _Null_unspecified)(proxyDict));
            if (!ok) {
                NSLog(@"failed to set proxy: %@", proxyDict);
            }
            return;
        }

        // last possibility: use a https proxy as a CONNECT proxy. This is an undocumented feature of CFNetwork.
        if ([proxyDict[(NSString *)kCFProxyTypeKey] isEqual:(NSString *)kCFProxyTypeHTTPS]) {
            NSDictionary *connectProxySettings = @{
                @"kCFStreamPropertyCONNECTProxyHost": proxyDict[(NSString *)kCFProxyHostNameKey],
                @"kCFStreamPropertyCONNECTProxyPort": proxyDict[(NSString *)kCFProxyPortNumberKey]
            };
            Boolean ok = CFReadStreamSetProperty(stream, CFSTR("kCFStreamPropertyCONNECTProxy"), (__bridge CFTypeRef _Null_unspecified)(connectProxySettings));
            if (!ok) {
                NSLog(@"failed to set proxy: %@", proxyDict);            }
            return;
        }

        NSLog(@"ignoring proxy %@", proxyDict);
    }
}

/// Gets the all proxies suitable for the given URL. It will resolve PAC proxies, so the result will not contain these.
+ (NSArray *)getProxyListForURL:(NSURL *)url error:(NSError **)errorP {

    NSDictionary *systemProxyConfig = CFBridgingRelease(CFNetworkCopySystemProxySettings());

    if (systemProxyConfig == nil) {
        if (errorP) {
            *errorP = [[NSError alloc] initWithDomain:PSProxyErrorDomain code:PSProxyErrorCodeNoSystemProxySettings userInfo:nil];
        }
        return nil;
    }

    // The system does not return any proxies for the ws/wss schemes, so we "translate" the URL to http/https.
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO];
    if ([components.scheme compare:@"wss" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
        components.scheme = @"https";
    } else if ([components.scheme compare:@"ws" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
        components.scheme = @"http";
    }
    NSURL *urlForProxySearch = components.URL;

    // Find a list of proxies suitable for the URL. This will consult the exception list etc.
    NSArray *proxies = CFBridgingRelease(CFNetworkCopyProxiesForURL((__bridge CFURLRef _Nonnull)(urlForProxySearch), (__bridge CFDictionaryRef _Nonnull)(systemProxyConfig)));

    NSMutableArray *resolvedProxies = [NSMutableArray new];

    // If the list contains a PAC entry, we need to resolve it.
    for (NSDictionary *proxyDict in proxies) {

        if ([proxyDict[(NSString *)kCFProxyTypeKey] isEqual:(NSString *)kCFProxyTypeAutoConfigurationURL]) {
            NSURL *pacURL = proxyDict[(NSString *)kCFProxyAutoConfigurationURLKey];
            if (!pacURL || ![pacURL isKindOfClass:[NSURL class]]) {
                NSLog(@"kCFProxyTypeAutoConfigurationURL missing url in dict");
                continue;
            }
            NSError *error = nil;
            NSArray *pacProxies = [self resolvePACProxiesForURL:urlForProxySearch pacURL:pacURL error:&error];
            if (!pacProxies) {
                NSLog(@"Failed to resolve PAC proxies: %@", error);
                continue;
            }
            [resolvedProxies addObjectsFromArray:pacProxies];
        } else {
            [resolvedProxies addObject:proxyDict];
        }
    }

    return resolvedProxies;
}

/// Downloads and parses the PAC file at the given URL. This method makes a blocking network call.
+ (nullable NSArray *)resolvePACProxiesForURL:(NSURL *)url pacURL:(NSURL *)pacURL error:(NSError **)errorP {
    CFTypeRef result;
    CFStreamClientContext context = { 0, &result, NULL, NULL, NULL };
    CFRunLoopSourceRef rls = CFNetworkExecuteProxyAutoConfigurationURL((__bridge CFURLRef _Nonnull)(pacURL), (__bridge CFURLRef _Nonnull)(url), ResultCallback, &context);
    if (rls == NULL) {
        if (errorP) {
            *errorP = [[NSError alloc] initWithDomain:PSProxyErrorDomain code:PSProxyErrorCodeNoRunLoopSource userInfo:nil];
        }
        return nil;
    }

    #define kPrivateRunLoopMode CFSTR("com.PocketSocket.PACProxy")

    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kPrivateRunLoopMode);
    CFRunLoopRunInMode(kPrivateRunLoopMode, 1.0e10, false);
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), rls, kPrivateRunLoopMode);

    // Once the runloop returns, we should have either an error result or a
    // proxies array result.  Do the appropriate thing with that result.

    assert(result != NULL);

    if ( CFGetTypeID(result) == CFErrorGetTypeID() ) {
        if (errorP) {
            *errorP = (NSError *)CFBridgingRelease(result);
        }
        return nil;
    } else if ( CFGetTypeID(result) == CFArrayGetTypeID() ) {
        return (NSArray *)CFBridgingRelease(result);
    } else {
        assert(false);
        if (errorP) {
            *errorP = [[NSError alloc] initWithDomain:PSProxyErrorDomain code:PSProxyErrorCodeInvalidPACResult userInfo:nil];
        }
        return nil;
    }
}

@end

/// "Inspired" by https://developer.apple.com/library/archive/samplecode/CFProxySupportTool/CFProxySupportTool.zip
static void ResultCallback(void * client, CFArrayRef proxies, CFErrorRef error)
    // Callback for CFNetworkExecuteProxyAutoConfigurationURL.  client is a
    // pointer to a CFTypeRef.  This stashes either error or proxies in that
    // location.
{
    CFTypeRef *        resultPtr;

    assert( (proxies != NULL) == (error == NULL) );

    resultPtr = (CFTypeRef *) client;
    assert( resultPtr != NULL);

    if (error != NULL) {
        *resultPtr = CFRetain(error);
    } else {
        *resultPtr = CFRetain(proxies);
    }
    CFRunLoopStop(CFRunLoopGetCurrent());
}
#else
// For now, don't do anything with proxies on iOS.
+ (void)applySuitableProxyForURL:(NSURL *)url toStream:(CFReadStreamRef)stream {}
#endif

