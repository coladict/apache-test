use strict;
use warnings FATAL => 'all';

use Apache::Test;
use Apache::TestRequest;

## testing include

plan tests => 1, test_module 'php4';

my $expected = "Hello";

my $result = GET_BODY "/php/include.php";
ok $result eq $expected;
