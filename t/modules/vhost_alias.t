use strict;
use warnings FATAL => 'all';
use Apache::Test;
use Apache::TestRequest;
use Apache::TestConfig ();

my $url = '/index.html';

my $cgi_name = "test-cgi.sh";
my $cgi_string = "test cgi for";

my @vh = qw(www.vha-test.com big.server.name.from.heck.org ab.com w-t-f.net);

plan tests => @vh * 2, ['vhost_alias'] && \&have_cgi;

my $config = Apache::TestRequest::test_config();
my $vars = Apache::TestRequest::vars();
local $vars->{port} = $config->port('mod_vhost_alias');

## test environment setup ##
mkdir "htdocs/modules/vhost_alias" unless -e "htdocs/modules/vhost_alias";
my @d = ();
foreach (@vh) {
    my @part = split /\./, $_;
    my $d = "htdocs/modules/vhost_alias/";

    ## create VirtualDocumentRoot htdocs/modules/vhost_alias/%2/%1.4/%-2/%2+
    ## %2 ##
    if ($part[1]) {
        $d .= $part[1];
    } else {
        $d .= "_";
    }
    mkdir $d or die "cant mkdir $d: $!";
    $d .= "/";

    ## %1.4 ##
    if (length($part[0]) < 4) {
        $d .= "_";
    } else {
        $d .= substr($part[0], 3, 1);
    }
    mkdir $d or die "cant mkdir $d: $!";
    $d .= "/";

    ## %-2 ##
    if ($part[@part-2]) {
        $d .= $part[@part-2];
    } else {
        $d .= "_";
    }
    mkdir $d or die "cant mkdir $d: $!";
    $d .= "/";

    ## %2+ ##
    for (my $i = 1;$i < @part;$i++) {
        $d .= $part[$i];
        $d .= "." if $part[$i+1];
    }
    mkdir $d or die "cant mkdir $d: $!";

    ## save directory for later deletion ##
    push (@d, $d);

    ## write index.html for the VirtualDocumentRoot ##
    open (HTML, ">$d$url") or die "cant open $d$url: $!";
    print HTML $_;
    close (HTML);

    ## create directories for VirtualScriptAlias tests ##
    $d = "htdocs/modules/vhost_alias/$_";
    mkdir $d or die "cant create $d: $!";
    push(@d, $d);
    $d .= "/";

    ## write cgi ##
    my $cgi_content = <<SCRIPT;
#!/bin/sh
echo Content-type: text/html
echo
echo $cgi_string $_
SCRIPT

    open (CGI, ">$d$cgi_name") or die "cant open $d$cgi_name: $!";
    print CGI $cgi_content;
    close (CGI);
    chmod 0755, "$d$cgi_name";

}

## run tests ##
foreach (@vh) {
    ## test VirtalDocumentRoot ##
    my $expected = $_;
    my $actual = GET_BODY $url, Host => $_;
    print "[VirtalDocumentRoot test]\n";
    print "expected: ->$expected<-\nactual: ->$actual<-\n";
    ok $actual eq $expected;

    ## test VirtualScriptAlias ##
    my $cgi_uri = "/cgi-bin/$cgi_name";
    $expected = "$cgi_string $_";
    $actual = GET_BODY $cgi_uri, Host => $_;
    chomp $actual;
    print "[VirtualScriptAlias test]\n";
    print "expected: ->$expected<-\nactual: ->$actual<-\n";
    ok $actual eq $expected;
}

## clean up ##
foreach (@d) {
    unlink "$_/index.html" if -e "$_/index.html";
    unlink "$_/$cgi_name" if -e "$_/$cgi_name";

    my @del = ();
    my $dir = '';
    foreach my $sd (split /\//, $_) {
        $dir .= "$sd/";
        next unless $dir =~ /^htdocs\/modules\/vhost_alias\/\w+/;

        push(@del, $dir);
    }

    while (1) {
        for (my $i = 0;$i <= @del;$i++) {
            splice(@del, $i, 1) if rmdir $del[$i];
        }

        last unless @del;

    }
}
rmdir "htdocs/modules/vhost_alias";
