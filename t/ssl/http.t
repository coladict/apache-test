use strict;
use warnings FATAL => 'all';
use Apache::Test;
use Apache::TestRequest;
use Apache::TestUtil;

#verify we can send an non-ssl http request to the ssl port
#without dumping core.

my $url = '/index.html';

my @todo;

if (Apache::TestConfig::WIN32) {
    print "\n#ap_core_translate() chokes on ':' here\n",
          "#where r->uri = /mod_ssl:error:HTTP-request\n";
    @todo = (todo => [2]);
}

plan tests => 2, @todo;

my $config = Apache::Test::config();
my $ssl_module = $config->{vars}->{ssl_module_name};
my $hostport = $config->{vhosts}->{$ssl_module}->{hostport};
my $rurl = "http://$hostport$url";

my $res = GET($rurl);
ok t_cmp(400,
         $res->code,
         "Expected bad request from 'GET $rurl'"
        );

ok t_cmp(qr{speaking plain HTTP to an SSL-enabled server port},
         $res->content,
         "that error document contains the proper hint"
        );

