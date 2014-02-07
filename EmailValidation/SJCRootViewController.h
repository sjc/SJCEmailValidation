//
//  SJCRootViewController.h
//  EmailValidation
//
//  Created by Stuart Crook on 31/01/2014.
//  Copyright (c) 2014 Stuart Crook. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SJCRootViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic,retain) IBOutlet UITextField *textfield;
@property (nonatomic,retain) IBOutlet UIButton *validateButton;
@property (nonatomic,retain) IBOutlet UILabel *resultLabel;
@property (nonatomic,retain) IBOutlet UIActivityIndicatorView *spinner;

- (IBAction)validateTapped:(id)sender;

@end
