//
//  BWTransaction.h
//  BWAsyncLayer
//
//  Created by bairdweng on 2021/6/15.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BWTransaction : NSObject

+ (BWTransaction *)transactionWithTarget:(id)target selector:(SEL)selector;

- (void)commit;

@end

NS_ASSUME_NONNULL_END
