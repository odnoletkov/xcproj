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

static void InitializeXcodeFrameworks(void)
{
	BOOL(*IDEInitialize)(int initializationOptions, NSError **error) = dlsym(RTLD_DEFAULT, "IDEInitialize");
	if (!IDEInitialize)
	{
		ddfprintf(stderr, @"IDEInitialize function not found.\n");
		exit(EX_SOFTWARE);
	}
	
	// Temporary redirect stderr to /dev/null in order not to print plugin loading errors
	// Adapted from http://stackoverflow.com/questions/4832603/how-could-i-temporary-redirect-stdout-to-a-file-in-a-c-program/4832902#4832902
	fflush(stderr);
	int saved_stderr = dup(STDERR_FILENO);
	int dev_null = open("/dev/null", O_WRONLY);
	dup2(dev_null, STDERR_FILENO);
	close(dev_null);
	// Xcode3Core.ideplugin`-[Xcode3CommandLineBuildTool run] calls IDEInitialize(1, &error)
	NSError *error;
	BOOL initialized = IDEInitialize(1, &error);
	NSCParameterAssert(initialized);
	fflush(stderr);
	dup2(saved_stderr, STDERR_FILENO);
	close(saved_stderr);
}

+ (void) initializeXcproj
{
	NSLog(@"started");
	
	NSBundle *bundle = [NSBundle bundleWithPath:@"/Applications/Xcode.app/Contents/Frameworks/IDEFoundation.framework"];
	NSParameterAssert(bundle && [bundle loadAndReturnError:nil]);

	NSLog(@"loaded frameworks");

	InitializeXcodeFrameworks();
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
	[self.class initializeXcproj];
	
	if (![PBXProject isProjectWrapperExtension:[projectName pathExtension]])
		@throw [DDCliParseException parseExceptionWithReason:[NSString stringWithFormat:@"The project name %@ does not have a valid extension.", projectName] exitCode:EX_USAGE];
	
	NSString *projectPath = projectName;
	if (![projectName isAbsolutePath])
		projectPath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:projectName];
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:projectPath])
		@throw [DDCliParseException parseExceptionWithReason:[NSString stringWithFormat:@"The project %@ does not exist in this directory.", projectName] exitCode:EX_NOINPUT];
	
	id<PBXProject> project = [PBXProject projectWithFile:projectPath];
	
	if (!project)
		@throw [DDCliParseException parseExceptionWithReason:[NSString stringWithFormat:@"The '%@' project is corrupted.", projectName] exitCode:EX_DATAERR];

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
			if ([PBXProject isProjectWrapperExtension:[fileName pathExtension]])
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
