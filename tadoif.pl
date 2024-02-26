#!/usr/bin/perl -w

use warnings;
use strict;
use Tado::IF;

my($error);

my($tadoif) = new Tado::IF;
die($error) if(defined($error = $tadoif->get_error()));
printf("%s", $tadoif->dump_header());
printf("%s", $tadoif->dump());
