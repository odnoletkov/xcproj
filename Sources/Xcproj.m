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

static NSString * const FrameworksToLoad = @"FrameworksToLoad";

@implementation Xcproj
{
	id<PBXProject> _project;
}

static Class PBXProject = Nil;

+ (void) setPBXProject:(Class)class                { PBXProject = class; }

static NSString *XcodeBundleIdentifier = @"com.apple.dt.Xcode";

static NSBundle * XcodeBundleAtPath(NSString *path)
{
	NSBundle *xcodeBundle = [NSBundle bundleWithPath:path];
	return [xcodeBundle.bundleIdentifier isEqualToString:XcodeBundleIdentifier] ? xcodeBundle : nil;
}

static NSBundle * XcodeBundle(void)
{
	NSString *xcodeAppPath = NSProcessInfo.processInfo.environment[@"XCPROJ_XCODE_APP_PATH"];
	NSBundle *xcodeBundle = XcodeBundleAtPath(xcodeAppPath);
	if (!xcodeBundle)
	{
		NSTask *task = [NSTask new];
		task.launchPath = @"/usr/bin/xcode-select";
		task.arguments = @[@"--print-path"];
		task.standardOutput = [NSPipe new];
		
		@try
		{
			[task launch];
			[task waitUntilExit];
			
			if (task.terminationStatus == 0)
			{
				NSData *outputData = [[task.standardOutput fileHandleForReading] readDataToEndOfFile];
				NSString *outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
				NSString *xcodePath = [[outputString stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
				xcodeBundle = XcodeBundleAtPath(xcodePath);
			}
		}
		@catch (NSException *exception)
		{
			NSURL *xcodeURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:XcodeBundleIdentifier];
			xcodeBundle = XcodeBundleAtPath(xcodeURL.path);
		}
	}
	
	if (!xcodeBundle)
	{
		ddfprintf(stderr, @"Xcode.app not found.\n");
		exit(EX_CONFIG);
	}
	
	if (xcodeAppPath && ![[xcodeAppPath stringByResolvingSymlinksInPath] isEqualToString:xcodeBundle.bundlePath])
	{
		ddfprintf(stderr, @"WARNING: '%@' does not point to an Xcode app, using '%@'\n", xcodeAppPath, xcodeBundle.bundlePath);
	}
	
	return xcodeBundle;
}

static NSString *DependentFramework(NSError *error)
{
	NSRegularExpression *notLoadedRegularExpression = [NSRegularExpression regularExpressionWithPattern:@"Library not loaded: @rpath/([^/]+)/" options:(NSRegularExpressionOptions)0 error:NULL];
	
	while (error)
	{
		NSString *debugDescription = error.userInfo[@"NSDebugDescription"];
		if (debugDescription)
		{
			NSTextCheckingResult *match = [notLoadedRegularExpression firstMatchInString:debugDescription options:(NSMatchingOptions)0 range:NSMakeRange(0, debugDescription.length)];
			if (match)
			{
				return [debugDescription substringWithRange:[match rangeAtIndex:1]];
			}
		}
		error = error.userInfo[NSUnderlyingErrorKey];
	}
	return nil;
}

static void LoadXcodeFrameworks(NSBundle *xcodeBundle, NSArray *frameworks)
{
	NSURL *xcodeContentsURL = [[xcodeBundle privateFrameworksURL] URLByDeletingLastPathComponent];
	for (NSString *framework in frameworks)
	{
		BOOL loaded = NO;
		BOOL abort = NO;
		NSArray *xcodeSubdirectories = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:xcodeContentsURL includingPropertiesForKeys:nil options:0 error:NULL];
		for (NSURL *frameworksDirectoryURL in xcodeSubdirectories)
		{
			NSURL *frameworkURL = [frameworksDirectoryURL URLByAppendingPathComponent:framework];
			NSBundle *frameworkBundle = [NSBundle bundleWithURL:frameworkURL];
			if (frameworkBundle)
			{
				NSError *loadError = nil;
				loaded = [frameworkBundle loadAndReturnError:&loadError];
				if (!loaded)
				{
					NSString *dependentFramework = DependentFramework(loadError);
					if (dependentFramework)
					{
						LoadXcodeFrameworks(xcodeBundle, [@[ dependentFramework ] arrayByAddingObjectsFromArray:frameworks]);
						abort = YES;
					}
					else
					{
						ddfprintf(stderr, @"The %@ %@ failed to load: %@\n", [framework stringByDeletingPathExtension], [framework pathExtension], loadError);
						exit(EX_SOFTWARE);
					}
				}
			}
			
			if (loaded || abort)
				break;
		}
		if (abort)
			break;
	}
}

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
	fflush(stderr);
	dup2(saved_stderr, STDERR_FILENO);
	close(saved_stderr);
	
	if (!initialized)
	{
		NSString *dependentFramework = DependentFramework(error);
		NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
		NSArray *frameworksToLoad = [standardUserDefaults objectForKey:FrameworksToLoad];
		if (dependentFramework && ![frameworksToLoad containsObject:dependentFramework])
		{
			[standardUserDefaults setObject:[frameworksToLoad arrayByAddingObject:dependentFramework] forKey:FrameworksToLoad];
			ddfprintf(stderr, @"Please try to relaunch %@ (%@ was added to the list of frameworks to load)\n\n%@\n", NSProcessInfo.processInfo.processName, dependentFramework, error);
		}
		else
		{
			ddfprintf(stderr, @"IDEInitialize failed: %@\n", error);
		}
		exit(EX_SOFTWARE);
	}
}

