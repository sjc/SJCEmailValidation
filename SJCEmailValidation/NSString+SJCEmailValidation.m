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

#import "NSString+SJCEmailValidation.h"
#include <arpa/inet.h>

NSString *const SJCEmailAddressErrorDomain = @"SJCEmailAddressErrorDomain";
NSString *const SJCEmailAddressLocationKey = @"SJCEmailAddressLocationKey";

static inline NSError *StreamError(CFStreamError streamError);
static void HostResolutionCallback(CFHostRef theHost, CFHostInfoType typeInfo, const CFStreamError *error, void *info);

const NSUInteger maxTotalLength = 254;
const NSUInteger maxLocalLength = 64;
const NSUInteger maxDomainLength = 255; // yes, i know this doesn't make sense
const NSUInteger maxDomainPartLength = 63;

NSError *Error(SJCEmailAddressError code, NSUInteger location, NSError *underlying) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if(underlying) { userInfo[NSUnderlyingErrorKey] = underlying; }
    if(NSNotFound != location) { userInfo[SJCEmailAddressLocationKey] = @(location); }
    NSString *message = nil;
    switch(code) {
        case kSJCEmailAddressErrorTooLong: message = [NSString stringWithFormat: @"Address is too long (longer than %d characters)", maxTotalLength];
            break;
        case kSJCEmailAddressErrorLocalTooLong: message = [NSString stringWithFormat: @"Local part of address is too long (longer than %d characters)", maxLocalLength];
            break;
        case kSJCEmailAddressErrorDomainTooLong: message = [NSString stringWithFormat: @"Whole domain part of address is too long (longer than %d characters)", maxDomainLength];
            break;
        case kSJCEmailAddressErrorDomainPartTooLong: message = [NSString stringWithFormat: @"Domain name part too long (longer than %d characters)", maxDomainPartLength];
            // TODO: get location informaton for this
            break;
        case kSJCEmailAddressErrorInvalidCharacterInLocalPart: message = [NSString stringWithFormat: @"Invalid character in local part (at index %d)", location];
            break;
        case kSJCEmailAddressErrorInvalidLocalPart: message = @"Local part is invalid";
            break;
        case kSJCEmailAddressErrorNoAtSign: message = @"Couldn't find an '@'";
            break;
        case kSJCEmailAddressErrorInvalidDomain: message = @"Domain is invalid";
            break;
        case kSJCEmailAddressErrorInvalidCharacterInDomain: message = [NSString stringWithFormat: @"Invalid character in domain (at index %d)", location];
            break;
        case kSJCEmailAddressErrorInvalidTLD: message = @"Invalid top level domain name";
            break;
        case kSJCEmailAddressErrorDNSCheckSkipped: message = @"DNS check was skipped";
            break;
        case kSJCEmailAddressErrorDNSCheckFailed: message = @"DNS check failed";
            break;
    }
    if(message) { userInfo[NSLocalizedDescriptionKey] = NSLocalizedString(message, nil); }
    return [NSError errorWithDomain: SJCEmailAddressErrorDomain code: code userInfo: userInfo];
}

// because we'll be doing this a lot
static inline BOOL Done(NSError **error, SJCEmailAddressError code, NSUInteger location, NSError *underlying) {
    if(error) { *error = Error(code, location, underlying); }
    return NO;
}

@interface NSString (SJCEmailValidation_Private)
- (BOOL)sjc_isCorrectlyFormedEmailAddress:(NSError *__autoreleasing *)error domain:(NSString **)domain;
@end

typedef NS_ENUM(int, State) {
    kStateDone,
    kStateStart, // starting a section in the local or domain part
    kStateDot, // just seen a dot (hope we don't see another)
    kStateLeadingComment, // comment at the start of the part
    kStateTrailingComment, // comment at the end of the part
    kStateExpectEnd, // when finishing trailing comments in local parts
    kStateQuoted, // local part quoted by "
    kStateLocal, // local part
    kStateDomain, // domain part, which could potentially be ipv4 or ipv6
};

@implementation NSString (SJCEmailValidation)

- (BOOL)sjc_isCorrectlyFormedEmailAddress {
    return [self sjc_isCorrectlyFormedEmailAddress: NULL domain: NULL];
}

- (BOOL)sjc_isCorrectlyFormedEmailAddress:(NSError **)error {
    return [self sjc_isCorrectlyFormedEmailAddress: error domain: NULL];
}

