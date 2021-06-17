//
//  BWTransaction.m
//  BWAsyncLayer
//
//  Created by bairdweng on 2021/6/15.
//

#import "BWTransaction.h"

@interface BWTransaction ()
@property (nonatomic, strong) id target;
@property (nonatomic, assign) SEL selector;
@end


@implementation BWTransaction



static NSMutableSet *transactionSet = nil;

static void BWRunLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
	if (transactionSet.count == 0) return;
	NSSet *currentSet = transactionSet;
	transactionSet = [NSMutableSet new];
	// 集合中的方法分别执行
	[currentSet enumerateObjectsUsingBlock:^(BWTransaction *transaction, BOOL *stop) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	         [transaction.target performSelector:transaction.selector];
#pragma clang diagnostic pop
	 }];
}


static void BWTransactionSetup() {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		transactionSet = [NSMutableSet new];
		CFRunLoopRef runloop = CFRunLoopGetMain();
		CFRunLoopObserverRef observer;
		/**
		   主线程 RunLoop 循环即将进入休眠或者即将退出的时候。而该 oberver 的优先级是 0xFFFFFF。
		 */
		observer = CFRunLoopObserverCreate(CFAllocatorGetDefault(),
		                                   kCFRunLoopBeforeWaiting | kCFRunLoopExit,
		                                   true, // repeat
		                                   0xFFFFFF, // after CATransaction(2000000)
		                                   BWRunLoopObserverCallBack, NULL);
		CFRunLoopAddObserver(runloop, observer, kCFRunLoopCommonModes);
		CFRelease(observer);
	});
}

+ (BWTransaction *)transactionWithTarget:(id)target selector:(SEL)selector {
	if (!target || !selector) return nil;
	BWTransaction *t = [BWTransaction new];
	t.target = target;
	t.selector = selector;
	return t;
}

- (void)commit {
	if (!_target || !_selector) return;
	BWTransactionSetup();
	[transactionSet addObject:self];
}

/**
   NSObject 类默认的 hash 值为 10 进制的内存地址，这里作者将_selector和_target的内存地址进行一个位异或处理，意味着只要_selector和_target地址都相同时，hash 值就相同。
   这个目的是为了避免方法重复调用。
 */
- (NSUInteger)hash {
	long v1 = (long)((void *)_selector);
	long v2 = (long)_target;
	return v1 ^ v2;
}

- (BOOL)isEqual:(id)object {
	if (self == object) return YES;
	if (![object isMemberOfClass:self.class]) return NO;
	BWTransaction *other = object;
	return other.selector == _selector && other.target == _target;
}

@end
