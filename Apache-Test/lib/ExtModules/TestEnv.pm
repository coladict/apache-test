package ExtModules::TestEnv;

use Apache::TestConfig;

my $env = Apache::TestConfig->thaw;

no strict 'refs';
my @module = ('perl', 'php4', 'jk', 'jserv', 'dav');
foreach my $mod (@module) {
	my $alias = join '_', 'has', $mod;
	*$alias = sub { $env->{modules}->{"mod_$mod.c"}; };
}
1;
 