+ (void) initializeXcproj
{
	static BOOL initialized = NO;
	if (initialized)
		return;
	NSLog(@"started: %@", [NSDate date]);
	
	NSArray *frameworksToLoad = @[
		@"IDEFoundation.framework",
		@"Xcode3Core.ideplugin",
		@"IBAutolayoutFoundation.framework",
		@"IDEKit.framework",
		@"DebugHierarchyFoundation.framework",
		@"DebugHierarchyKit.framework",
		
//		@"DevToolsCore.framework"
	];
	
	LoadXcodeFrameworks(XcodeBundle(), frameworksToLoad);
	NSLog(@"loaded frameworks: %@", [NSDate date]);
	InitializeXcodeFrameworks();
	NSLog(@"initialized frameworks: %@", [NSDate date]);
	
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
	NSLog(@"protocols: %@", [NSDate date]);
	
	if (!isSafe)
		exit(EX_SOFTWARE);
	
	initialized = YES;
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

- (void) setProject:(NSString *)projectName
{
	[self.class initializeXcproj];
	
	if (![PBXProject isProjectWrapperExtension:[projectName pathExtension]])
		@throw [DDCliParseException parseExceptionWithReason:[NSString stringWithFormat:@"The project name %@ does not have a valid extension.", projectName] exitCode:EX_USAGE];
	
	NSString *projectPath = projectName;
	if (![projectName isAbsolutePath])
		projectPath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:projectName];
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:projectPath])
		@throw [DDCliParseException parseExceptionWithReason:[NSString stringWithFormat:@"The project %@ does not exist in this directory.", projectName] exitCode:EX_NOINPUT];
	
	_project = [PBXProject projectWithFile:projectPath];
	
	if (!_project)
		@throw [DDCliParseException parseExceptionWithReason:[NSString stringWithFormat:@"The '%@' project is corrupted.", projectName] exitCode:EX_DATAERR];
}

- (void) setHelp:(NSNumber *)help
{
	if ([help boolValue])
		[self printUsage:EX_OK];
}

