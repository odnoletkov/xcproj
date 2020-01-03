@protocol PBXProject <NSObject>

+ (BOOL) isProjectWrapperExtension:(NSString *)extension;
+ (id<PBXProject>) projectWithFile:(NSString *)projectAbsolutePath;

- (BOOL) writeToFileSystemProjectFile:(BOOL)projectWrite userFile:(BOOL)userWrite checkNeedsRevert:(BOOL)checkNeedsRevert;

@end

@protocol PRIVATE
+ (void)removeContainerForResolvedAbsolutePath:(NSString *)idd;
@end

@interface NSDictionary (PRIVATE)
+ (NSDictionary *)plistWithDescriptionData:(NSData *)data error:(NSError **)error;
@end

@protocol PBXPListUnarchiver <NSObject>
- (id)initWithPListArchive:(NSDictionary *)archive userSettings:(id)settings contextInfo:(NSDictionary *)contextInfo;
- (id)decodeRootObject;
@end
