//
//  Xcproj.m
//  xcproj
//
//  Created by Cédric Luthi on 07.02.11.
//  Copyright Cédric Luthi 2011. All rights reserved.
//

#import "Xcproj.h"

#import <dlfcn.h>
#import <objc/runtime.h>

@implementation Xcproj

+ (void) initializeXcproj
{
	NSLog(@"started");
	
	NSBundle *bundle = [NSBundle bundleWithPath:@"/Applications/Xcode.app/Contents/Frameworks/IDEFoundation.framework"];
	NSParameterAssert(bundle && [bundle loadAndReturnError:nil]);

	NSLog(@"loaded frameworks");

	BOOL(*IDEInitialize)(int initializationOptions, NSError **error) = dlsym(RTLD_DEFAULT, "IDEInitialize");
	NSCParameterAssert(IDEInitialize(1, nil));

	NSLog(@"initialized frameworks");
}

// MARK: - Options

- (void) application:(DDCliApplication *)app willParseOptions:(DDGetoptLongParser *)optionsParser {
}

- (void) setProject:(NSString *)projectName
{
	if (![projectName.lastPathComponent isEqualToString:@"project.pbxproj"]) {
		projectName = [projectName stringByAppendingPathComponent:@"project.pbxproj"];
	}

	NSLog(@"%@", projectName);
	NSData *data = [NSData dataWithContentsOfFile:projectName];
	NSError *error = nil;
//	id obj = [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:&error];
	id obj = [NSDictionary plistWithDescriptionData:data error:&error];
	if (obj == nil && error) {
		NSLog(@"%@", error);
	}

	id test = [projectName.pathComponents mutableCopy];
	id url = [NSURL fileURLWithPathComponents:test].URLByDeletingLastPathComponent.absoluteURL.path;

	id contextInfo = @{
		@"path": url,
		@"read-only": @0,
		@"upgrade-log": [NSClassFromString(@"PBXLogOutputString") new],
	};
	id<PBXPListUnarchiver> arch = [[NSClassFromString(@"PBXPListUnarchiver") alloc] initWithPListArchive:obj userSettings:nil contextInfo:contextInfo];
	id project = [arch decodeRootObject];

	id archiver = [[NSClassFromString(@"PBXPListArchiver") alloc] initWithRootObject:project delegate:project];
	NSData *data2 = [[archiver plistArchive] plistDescriptionUTF8Data];
	NSParameterAssert(data2);
	NSParameterAssert([data2 writeToFile:projectName options:0 error:nil]);

	[NSClassFromString(@"PBXProject") removeContainerForResolvedAbsolutePath:url];
}

// MARK: - App run

- (int) application:(DDCliApplication *)app runWithArguments:(NSArray *)arguments
{
	[self.class initializeXcproj];

	if ([arguments count] == 0) {
		arguments = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[NSFileManager defaultManager] currentDirectoryPath]
																		error:nil];
		arguments = [arguments filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH '.xcodeproj'"]];
		NSAssert([arguments count] != 0, @"xcodeproj file not found in the current directory");
		NSAssert([arguments count] == 1, @"multiple xcodeproject files found in the directory");
	}

	for (NSString *path in arguments) {
		[self setProject:path];
	}

	return EX_OK;
}

@end
