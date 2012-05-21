//
//  NodeWrapper.m
//  node-shell
//
//  Created by Joel Brandt on 5/21/12.
//  Copyright (c) 2012 Adobe Systems. All rights reserved.
//

#import "NodeWrapper.h"

@implementation NodeWrapper

-(id) init {
    if (self = [super init]) {
        commandBuffer = [[NSMutableString alloc] init];
    }
    return self;
}

-(void)dealloc {
    [self stop];
    [task release];
    [commandBuffer release];
    [super dealloc];
}

-(void) start {
    NSString *appPath = [[NSBundle mainBundle] bundlePath];
    NSString *nodePath = [appPath stringByAppendingString:@"/Contents/Resources/node-executable"];
    NSString *nodeJSPath = [appPath stringByAppendingString:@"/Contents/Resources/server.js"];
    
    NSLog(@"Here's where node is: %@\n", nodePath);
    
    task = [[NSTask alloc] init];
    [task setStandardOutput: [NSPipe pipe]];
    [task setStandardInput: [NSPipe pipe]];
    // [task setStandardError: [task standardOutput]];  // enable to pipe stderr to stdout
    
    
    [task setLaunchPath: nodePath];
    
    NSArray *arguments = [NSArray arrayWithObject:nodeJSPath];
    [task setArguments: arguments];
    
    // Here we register as an observer of the NSFileHandleReadCompletionNotification, which lets
    // us know when there is data waiting for us to grab it in the task's file handle (the pipe
    // to which we connected stdout and stderr above).  -receiveData: will be called when there
    // is data waiting.  The reason we need to do this is because if the file handle gets
    // filled up, the task will block waiting to send data and we'll never get anywhere.
    // So we have to keep reading data from the file handle as we go.
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(receiveData:) 
                                                 name: NSFileHandleReadCompletionNotification 
                                               object: [[task standardOutput] fileHandleForReading]];
    // We tell the file handle to go ahead and read in the background asynchronously, and notify
    // us via the callback registered above when we signed up as an observer.  The file handle will
    // send a NSFileHandleReadCompletionNotification when it has data that is available.
    [[[task standardOutput] fileHandleForReading] readInBackgroundAndNotify];
    
    [task launch];
    
}
-(void) stop {
    NSLog(@"Shutting down node process\n");
    
    NSData *data;
    
    // It is important to clean up after ourselves so that we don't leave potentially deallocated
    // objects as observers in the notification center; this can lead to crashes.
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object: [[task standardOutput] fileHandleForReading]];
    
    // Make sure the task has actually stopped!
    [task terminate];
    
    while ((data = [[[task standardOutput] fileHandleForReading] availableData]) && [data length])
    {
        NSLog(@"app got some data: %@\n", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
    }
    [self parseCommandBuffer];
}

-(void) receiveData: (NSNotification *)aNotification {
    NSData *data = [[aNotification userInfo] objectForKey:NSFileHandleNotificationDataItem];
    // If the length of the data is zero, then the task is basically over - there is nothing
    // more to get from the handle so we may as well shut down.
    if ([data length]) {
        // Send the data on to the controller; we can't just use +stringWithUTF8String: here
        // because -[data bytes] is not necessarily a properly terminated string.
        // -initWithData:encoding: on the other hand checks -[data length]
        
        NSString *dataString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        
        NSLog(@"app got some data: %@\n", dataString);
        
        [commandBuffer appendString:dataString];
        
        [self parseCommandBuffer];
        
    } else {
        // We're finished here
        [self stop];
    }
    
    // we need to schedule the file handle go read more data in the background again.
    [[aNotification object] readInBackgroundAndNotify];  
}

-(void) parseCommandBuffer {
    NSRange range = [commandBuffer rangeOfString:@"\n\n"];
    while (range.location != NSNotFound) {
        // change range to go from start of buffer to start of new lines
        range.length = range.location;
        range.location = 0;
        
        // remove the command from buffer, then process it
        NSString *command = [commandBuffer substringWithRange:range];
        range.length = range.length + 2; // now the range goes to end of new lines, because we want to remove those too
        [commandBuffer deleteCharactersInRange:range];
        [self processCommand:command];
        
        // search again
        range = [commandBuffer rangeOfString:@"\n\n"];
    }
}

-(void) processCommand: (NSString *)command {
    NSArray *args = [command componentsSeparatedByString: @"|"];
    if ([args count] > 0) {
        NSString *name = [args objectAtIndex:0];
        if ([name isEqualToString:@"ping"]) {
            NSLog(@"got a ping");
            [self sendCommand:@"pong", @"asdf", @"fdsa", nil];
        } else {
            NSLog(@"unknown command: %@", name);
        }
        
    } else {
        NSLog(@"empty command");
    }
}

-(void) sendCommand: (NSString *)command, ... {
    NSMutableString *fullCommand = [[[NSMutableString alloc] initWithString:command] autorelease];
    
    va_list args;
    va_start(args, command);
    for (NSString *arg = arg = va_arg(args, NSString*); arg != nil; arg = va_arg(args, NSString*))
    {
        [fullCommand appendString:@"|"];
        [fullCommand appendString:arg];
    }
    va_end(args);
    [fullCommand appendString:@"\n\n"];
    [self sendData:fullCommand];
}

-(void) sendData: (NSString *)dataString {
    const char * utf8DataString = [dataString UTF8String];
    NSData *data = [[[NSData alloc] initWithBytes:utf8DataString length:strlen(utf8DataString)] autorelease];
    [[[task standardInput] fileHandleForWriting] writeData:data];
}

@end