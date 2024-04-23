//==============================================================================
/**
@file       MyStreamDeckPlugin.m

@brief      A Stream Deck plugin displaying the number of reminders due today in Apple's Reminders

@copyright  (c) 2018, Corsair Memory, Inc.
			This source code is licensed under the MIT-style license found in the LICENSE file.

**/
//==============================================================================

#import "MyStreamDeckPlugin.h"

#import "ESDSDKDefines.h"
#import "ESDConnectionManager.h"
#import "ESDUtilities.h"
#import <AppKit/AppKit.h>


// Refresh the due count every 60s
#define REFRESH_DUE_COUNT_TIME_INTERVAL		60.0


// Size of the images
#define IMAGE_SIZE	144



// MARK: - Utility methods


//
// Utility function to get the fullpath of an resource in the bundle
//
static NSString * GetResourcePath(NSString *inFilename)
{
	NSString *outPath = nil;
	
	if([inFilename length] > 0)
	{
		NSString * bundlePath = [ESDUtilities pluginPath];
		if(bundlePath != nil)
		{
			outPath = [bundlePath stringByAppendingPathComponent:inFilename];
		}
	}
	
	return outPath;
}


//
// Utility function to create a CGContextRef
//
static CGContextRef CreateBitmapContext(CGSize inSize)
{
	CGFloat bitmapBytesPerRow = inSize.width * 4;
	CGFloat bitmapByteCount = (bitmapBytesPerRow * inSize.height);
	
	void *bitmapData = calloc(bitmapByteCount, 1);
	if(bitmapData == NULL)
	{
		return NULL;
	}
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(bitmapData, inSize.width, inSize.height, 8, bitmapBytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast);
	if(context == NULL)
	{
		CGColorSpaceRelease(colorSpace);
		free(bitmapData);
		return NULL;
	}
	else
	{
		CGColorSpaceRelease(colorSpace);
		return context;
	}
}

//
// Utility method that takes the path of an image and create a base64 encoded string
//
static NSString * CreateBase64EncodedString(NSString *inImagePath)
{
	NSString *outBase64PNG = nil;
	
	NSImage* image = [[NSImage alloc] initWithContentsOfFile:inImagePath];
	if(image != nil)
	{
		// Find the best CGImageRef
		CGSize iconSize = CGSizeMake(IMAGE_SIZE, IMAGE_SIZE);
		NSRect theRect = NSMakeRect(0, 0, iconSize.width, iconSize.height);
		CGImageRef imageRef = [image CGImageForProposedRect:&theRect context:NULL hints:nil];
		if(imageRef != NULL)
		{
			// Create a CGContext
			CGContextRef context = CreateBitmapContext(iconSize);
			if(context != NULL)
			{
				// Draw the app icon
				CGContextDrawImage(context, theRect, imageRef);
				
				// Generate the final image
				CGImageRef completeImage = CGBitmapContextCreateImage(context);
				if(completeImage != NULL)
				{
					// Export the image to PNG
					CFMutableDataRef pngData = CFDataCreateMutable(kCFAllocatorDefault, 0);
					if(pngData != NULL)
					{
						CGImageDestinationRef destinationRef = CGImageDestinationCreateWithData(pngData, kUTTypePNG, 1, NULL);
						if (destinationRef != NULL)
						{
							CGImageDestinationAddImage(destinationRef, completeImage, nil);
							if (CGImageDestinationFinalize(destinationRef))
							{
								NSString *base64PNG = [(__bridge NSData *)pngData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithCarriageReturn];
								if([base64PNG length] > 0)
								{
									outBase64PNG = [NSString stringWithFormat:@"data:image/png;base64,%@\">", base64PNG];
								}
							}
							
							CFRelease(destinationRef);
						}
						
						CFRelease(pngData);
					}
					
					CFRelease(completeImage);
				}
				
				CFRelease(context);
			}
		}
	}
	
	return outBase64PNG;
}


// MARK: - MyStreamDeckPlugin

@interface MyStreamDeckPlugin ()

// Tells us if Reminders is running
@property (assign) BOOL isRemindersRunning;

// A timer fired each minute to update the number of due reminders from Apple's Reminders

@property (strong) NSTimer *refreshTimer;

// The list of visible contexts
@property (strong) NSMutableArray *knownContexts;

// The icon encoded in base64
@property (strong) NSString *base64RemindersconString;

// The  icon with a badge encoded in base64
@property (strong) NSString *base64RemindersBadgeIconString;

