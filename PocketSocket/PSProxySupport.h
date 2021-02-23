//  Created by Matthias Keiser on 23/02/2021.
//  Copyright © 2021 Zwopple Limited. All rights reserved.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PSProxySupport : NSObject
/// Reads the system proxy settings and applies the first suitable proxy to the stream.
/// Note: this method might make a synchronous network call, so it should only be called on a background thread.
+ (void)applySuitableProxyForURL:(NSURL *)url toStream:(CFReadStreamRef)stream;
@end

NS_ASSUME_NONNULL_END
