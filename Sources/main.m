#import <Foundation/Foundation.h>
#import <sysexits.h>
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

int main(int argc, char *const *argv) { @autoreleasepool {

	NSLog(@"started");

	__auto_type arguments = [NSProcessInfo processInfo].arguments;
	arguments = [arguments subarrayWithRange:NSMakeRange(1, [arguments count] - 1)];

	__auto_type bundle = [NSBundle bundleWithPath:@"/Applications/Xcode.app/Contents/Frameworks/IDEFoundation.framework"];
	NSCParameterAssert(bundle && [bundle loadAndReturnError:nil]);

	NSLog(@"loaded frameworks");

	BOOL(*IDEInitialize)(int initializationOptions, NSError **error) = dlsym(RTLD_DEFAULT, "IDEInitialize");
	NSCParameterAssert(IDEInitialize(1, nil));

	NSLog(@"initialized frameworks");

	if ([arguments count] == 0) {
		arguments = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[NSFileManager defaultManager] currentDirectoryPath]
																		error:nil];
		arguments = [arguments filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH '.xcodeproj'"]];
		NSCAssert([arguments count] != 0, @"xcodeproj file not found in the current directory");
		NSCAssert([arguments count] == 1, @"multiple xcodeproject files found in the directory");
	}

	for (NSString *arg in arguments) {
		__auto_type path = arg;
		if (![path.lastPathComponent isEqualToString:@"project.pbxproj"]) {
			path = [path stringByAppendingPathComponent:@"project.pbxproj"];
		}

		__auto_type dataIn = [NSData dataWithContentsOfFile:path];
		NSCParameterAssert(dataIn);
		__auto_type obj = [NSDictionary plistWithDescriptionData:dataIn error:nil];
		NSCParameterAssert(obj);

		__auto_type projectPath = [NSProcessInfo processInfo].environment[@"XCODEPROJ"] ?: path.stringByDeletingLastPathComponent;

		__auto_type contextInfo = @{
			@"path": [NSURL fileURLWithPath:projectPath].absoluteURL.path,
			@"read-only": @0,
			@"upgrade-log": [NSClassFromString(@"PBXLogOutputString") new],
		};
		id<PBXPListUnarchiver> archiver = [[NSClassFromString(@"PBXPListUnarchiver") alloc] initWithPListArchive:obj userSettings:nil contextInfo:contextInfo];
		NSCParameterAssert(archiver);
		id project = [archiver decodeRootObject];
		NSCParameterAssert(project);

		NSLog(@"read %@", path);

		id unarchiver = [[NSClassFromString(@"PBXPListArchiver") alloc] initWithRootObject:project delegate:project];
		NSCParameterAssert(unarchiver);
		NSData *dataOut = [[unarchiver plistArchive] plistDescriptionUTF8Data];
		NSCParameterAssert(dataOut && [dataOut writeToFile:path options:0 error:nil]);

		NSLog(@"wrote %@", path);

		[NSClassFromString(@"PBXProject") removeContainerForResolvedAbsolutePath:contextInfo[@"path"]];
	}

	return EX_OK;
}}
