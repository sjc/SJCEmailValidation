SJCEmailValidation
==================

Validate an email address by (1) checking that it appears to be correctly formed, and (2) performing a DNS check that its domain portion can be correctly resolved.

The code is implemented as a category on NSString. To use them, add SJCEmailValidation.h and .m (from /SJCEmailValidation) to your iOS or Mac OS X project. An example iOS project is included under /EmailValidation to demonstrate their use.

Simple, synchronous checking of the formatting of the email address can be performed using `sjc_isCorrectlyFormedEmailAddress:` (or `sjc_isCorrectlyFormedEmailAddress` if you aren't bothered with getting a descriptive error back).

To also perform a DNS check, call `sjc_checkEmailAddress:`. This method will perform the same check for formatting before attempting DNS lookup if the domain of the email address is not an IP address. The block will be called asynchronously on the main dispatch queue (so even if the initial formatting check fails, the block will be invoked at a later point). The isValid parameter may be YES even if an error is also returned. This will typically happen if the DNS check is skipped or fails due to eg. networking issues. Therefore you should check both the value of isValid and the error parameter and decide whether to accept the email address as valid based on both of these.

This library is in constant development. If you find valid email addresses which are not correctly identified as such (or vice versa) please let me know.

The list of valid and invalid email addresses used in the tests is based on the one found [here][http://blogs.msdn.com/b/testing123/archive/2009/02/05/email-address-test-cases.aspx], with the additional addresses added from [here][href="http://codefool.tumblr.com/post/15288874550/list-of-valid-and-invalid-email-addresses].
