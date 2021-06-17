//
//  ShowLabel.m
//  BWAsyncLayer
//
//  Created by bairdweng on 2021/6/15.
//

#import "ShowLabel.h"
#import "BWAsyncLayer.h"
#import <CoreText/CoreText.h>
#import "BWTransaction.h"
@interface ShowLabel () <YYAsyncLayerDelegate> {
	NSString *_text;
	UIFont *_font;
}

@end
@implementation ShowLabel


- (void)setText:(NSString *)text {
	_text = text;
	[[BWTransaction transactionWithTarget:self selector:@selector(contentsNeedUpdated)] commit];
}

// 异步渲染
+ (Class)layerClass {
	return BWAsyncLayer.class;
}

- (nonnull YYAsyncLayerDisplayTask *)newAsyncDisplayTask {
	NSString *text = _text;
	YYAsyncLayerDisplayTask *task = [YYAsyncLayerDisplayTask new];
	task.willDisplay = ^(CALayer *layer) {
		layer.contentsScale = 2;
	};

	__weak typeof(&*self) weakself = self;
	task.display = ^(CGContextRef context, CGSize size, BOOL (^isCancelled)(void)) {
		if (isCancelled()) return;
		if (!text.length) return;
		[weakself drawInContext:context withSize:size];
	};
	task.didDisplay = ^(CALayer * _Nonnull layer, BOOL isFinish) {
	};
	return task;
}

- (void)contentsNeedUpdated {
	// do update
	[self.layer setNeedsDisplay];
}

- (void)drawInContext:(CGContextRef)context withSize:(CGSize)size {
	//设置context的ctm，用于适应core text的坐标体系
	CGContextSaveGState(context);
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);
	CGContextTranslateCTM(context, 0, size.height);
	CGContextScaleCTM(context, 1.0, -1.0);

	CGMutablePathRef path = CGPathCreateMutable();
	CGPathAddRect(path, NULL, CGRectMake(0, 0, size.width, size.height));
	NSMutableAttributedString *attri = [[NSMutableAttributedString alloc]initWithString:_text];
	[attri addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:10] range:NSMakeRange(0, _text.length)];

	CTFramesetterRef ctFramesetting = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)attri);
	CTFrameRef ctFrame = CTFramesetterCreateFrame(ctFramesetting, CFRangeMake(0, attri.length), path, NULL);
	//6.在CTFrame中绘制文本关联上下文
	CTFrameDraw(ctFrame, context);
	//7.释放变量
	CFRelease(path);
	CFRelease(ctFramesetting);
	CFRelease(ctFrame);

}

@end




