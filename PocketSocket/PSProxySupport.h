//  Created by Matthias Keiser on 23/02/2021.
//  Copyright © 2021 Zwopple Limited. All rights reserved.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PSProxySupport : NSObject
+ (void)applySuitableProxyForURL:(NSURL *)url toStream:(CFReadStreamRef)stream;
@end

NS_ASSUME_NONNULL_END
