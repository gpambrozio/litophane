//
//  ViewController.m
//  litophane
//
//  Created by Gustavo Ambrozio on 10/22/15.
//  Copyright © 2015 Gustavo Ambrozio. All rights reserved.
//

#import <ifaddrs.h>
#import <arpa/inet.h>

#import "ViewController.h"

#import "ColorPickerImageView.h"
#import "ColorPickerLens.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet ColorPickerImageView *colorPicker;
@property (weak, nonatomic) IBOutlet ColorPickerLens *pickerLens;
@property (weak, nonatomic) IBOutlet UILabel *labelIP;
@property (weak, nonatomic) IBOutlet UILabel *labelStatus;
@property (weak, nonatomic) IBOutlet UISlider *sliderBrightness;
@property (weak, nonatomic) IBOutlet UIDatePicker *wakeTimePicker;

@property (nonatomic, strong) NSString *litophaneIP;

@property (nonatomic, readwrite, strong) NSOperationQueue *discoveryQueue;
@property (nonatomic, readwrite, strong) NSURLSession *urlSession;
@property (nonatomic, readwrite, strong) NSURLSession *discoveryURLSession;

@property (nonatomic, readwrite, assign) NSTimeInterval lastCommand;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.discoveryQueue = [[NSOperationQueue alloc] init];
    self.discoveryQueue.maxConcurrentOperationCount = 50;

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.HTTPMaximumConnectionsPerHost = 1;
    self.urlSession = [NSURLSession sessionWithConfiguration:configuration];

    self.litophaneIP = @"litho.local";
}

- (void)setLitophaneIP:(NSString *)litophaneIP {
    _litophaneIP = litophaneIP;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.labelIP.text = [NSString stringWithFormat:@"IP: %@", self.litophaneIP];
    });
}

- (void)setStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.labelStatus.text = status;
    });
    NSLog(@"Status: %@", status);
}

- (void)sendCommand:(NSString *)command {
    if (!self.litophaneIP) {
        return;
    }

#define MIN_TIME_FOR_COMMANDS   1.5

    NSTimeInterval diff = [NSDate timeIntervalSinceReferenceDate] - self.lastCommand;
    diff = MAX(0.0, MIN_TIME_FOR_COMMANDS - diff);

    self.lastCommand = [NSDate timeIntervalSinceReferenceDate] + diff;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(diff * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSURLSessionDataTask *task = [self.urlSession dataTaskWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@/%@", self.litophaneIP, command]]
                                                    completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                                                        if (data) {
                                                            NSString *response = [[NSString alloc] initWithData:data
                                                                                                       encoding:NSUTF8StringEncoding];

                                                            if ([response hasPrefix:@"OK"]) {
                                                                [self setStatus:[NSString stringWithFormat:@"OK for command %@", command]];
                                                            } else {
                                                                [self setStatus:[NSString stringWithFormat:@"Weird response for command %@: %@", command, response]];
                                                            }
                                                        }

                                                        else if (error) {
                                                            [self setStatus:[NSString stringWithFormat:@"Got error for command %@: %@", command, error]];
                                                        }
                                                    }];
        [task resume];
    });
}

// From http://stackoverflow.com/a/7073029
- (NSString *)getIPAddress {
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;

    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }

    // Free memory
    freeifaddrs(interfaces);
    return address;
}

- (void)checkQueueAndIP {
    if (self.litophaneIP) {
        return;
    }

    if (self.discoveryQueue.operationCount == 0) {
        [self setStatus:@"Litophane not found. Trying again"];
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self checkQueueAndIP];
        });
    }
}

- (IBAction)brightnessChanged:(UISlider *)sender {
    [self sendCommand:[NSString stringWithFormat:@"b?a=%.0f", sender.value]];
}

- (IBAction)rainbow:(id)sender {
    [self sendCommand:@"r"];
}

- (IBAction)onOff:(id)sender {
    [self sendCommand:@"p"];
}

- (IBAction)setWakeTime:(id)sender {
    NSDate *date = self.wakeTimePicker.date;
    NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *comps = [gregorian components:NSCalendarUnitHour | NSCalendarUnitMinute
                                           fromDate:date];
    long seconds = comps.hour * 3600 + comps.minute * 60;
    [self sendCommand:[NSString stringWithFormat:@"w?a=%ld", seconds]];
}

#pragma mark - ColorPickerImageViewDelegate

- (void)picker:(ColorPickerImageView*)picker pickedColor:(UIColor*)color {
    [UIView animateWithDuration:0.5
                     animations:^{
                         self.pickerLens.alpha = 0.0;
                     }];

    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    long fullColor = ((int)(r*255)) << 16 | ((int)(g*255)) << 8 | (int)(b*255);
    [self sendCommand:[NSString stringWithFormat:@"c?a=%ld", fullColor]];
}

- (void)picker:(ColorPickerImageView*)picker touchedColor:(UIColor*)color inPoint:(CGPoint)point {
    if (color) {
        if (self.pickerLens.alpha == 0.0f)
            [UIView animateWithDuration:0.2
                             animations:^{
                                 self.pickerLens.alpha = 1.0;
                             }];

        point = [self.view convertPoint:point fromView:picker];
        self.pickerLens.frame = CGRectMake(point.x - _pickerLens.frame.size.width / 2.0f,
                                           point.y - _pickerLens.frame.size.height,
                                           self.pickerLens.frame.size.width,
                                           self.pickerLens.frame.size.height);
        self.pickerLens.color = color;
    } else {
        [UIView animateWithDuration:0.2
                         animations:^{
                             self.pickerLens.alpha = 0.0;
                         }];
    }
}

@end
