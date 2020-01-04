#import <Foundation/Foundation.h>
#import <sysexits.h>
#import <dlfcn.h>

@interface NSDictionary (PRIVATE)
+ (NSDictionary *)plistWithDescriptionData:(NSData *)data error:(NSError **)error;
- (id)plistDescriptionUTF8Data;
@end

@protocol PBXPListUnarchiver <NSObject>
- (id)initWithPListArchive:(NSDictionary *)archive userSettings:(id)settings contextInfo:(NSDictionary *)contextInfo;
- (void)setDelegate:(id)delegate;
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

	if (!getenv("D0NE")) {
		setenv("D0NE", "", 1);

		__auto_type contentsPath = [({
			NSTask *task = [NSTask new];
			task.launchPath = @"/usr/bin/xcode-select";
			task.arguments = @[@"--print-path"];
			task.standardOutput = [NSPipe new];
			[task launch];
			[task waitUntilExit];
			NSCParameterAssert(task.terminationStatus == 0);
			[[NSString alloc] initWithData:[[task.standardOutput fileHandleForReading] readDataToEndOfFile]
								  encoding:NSUTF8StringEncoding];
		}) stringByDeletingLastPathComponent];
		NSCParameterAssert(contentsPath);

		setenv("DYLD_FRAMEWORK_PATH",
			   [[@[
				   [contentsPath stringByAppendingPathComponent:@"Frameworks"],
				   [contentsPath stringByAppendingPathComponent:@"SharedFrameworks"],
			   ] componentsJoinedByString:@":"] cStringUsingEncoding:NSUTF8StringEncoding],
			   1);

		NSCParameterAssert(execvp(argv[0], argv) != -1);
	}

	__auto_type arguments = [NSProcessInfo processInfo].arguments;
	arguments = [arguments subarrayWithRange:NSMakeRange(1, [arguments count] - 1)];

	NSCAssert(dlopen("IDEFoundation.framework/IDEFoundation", RTLD_NOW), @"%s", dlerror());

	BOOL(*IDEInitialize)(int initializationOptions, NSError **error) = dlsym(RTLD_DEFAULT, "IDEInitialize");
	NSCParameterAssert(IDEInitialize(1, nil));

	if ([arguments count] == 0) {
		arguments = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[NSFileManager defaultManager] currentDirectoryPath]
																		error:nil];
		arguments = [arguments filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH 'xcodeproj'"]];
		NSCAssert([arguments count] != 0, @"xcodeproj file not found in the current directory");
		NSCAssert([arguments count] == 1, @"multiple xcodeproject files found in the directory");
	}

	for (NSString *arg in arguments) {
		__auto_type path = arg;
		if ([path.lastPathComponent.pathExtension isEqualToString:@"xcodeproj"]) {
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
		[archiver setDelegate:NSClassFromString(@"PBXProject")];
		id project = [archiver decodeRootObject];
		NSCParameterAssert(project);

		id unarchiver = [[NSClassFromString(@"PBXPListArchiver") alloc] initWithRootObject:project delegate:project];
		NSCParameterAssert(unarchiver);
		NSData *dataOut = [[unarchiver plistArchive] plistDescriptionUTF8Data];
		NSCParameterAssert(dataOut && [dataOut writeToFile:path options:0 error:nil]);

		[NSClassFromString(@"PBXProject") removeContainerForResolvedAbsolutePath:contextInfo[@"path"]];
	}

	return EX_OK;
}}
