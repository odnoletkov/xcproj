@protocol PBXProject <NSObject>

@end

@protocol PRIVATE
+ (void)removeContainerForResolvedAbsolutePath:(NSString *)idd;
@end

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
