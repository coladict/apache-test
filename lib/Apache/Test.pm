package Apache::Test;

use strict;
use warnings FATAL => 'all';

use Test qw(ok skip);
use Exporter ();
use Config;
use Apache::TestConfig ();

use vars qw(@ISA @EXPORT $VERSION %SubTests @SkipReasons);

@ISA = qw(Exporter);
@EXPORT = qw(ok skip sok plan have have_lwp have_http11
             have_cgi have_access have_auth have_module
             have_apache have_perl);
$VERSION = '0.01';

%SubTests = ();
@SkipReasons = ();

if (my $subtests = $ENV{HTTPD_TEST_SUBTESTS}) {
    %SubTests = map { $_, 1 } split /\s+/, $subtests;
}

my $Config;

sub config {
    $Config ||= Apache::TestConfig->thaw;
}

sub vars {
    config()->{vars};
}

sub sok (&;$) {
    my $sub = shift;
    my $nok = shift || 1; #allow sok to have 'ok' within

    if (%SubTests and not $SubTests{ $Test::ntest }) {
        for my $n (1..$nok) {
            skip "skipping this subtest", 0;
        }
        return;
    }

    ok $sub->();
}

#so Perl's Test.pm can be run inside mod_perl
sub test_pm_refresh {
    $Test::TESTOUT = \*STDOUT;
    $Test::planned = 0;
    $Test::ntest = 1;
    %Test::todo = ();
}

sub init_test_pm {
    my $r = shift;

    if (defined &Apache::RequestRec::TIEHANDLE) {
        untie *STDOUT;
        tie *STDOUT, $r;
        require APR::Pool;
        $r->pool->cleanup_register(sub { untie *STDOUT });
    }
    else {
        $r->send_http_header; #1.xx
    }

    $r->content_type('text/plain');
}

sub have_http11 {
    require Apache::TestRequest;
    if (Apache::TestRequest::install_http11()) {
        return 1;
    }
    else {
        push @SkipReasons,
           "LWP version 5.60+ required for HTTP/1.1 support";
        return 0;
    }
}

sub have_ssl {
    my $vars = vars();
    have_module([$vars->{ssl_module_name}, 'Net::SSL']);
}

sub have_lwp {
    require Apache::TestRequest;
    if (Apache::TestRequest::has_lwp()) {
        return 1;
    }
    else {
        push @SkipReasons, "libwww-perl is not installed";
        return 0;
    }
}

sub plan {
    init_test_pm(shift) if ref $_[0];
    test_pm_refresh();

    # extending Test::plan's functionality, by using the optional
    # single value in @_ coming after a ballanced %hash which
    # Test::plan expects
    if (@_ % 2) {
        my $condition = pop @_;
        my $ref = ref $condition;
        my $meets_condition = 0;
        if ($ref) {
            if ($ref eq 'CODE') {
                #plan tests $n, \&has_lwp
                $meets_condition = $condition->();
            }
            elsif ($ref eq 'ARRAY') {
                #plan tests $n, [qw(php4 rewrite)];
                $meets_condition = have_module($condition);
            }
            else {
                die "don't know how to handle a condition of type $ref";
            }
        }
        else {
            # we have the verdict already: true/false
            $meets_condition = $condition ? 1 : 0;
        }

        # trying to emulate a dual variable (ala errno)
        unless ($meets_condition) {
            my $reason = join ', ',
              @SkipReasons ? @SkipReasons : "no reason given";
            print "1..0 # skipped: $reason\n";
            exit; #XXX: Apache->exit
        }
    }
    @SkipReasons = (); # reset

    Test::plan(@_);
}

sub have {
    my $have_all = 1;
    for my $cond (@_) {
        if (ref $cond eq 'HASH') {
            while (my($reason, $code) = each %$cond) {
                if (ref $code eq 'CODE' && $code->()) {
                    next;
                }
                else {
                    push @SkipReasons, $reason;
                    $have_all = 0;
                }
            }
        }
        else {
            $have_all = 0 unless have_module($cond);
        }
    }
    return $have_all;

}

