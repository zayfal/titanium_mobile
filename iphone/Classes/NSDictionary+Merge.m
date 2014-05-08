
#import "NSDictionary+Merge.h"

@implementation NSDictionary (Merge)

+ (NSDictionary *) dictionaryByMerging: (NSDictionary *) dict1 with: (NSDictionary *) dict2 {
    return [[self class] dictionaryByMerging:dict1 with:dict2 force:NO];
}

+ (NSDictionary *) dictionaryByMerging: (NSDictionary *) dict1 with: (NSDictionary *) dict2 force:(BOOL)force {
    NSMutableDictionary * result = [NSMutableDictionary dictionaryWithDictionary:dict1];
    
    [dict2 enumerateKeysAndObjectsUsingBlock: ^(id key, id obj, BOOL *stop) {
        if (force || ![dict1 objectForKey:key]) {
            if ([obj isKindOfClass:[NSDictionary class]]) {
                NSDictionary * newVal = [[dict1 objectForKey: key] dictionaryByMergingWith:(NSDictionary *) obj force:force];
                [result setObject: newVal forKey: key];
            } else {
                [result setObject: obj forKey: key];
            }
        }
    }];
    
    return (NSDictionary *) [[result mutableCopy] autorelease];
}

- (NSDictionary *) dictionaryByMergingWith: (NSDictionary *) dict {
    return [self dictionaryByMergingWith:dict force:false];
}

- (NSDictionary *) dictionaryByMergingWith: (NSDictionary *) dict force:(BOOL)force {
    return [[self class] dictionaryByMerging: self with: dict force:force];
}

@end
