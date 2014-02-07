/*
 The MIT License (MIT)
 
 Copyright (c) 2014 Stuart Crook
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 the Software, and to permit persons to whom the Software is furnished to do so,
 subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import <Foundation/Foundation.h>

// the error domain under which these specific errors are produced
extern NSString *const SJCEmailAddressErrorDomain;

// the character offset into the address at which the issue was discovered
extern NSString *const SJCEmailAddressLocationKey;

// error codes within SJCEmailAddressErrorDomain
typedef NS_ENUM(NSUInteger, SJCEmailAddressError) {
    kSJCEmailAddressErrorTooLong,
    kSJCEmailAddressErrorLocalTooLong,
    kSJCEmailAddressErrorDomainTooLong,     // the whole domain after the @ is too long
    kSJCEmailAddressErrorDomainPartTooLong, // an individual part of the domain is too long

    kSJCEmailAddressErrorInvalidCharacterInLocalPart,
    kSJCEmailAddressErrorInvalidLocalPart,

    kSJCEmailAddressErrorNoAtSign,
    
    kSJCEmailAddressErrorInvalidDomain,
    kSJCEmailAddressErrorInvalidCharacterInDomain,
    kSJCEmailAddressErrorInvalidTLD,
    
    kSJCEmailAddressErrorDNSCheckSkipped = 100, // returned when no domain was available eg. ip address
    kSJCEmailAddressErrorDNSCheckFailed = 101, // examine the underlying error for failure reason
};


@interface NSString (SJCEmailValidation)

/** Check whether an email address is correctly formed, optionally returning an
    error detailing the first mistake identified in the address.
 */
- (BOOL)sjc_isCorrectlyFormedEmailAddress:(NSError **)error;

/** As -sjc_isCorrectlyFormedEmailAddress: but without the optional error parameter,
    for people who don't care or have narrow monitors
 */
- (BOOL)sjc_isCorrectlyFormedEmailAddress;

/** Checks 1) whether an email address is correctly formed, as above, and then, if 
    it appears to be correctly formed, 2) whether the domain part of the email can
    be mapped via DNS to a valid IP address.
 
    The block is executed asynchronously on the main thread, even in cases when the 
    initial check for correctness of form fails.
 
    In the cases where DNS lookup either isn't performed (eg. because the domain is
    a raw IP address) or fails (eg. due to a networking error), isValid will return 
    the result of the check for correctness (which will be YES). How you interpret 
    this is up to you, but bear in mind that the presence of an error won't always 
    signify that an email address failed validation.
 */
- (void)sjc_checkEmailAddress:(void(^)(NSString *email, BOOL isValid, NSError *error))block;

@end