- (BOOL)sjc_isCorrectlyFormedEmailAddress:(NSError *__autoreleasing *)error domain:(NSString *__autoreleasing *)dom {
    
    static NSCharacterSet *validLocalCharacters = nil;
    static NSCharacterSet *validDomainCharacters = nil;
    static NSCharacterSet *validIPv4Characters = nil;
    static NSCharacterSet *validIPv6Characters = nil;
    static NSCharacterSet *validAlphaCharacters = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        validLocalCharacters = [NSCharacterSet characterSetWithCharactersInString: @"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!#$%&'*+-/=?^_`{|}~."];
        validDomainCharacters = [NSCharacterSet characterSetWithCharactersInString: @"0123456789-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"];
        validIPv4Characters = [NSCharacterSet characterSetWithCharactersInString: @"0123456789"];
        validIPv6Characters = [NSCharacterSet characterSetWithCharactersInString: @"0123456789abcdefABCDEF"];
        validAlphaCharacters = [NSCharacterSet characterSetWithCharactersInString: @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-"];
    });

    NSString *email = [self stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSUInteger length = email.length;
    if(length > maxTotalLength) {
        return Done(error, kSJCEmailAddressErrorTooLong, NSNotFound, nil);
    }
    
    unichar buffer[maxTotalLength];

    [email getCharacters: buffer range: NSMakeRange(0, length)];

    NSCharacterSet *valid = validLocalCharacters;
    NSInteger loc = 0;
    NSInteger depth = 0;
    State state = kStateStart;
    
    // forward parse the local part of the address
    while(state != kStateDone && loc != length) {

        unichar ch = buffer[loc++];

        switch(state) {
            case kStateStart:
                if('(' == ch) {
                    // starting a comment
                    state = kStateLeadingComment;
                    depth = 1;
                    break;
                }
                // drop through to other possibilities...
                
            case kStateDot:
                if('.' == ch || '@' == ch) {
                    return Done(error, kSJCEmailAddressErrorInvalidCharacterInLocalPart, loc - 1, nil);
                }
                else if('"' == ch) {
                    // starting a quoted section
                    state = kStateQuoted;
                    break;
                }
                else if(![valid characterIsMember: ch]) {
                    return Done(error, kSJCEmailAddressErrorInvalidCharacterInLocalPart, loc - 1, nil);
                }
                state = kStateLocal;
                break;
                
            case kStateLocal:
                if('.' == ch) {
                    state = kStateDot;
                }
                else if('(' == ch) {
                    state = kStateTrailingComment;
                    depth = 1;
                }
                else if('\\' == ch) {
                    loc++; // skip the escaped character and continue
                }
                else if('@' == ch) {
                    state = kStateDone;
                }
                else if(![valid characterIsMember: ch]) {
                    return Done(error, kSJCEmailAddressErrorInvalidCharacterInLocalPart, loc - 1, nil);
                }
                break; // okay to keep going for the next char
                
            case kStateLeadingComment:
            case kStateTrailingComment:
                if('(' == ch) {
                    depth++;
                }
                else if(')' == ch) {
                    depth--;
                    if(0 == depth) {
                        state = kStateTrailingComment == state ? kStateExpectEnd : kStateStart;
                    }
                }
                // this assumes that we allow absolutely everything else in comments
                break;
                
            case kStateExpectEnd:
                if('@' != ch) {
                    return Done(error, kSJCEmailAddressErrorInvalidLocalPart, loc - 1, nil);
                }
                state = kStateDone;
                break;

            case kStateQuoted:
                if('\\' == ch && '"' == buffer[loc]) {
                    // a quote mark may appear escaped with a slash
                    loc++;
                }
                else if('"' == ch) {
                    // a quote must mark the end of a section, being followed by '.', '@' or '('
                    ch = buffer[loc];
                    if(!('.' == ch || '@' == ch || '(' == ch)) {
                        return Done(error, kSJCEmailAddressErrorInvalidCharacterInLocalPart, loc - 1, nil);
                    }
                    state = kStateLocal;
                }
                break;
                   
            default: break;
        }
    }
    
    if(kStateDone != state || loc == length) {
        return Done(error, kSJCEmailAddressErrorNoAtSign, NSNotFound, nil);
    }
    
    if(loc > maxLocalLength) {
        return Done(error, kSJCEmailAddressErrorLocalTooLong, NSNotFound, nil);
    }
    
    // forward parse the domain part
    valid = validDomainCharacters;
    state = kStateStart;
    
    BOOL ip = NO; // are we parsing a domain name or an ip address
    BOOL ipv6 = NO; // if we're parsing an ip address
    
    NSUInteger start = 0;
    NSUInteger end = 0;
    
    while(loc != length) {
        
        unichar ch = buffer[loc++];
        
        switch(state) {
            case kStateStart:
                if('(' == ch) {
                    // starting a comment
                    state = kStateLeadingComment;
                    depth = 1;
                    break;
                }
                else if('[' == ch) { // also '{' ???
                    // this is an ip address
                    ip = YES;
                    if(length >= loc + 4 && NSOrderedSame == [email compare: @"ipv6:" options: NSCaseInsensitiveSearch range: NSMakeRange(loc, 5)])
                    {
                        ipv6 = YES;
                        valid = validIPv6Characters;
                        loc += 5;
                    }
                    else {
                        valid = validIPv4Characters;
                    }
                    start = loc;
                    state = kStateDomain;
                    break;
                }
                // drop through to other possibilities...
                
            case kStateDot:
                if('.' == ch || '-' == ch) {
                    // double dots or hyphen at start of domain part
                    return Done(error, kSJCEmailAddressErrorInvalidCharacterInDomain, loc - 1, nil);
                }
                else if(![valid characterIsMember: ch]) {
                    return Done(error, kSJCEmailAddressErrorInvalidCharacterInDomain, loc - 1, nil);
                }
                if(!start) { start = loc - 1; }
                state = kStateDomain;
                break;
                
            case kStateDomain:
                if(!ipv6 && '.' == ch) {
                    state = kStateDot;
                }
                else if(ipv6 && ':' == ch) {
                    break;
                }
                else if('(' == ch) {
                    end = loc - 1; // but keep going
                    state = kStateTrailingComment;
                    depth = 1;
                }
                else if(ip && ']' == ch) {
                    end = loc - 1;
                    if(loc == length) {
                        state = kStateExpectEnd;
                    } else if('(' == buffer[loc]) {
                        state = kStateTrailingComment;
                        loc++;
                    } else {
                        return Done(error, kSJCEmailAddressErrorInvalidCharacterInDomain, loc - 1, nil);
                    }
                }
                else if('-' == ch && (loc == length || '.' == buffer[loc])) {
                    // hyphen at end of domain part
                    return Done(error, kSJCEmailAddressErrorInvalidCharacterInDomain, loc - 1, nil);
                }
                else if(![valid characterIsMember: ch]) {
                    return Done(error, kSJCEmailAddressErrorInvalidCharacterInDomain, loc - 1, nil);
                }
                break; // okay to keep going for the next char
                
            case kStateLeadingComment:
            case kStateTrailingComment:
                if('(' == ch) {
                    depth++;
                }
                else if(')' == ch) {
                    depth--;
                    if(0 == depth) {
                        if(kStateLeadingComment == state) {
                            state = kStateStart;
                        } else {
                            if(loc == length) {
                                state = kStateExpectEnd;
                            } else {
                                return Done(error, kSJCEmailAddressErrorInvalidCharacterInDomain, loc - 1, nil);
                            }
                        }
                    }
                    else if(depth < 0) {
                        return Done(error, kSJCEmailAddressErrorInvalidDomain, loc - 1, nil);
                    }
                }
                // this assumes that we allow absolutely everything else in comments
                break;
                
            case kStateExpectEnd:
                return Done(error, kSJCEmailAddressErrorInvalidDomain, loc - 1, nil);
                break;
                
            default: break;
        }
    }
    
    if(0 == end) { end = length; }
    
    if(end - start > maxDomainLength) {
        return Done(error, kSJCEmailAddressErrorDomainTooLong, NSNotFound, nil);
    }
    
    NSString *domain = [NSString stringWithCharacters: buffer + start length: end - start];
    
    if(ip) {
        // check that the IP address can be correctly parsed by code written by someone who knows what they're doing
        uint8_t addr[16];
        if(1 != inet_pton(ipv6 ? AF_INET6 : AF_INET, [domain cStringUsingEncoding: NSASCIIStringEncoding], addr)) {
            return Done(error, kSJCEmailAddressErrorInvalidDomain, NSNotFound, nil);
        }

    } else {
        NSArray *parts = [domain componentsSeparatedByString: @"."];
        if(parts.count < 2) {
            return Done(error, kSJCEmailAddressErrorInvalidDomain, NSNotFound, nil);
        }
        
        NSEnumerator *en = [parts reverseObjectEnumerator];
        
        // if the domain ends in . we can throw away the first (last) part
        NSString *part = [en nextObject];
        if(![domain hasSuffix: @"."]) {
            // this checks that the top level domain is at least 2 chars... which may bite us one day
            NSUInteger len = part.length;
            if(len < 2 || len > maxDomainPartLength) {
                return Done(error, kSJCEmailAddressErrorInvalidDomain, NSNotFound, nil);
            }
            // check that there is at least one non-numeric character in the TLD
            if(NSNotFound == [part rangeOfCharacterFromSet: validAlphaCharacters].location) {
                return Done(error, kSJCEmailAddressErrorInvalidTLD, NSNotFound, nil);
            }
        }
        
        // check the other parts
        for(NSString *part in en) {
            if(part.length > maxDomainPartLength) {
                return Done(error, kSJCEmailAddressErrorDomainPartTooLong, NSNotFound, nil);
            }
        }
    }
    
    // if we were asked to return the domain, and it wasn't a dotted quad, then do so
    if(dom && !ip) { *dom = domain; }
    
    return YES;
}

