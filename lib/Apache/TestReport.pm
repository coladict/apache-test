package Apache::TestReport;

use strict;
use warnings FATAL => 'all';

use Apache::Test ();
use Apache::TestConfig ();

use File::Spec::Functions qw(catfile);

# generate t/REPORT script (or a different filename) which will drive
# Apache::TestReport
sub generate_script {
    my ($class, $file) = @_;

    $file ||= catfile 't', 'REPORT';

    local $/;
    my $content = <DATA>;
    $content =~ s/__CLASS__/$class/g;
    Apache::Test::config()->write_perlscript($file, $content);

}

sub build_config_as_string { Apache::TestConfig::as_string() }

1;
__DATA__

use strict;
use FindBin qw($Bin);
use lib "$Bin/../Apache-Test/lib";
use lib 'lib';

use __CLASS__ ();

my %map = (
    CONFIG     => __CLASS__->build_config_as_string,
    EXECUTABLE => $0,
    DATE       => scalar gmtime() . " GMT",
);
{
    local $/ = undef;
    my $template = <DATA>;
    $template =~ s/\@(\w+)\@/$map{$1}||''/eg;
    print $template;
}

__DATA__


-------------8<---------- Start Bug Report ------------8<----------
1. Problem Description:

  [DESCRIBE THE PROBLEM HERE]

2. Used Components and their Configuration:

@CONFIG@

3. This is the core dump trace: (if you get a core dump):

  [CORE TRACE COMES HERE]

This report was generated by @EXECUTABLE@ on @DATE@.

-------------8<---------- End Bug Report --------------8<----------

Note: Complete the rest of the details and post this bug report to
test-dev <at> httpd.apache.org. To subscribe to the list send an empty
email to test-dev-subscribe@httpd.apache.org.
