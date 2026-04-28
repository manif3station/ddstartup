PERL ?= perl

install:
	PERL5LIB=lib $(PERL) -MDDStartup::Manager -e 'DDStartup::Manager->new()->auto_setup()'
