/*
 * Copyright 2011 Tae Won Ha, See LICENSE for details.
 *
 */

#import <objc/objc-runtime.h>

#import "TBLog.h"

#import "NSObject+TBCacao.h"
#import "NSString+TBCacao.h"

#import "TBCacao.h"
#import "TBObjcProperty.h"
#import "TBManualCacaoProvider.h"
#import "TBConfigManager.h"
#import "TBError.h"


static TBCacao *cacao = nil;


@implementation TBCacao


@synthesize configManager;
@dynamic manualCacaoProviders;


- (NSArray *)manualCacaoProviders {
    return (NSArray *)manualCacaoProviders;
}


- (BOOL)checkSuperclassOfManualCacaoProvider:(Class)class {

    if (class == nil) {
        NSString *errorMsg = [NSString stringWithFormat:@"The class %@ seems to be not there in the ObjC-Runtime, therefore it could not be instantiated.", class];

        log4Fatal(@"%@", errorMsg);

        return NO;
    }

    if ([class superclass] != [TBManualCacaoProvider class]) {
        NSString *errorMsg = [NSString stringWithFormat:@"The manual Cacao provider \"%@\" is not a subclass of \"%@.\"", [class classAsString], [TBManualCacaoProvider classAsString]];

        log4Fatal(@"%@", errorMsg);

        return NO;
    }

    return YES;
}


- (BOOL)buildManualCacaoProvidersFrom:(NSArray *)configDict {
    manualCacaoProviders = [[NSMutableArray allocWithZone:nil] initWithCapacity:[configDict count]];
    
    for (NSDictionary *providerDict in configDict) {
        
        NSString *className = [providerDict objectForKey:@"class"];

        id class = objc_getClass([className UTF8String]);
        
        if ([self checkSuperclassOfManualCacaoProvider:class] == NO) {
            break;
        }
        
        id provider = [class_createInstance(class, 0) init];
        [manualCacaoProviders addObject:provider];
        [provider release];

    }
    
    return YES;
}

- (BOOL)hasClass:(Class)class {
    for (NSDictionary *config in configManager.configCacaos) {
        NSString *cacaoClass = [config objectForKey:@"class"];
        
        if ([cacaoClass isEqualToString:[class classAsString]]) {
            return YES;
        }
    }
    
    return NO;
}

- (NSArray *)objcPropertiesForClass:(Class)class {
    unsigned int nrOfProps;
    objc_property_t *properties = class_copyPropertyList(class, &nrOfProps);
    
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:nrOfProps];
    for (int i = 0; i < nrOfProps; i++) {
        TBObjcProperty *property = [[TBObjcProperty allocWithZone:nil] initWithProperty:properties[i]];
        [result addObject:property];
        [property release];
    }
    
    free(properties);
    
    if ([self hasClass:class_getSuperclass(class)]) {
        [result addObjectsFromArray:[self objcPropertiesForClass:class_getSuperclass(class)]];
    }
    
    return (NSArray *)result;
}

- (NSArray *)objcPropertiesForCacao:(NSString *)name {
    Class class = objc_getClass([[configManager.configCacaos valueForKeyPath:[name stringByAppendingFormat:@".%@", @"class"]] UTF8String]);
    
    return [self objcPropertiesForClass:class];
}

- (void) setForCacao: (id) cacao autowireCacao: (id) cacaoToAutowire  {
    NSArray *objcProperties = [self objcPropertiesForClass:[cacao class]];
    
    for (TBObjcProperty *property in objcProperties) {
        if ([[[cacaoToAutowire class] classAsString] isEqualToString:property.nameOfClass]) {
            [cacao setValue:cacaoToAutowire forKey:property.name];
        }
    }
}

- (void) autowireCacao:(id)cacao cacaosToAutowire:(NSArray *)cacaosToAutowire  {
    for (NSString *autowireCacaoName in cacaosToAutowire) {
        id cacaoToAutowire = [self cacaoForName:autowireCacaoName];
        
        [self setForCacao: cacao autowireCacao: cacaoToAutowire];
    }
}

