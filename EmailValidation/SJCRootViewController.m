//
//  SJCRootViewController.m
//  EmailValidation
//
//  Created by Stuart Crook on 31/01/2014.
//  Copyright (c) 2014 Stuart Crook. All rights reserved.
//

#import "SJCRootViewController.h"
#import "NSString+SJCEmailValidation.h"

@interface SJCRootViewController ()
- (void)validateEmailAddress;
@end
		
@implementation SJCRootViewController

- (void)validateEmailAddress {
    
    NSString *email = [_textfield.text stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    [email sjc_checkEmailAddress:^(NSString *email, BOOL isValid, NSError *error) {
       
        // yeah, i know accessing ivars like this leads to self being retained. this
        // is meant to be a quick demo, what do you expect? (no, don't answer that)
        
        NSString *message = nil;
        
        if(NO == isValid) {
            // definitely didn't work
            message = [@"Validation failed: " stringByAppendingString: error.localizedDescription];
        
        } else if(error.code == kSJCEmailAddressErrorDNSCheckSkipped) {
            message = @"Validation passed (DNS check skipped)";
        
        } else if(error.code == kSJCEmailAddressErrorDNSCheckFailed) {
            message = [NSString stringWithFormat: @"Validation passed (DNS check failed with network error: %@)", error.localizedDescription];
        
        } else {
            message = @"Validation passed";
        }
        
        _resultLabel.text = message;
        
        [UIView animateWithDuration: 0.25 animations: ^{
            _resultLabel.alpha = 1.0f;
            _spinner.alpha = 0.0f;
        }];
        
    }];
    
    [UIView animateWithDuration: 0.25 animations: ^{
        _resultLabel.alpha = 0.0f;
        _spinner.alpha = 1.0f;
    }];
}

- (IBAction)validateTapped:(id)sender {
    
    NSString *email = [_textfield.text stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if(email.length) {
        [self validateEmailAddress];
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self validateTapped: nil];
    });
    return YES;
}

@end