sub have_module {
    my $cfg = config();
    my @modules = ref($_[0]) ? @{ $_[0] } : @_;

    my @reasons = ();
    for (@modules) {
        if (/^[a-z0-9_.]+$/) {
            my $mod = $_;
            unless ($mod =~ /\.c$/) {
                $mod = 'mod_' . $mod unless $mod =~ /^mod_/;
                $mod .= '.c'
            }
            next if $cfg->{modules}->{$mod};
            if (exists $cfg->{cmodules_disabled}->{$mod}) {
                push @reasons, $cfg->{cmodules_disabled}->{$mod};
                next;
            }
        }
        die "bogus module name $_" unless /^[\w:.]+$/;
        eval "require $_";
        #print $@ if $@;
        if ($@) {
            push @reasons, "cannot find module '$_'";
        }
    }
    if (@reasons) {
        push @SkipReasons, @reasons;
        return 0;
    }
    else {
        return 1;
    }
}

sub have_cgi {
    have_module('cgi') || have_module('cgid');
}

sub have_access {
    have_module('access') || have_module('authz_host');
}

sub have_auth {
    have_module('auth') || have_module('auth_basic');
}

sub have_apache {
    my $version = shift;
    my $cfg = Apache::Test::config();
    my $rev = $cfg->{server}->{rev};

    if ($rev == $version) {
        return 1;
    }
    else {
        push @SkipReasons,
          "apache version $version required, this is version $rev";
        return 0;
    }
}

sub config_enabled {
    my $key = shift;
    defined $Config{$key} and $Config{$key} eq 'define';
}

sub have_perl_iolayers {
    if (my $ext = $Config{extensions}) {
        #XXX: better test?  might need to test patchlevel
        #if support depends bugs fixed in bleedperl
        return $ext =~ m:PerlIO/scalar:;
    }
    0;
}

sub have_perl {
    my $thing = shift;
    #XXX: $thing could be a version
    my $config;

    my $have = \&{"have_perl_$thing"};
    if (defined &$have) {
        return 1 if $have->();
    }
    else {
        for my $key ($thing, "use$thing") {
            if (exists $Config{$key}) {
                $config = $key;
                return 1 if config_enabled($key);
            }
        }
    }

    push @SkipReasons, $config ?
      "Perl was not built with $config enabled" :
        "$thing is not available with this version of Perl";

    return 0;
}

package Apache::TestToString;

sub TIEHANDLE {
    my $string = "";
    bless \$string;
}

sub PRINT {
    my $string = shift;
    $$string .= join '', @_;
}

sub start {
    tie *STDOUT, __PACKAGE__;
    Apache::Test::test_pm_refresh();
}

sub finish {
    my $s;
    {
        my $o = tied *STDOUT;
        $s = $$o;
    }
    untie *STDOUT;
    $s;
}

1;
__END__


=head1 NAME

Apache::Test - Test.pm wrapper with helpers for testing Apache

=head1 SYNOPSIS

    use Apache::Test;

=head1 DESCRIPTION

B<Apache::Test> is a wrapper around the standard C<Test.pm> with
helpers for testing an Apache server.

=head1 FUNCTIONS

=over 4

=item plan

This function is a wrapper around C<Test::plan>:

    plan tests => 3;

just like using Test.pm, plan 3 tests.

If the first argument is an object, such as an C<Apache::RequestRec>
object, C<STDOUT> will be tied to it. The C<Test.pm> global state will
also be refreshed by calling C<Apache::Test::test_pm_refresh>. For
example:

    plan $r, tests => 7;

ties STDOUT to the request object C<$r>.

If there is a last argument that doesn't belong to C<Test::plan>
(which expects a balanced hash), it's used to decide whether to
continue with the test or to skip it all-together. This last argument
can be:

=over

=item * a C<SCALAR>

the test is skipped if the scalar has a false value. For example:

  plan tests => 5, 0;

But this won't hint the reason for skipping therefore it's better to
use have():

  plan tests => 5,
      have 'LWP',
           { "perl >= 5.7.3 is required" => sub { $] >= 5.007003 } };

see have() for more info.

=item * an C<ARRAY> reference

have_module() is called for each value in this array. The test is
skipped if have_module() returns false (which happens when at least
one C or Perl module from the list cannot be found).

