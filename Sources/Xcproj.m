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
#import "XCDUndocumentedChecker.h"

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
	
	BOOL isSafe = YES;
	NSArray *protocols = @[@protocol(PBXProject)];
	
	for (Protocol *protocol in protocols)
	{
		NSError *classError = nil;
		Class class = XCDClassFromProtocol(protocol, &classError);
		if (class)
			[self setValue:class forKey:@(protocol_getName(protocol))];
		else
		{
			isSafe = NO;
			ddfprintf(stderr, @"%@\n%@\n", [classError localizedDescription], [classError userInfo]);
		}
	}

	if (!isSafe)
		exit(EX_SOFTWARE);
}

// MARK: - Options

- (void) application:(DDCliApplication *)app willParseOptions:(DDGetoptLongParser *)optionsParser
{
	DDGetoptOption optionTable[] = 
	{
		// Long           Short  Argument options
		{"project",       'p',   DDGetoptRequiredArgument},
		{"target",        't',   DDGetoptRequiredArgument},
		{"configuration", 'c',   DDGetoptRequiredArgument},
		{"help",          'h',   DDGetoptNoArgument},
		{"version",       'V',   DDGetoptNoArgument},
		{nil,           0,    0},
	};
	[optionsParser addOptionsFromTable:optionTable];
}

- (id <PBXProject>) setProject:(NSString *)projectName
{
//	if (![PBXProject isProjectWrapperExtension:[projectName pathExtension]])
//		@throw [DDCliParseException parseExceptionWithReason:[NSString stringWithFormat:@"The project name %@ does not have a valid extension.", projectName] exitCode:EX_USAGE];
//
//	NSString *projectPath = projectName;
//	if (![projectName isAbsolutePath])
//		projectPath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:projectName];
//
//	if (![[NSFileManager defaultManager] fileExistsAtPath:projectPath])
//		@throw [DDCliParseException parseExceptionWithReason:[NSString stringWithFormat:@"The project %@ does not exist in this directory.", projectName] exitCode:EX_NOINPUT];
//
//	id<PBXProject> project = [PBXProject projectWithFile:projectPath];
//
//	if (!project)
//		@throw [DDCliParseException parseExceptionWithReason:[NSString stringWithFormat:@"The '%@' project is corrupted.", projectName] exitCode:EX_DATAERR];

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
