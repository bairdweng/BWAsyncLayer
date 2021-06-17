//
//  BWAsyncLayer.h
//  BWAsyncLayer
//
//  Created by bairdweng on 2021/6/15.
//

#import <Foundation/Foundation.h>

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@class YYAsyncLayerDisplayTask;



NS_ASSUME_NONNULL_BEGIN

@interface BWAsyncLayer : CALayer

@property BOOL displaysAsynchronously;

@end


@protocol YYAsyncLayerDelegate <NSObject>
@required

- (YYAsyncLayerDisplayTask *)newAsyncDisplayTask;

@end



@interface YYAsyncLayerDisplayTask : NSObject

@property (nullable, nonatomic, copy) void (^willDisplay)(CALayer *layer);
@property (nullable, nonatomic, copy) void (^display)(CGContextRef context, CGSize size, BOOL (^isCancelled)(void));
@property (nullable, nonatomic, copy) void (^didDisplay)(CALayer *layer, BOOL finished);

@end





NS_ASSUME_NONNULL_END