- (void)sjc_checkEmailAddress:(void(^)(NSString *email, BOOL isValid, NSError *error))block {
    
    if(nil == block) { return; } // i mean really, why bother?
    
    NSError *error = nil;
    NSString *domain = nil;
    
    // check whether the email address is correctly formed
    if(![self sjc_isCorrectlyFormedEmailAddress: &error domain: &domain]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(self, NO, error);
        });
        return;
    }
    
    // did we get a domain back?
    if(nil == domain) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(self, YES, Error(kSJCEmailAddressErrorDNSCheckSkipped, 0, nil));
        });
        return;
    }
    
    // if we've got this far then we have a valid-looking domain name we can perform a DNS lookup against
    CFHostRef host = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)domain);

    void(^callback)(BOOL valid, NSError *underlying) = ^(BOOL valid, NSError *underlying) {
    
        NSError *error = underlying ? Error(kSJCEmailAddressErrorDNSCheckFailed, NSNotFound, underlying) : nil;

        dispatch_async(dispatch_get_main_queue(), ^{
            // if we had an error, this will still return YES because the basic validation passed
            // if we had no errors, return the result of DNS validation
            block(self, valid, error);
        });
        
        CFHostSetClient(host, NULL, NULL);
        CFRelease(host);
    };
    
    CFHostClientContext context = { 0, (void *)CFBridgingRetain(callback), NULL, NULL, NULL };

    if(!CFHostSetClient(host, HostResolutionCallback, &context)) {
        NSError *underlying = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            block(self, YES, Error(kSJCEmailAddressErrorDNSCheckFailed, NSNotFound, underlying));
        });
        CFRelease(host);
        return;
    }
    
    CFHostScheduleWithRunLoop(host, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    
    CFStreamError streamError;
    if(!CFHostStartInfoResolution(host, kCFHostAddresses, &streamError)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(self, YES, Error(kSJCEmailAddressErrorDNSCheckFailed, NSNotFound, StreamError(streamError)));
        });
        CFHostSetClient(host, NULL, NULL);
        CFRelease(host);
        return;
    }
}

