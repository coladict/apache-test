package Apache::TestRun;

use strict;
use warnings FATAL => 'all';

use Apache::TestConfig ();
use Apache::TestConfigC ();
use Apache::TestRequest ();
use Apache::TestHarness ();
use Apache::TestTrace;

use File::Find qw(finddepth);
use File::Spec::Functions qw(catfile);
use Getopt::Long qw(GetOptions);
use Config;

use constant STARTUP_TIMEOUT => 300; # secs (good for extreme debug cases)

my @std_run      = qw(start-httpd run-tests stop-httpd);
my @others       = qw(verbose configure clean help ssl http11);
my @flag_opts    = (@std_run, @others);
my @string_opts  = qw(order);
my @ostring_opts = qw(proxy ping);
my @debug_opts   = qw(debug);
my @num_opts     = qw(times);
my @list_opts    = qw(preamble postamble breakpoint);
my @hash_opts    = qw(header);
my @help_opts    = qw(clean help ping);
my @exit_opts    = (@help_opts, @debug_opts);
my @request_opts = qw(get post head);

my %usage = (
   'start-httpd'     => 'start the test server',
   'run-tests'       => 'run the tests',
   'times=N'         => 'repeat the tests N times',
   'order=mode'      => 'run the tests in one of the modes: (repeat|rotate|random|SEED)',
   'stop-httpd'      => 'stop the test server',
   'verbose'         => 'verbose output',
   'configure'       => 'force regeneration of httpd.conf (tests will not be run)',
   'clean'           => 'remove all generated test files',
   'help'            => 'display this message',
   'preamble'        => 'config to add at the beginning of httpd.conf',
   'postamble'       => 'config to add at the end of httpd.conf',
   'ping[=block]'    => 'test if server is running or port in use',
   'debug[=name]'    => 'start server under debugger name (e.g. gdb, ddd, ...)',
   'breakpoint=bp'   => 'set breakpoints (multiply bp can be set)',
   'header'          => "add headers to (".join('|', @request_opts).") request",
   'http11'          => 'run all tests with HTTP/1.1 (keep alive) requests',
   'ssl'             => 'run tests through ssl',
   'proxy'           => 'proxy requests (default proxy is localhost)',
   (map { $_, "\U$_\E url" } @request_opts),
);

sub fixup {
    #make sure we use an absolute path to perl
    #else Test::Harness uses the perl in our PATH
    #which might not be the one we want
    $^X = $Config{perlpath} if $^X eq 'perl';
}

sub new {
    my $class = shift;

    my $self = bless {
        tests => [],
        @_,
    }, $class;

    $self->fixup;

    $self;
}

#split arguments into test files/dirs and options
#take extra care if -e, the file matches /\.t$/
#                if -d, the dir contains .t files
#so we dont slurp arguments that are not tests, example:
# httpd $HOME/apache-2.0/bin/httpd