@end


@implementation MyStreamDeckPlugin



// MARK: - Setup the instance variables if needed

- (void)setupIfNeeded
{
	// Create the array of known contexts
	if(_knownContexts == nil)
	{
		_knownContexts = [[NSMutableArray alloc] init];
	}
	
	// Create a timer to repetivily update the actions
	if(_refreshTimer == nil)
	{
		_refreshTimer = [NSTimer scheduledTimerWithTimeInterval:REFRESH_DUE_COUNT_TIME_INTERVAL target:self selector:@selector(refreshDueCount) userInfo:nil repeats:YES];
	}
	
	if(_base64RemindersconString == nil)
	{
		_base64RemindersconString = CreateBase64EncodedString(GetResourcePath(@"Remindersicon.png"));
	}
	
	if(_base64RemindersBadgeIconString == nil)
	{
		_base64RemindersBadgeIconString = CreateBase64EncodedString(GetResourcePath(@"RemindersBadgeIcon.png"));
	}
}


// MARK: - Refresh all actions

- (void)refreshDueCount
{
    if(!self.isRemindersRunning)
	{
		return;
	}
	
	// Execute the NumberOfDueReminders.scpt Applescript tp retrieve the number of due reminders
	int numberOfDueReminders = -1;
	NSURL* url = [NSURL fileURLWithPath:GetResourcePath(@"NumberOfDueReminders.scpt")];
	
	NSDictionary *errors = nil;
	NSAppleScript* appleScript = [[NSAppleScript alloc] initWithContentsOfURL:url error:&errors];
	if(appleScript != nil)
	{
		NSAppleEventDescriptor *eventDescriptor = [appleScript executeAndReturnError:&errors];
		if(eventDescriptor != nil && [eventDescriptor descriptorType] != kAENullEvent)
		{
			numberOfDueReminders = (int)[eventDescriptor int32Value];
		}
	}
	
	// Update each known context with the new value
	for(NSString *context in self.knownContexts)
	{
		if(numberOfDueReminders > 0)
		{
			[self.connectionManager setImage:self.base64RemindersBadgeIconString withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
			[self.connectionManager setTitle:[NSString stringWithFormat:@"%d", numberOfDueReminders] withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
		}
		else if(numberOfDueReminders == 0)
		{
			[self.connectionManager setImage:self.base64RemindersconString withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
			[self.connectionManager setTitle:@" " withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
		}
		else
		{
			[self.connectionManager setImage:self.base64RemindersconString withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
			[self.connectionManager setTitle:nil withContext:context withTarget:kESDSDKTarget_HardwareAndSoftware];
			[self.connectionManager showAlertForContext:context];
		}
	}
}


// MARK: - Events handler


- (void)keyDownForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
	// On key press, open the Reminders.app application
	NSURL* url = [NSURL fileURLWithPath:GetResourcePath(@"OpenReminders.scpt")];
	
	NSDictionary *errors = nil;
	NSAppleScript* appleScript = [[NSAppleScript alloc] initWithContentsOfURL:url error:&errors];
	if(appleScript != nil)
	{
		[appleScript executeAndReturnError:&errors];
	}
}

- (void)keyUpForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
	// Nothing to do
}

- (void)willAppearForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
	// Set up the instance variables if needed
	[self setupIfNeeded];
	
	// Add the context to the list of known contexts
	[self.knownContexts addObject:context];
	
	// Explicitely refresh the number of due reminders
	[self refreshDueCount];
}

- (void)willDisappearForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
	// Remove the context from the list of known contexts
	[self.knownContexts removeObject:context];
}

- (void)deviceDidConnect:(NSString *)deviceID withDeviceInfo:(NSDictionary *)deviceInfo
{
	// Nothing to do
}

- (void)deviceDidDisconnect:(NSString *)deviceID
{
	// Nothing to do
}

- (void)applicationDidLaunch:(NSDictionary *)applicationInfo
{
	if([applicationInfo[@kESDSDKPayloadApplication] isEqualToString:@"com.apple.reminders"])
	{
        self.isRemindersRunning = YES;
		
		// Explicitely refresh the number of due reminders
		[self refreshDueCount];
	}
}

- (void)applicationDidTerminate:(NSDictionary *)applicationInfo
{
	if([applicationInfo[@kESDSDKPayloadApplication] isEqualToString:@"com.apple.reminders"])
	{
        self.isRemindersRunning = NO;
	}
}

@end
