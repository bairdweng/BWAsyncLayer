//
//  BWSentinel.h
//  BWAsyncLayer
//
//  Created by bairdweng on 2021/6/15.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BWSentinel : NSObject

@property (readonly) int32_t value;
- (int32_t)increase;
@end

NS_ASSUME_NONNULL_END