- (id) createCacao:(NSDictionary *)config {
    NSString *name = [config objectForKey:@"name"];
    id cacao = [cacaos objectForKey:name];
    
    if (cacao) {
        return cacao;
    }
    
    NSString *className = [config objectForKey:@"class"];
    cacao = class_createInstance(objc_getClass([className UTF8String]), 0);
    
    if (cacao == nil) {
        log4Warn(@"Cacao \"%@\" could not be created since the class \"%@\" does not seem to be present.", name, className);
        
        return nil;
    }
    
    [cacao init];
    [cacaos setObject:cacao forKey:name];
    [cacao release];
    
    log4Info(@"Cacao \"%@\" of class \"%@\" created.", name, className);
    
    return cacao;
}

- (NSString *)classNameOfManualCacao: (NSString *) name  {
    for (NSDictionary *manualCacaoConfig in configManager.configManualCacaos) {
        if ([[manualCacaoConfig objectForKey:@"name"] isEqualToString:name]) {
            return [manualCacaoConfig objectForKey:@"class"];
        }        
    }
    
    return nil;
}

- (id)manualCacaoFromFirstProviderHavingPropertyClass:(NSString *)className {
    
    for (id provider in manualCacaoProviders) {
        NSArray *properties = [[provider class] objcProperties];
        
        for (TBObjcProperty *property in properties) {
        
            if ([property.nameOfClass isEqualToString:className]) {
                return [provider valueForKey:property.name];
            }
            
        }
        
    }
    
    log4Fatal(@"There is no manual Cacao provider which has a property with the class \"%@.\"", className);
    
    return nil;
}

- (id)createManualCacao:(NSString *)name {
    id manualCacao = [self manualCacaoFromFirstProviderHavingPropertyClass:[self classNameOfManualCacao:name]];
    
    log4Info(@"Manual Cacao \"%@\" created.", name);
    
    return manualCacao;
}

- (void) autowireAllCacaos {
    for (NSDictionary *cacaoConfig in configManager.configManualCacaos) {
        NSString *name = [cacaoConfig objectForKey:@"name"];
        
        [self autowireCacao:[self cacaoForName:name] cacaosToAutowire:[cacaoConfig objectForKey:@"autowire"]];
        
        log4Info(@"Manual Cacao \"%@\" autowired.", name);
    }
    
    for (NSDictionary *cacaoConfig in configManager.configCacaos) {
        NSString *name = [cacaoConfig objectForKey:@"name"];
        id cacao = [self cacaoForName:name];
        
        if (cacao) {
            [self autowireCacao:[self cacaoForName:name] cacaosToAutowire:[cacaoConfig objectForKey:@"autowire"]];
            log4Info(@"Cacao \"%@\" autowired.", name);
        } else {
            log4Info(@"Cacao \"%@\" is not there and therefore cannot be autowired.", name);
        }
    }
}

- (void) createAllManualCacaos {
    for (NSDictionary *cacaoConfig in configManager.configManualCacaos) {
        NSString *name = [cacaoConfig objectForKey:@"name"];
        
        id manualCacao = [self createManualCacao:name];
        
        [cacaos setObject:manualCacao forKey:name];
        
        log4Debug(@"%d", (int)[manualCacao retainCount]);
    }
}

- (void) createAllCacaos {
    for (NSDictionary *cacaoConfig in configManager.configCacaos) {
        [self createCacao:cacaoConfig];
    }
}


- (void)initializeCacao {
    log4Info(@"Cacao initialization started.");
    
    if (configManager == nil) {
        log4Fatal(@"No config manager present.");

        return;
    }

    [configManager readConfigWithPossibleError:nil];
    
    cacaos = [[NSMutableDictionary allocWithZone:nil] initWithCapacity:([configManager.configCacaos count] + [configManager.configManualCacaos count])];
    
    [self buildManualCacaoProvidersFrom:configManager.configManualCacaoProviders];
    
    [self createAllManualCacaos];
    
    [self createAllCacaos];
    
   	[self autowireAllCacaos];
    
    log4Info(@"Cacao initialization finished.");
}

- (id)cacaoForName:(NSString *)name {
    return [cacaos objectForKey:name];
}


+ (TBCacao *)cacao {
    @synchronized(self) {
        if (cacao == nil) {
            cacao = [[self allocWithZone:nil] init];
        }
        
        return cacao;
    }
    
    return nil;
}

- (void)dealloc {
    [configManager release];
    [manualCacaoProviders release];
    [cacaos release];

    [super dealloc];
}


@end