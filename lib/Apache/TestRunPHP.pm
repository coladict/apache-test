# Copyright 2001-2004 The Apache Software Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
package Apache::TestRunPHP;

use strict;
use warnings FATAL => 'all';

use Apache::TestRun ();
use Apache::TestConfigParse ();
use Apache::TestTrace;
use Apache::TestConfigPHP ();

use vars qw($VERSION);
$VERSION = '1.00'; # make CPAN.pm's r() version scanner happy

use File::Spec::Functions qw(catfile);

#subclass of Apache::TestRun that configures mod_perlish things
use vars qw(@ISA);
@ISA = qw(Apache::TestRun);

sub new_test_config {
    my $self = shift;

    Apache::TestConfigPHP->new($self->{conf_opts});
}

sub configure_php {
    my $self = shift;

    my $test_config = $self->{test_config};

    $test_config->postamble_register(qw(configure_php_inc
                                        configure_php_functions
                                        configure_php_tests));
}

sub configure {
    my $self = shift;

    $self->configure_php;

    $self->SUPER::configure;
}

#if Apache::TestRun refreshes config in the middle of configure
#we need to re-add php configure hooks
sub refresh {
    my $self = shift;
    $self->SUPER::refresh;
    $self->configure_php;
}

1;
__END__

=head1 NAME

Apache::TestRunPHP - configure and run a PHP-based test suite

=head1 SYNOPSIS

  use Apache::TestRunPHP;
  Apache::TestRunPHP->new->run(@ARGV);

=head1 DESCRIPTION

The C<Apache::TestRunPHP> package controls the configuration and
running of the test suite for PHP-based tests.  It's a subclass
of C<Apache::TestRun> and similar in function to C<Apache::TestRunPerl>.

Refer to the C<Apache::TestRun> manpage for information on the
available API.

=head1 EXAMPLE

C<TestRunPHP> works almost identially to C<TestRunPerl>, but in
case you are new to C<Apache-Test> here is a quick getting started
guide.  be sure to see the links at the end of this document for
places to find additional details.

because C<Apache-Test> is a Perl-based testing framework we start
from a C<Makefile.PL>, which should have the following lines (in
addition to the standard C<Makefile.PL> parts):

  use Apache::TestMM qw(test clean);
  use Apache::TestRunPHP ();

  Apache::TestMM::filter_args();

  Apache::TestRunPHP->generate_script();

C<generate_script()> will create a script named C<t/TEST>, the gateway
to the Perl testing harness and what is invoked when you call
C<make test>.  C<filter_args()> accepts some C<Apache::Test>-specific
arguments and passes them along.  for example, to point to a specific
C<httpd> installation you would invoke C<Makefile.PL> as follows

  $ perl Makefile.PL -httpd /my/local/apache/bin/httpd

and C</my/local/apache/bin/httpd> will be propagated throughout the
rest of the process.  note that PHP needs to be active within Apache
prior to configuring the test framework as shown above, either by 
virtue of PHP being compiled into the C<httpd> binary statically or
through an active C<LoadModule> statement within the configuration
located in C</my/local/apache/conf/httpd.conf>.

now, like with C<Apache::TestRun> and C<Apache::TestRunPerl>, you can
place client-side Perl test scripts under C<t/>, such as C<t/01basic.t>,
and C<Apache-Test> will run these scripts when you call C<make test>.
however, what makes C<Apache::TestRunPHP> unique is some added magic
specifically tailored to a PHP environment.  here are the mechanics.

C<Apache::TestRunPHP> will look for PHP test scripts in that match
the following pattern

  t/response/TestFoo/bar.php

where C<Foo> and C<bar> can be anything you like, and C<t/response/Test*>
is case sensitive.  when this format is adhered to, C<Apache::TestRunPHP>
will create an associated Perl test script called C<t/foo/bar.t>, which
will be executed when you call C<make test>.  all C<bar.t> does is issue
a simple GET to C<bar.php>, leaving the actual testing to C<bar.php>.  in
essence, you can forget that C<bar.t> even exists.

what does C<bar.php> look like?  here is an example:

  <?php
    print "1..1\n";
    print "ok 1\n"
  ?>

if it looks odd, that's ok because it is.  I could explain to you exactly
what this means, but it isn't important to understand the gory details.
instead, it is sufficient to understand that when C<Apache::Test> calls
C<bar.php> it feeds the results directly to C<Test::Harness>, a module
that comes with every Perl installation, and C<Test::Harness> expects
what it receives to be formated in a very specific way.  by itself, all
of this is pretty useless, so C<Apache::Test> provides PHP testers with
something much better.  here is a much better example:

  <?php
    // import the Test::More emulation layer
    // see
    //   http://www.perldoc.com/perl5.8.4/lib/Test/More.html
    // for more information
    require 'more.php';

    // plan() the number of tests
    plan(6);

    // call ok() for each test you plan
    ok ('foo' == 'foo', 'foo is equal to foo');
    ok ('foo' != 'foo', 'foo is not equal to foo');

    // ok() can be other things as well
    is ('bar', 'bar', 'bar is bar');
    is ('baz', 'bar', 'baz is baz');
    isnt ('bar', 'beer', 'bar is not beer');
    like ('bar', '/ar$/', 'bar matches ar$');

    diag("printing some debugging information");

    // whoops! one too many tests.  I wonder what will happen...
    is ('biff', 'biff', 'baz is a baz');
?>

the include library C<more.php> is automatically generated by
C<Apache::TestConfigPHP> and configurations tweaked in such a
a way that your PHP scripts can find it without issue.  the 
functions provided by C<more.php> are equivalent in name and
function to those in C<Test::More>, a standard Perl testing
library, so you can see that manpage for details on the syntax
and functionality of each.

at this point, we have enough in place to run some tests from
PHP-land - a C<Makefile.PL> to configure Apache for us, and
a PHP script in C<t/response/TestFoo/bar.php> to send some 
results out to the testing engine.  issuing C<make test>
would start Apache, issue the request to C<bar.php>, generate
a report, and shut down Apache.  the report would look like 
something like this after running the tests in verbose mode
(eg C<make test TEST_VERBOSE=1>):

  t/php/foo....1..6
  ok 1 - foo is equal to foo
  not ok 2 - foo is not equal to foo
  #     Failed test (/src/devel/perl-php-test/t/response/TestPHP/foo.php at line 13)
  ok 3 - bar is bar
  not ok 4 - baz is baz
  #     Failed test (/src/devel/perl-php-test/t/response/TestPHP/foo.php at line 17)
  #           got: 'baz'
  #      expected: 'bar'
  ok 5 - bar is not beer
  ok 6 - bar matches ar$
  # printing some debugging information
  ok 7 - baz is a baz
  FAILED tests 2, 4, 7
          Failed 3/6 tests, 50.00% okay
  Failed Test Stat Wstat Total Fail  Failed  List of Failed
  -------------------------------------------------------------------------------
  t/php/foo.t                6    3  50.00%  2 4 7
  Failed 1/1 test scripts, 0.00% okay. 1/6 subtests failed, 83.33% okay.

=head1 SEE ALSO

The Apache-Test tutorial:
L<http://perl.apache.org/docs/general/testing/testing.html>
as all of the mod_perl-specific syntax and features have been
ported to PHP with this class.

=head1 AUTHOR

C<Apache::Test> is a community effort, maintained by a group of
dedicated volunteers.

Questions can be asked at the test-dev <at> httpd.apache.org list
For more information see: http://httpd.apache.org/test/.

=cut