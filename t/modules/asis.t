use strict;
use warnings FATAL => 'all';

use Apache::Test;
use Apache::TestRequest;
use Apache::TestUtil;

## 
## mod_asis tests
##

plan tests => 3;

my $body = GET_BODY "/modules/asis/foo.asis";
ok t_cmp("This is asis content.\n", $body, "asis content OK");

my $rc = GET_RC "/modules/asis/notfound.asis";
ok t_cmp(404, $rc, "asis gave 404 error");

$rc = GET_RC "/modules/asis/forbid.asis";
ok t_cmp(403, $rc, "asis gave 403 error");
