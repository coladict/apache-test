use strict;
use warnings FATAL => 'all';

use Apache::Test;
use Apache::TestRequest;
use Ext-Modules::TestEnv;

plan tests => 1, \&Ext-Modules::TestEnv::has_php4;

my $expected = <<EXPECT;
hey=0, 0
hey=1, -1
hey=2, -2
EXPECT

my $result = GET_BODY "/php/func2.php";
ok $result eq $expected;
