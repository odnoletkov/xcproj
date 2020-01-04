#import "Xcproj.h"

#import <dlfcn.h>

@interface NSDictionary (PRIVATE)
+ (NSDictionary *)plistWithDescriptionData:(NSData *)data error:(NSError **)error;
- (id)plistDescriptionUTF8Data;
@end

@protocol PBXPListUnarchiver <NSObject>
- (id)initWithPListArchive:(NSDictionary *)archive userSettings:(id)settings contextInfo:(NSDictionary *)contextInfo;
- (id)decodeRootObject;
@end

@protocol PBXPListArchiver
- (id)initWithRootObject:(id)arg1 delegate:(id)arg2;
- (id)plistArchive;
@end

@protocol PBXProject
+ (void)removeContainerForResolvedAbsolutePath:(NSString *)idd;
@end

@implementation Xcproj

- (void) application:(DDCliApplication *)app willParseOptions:(DDGetoptLongParser *)optionsParser {
}

- (void)processPath:(NSString *)path {
	if (![path.lastPathComponent isEqualToString:@"project.pbxproj"]) {
		path = [path stringByAppendingPathComponent:@"project.pbxproj"];
	}

	__auto_type dataIn = [NSData dataWithContentsOfFile:path];
	NSParameterAssert(dataIn);
	__auto_type obj = [NSDictionary plistWithDescriptionData:dataIn error:nil];
	NSParameterAssert(obj);

	__auto_type contextInfo = @{
		@"path": [NSURL fileURLWithPath:path].URLByDeletingLastPathComponent.absoluteURL.path,
		@"read-only": @0,
		@"upgrade-log": [NSClassFromString(@"PBXLogOutputString") new],
	};
	id<PBXPListUnarchiver> archiver = [[NSClassFromString(@"PBXPListUnarchiver") alloc] initWithPListArchive:obj userSettings:nil contextInfo:contextInfo];
	NSParameterAssert(archiver);
	id project = [archiver decodeRootObject];
	NSParameterAssert(project);

	NSLog(@"read %@", path);

	id unarchiver = [[NSClassFromString(@"PBXPListArchiver") alloc] initWithRootObject:project delegate:project];
	NSParameterAssert(unarchiver);
	NSData *dataOut = [[unarchiver plistArchive] plistDescriptionUTF8Data];
	NSParameterAssert(dataOut && [dataOut writeToFile:path options:0 error:nil]);

	NSLog(@"wrote %@", path);

	[NSClassFromString(@"PBXProject") removeContainerForResolvedAbsolutePath:contextInfo[@"path"]];
}

// MARK: - App run

- (int) application:(DDCliApplication *)app runWithArguments:(NSArray *)arguments {

	NSLog(@"started");

	__auto_type bundle = [NSBundle bundleWithPath:@"/Applications/Xcode.app/Contents/Frameworks/IDEFoundation.framework"];
	NSParameterAssert(bundle && [bundle loadAndReturnError:nil]);

	NSLog(@"loaded frameworks");

	BOOL(*IDEInitialize)(int initializationOptions, NSError **error) = dlsym(RTLD_DEFAULT, "IDEInitialize");
	NSCParameterAssert(IDEInitialize(1, nil));

	NSLog(@"initialized frameworks");

	if ([arguments count] == 0) {
		arguments = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[NSFileManager defaultManager] currentDirectoryPath]
																		error:nil];
		arguments = [arguments filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH '.xcodeproj'"]];
		NSAssert([arguments count] != 0, @"xcodeproj file not found in the current directory");
		NSAssert([arguments count] == 1, @"multiple xcodeproject files found in the directory");
	}

	for (NSString *path in arguments) {
		[self processPath:path];
	}

	return EX_OK;
}

@end