sub split_test_args {
    my($self) = @_;

    my(@tests);

    my $argv = $self->{argv};
    my @leftovers = ();
    for (@$argv) {
        my $arg = $_;
        #need the t/ for stat-ing, but dont want to include it in test output
        $arg =~ s@^(?:\./)?t/@@;
        my $t_dir = catfile qw(.. t);
        my $file = catfile $t_dir, $arg;

        if (-d $file and $_ ne '/') {
            my @files = <$file/*.t>;
            if (@files) {
                my $remove = catfile $t_dir, "";
                push @tests, map { s,^\Q$remove,,; $_ } @files;
                next;
            }
        }
        else {
            if ($file =~ /\.t$/ and -e $file) {
                push @tests, "$arg";
                next;
            }
            elsif (-e "$file.t") {
                push @tests, "$arg.t";
                next;
            }
            elsif (/^[\d.]+$/) {
                my @t = $_;
                #support range of subtests: t/TEST t/foo/bar 60..65
                if (/^(\d+)\.\.(\d+)$/) {
                    @t =  $1..$2;
                }

                push @{ $self->{subtests} }, @t;
                next;
            }
        }
        push @leftovers, $_;
    }

    $self->{tests} = \@tests;
    $self->{argv}  = \@leftovers;
}

sub die_on_invalid_args {
    my($self) = @_;

    # at this stage $self->{argv} should be empty
    my @invalid_argv = @{ $self->{argv} };
    if (@invalid_argv) {
        error "unknown opts or test names: @invalid_argv";
        exit;
    }

}

sub passenv {
    my $passenv = Apache::TestConfig->passenv;
    for (keys %$passenv) {
        return 1 if $ENV{$_};
    }
    0;
}

sub getopts {
    my($self, $argv) = @_;

    local *ARGV = $argv;
    my(%opts, %vopts, %conf_opts);

    # permute      : optional values can come before the options
    # pass_through : all unknown things are to be left in @ARGV
    Getopt::Long::Configure(qw(pass_through permute));

    # grab from @ARGV only the options that we expect
    GetOptions(\%opts, @flag_opts, @help_opts,
               (map "$_:s", @debug_opts, @request_opts, @ostring_opts),
               (map "$_=s", @string_opts),
               (map "$_=i", @num_opts),
               (map { ("$_=s", $vopts{$_} ||= []) } @list_opts),
               (map { ("$_=s", $vopts{$_} ||= {}) } @hash_opts));

    $opts{$_} = $vopts{$_} for keys %vopts;

    # separate configuration options and test files/dirs
    my $req_wanted_args = Apache::TestRequest::wanted_args();
    my @argv = ();
    my %req_args = ();
    while (@ARGV) {
        my $val = shift @ARGV;
        if ($val =~ /^--?(.+)/) { # must have a leading - or --
            my $key = lc $1;
            # a known config option?
            if (exists $Apache::TestConfig::Usage{$key}) {
                $conf_opts{$key} = shift @ARGV;
                next;
            } # a TestRequest config option?
            elsif (exists $req_wanted_args->{$key}) {
                $req_args{$key} = shift @ARGV;
                next;
            }
        }
        # to be processed later
        push @argv, $val;
    }

    $opts{req_args} = \%req_args;

    # only test files/dirs if any at all are left in argv
    $self->{argv} = \@argv;

    # force regeneration of httpd.conf if commandline args want to modify it
    $self->{reconfigure} = $opts{configure} ||
      (grep { $opts{$_}->[0] } qw(preamble postamble)) ||
        (grep { $Apache::TestConfig::Usage{$_} } keys %conf_opts ) ||
          $self->passenv() || (! -e 'conf/httpd.conf');

    if (exists $opts{debug}) {
        $opts{debugger} = $opts{debug};
        $opts{debug} = 1;
    }

    # breakpoint automatically turns the debug mode on
    if (@{ $opts{breakpoint} }) {
        $opts{debug} ||= 1;
    }

    if ($self->{reconfigure}) {
        $conf_opts{save} = 1;
    }
    else {
        $conf_opts{thaw} = 1;
    }

    #propagate some values
    for (qw(verbose)) {
        $conf_opts{$_} = $opts{$_};
    }

    $self->{opts} = \%opts;
    $self->{conf_opts} = \%conf_opts;
}

sub default_run_opts {
    my $self = shift;
    my($opts, $tests) = ($self->{opts}, $self->{tests});

    unless (grep { exists $opts->{$_} } @std_run, @request_opts) {
        if (@$tests && $self->{server}->ping) {
            #if certain tests are specified and server is running, dont restart
            $opts->{'run-tests'} = 1;
        }
        else {
            #default is server-server run-tests stop-server
            $opts->{$_} = 1 for @std_run;
        }
    }

    $opts->{'run-tests'} ||= @$tests;
}

my $caught_sig_int = 0;

sub install_sighandlers {
    my $self = shift;

    my($server, $opts) = ($self->{server}, $self->{opts});

    $SIG{__DIE__} = sub {
        return unless $_[0] =~ /^Failed/i; #dont catch Test::ok failures
        $server->stop(1) if $opts->{'start-httpd'};
        $server->failed_msg("error running tests");
    };

    $SIG{INT} = sub {
        if ($caught_sig_int++) {
            warning "\ncaught SIGINT";
            exit;
        }
        warning "\nhalting tests";
        $server->stop if $opts->{'start-httpd'};
        exit;
    };

    #try to make sure we scan for core no matter what happens
    #must eval "" to "install" this END block, otherwise it will
    #always run, a subclass might not want that

    eval 'END {
             local $?; # preserve the exit status
             eval {
                Apache::TestRun->new(test_config =>
                                     Apache::TestConfig->thaw)->scan;
             };
         }';
}

#throw away cached config and start fresh
sub refresh {
    my $self = shift;
    $self->opt_clean(1);
    $self->{conf_opts}->{save} = delete $self->{conf_opts}->{thaw} || 1;
    $self->{test_config} = $self->new_test_config($self->{conf_opts});
    $self->{server} = $self->{test_config}->server;
}

sub configure_opts {
    my $self = shift;
    my $save = shift;
    my $refreshed = 0;

    my($test_config, $opts) = ($self->{test_config}, $self->{opts});

    $test_config->{vars}->{scheme} =
      $opts->{ssl} ? 'https' :
        $self->{conf_opts}->{scheme} || 'http';

    if ($opts->{http11}) {
        $ENV{APACHE_TEST_HTTP11} = 1;
    }

    if (my @reasons = $self->{test_config}->need_reconfiguration) {
        warning "forcing re-configuration:";
        warning "\t- $_." for @reasons;
        unless ($refreshed) {
            $self->refresh;
            $refreshed = 1;
            $test_config = $self->{test_config};
        }
    }

    if (exists $opts->{proxy}) {
        my $max = $test_config->{vars}->{maxclients};
        $opts->{proxy} ||= 'on';

        #if config is cached and MaxClients == 1, must reconfigure
        if (!$$save and $opts->{proxy} eq 'on' and $max == 1) {
            $$save = 1;
            warning "server is reconfigured for proxy";
            unless ($refreshed) {
                $self->refresh;
                $refreshed = 1;
                $test_config = $self->{test_config};
            }
        }

        $test_config->{vars}->{proxy} = $opts->{proxy};
    }
    else {
        $test_config->{vars}->{proxy} = 'off';
    }

    return unless $$save;

    my $preamble  = sub { shift->preamble($opts->{preamble}) };
    my $postamble = sub { shift->postamble($opts->{postamble}) };

    $test_config->preamble_register($preamble);
    $test_config->postamble_register($postamble);
}

sub configure {
    my $self = shift;

    my $save = \$self->{conf_opts}->{save};
    $self->configure_opts($save);

    my $config = $self->{test_config};
    unless ($$save) {
        my $addr = \$config->{vars}->{remote_addr};
        my $remote_addr = $config->our_remote_addr;
        unless ($$addr eq $remote_addr) {
            warning "local ip address has changed, updating config cache";
            $$addr = $remote_addr;
        }
        #update minor changes to cached config
        #without complete regeneration
        #for example this allows switching between
        #'t/TEST' and 't/TEST -ssl'
        $config->sync_vars(qw(scheme proxy remote_addr));
        return;
    }

    my $test_config = $self->{test_config};
    $test_config->sslca_generate;
    $test_config->generate_ssl_conf if $self->{opts}->{ssl};
    $test_config->cmodules_configure;
    $test_config->generate_httpd_conf;
    $test_config->save;
}

sub try_exit_opts {
    my $self = shift;

    for (@exit_opts) {
        next unless exists $self->{opts}->{$_};
        my $method = "opt_$_";
        exit if $self->$method();
    }

    if ($self->{opts}->{'stop-httpd'}) {
        if ($self->{server}->ping) {
            $self->{server}->stop;
        }
        else {
            warning "server $self->{server}->{name} is not running";
        }
        exit;
    }
}

sub start {
    my $self = shift;

    my $test_config = $self->{test_config};

    unless ($test_config->{vars}->{httpd}) {
        error "no test server configured, please specify an httpd or ".
              ($test_config->{APXS} ?
               "an apxs other than $test_config->{APXS}" : "apxs").
               " or put either in your PATH";
        exit 1;
    }

    my $opts = $self->{opts};
    my $server = $self->{server};

    #if t/TEST -d is running make sure we don't try to stop/start the server
    my $file = $server->debugger_file;
    if (-e $file and $opts->{'start-httpd'}) {
        if ($server->ping) {
            warning "server is running under the debugger, defaulting to -run";
            $opts->{'start-httpd'} = $opts->{'stop-httpd'} = 0;
        }
        else {
            warning "removing stale debugger note: $file";
            unlink $file;
        }
    }

    if ($opts->{'start-httpd'}) {
        exit 1 unless $server->start;
    }
    elsif ($opts->{'run-tests'}) {
        my $is_up = $server->ping
            || (exists $self->{opts}->{ping}
                && $self->{opts}->{ping}  eq 'block'
                && $server->wait_till_is_up(STARTUP_TIMEOUT));
        unless ($is_up) {
            error "server is not ready yet, try again.";
            exit;
        }
    }
}

sub run_tests {
    my $self = shift;

    my $test_opts = {
        verbose => $self->{opts}->{verbose},
        tests   => $self->{tests},
        times   => $self->{opts}->{times},
        order   => $self->{opts}->{order},
        subtests => $self->{subtests} || [],
    };

    if (grep { exists $self->{opts}->{$_} } @request_opts) {
        run_request($self->{test_config}, $self->{opts});
    }
    else {
        Apache::TestHarness->run($test_opts)
            if $self->{opts}->{'run-tests'};
    }
}

sub stop {
    my $self = shift;

    $self->{server}->stop if $self->{opts}->{'stop-httpd'};
}

sub new_test_config {
    my $self = shift;
    Apache::TestConfig->new($self->{conf_opts});
}

sub set_ulimit_via_sh {
    return if Apache::TestConfig::WINFU;
    return if $ENV{APACHE_TEST_ULIMIT_SET};
    my $binsh = '/bin/sh';
    return unless -e $binsh;
    $ENV{APACHE_TEST_ULIMIT_SET} = 1;

    my $sh = Symbol::gensym();
    open $sh, "echo ulimit -a | $binsh|" or die;
    local $_;
    while (<$sh>) {
        if (/^core.*unlimited$/) {
            #already set to unlimited
            $ENV{APACHE_TEST_ULIMIT_SET} = 1;
            return;
        }
    }
    close $sh;

    open $sh, "|$binsh" or die;
    my @cmd = ("ulimit -c unlimited\n",
               "exec $0 @ARGV");
    warning "setting ulimit to allow core files\n@cmd";
    print $sh @cmd;
    close $sh;
    exit; #exec above will take over
}

sub set_ulimit {
    my $self = shift;
    #return if $self->set_ulimit_via_bsd_resource;
    eval { $self->set_ulimit_via_sh };
}

sub set_env {
    #export some environment variables for t/modules/env.t
    #(the values are unimportant)
    $ENV{APACHE_TEST_HOSTNAME} = 'test.host.name';
    $ENV{APACHE_TEST_HOSTTYPE} = 'z80';
}

sub run {
    my $self = shift;

    $self->set_ulimit;
    $self->set_env; #make sure these are always set

    my(@argv) = @_;

    Apache::TestHarness->chdir_t;

    $self->getopts(\@argv);

    $self->{test_config} = $self->new_test_config;

    $self->warn_core();

    $self->{server} = $self->{test_config}->server;

    local($SIG{__DIE__}, $SIG{INT});
    $self->install_sighandlers;

    if ($self->{opts}->{configure}) {
        warning "cleaning out current configuration";
        $self->opt_clean(1);
    }

    # if configure() fails for some reason before it has flushed the
    # config to a file, save it so -clean will be able to clean
    unless ($self->{opts}->{clean}) {
        eval { $self->configure };
        if ($@) {
            error "configure() has failed:\n$@";
            warning "forcing Apache::TestConfig object save";
            $self->{test_config}->save;
            warning "run 't/TEST -clean' to clean up before continuing";
            exit 1;
        }
    }

    if ($self->{opts}->{configure}) {
        warning "reconfiguration done";
        exit;
    }

    $self->try_exit_opts;

    $self->default_run_opts;

    $self->split_test_args;

    $self->die_on_invalid_args;

    $self->start;

    $self->run_tests;

    $self->stop;
}

my @oh = qw(jeez golly gosh darn shucks dangit rats nuts dangnabit crap);
sub oh {
    $oh[ rand scalar @oh ];
}

sub scan {
    my $self = shift;
    my $vars = $self->{test_config}->{vars};
    my $times = 0;

    finddepth(sub {
        return unless /^core$/;
        my $core = "$File::Find::dir/$_";
        my $oh = oh();
        my $again = $times++ ? "again" : "";
        error "oh $oh, server dumped core $again";
        error "for stacktrace, run: gdb $vars->{httpd} -core $core";
    }, $vars->{top_dir});
}

# warn the user that there is a core file before the tests
# start. suggest to delete it before proceeding or a false alarm can
# be generated at the end of the test routine run.
sub warn_core {
    my $self = shift;
    my $vars = $self->{test_config}->{vars};

    finddepth(sub {
        return unless /^core$/;
        my $core = "$File::Find::dir/$_";
        error "consider removing an old $core file before running tests";
    }, $vars->{top_dir});
}

sub run_request {
    my($test_config, $opts) = @_;

    my @args = (%{ $opts->{header} }, %{ $opts->{req_args} });

    my($request, $url) = ("", "");

    for (@request_opts) {
        next unless exists $opts->{$_};
        $url = $opts->{$_} if $opts->{$_};
        $request = join $request ? '_' : '', $request, $_;
    }

    if ($request) {
        my $method = \&{"Apache::TestRequest::\U$request"};
        my $res = $method->($url, @args);
        print Apache::TestRequest::to_string($res);
    }
}

sub opt_clean {
    my($self, $level) = @_;
    my $test_config = $self->{test_config};
    $test_config->server->stop;
    $test_config->clean($level);
    1;
}

sub opt_ping {
    my($self) = @_;

    my $test_config = $self->{test_config};
    my $server = $test_config->server;
    my $pid = $server->ping;
    my $name = $server->{name};
    my $exit = not $self->{opts}->{'run-tests'}; #support t/TEST -ping=block -run ...

    if ($pid) {
        if ($pid == -1) {
            error "port $test_config->{vars}->{port} is in use, ".
                  "but cannot determine server pid";
        }
        else {
            my $version = $server->{version};
            warning "server $name running (pid=$pid, version=$version)";
        }
        return $exit;
    }

    if (exists $self->{opts}->{ping} && $self->{opts}->{ping} eq 'block') {
        $server->wait_till_is_up(STARTUP_TIMEOUT);
    }
    else {
        warning "no server is running on $name";
    }

    return $exit; #means call exit() if true
}

sub test_inc {
    map { "$_/Apache-Test/lib" } qw(. ..);
}

sub set_perl5lib {
    $ENV{PERL5LIB} = join $Config{path_sep}, shift->test_inc();
}

sub set_perldb_opts {
    my $config = shift->{test_config};
    my $file = catfile $config->{vars}->{t_logs}, 'perldb.out';
    $config->genfile($file); #mark for -clean
    $ENV{PERLDB_OPTS} = "NonStop frame=4 AutoTrace LineInfo=$file";
    warning "perldb log is t/logs/perldb.out";
}

sub opt_debug {
    my $self = shift;
    my $server = $self->{server};

    my $opts = $self->{opts};
    my $debug_opts = {};

    for (qw(debugger breakpoint)) {
        $debug_opts->{$_} = $opts->{$_};
    }

    if (my $db = $opts->{debugger}) {
        if ($db =~ s/^perl=?//) {
            $opts->{'run-tests'} = 1;
            $self->start; #if not already running
            $self->set_perl5lib;
            $self->set_perldb_opts if $db eq 'nostop';
            system $^X, '-MApache::TestPerlDB', '-d', @{ $self->{tests} };
            $self->stop;
            return 1;
        }
        elsif ($db =~ s/^lwp[=:]?//) {
            $ENV{APACHE_TEST_DEBUG_LWP} = $db || 1;
            $opts->{verbose} = 1;
            return 0;
        }
    }

    $server->stop;
    $server->start_debugger($debug_opts);
    1;
}

sub opt_help {
    my $self = shift;

    print <<EOM;
usage: TEST [options ...]
   where options include:
EOM

    for (sort keys %usage){
        printf "   -%-16s %s\n", $_, $usage{$_};
    }

    print "\n   configuration options:\n";

    Apache::TestConfig->usage;
    1;
}

1;
