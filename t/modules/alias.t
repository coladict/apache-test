use strict;
use warnings FATAL => 'all';

use Apache::Test;
use Apache::TestRequest;
use Apache::TestConfig;

##
## mod_alias test
##

## redirect codes for Redirect testing ##
my %redirect = (
    perm     =>  '301',
    perm2    =>  '301',
    temp     =>  '302',
    temp2    =>  '302',
    seeother =>  '303',
    gone     =>  '410'
);

## RedirectMatch testing ##
my %rm_body = (
    p   =>  '301',
    t   =>  '302'
);

my %rm_rc = (
    s   =>  '303',
    g   =>  '410'
);


plan tests => (keys %redirect) + (keys %rm_body) * 10 + (keys %rm_rc) * 10 + 16,
    test_module 'alias';

## simple alias ##
ok ('200' eq GET_RC "/alias/");
## alias to a non-existant area ##
ok ('404' eq GET_RC "/bogu/");


for (my $i=0 ; $i <= 9 ; $i++) {
    ok ("$i" eq GET_BODY "/ali$i");
}

my ($actual, $expected);
foreach (keys %redirect) {
    ## make LWP not follow the redirect since we
    ## are just interested in the return code.
    local $Apache::TestRequest::RedirectOK = 0;

    $expected = $redirect{$_};
    $actual = GET_RC "/$_";
    ok ($actual eq $expected);
}

foreach (keys %rm_body) {
    for (my $i=0 ; $i <= 9 ; $i++) {
        $expected = $i;
        $actual = GET_BODY "/$_$i";
        ok ($actual eq $expected);
    }
}

foreach (keys %rm_rc) {
    $expected = $rm_rc{$_};
    for (my $i=0 ; $i <= 9 ; $i++) {
        $actual = GET_RC "$_$i";
        ok ($actual eq $expected);
    }
}

## create a little cgi to test ScriptAlias and ScriptAliasMatch ##
my $string = "this is a shell script cgi.";
my $cgi =<<EOF;
#!/bin/sh
echo Content-type: text/plain
echo
echo $string
EOF

my $config = Apache::TestConfig->thaw;
my $script = "$config->{vars}->{t_dir}/htdocs/modules/alias/script";

open (CGI, ">$script");
print CGI $cgi;
close (CGI);
chmod 0755, $script;

## if we get the script here it will be plain text ##
ok ($cgi eq GET_BODY "/modules/alias/script");

## here it should be the result of the executed cgi ##
ok ("$string\n" eq GET_BODY "/cgi/script");
## with ScriptAliasMatch ##
ok ("$string\n" eq GET_BODY "/cgi-script");

## failure with ScriptAliasMatch ##
ok ('404' eq GET_RC "/cgi-nada");

## clean up ##
unlink $script;
unlink "$config->{vars}->{t_logs}/mod_cgi.log"
    if -e "$config->{vars}->{t_logs}/mod_cgi.log";