=item * a C<CODE> reference

the tests will be skipped if the function returns a false value. For
example:

    plan tests => 5, \&have_lwp;

the test will be skipped if LWP is not available

=back

All other arguments are passed through to I<Test::plan> as is.

=item ok

Same as I<Test::ok>, see I<Test.pm> documentation.

=item sok

Allows to skip a sub-test, controlled from the command line.  The
argument to sok() is a CODE reference or a BLOCK whose return value
will be passed to ok(). By default behaves like ok(). If all sub-tests
of the same test are written using sok(), and a test is executed as:

  % ./t/TEST -v skip_subtest 1 3

only sub-tests 1 and 3 will be run, the rest will be skipped.

=item skip

Same as I<Test::skip>, see I<Test.pm> documentation.

=item test_pm_refresh

Normally called by I<Apache::Test::plan>, this function will refresh
the global state maintained by I<Test.pm>, allowing C<plan> and
friends to be called more than once per-process.  This function is not
exported.

=back

Functions that can be used as a last argument to the extended plan():

=over have_http11

  plan tests => 5, &have_http11;

Require HTTP/1.1 support.

=item have_ssl

  plan tests => 5, &have_ssl;

Require SSL support.

Not exported by default.

=item have_lwp

  plan tests => 5, &have_lwp;

Require LWP support.

=item have_cgi

  plan tests => 5, &have_cgi;

Requires mod_cgi or mod_cgid to be installed.

=item have_apache

  plan tests => 5, have_apache 2;

Requires httpd-2.x (apache-2.x).

  plan tests => 5, have_apache 1;

Requires apache-1.3.x.

=item have_perl

  plan tests => 5, have_perl 'iolayers';
  plan tests => 5, have_perl 'ithreads';

Requires a perl extension to be present, or perl compiled with certain
capabilities.

The first example tests whether C<PerlIO> is available, the second
whether:

  $Config{useithread} eq 'define';

=item have_module

  plan tests => 5, have_module 'CGI';
  plan tests => 5, have_module qw(CGI Find::File);
  plan tests => 5, have_module ['CGI', 'Find::File', 'cgid'];

Requires Apache C and Perl modules. The function accept a list of
arguments or a reference to a list.

In case of C modules, depending on how the module name was passed it
may pass through the following completions:

=over

=item 1 have_module 'proxy_http.c'

If there is the I<.c> extension, the module name will be looked up as
is, i.e. I<'proxy_http.c'>.

=item 2 have_module 'mod_cgi'

The I<.c> extension will be appended before the lookup, turning it into
I<'mod_cgi.c'>.

=item 3 have_module 'cgi'

The I<.c> extension and I<mod_> prefix will be added before the
lookup, turning it into I<'mod_cgi.c'>.

=back

=item have

  plan tests => 5,
      have 'LWP',
           { "perl >= 5.7.3 is required" => sub { $] >= 5.007003   } },
           { "not Win32"                 => sub { $^O eq 'MSWin32' } },
           'cgid';

have() is more generic function which can impose multiple requirements
at once. All requirements must be satisfied.

have()'s argument is a list of things to test. The list can include
scalars, which are passed to have_module(), and hash references. The
hash references have a condition code reference as a value and a
reason for failure as a key. The condition code is run and if it fails
the provided reason is used to tell user why the test was skipped.

In the presented example, we require the presense of the C<LWP> Perl
module, C<mod_cgid>, that we run under perl E<gt>= 5.7.3 on Win32.

It's possible to put more than one requirement into a single hash
reference, but be careful that the keys will be different:

      have 'LWP',
           { "perl >= 5.7.3 is required" => sub { $] >= 5.007003   },
             "not Win32"                 => sub { $^O eq 'MSWin32' },
           },
           'cgid';

Also see plan().

=back

=head1 Apache::TestToString Class

The I<Apache::TestToString> class is used to capture I<Test.pm> output
into a string.  Example:

    Apache::TestToString->start;

    plan tests => 4;

    ok $data eq 'foo';

    ...

    # $tests will contain the Test.pm output: 1..4\nok 1\n...
    my $tests = Apache::TestToString->finish;

=cut