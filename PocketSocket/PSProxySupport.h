//  Created by Matthias Keiser on 23/02/2021.
//  Copyright © 2021 Zwopple Limited. All rights reserved.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PSProxySupport : NSObject
/// Reads the system proxy settings and applies the first suitable proxy to the stream.
/// This is not perfect, it would be better to not just try the first proxy in the list, but try each one until one works. However it is
/// not clear what would be the error conditions on which one tries the next proxy, vs just a "regular" network problem.
/// Note: this method might make a synchronous network call, so it should only be called on a background thread.
+ (void)applySuitableProxyForURL:(NSURL *)url toStream:(CFReadStreamRef)stream;
@end

NS_ASSUME_NONNULL_END
