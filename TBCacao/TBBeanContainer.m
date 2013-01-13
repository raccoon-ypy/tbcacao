/**
 * Tae Won Ha
 * http://qvacua.com
 *
 * Copyright © 2012 Tae Won Ha. See LICENSE
 */

#import "TBBeanContainer.h"

@implementation TBBeanContainer {
@private
    NSString *_identifier;
    id _targetSource;
}

@synthesize identifier = _identifier;
@synthesize targetSource = _targetSource;

#pragma mark NSObject
- (id)initWithIdentifier:(NSString *)anIdentifier bean:(id)aBean {
    self = [super init];
    if (self) {
        _identifier = anIdentifier;
        _targetSource = aBean;
    }

    return self;
}

- (id)initWithTargetSource:(id)targetSource {
    return [self initWithIdentifier:NSStringFromClass([targetSource class]) bean:targetSource];
}

+ (id)objectWithTargetSource:(id)targetSource {
    return [[TBBeanContainer alloc] initWithTargetSource:targetSource];
}

+ (id)objectWithIdentifier:(NSString *)anIdentifier bean:(id)aBean {
    return [[TBBeanContainer alloc] initWithIdentifier:anIdentifier bean:aBean];
}

- (BOOL)isEqual:(TBBeanContainer *)beanToCompare {
    return [self.identifier isEqualToString:beanToCompare.identifier];
}

- (NSString *)description {
    return [[NSString alloc] initWithFormat:@"Bean %@ of class %@", self.identifier, NSStringFromClass([self.targetSource class])];
}

@end