//
//  ViewController.m
//  BWAsyncLayer
//
//  Created by bairdweng on 2021/6/15.
//

#import "ViewController.h"
#import "ShowLabel.h"
@interface ViewController ()
@property(nonatomic, strong) ShowLabel *showLabel;
@end

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];


	[self.view addSubview:self.showLabel];
	self.showLabel.frame = CGRectMake(0, 0, 200, 50);
	self.showLabel.center = self.view.center;
	self.showLabel.text = @"我是异步渲染，速度可能会很快哦";
	// Do any additional setup after loading the view.
}


-(ShowLabel *)showLabel {
	if (!_showLabel) {
		_showLabel = [ShowLabel new];
		_showLabel.font = [UIFont systemFontOfSize:19];
	}
	return _showLabel;
}

@end
