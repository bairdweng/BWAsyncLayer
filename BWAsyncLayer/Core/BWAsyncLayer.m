//
//  BWAsyncLayer.m
//  BWAsyncLayer
//
//  Created by bairdweng on 2021/6/15.
//

#import "BWAsyncLayer.h"
#import <libkern/OSAtomic.h>
#import "BWSentinel.h"

#pragma mark -----C函数------

/**
   并行一定并发，并发不一定并行。在单核设备上，CPU通过频繁的切换上下文来运行不同的线程，速度足够快以至于我们看起来它是‘并行’处理的，然而我们只能说这种情况是并发而非并行。例如：你和两个人一起百米赛跑，你一直在不停的切换跑道，而其他两人就在自己的跑道上，最终，你们三人同时到达了终点。我们把跑道看做任务，那么，其他两人就是并行执行任务的，而你只能的说是并发执行任务。
   所以，实际上一个 n 核设备同一时刻最多能 并行 执行 n 个任务，也就是最多有 n 个线程是相互不竞争 CPU 资源的。
 */
static dispatch_queue_t YYAsyncLayerGetDisplayQueue() {
//最大队列数量
#define MAX_QUEUE_COUNT 16
	static int queueCount;
	//使用栈区的数组存储队列
	static dispatch_queue_t queues[MAX_QUEUE_COUNT];
	static dispatch_once_t onceToken;
	static int32_t counter = 0;
	dispatch_once(&onceToken, ^{
		//要点 1 ：串行队列数量和处理器数量相同
		queueCount = (int)[NSProcessInfo processInfo].activeProcessorCount;
		queueCount = queueCount < 1 ? 1 : queueCount > MAX_QUEUE_COUNT ? MAX_QUEUE_COUNT : queueCount;
		//要点 2 ：创建串行队列，设置优先级
		if ([UIDevice currentDevice].systemVersion.floatValue >= 8.0) {
			for (NSUInteger i = 0; i < queueCount; i++) {
				dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
				queues[i] = dispatch_queue_create("com.ibireme.yykit.render", attr);
			}
		} else {
			for (NSUInteger i = 0; i < queueCount; i++) {
				queues[i] = dispatch_queue_create("com.ibireme.yykit.render", DISPATCH_QUEUE_SERIAL);
				dispatch_set_target_queue(queues[i], dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
			}
		}
	});
	//要点 3 ：轮询返回队列
	int32_t cur = OSAtomicIncrement32(&counter);
	if (cur < 0) cur = -cur;
	return queues[(cur) % queueCount];
#undef MAX_QUEUE_COUNT
}

static dispatch_queue_t YYAsyncLayerGetReleaseQueue() {
	return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
}

@implementation YYAsyncLayerDisplayTask
@end


@implementation BWAsyncLayer {
	BWSentinel *_sentinel;
}

#pragma mark - Override
+ (id)defaultValueForKey:(NSString *)key {
	if ([key isEqualToString:@"displaysAsynchronously"]) {
		return @(YES);
	} else {
		return [super defaultValueForKey:key];
	}
}

- (instancetype)init {
	self = [super init];
	static CGFloat scale; //global
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		scale = [UIScreen mainScreen].scale;
	});
	self.contentsScale = scale;
	_sentinel = [BWSentinel new];
	_displaysAsynchronously = YES;
	return self;
}

- (void)dealloc {
	[_sentinel increase];
}

- (void)setNeedsDisplay {
	[self _cancelAsyncDisplay];
	[super setNeedsDisplay];
}

- (void)display {
	super.contents = super.contents;
	[self _displayAsync:_displaysAsynchronously];
}



