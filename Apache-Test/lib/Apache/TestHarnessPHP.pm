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
package Apache::TestHarnessPHP;

use strict;
use warnings FATAL => 'all';

use File::Spec::Functions qw(catfile catdir);
use File::Find qw(finddepth);
use Apache::TestHarness ();

use vars qw(@ISA);
@ISA = qw(Apache::TestHarness);

# Test::Harness didn't start using Test::Harness::Straps until 5.8.0
# everything except t/foo.php with earlier perls, so let things
# go for the moment
eval {
  require Test::Harness::Straps;
  push @ISA, qw(Test::Harness::Straps);
  $Test::Harness::Strap = __PACKAGE__->new;
};

sub get_tests {

    my $self = shift;
    my $args = shift;
    my @tests = ();

    my $base = -d 't' ? catdir('t', '.') : '.';

    my $ts = $args->{tests} || [];

    if (@$ts) {
	for (@$ts) {
	    if (-d $_) {
		push(@tests, sort <$base/$_/*.t>);
		push(@tests, sort <$base/$_/*.php>);
	    }
	    else {
		$_ .= ".t" unless /(\.t|\.php)$/;
		push(@tests, $_);
	    }
	}
    }
    else {
        if ($args->{tdirs}) {
            push @tests, map { sort <$base/$_/*.t> } @{ $args->{tdirs} };
            push @tests, map { sort <$base/$_/*.php> } @{ $args->{tdirs} };
        }
        else {
            finddepth(sub {
                          return unless /(\.t|\.php)$/;
                          my $t = catfile $File::Find::dir, $_;
                          my $dotslash = catfile '.', "";
                          $t =~ s:^\Q$dotslash::;
                          push @tests, $t
                      }, $base);
            @tests = sort @tests;
        }
    }

    @tests = $self->prune(@tests);

    if (my $skip = $self->skip) {
        # Allow / \ and \\ path delimiters in SKIP file
        $skip =~ s![/\\\\]+![/\\\\]!g;

        @tests = grep { not /(?:$skip)/ } @tests;
    }

    Apache::TestSort->run(\@tests, $args);

    #when running 't/TEST t/dir' shell tab completion adds a /
    #dir//foo output is annoying, fix that.
    s:/+:/:g for @tests;

    return @tests;
}

sub run {
    my $self = shift;
    my $args = shift || {};

    $Test::Harness::verbose ||= $args->{verbose};

    if (my(@subtests) = @{ $args->{subtests} || [] }) {
        $ENV{HTTPD_TEST_SUBTESTS} = "@subtests";
    }

    Test::Harness::runtests($self->get_tests($args, @_));
}

sub _command_line {

    my $self = shift;
    my $file = shift;

    return $self->SUPER::_command_line($file)
        unless $file =~ m/\.php$/;

    $file = qq["$file"] if ($file =~ /\s/) && ($file !~ /^".*"$/);

    my $server_root = Apache::Test::vars('serverroot');

    $ENV{SERVER_ROOT} = $server_root;

    my $conf = catfile($server_root, 'conf');
                                                                                                                             
    my $ini = catfile($conf, 'php.ini');

    my $switches = join ' ', "--php-ini $ini",
                             "--define include_path=$conf";

    my $line = "php $switches $file";
                                                                                                                             
    return $line;
}

1;
