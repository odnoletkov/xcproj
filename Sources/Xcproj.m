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

static Class PBXProject = Nil;

+ (void) setPBXProject:(Class)class                { PBXProject = class; }

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

- (id <PBXProject>) setProject:(NSString *)projectName
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

	[PBXProject removeContainerForResolvedAbsolutePath:url];

	return project;
}

// MARK: - App run

- (int) application:(DDCliApplication *)app runWithArguments:(NSArray *)arguments
{
	[self.class initializeXcproj];

	NSMutableArray<id<PBXProject>> *projects = [@[] mutableCopy];

	for (NSString *path in arguments) {
		[projects addObject:[self setProject:path]];
	}

	NSString *currentDirectoryPath = [[NSFileManager defaultManager] currentDirectoryPath];

	if ([projects count] == 0) {
		for (NSString *fileName in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:currentDirectoryPath error:NULL]) {
			if ([[fileName pathExtension] isEqualToString:@"xcodeproj"])
			{
				if ([projects count] == 0) {
					[projects addObject:[self setProject:fileName]];
				} else {
					ddfprintf(stderr, @"%@: The directory %@ contains more than one Xcode project. You will need to specify the project with the --project option.\n", app, currentDirectoryPath);
					return EX_USAGE;
				}
			}
		}
	}

	NSLog(@"projects loaded");
	
	if ([projects count] == 0)
	{
		ddfprintf(stderr, @"%@: The directory %@ does not contain an Xcode project.\n", app, currentDirectoryPath);
		return EX_USAGE;
	}

	for (id<PBXProject> project in projects) {
		int ret = [[self writeProject:project] intValue];
		NSLog(@"written project");
		if (ret != EX_OK) {
			return ret;
		}
	}

	return EX_OK;
}

// MARK: - Actions

- (NSNumber *)writeProject:(id<PBXProject>)project
{
	BOOL written = [project writeToFileSystemProjectFile:YES userFile:NO checkNeedsRevert:NO];
	if (!written)
	{
		ddfprintf(stderr, @"Could not write '%@' to file system.", project);
		return @(EX_IOERR);
	}
	return @(EX_OK);
}

@end