#pragma mark - Private
- (void)_displayAsync:(BOOL)async {
	__strong id<YYAsyncLayerDelegate> delegate = (id)self.delegate;
	YYAsyncLayerDisplayTask *task = [delegate newAsyncDisplayTask];
	if (!task.display) {
		if (task.willDisplay) task.willDisplay(self);
		self.contents = nil;
		if (task.didDisplay) task.didDisplay(self, YES);
		return;
	}
	if (async) {
		if (task.willDisplay) task.willDisplay(self);
		/**
		   这就是YYSentinel计数类起作用的时候了，这里用一个局部变量value来保持当前绘制逻辑的计数值，保证其他线程改变了全局变量_sentinel的值也不会影响当前的value；若当前value不等于最新的_sentinel .value时，说明当前绘制任务已经被放弃，就需要及时的做返回逻辑。
		 */
		BWSentinel *sentinel = _sentinel;
		int32_t value = sentinel.value;
		BOOL (^isCancelled)(void) = ^BOOL () {
			return value != sentinel.value;
		};
		CGSize size = self.bounds.size;
		BOOL opaque = self.opaque;
		CGFloat scale = self.contentsScale;
		CGColorRef backgroundColor = (opaque && self.backgroundColor) ? CGColorRetain(self.backgroundColor) : NULL;
		if (size.width < 1 || size.height < 1) {
			CGImageRef image = (__bridge_retained CGImageRef)(self.contents);
			self.contents = nil;
			if (image) {
				dispatch_async(YYAsyncLayerGetReleaseQueue(), ^{
					CFRelease(image);
				});
			}
			if (task.didDisplay) task.didDisplay(self, YES);
			CGColorRelease(backgroundColor);
			return;
		}
		// 核心代码
		dispatch_async(YYAsyncLayerGetDisplayQueue(), ^{
			if (isCancelled()) {
				CGColorRelease(backgroundColor);
				return;
			}
			UIGraphicsBeginImageContextWithOptions(size, opaque, scale);
			CGContextRef context = UIGraphicsGetCurrentContext();
			if (opaque) {
				CGContextSaveGState(context); {
					if (!backgroundColor || CGColorGetAlpha(backgroundColor) < 1) {
						CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
						CGContextAddRect(context, CGRectMake(0, 0, size.width * scale, size.height * scale));
						CGContextFillPath(context);
					}
					if (backgroundColor) {
						CGContextSetFillColorWithColor(context, backgroundColor);
						CGContextAddRect(context, CGRectMake(0, 0, size.width * scale, size.height * scale));
						CGContextFillPath(context);
					}
				} CGContextRestoreGState(context);
				CGColorRelease(backgroundColor);
			}
			task.display(context, size, isCancelled);
			if (isCancelled()) {
				UIGraphicsEndImageContext();
				dispatch_async(dispatch_get_main_queue(), ^{
					if (task.didDisplay) task.didDisplay(self, NO);
				});
				return;
			}
			UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
			if (isCancelled()) {
				dispatch_async(dispatch_get_main_queue(), ^{
					if (task.didDisplay) task.didDisplay(self, NO);
				});
				return;
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				if (isCancelled()) {
					if (task.didDisplay) task.didDisplay(self, NO);
				} else {
					self.contents = (__bridge id)(image.CGImage);
					if (task.didDisplay) task.didDisplay(self, YES);
				}
			});
		});
	} else {
		[_sentinel increase];
		if (task.willDisplay) task.willDisplay(self);
		UIGraphicsBeginImageContextWithOptions(self.bounds.size, self.opaque, self.contentsScale);
		CGContextRef context = UIGraphicsGetCurrentContext();
		if (self.opaque) {
			CGSize size = self.bounds.size;
			size.width *= self.contentsScale;
			size.height *= self.contentsScale;
			CGContextSaveGState(context); {
				if (!self.backgroundColor || CGColorGetAlpha(self.backgroundColor) < 1) {
					CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
					CGContextAddRect(context, CGRectMake(0, 0, size.width, size.height));
					CGContextFillPath(context);
				}
				if (self.backgroundColor) {
					CGContextSetFillColorWithColor(context, self.backgroundColor);
					CGContextAddRect(context, CGRectMake(0, 0, size.width, size.height));
					CGContextFillPath(context);
				}
			} CGContextRestoreGState(context);
		}
		task.display(context, self.bounds.size, ^{return NO;});
		UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		self.contents = (__bridge id)(image.CGImage);
		if (task.didDisplay) task.didDisplay(self, YES);
	}

}
// 提交绘制时，计数器+1，在异步的绘制任务时会执行取消的操作。
- (void)_cancelAsyncDisplay {
	[_sentinel increase];
}


@end
