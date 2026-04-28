use strict;
use warnings;

use Test::More;

use lib 'lib';

require_ok('DDStartup::Manager');
ok( -f 'Makefile', 'skill ships a Makefile install hook for auto-setup during installation' );

done_testing();
