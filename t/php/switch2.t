use strict;
use warnings FATAL => 'all';

use Apache::Test;
use Apache::TestRequest;
use Ext-Modules::TestEnv;

plan tests => 1, \&Ext-Modules::TestEnv::has_php4;

my $expected = <<EXPECT;
In branch 1
Inner default...
blah=100
In branch 1
Inner default...
blah=100
In branch 1
Inner default...
blah=100
In branch 1
Inner default...
blah=100
In branch 1
Inner default...
blah=100
In branch 1
Inner default...
blah=100
In branch 1
Inner default...
blah=100
In branch 1
Inner default...
blah=100
In branch 1
Inner default...
blah=100
In branch 1
Inner default...
blah=100
EXPECT

my $result = GET_BODY "/php/switch2.php";
ok $result eq $expected;
