use strict;
use warnings FATAL => 'all';

use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest;

plan tests => 1, need_min_apache_version('2.1.0');

my $resp;

$resp = GET_BODY "/modules/cgi/ranged.pl",
    Range => 'bytes=5-10/10';

ok t_cmp($resp, "hello\n", "return correct content");