@end

static void HostResolutionCallback(CFHostRef theHost, CFHostInfoType typeInfo, const CFStreamError *error, void *info) {

    void (^block)(BOOL valid, NSError *underlying) = CFBridgingRelease(info);

    NSError *underlying = nil;
    BOOL valid = YES;
    
    if(error == NULL || (error->domain == 0 && error->error == 0)) {
        Boolean hasBeenResolved;
        NSArray *results = (__bridge NSArray *)CFHostGetAddressing(theHost, &hasBeenResolved);
        // only change validity to NO if resolution succeeded but returned no results
        if(hasBeenResolved && 0 == results.count) { valid = NO; }

    } else {
        underlying = StreamError(*error);
    }
    
    block(valid, underlying);
}

// convert (roughly) a CFStreamError to an NSError
static inline NSError *StreamError(CFStreamError streamError) {
    if(0 == streamError.domain) { return nil; }
    NSString *dom = nil;
    switch(streamError.domain) {
        case kCFStreamErrorDomainPOSIX: dom = NSPOSIXErrorDomain; break;
        case kCFStreamErrorDomainMacOSStatus: dom = NSOSStatusErrorDomain; break;
        default: dom = (__bridge NSString *)kCFErrorDomainCFNetwork; break;
    }
    return [NSError errorWithDomain: dom code: streamError.error userInfo: nil];
}
