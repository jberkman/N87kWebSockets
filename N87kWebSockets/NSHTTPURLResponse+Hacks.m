//
//  NSHTTPURLResponse+Hacks.m
//  N87kWebSockets
//
//  Created by jacob berkman on 2014-09-25.
//  Copyright (c) 2014 jacob berkman. All rights reserved.
//

#import "NSHTTPURLResponse+Hacks.h"

@implementation NSHTTPURLResponse (Hacks)

+ (id)N87k_responseWithURL:(NSURL *)url statusCode:(NSInteger)statusCode HTTPVersion:(NSString *)HTTPVersion headerFields:(NSDictionary *)headerFields {
    return [[self alloc] initWithURL:url statusCode:statusCode HTTPVersion:HTTPVersion headerFields:headerFields];
}

@end