- (void) setVersion:(NSNumber *)version
{
	if ([version boolValue])
	{
		ddprintf(@"%@\n", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
		exit(EX_OK);
	}
}

// MARK: - App run

- (int) application:(DDCliApplication *)app runWithArguments:(NSArray *)arguments
{
	if ([arguments count] < 1)
		[self printUsage:EX_USAGE];
	
	[self.class initializeXcproj];
	
	NSString *currentDirectoryPath = [[NSFileManager defaultManager] currentDirectoryPath];
	
	if (!_project)
	{
		for (NSString *fileName in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:currentDirectoryPath error:NULL])
		{
			if ([PBXProject isProjectWrapperExtension:[fileName pathExtension]])
			{
				if (!_project)
					[self setProject:fileName];
				else
				{
					ddfprintf(stderr, @"%@: The directory %@ contains more than one Xcode project. You will need to specify the project with the --project option.\n", app, currentDirectoryPath);
					return EX_USAGE;
				}
			}
		}
	}
	
	if (!_project)
	{
		ddfprintf(stderr, @"%@: The directory %@ does not contain an Xcode project.\n", app, currentDirectoryPath);
		return EX_USAGE;
	}
	
	NSString *action = [arguments objectAtIndex:0];
	if (![[self allowedActions] containsObject:action])
		[self printUsage:EX_USAGE];
	
	NSArray *actionArguments = nil;
	if ([arguments count] >= 2)
		actionArguments = [arguments subarrayWithRange:NSMakeRange(1, [arguments count] - 1)];
	else
		actionArguments = @[];
	
	NSArray *actionParts = [[action componentsSeparatedByString:@"-"] valueForKeyPath:@"capitalizedString"];
	NSMutableString *selectorString = [NSMutableString stringWithString:[actionParts componentsJoinedByString:@""]];
	[selectorString replaceCharactersInRange:NSMakeRange(0, 1) withString:[[selectorString substringToIndex:1] lowercaseString]];
	[selectorString appendString:@":"];
	SEL actionSelector = NSSelectorFromString(selectorString);
	return [[self performSelector:actionSelector withObject:actionArguments] intValue];
}

// MARK: - Actions

- (NSArray *) allowedActions
{
	return @[ @"list-targets",
	          @"list-headers",
	          @"read-build-setting",
	          @"write-build-setting",
	          @"add-xcconfig",
	          @"add-resources-bundle",
	          @"touch" ];
}

- (void) printUsage:(int)exitCode
{
	ddprintf(@"Usage: %@ [options] <action> [arguments]\n", [[NSBundle mainBundle] objectForInfoDictionaryKey:(id)kCFBundleExecutableKey]);
	ddprintf(@"\nOptions:\n"
	         @" -h, --help              Show this help text and exit\n"
	         @" -V, --version           Show program version and exit\n"
	         @" -p, --project           Path to an Xcode project (*.xcodeproj file). If not specified, the project in the current working directory is used\n"
	         @" -t, --target            Name of the target. If not specified, the action is performed at the project level. Required for the `list-headers` and `add-resources-bundle` actions\n"
	         @" -c, --configuration     Name of the configuration. If not specified, the default configuration (i.e. for command-line builds) is used\n"
	         @"\nActions:\n"
	         @" * list-targets\n"
	         @"     List all the targets in the project\n\n"
	         @" * list-headers [All|Public|Project|Private] (default=Public)\n"
	         @"     List headers from the `Copy Headers` build phase\n\n"
	         @" * read-build-setting <build_setting>\n"
	         @"     Evaluate a build setting and print its value. If the build setting does not exist, nothing is printed\n\n"
	         @" * write-build-setting <build_setting> <value>\n"
	         @"     Assign a value to a build setting. If the build setting does not exist, it is added to the target\n\n"
	         @" * add-xcconfig <xcconfig_path>\n"
	         @"     Add an xcconfig file to the project and base all configurations on it\n\n"
	         @" * add-resources-bundle <bundle_path>\n"
	         @"     Add a bundle to the project and in the `Copy Bundle Resources` build phase\n\n"
	         @" * touch\n"
	         @"     Rewrite the project file\n");
	exit(exitCode);
}

- (NSNumber *) writeProject
{
	BOOL written = [_project writeToFileSystemProjectFile:YES userFile:NO checkNeedsRevert:NO];
	if (!written)
	{
		ddfprintf(stderr, @"Could not write '%@' to file system.", _project);
		return @(EX_IOERR);
	}
	return @(EX_OK);
}

- (NSNumber *) touch:(NSArray *)arguments
{
	NSLog(@"before write: %@", [NSDate date]);
	id res = [self writeProject];
	NSLog(@"after write: %@", [NSDate date]);
	return res;
}

@end
