//
//  EmailValidationTests.m
//  EmailValidationTests
//
//  Created by Stuart Crook on 31/01/2014.
//  Copyright (c) 2014 Stuart Crook. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "NSString+SJCEmailValidation.h"

@interface EmailValidationTests : XCTestCase
@end

@implementation EmailValidationTests

- (void)testValidEmailAddresses {
    
    NSArray *valid = @[
                       @"email@[123.123.123.123]",
                       @"user@[IPv6:2001:db8:1ff::a0b:dbd0]",
                       @"email@example.com",
                       @"firstname.lastname@example.com",
                       @"email@subdomain.example.com",
                       @"firstname+lastname@example.com",
                       @"\"email\"@example.com",
                       @"1234567890@example.com",
                       @"email@example-one.com",
                       @"_______@example.com",
                       @"email@example.name",
                       @"email@example.museum",
                       @"email@example.co.jp",
                       @"firstname-lastname@example.com",
                       @"much.\"more\\ unusual\"@example.com",
                       @"very.unusual.\"@\".unusual.com@example.com",
                       @"very.\"(),:;<>[]\".VERY.\"very@\\\"very\".unusual@strange.example.com",
                       ];
    
    for(NSString *email in valid) {
        NSError *error = nil;
        XCTAssertTrue(YES == [email sjc_isCorrectlyFormedEmailAddress: &error], @"'%@' is a valid email address but failed validation with error: %@", email, error);
    }
    
}

- (void)testInvalidEmailAddresses {
    
    NSArray *invalid = @[
                         @"plainaddress",
                         @"#@%^%#$@#$@#.com",
                         @"@example.com",
                         @"Joe Smith <email@example.com>",
                         @"email.example.com",
                         @"email@example@example.com",
                         @".email@example.com",
                         @"email.@example.com",
                         @"email..email@example.com",
                         @"あいうえお@example.com",
                         @"email@example.com (Joe Smith)",
                         @"email@example",
                         @"email@-example.com",
                         @"email@111.222.333.44444",
                         @"email@example..com",
                         @"Abc..123@example.com",
                         @"\"(),:;<>[\\]@example.com",
                         @"just\"not\"right@example.com",
                         @"this\\ is\"really\"not\\allowed@example.com",
                         ];
    
    for(NSString *email in invalid) {
        XCTAssertFalse([email sjc_isCorrectlyFormedEmailAddress], @"'%@' is a invalid email address but passed validation", email);
    }
    
}

@end
