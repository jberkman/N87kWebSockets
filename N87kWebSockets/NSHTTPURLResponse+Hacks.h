//
//  NSHTTPURLResponse+Hacks.h
//  N87kWebSockets
//
//  Created by jacob berkman on 2014-09-25.
//  Copyright (c) 2014 jacob berkman. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSHTTPURLResponse (Hacks)

+ (id)N87k_responseWithURL:(NSURL *)url statusCode:(NSInteger)statusCode HTTPVersion:(NSString *)HTTPVersion headerFields:(NSDictionary *)headerFields;

@end
