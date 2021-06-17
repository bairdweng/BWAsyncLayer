# 异步渲染的机制

异步渲染，这里主要基于YYAsyncLayer的源码进行分析。

##### 1. BWSentinel 计数器

> 该类主要采用了OSAtomicIncrement32，会对自身的值进行自增且是线程安全的，相对于加锁会更加地优雅。

```objective-c
- (int32_t)increase {
	return OSAtomicIncrement32(&_value);
}
```

##### 2. BWTransaction 事务管理

> 主要是记录一系列事件，并且在合适的机会调用这些事件。

1. 监听主线程的Runloop，RunLoop 循环即将进入休眠或者即将退出的时候执行任务，这里有一个优先级的操作，将自定义的绘制逻辑装入transactionSet，然后在 Runloop 要结束时统一执行，Runloop 回调的优先级避免与系统绘制逻辑竞争资源，使用NSSet合并了一次 Runloop 周期多次的绘制请求为一个。

   ```objective-c
   		CFRunLoopRef runloop = CFRunLoopGetMain();
   		CFRunLoopObserverRef observer;
   		observer = CFRunLoopObserverCreate(CFAllocatorGetDefault(),
   		                                   kCFRunLoopBeforeWaiting | kCFRunLoopExit,
   		                                   true, // repeat
   		                                   0xFFFFFF, // after CATransaction(2000000)
   		                                   BWRunLoopObserverCallBack, NULL);
   		CFRunLoopAddObserver(runloop, observer, kCFRunLoopCommonModes);
   		CFRelease(observer);
   ```

2. Hash处理，_selector和_target的内存地址进行一个位异或处理，意味着只要_selector和_target地址都相同时，hash 值就相同，其目的是避免方法重复调用

   ```objective-c
   - (NSUInteger)hash {
   	long v1 = (long)((void *)_selector);
   	long v2 = (long)_target;
   	return v1 ^ v2;
   }
   ```

##### 3. BWAsyncLayer

  1. 重写绘制的方法

      ```objective-c
      - (void)setNeedsDisplay {
          [self _cancelAsyncDisplay];
          [super setNeedsDisplay];
      }
      - (void)display {
          super.contents = super.contents;
          [self _displayAsync:_displaysAsynchronously];
      }
      ```

   2. 异步绘制的核心

      ```objective-c
      ...
      dispatch_async(YYAsyncLayerGetDisplayQueue(), ^{
              UIGraphicsBeginImageContextWithOptions(size, opaque, scale);
              CGContextRef context = UIGraphicsGetCurrentContext();
              task.display(context, size, isCancelled);
              UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
              UIGraphicsEndImageContext();
              dispatch_async(dispatch_get_main_queue(), ^{
                  self.contents = (__bridge id)(image.CGImage);
              });
          }];
 ...
      ```
      
  3. 及时结束无用绘制，当判断计数器不是当前的值的时候，return绘制请求，这种场景通常是在tableview快速滑动的时候。

      ```objective-c
      YYSentinel *sentinel = _sentinel;
      int32_t value = sentinel.value;
      BOOL (^isCancelled)(void) = ^BOOL() {
        return value != sentinel.value;
      };
      
      ...
      - (void)setNeedsDisplay {
          [self _cancelAsyncDisplay];
          [super setNeedsDisplay];
      }
      - (void)_cancelAsyncDisplay {
          [_sentinel increase];
      }
      ```

##### 4. 异步线程的管理

1. 队列数量跟处理器数量相同

   > 过多的线程并行并不是正真的并发，可能线程数超过处理器核心的时候会通过切换上下文来带到目的，这并不是更加高效的做法。
   
   ```objective-c
   		#define MAX_QUEUE_COUNT 16
       queueCount = (int)[NSProcessInfo processInfo].activeProcessorCount;
   		queueCount = queueCount < 1 ? 1 : queueCount > MAX_QUEUE_COUNT ? MAX_QUEUE_COUNT : queueCount;
   ```
   
2. 采用串行队列

   > 首先为什么要使用串行队列而不使用并行，采用并行的话，开启的线程数量无法保证。

   ```objective-c
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
   ```

3. 轮训返回队列

   ```objective-c
   	int32_t cur = OSAtomicIncrement32(&counter);
   	if (cur < 0) cur = -cur;
   	return queues[(cur) % queueCount];
   ```

##### 5. 总结

1. 常规的Calayer绘制通常经过以下几个流程 setNeedsDisplay display 的过程，而这些方法都是在主线程操作的。一旦绘制的任务过于繁杂，则会发生卡顿。
2. 所有需要在Layer这几个方法中实现异步渲染，首先绘制核心UIGraphicsBeginImageContextWithOptions...是线程安全的，可以放在dispatch_async(...)中执行。
3. 在明确知道几个方法后，接下来是构建异步渲染的任务机制，要解决一下几个问题，什么时候执行异步渲染，如何更好利用多核，如何避免重复绘制。
4. 对于执行时机，我们可以看到主线程有个监听，当Runloop空闲的时候执行了任务，这有效提高绘制性能，不阻塞主线程的操作。
5. 利用多核，可以看到没有用并行队列，而是创建可与处理器核心数相同的串行队列，并轮询使用它。这有效的避免创建过多的线程，避免的线程上下文切换导致不必要的CPU开销。
6. 利用自增值判断任务绘制是否取消，极大的避免重复绘制。

 