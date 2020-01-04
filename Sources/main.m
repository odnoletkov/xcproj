#import <Foundation/Foundation.h>
#import <sysexits.h>
#import <dlfcn.h>

@interface NSDictionary ()
+ (NSDictionary *)plistWithDescriptionData:(NSData *)data error:(NSError **)error;
- (id)plistDescriptionUTF8Data;
@end

@protocol PBXPListUnarchiver
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

		NSString *contentsPath = [({
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

	NSCAssert(dlopen("IDEFoundation.framework/IDEFoundation", RTLD_NOW), @"%s", dlerror());

	BOOL(*IDEInitialize)(int initializationOptions, NSError **error) = dlsym(RTLD_DEFAULT, "IDEInitialize");
	NSCParameterAssert(IDEInitialize);
	NSCParameterAssert(IDEInitialize(1, nil));

	NSArray *arguments = [NSProcessInfo processInfo].arguments;
	arguments = [arguments subarrayWithRange:NSMakeRange(1, [arguments count] - 1)];

	if ([arguments count] == 0) {
		arguments = [[NSFileManager defaultManager]
					 contentsOfDirectoryAtPath:[[NSFileManager defaultManager] currentDirectoryPath]
					 error:nil];
		arguments = [arguments filteredArrayUsingPredicate:
					 [NSPredicate predicateWithFormat:@"self ENDSWITH 'xcodeproj'"]];
		NSCAssert([arguments count] != 0, @"xcodeproj file not found in the current directory");
		NSCAssert([arguments count] == 1, @"multiple xcodeproject files found in the current directory");
	}

	for (NSString *arg in arguments) {
		NSString *path = arg;
		if ([path.lastPathComponent.pathExtension isEqualToString:@"xcodeproj"]) {
			path = [path stringByAppendingPathComponent:@"project.pbxproj"];
		}

		NSData *dataIn = [NSData dataWithContentsOfFile:path];
		NSCParameterAssert(dataIn);
		NSDictionary *obj = [NSDictionary plistWithDescriptionData:dataIn error:nil];
		NSCParameterAssert(obj);

		NSString *projectPath =
		[NSProcessInfo processInfo].environment[@"XCODEPROJ"]
		?: path.stringByDeletingLastPathComponent;

		NSDictionary *contextInfo = @{
			@"path": [NSURL fileURLWithPath:projectPath].absoluteURL.path,
			@"read-only": @0,
			@"upgrade-log": [NSClassFromString(@"PBXLogOutputString") new],
		};
		id<PBXPListUnarchiver> unarchiver = [[NSClassFromString(@"PBXPListUnarchiver") alloc]
											 initWithPListArchive:obj userSettings:nil contextInfo:contextInfo];
		NSCParameterAssert(unarchiver);
		[unarchiver setDelegate:NSClassFromString(@"PBXProject")];
		id project = [unarchiver decodeRootObject];
		NSCParameterAssert(project);

		id<PBXPListArchiver> archiver = [[NSClassFromString(@"PBXPListArchiver") alloc]
										 initWithRootObject:project delegate:project];
		NSCParameterAssert(archiver);
		NSData *dataOut = [[archiver plistArchive] plistDescriptionUTF8Data];
		NSCParameterAssert(dataOut);
		NSCParameterAssert([dataOut writeToFile:path options:0 error:nil]);

		[NSClassFromString(@"PBXProject") removeContainerForResolvedAbsolutePath:contextInfo[@"path"]];
	}

	return EX_OK;
}}
