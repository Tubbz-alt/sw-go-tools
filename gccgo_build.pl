#!/usr/bin/perl
use strict;
use warnings;
use 5.018;

use Getopt::Std;
use Data::Dumper;

sub get_libs_L {
	my $pkgnames = shift;
	my $opt_L = qx(pkg-config --libs-only-L --static $pkgnames);
	chomp $opt_L;
	return $opt_L;
}

my $arch = qx(arch);
chomp $arch;
say "arch: $arch";

sub get_part_gccgo_flags {
    my $pkgnames = shift;
    my $opt_L = get_libs_L($pkgnames);

    my @libs = ("/lib/$arch-linux-gnu", "/usr/lib/$arch-linux-gnu");
    my @opt_L = split /\s/, $opt_L;
    for my $opt (@opt_L) {
        $opt =~ s/^-L//;
        if (!grep { $_ eq $opt } @libs) {
            push @libs, $opt;
        }
    }
    my @flags;
    for my $lib (@libs) {
        push @flags, "-L$lib -Wl,-rpath=$lib";
    }
    return join(" ", @flags);
}

$ENV{LD_LIBRARY_PAT}="/usr/sw/swgcc720-standard/usr/lib";
$ENV{C_INCLUDE_PATH}="/usr/include";
$ENV{PKG_CONFIG_ALLOW_SYSTEM_LIBS} = '1';
my $gobin = "/usr/sw/swgcc720-standard/usr/bin/go";


my %opts;

# -o output name
# -p pkg-config pkgnames
# -f extra gccgoflags
getopts('o:p:f:', \%opts);

if (!defined $opts{o}) {
    die "no set output";
}
my $output = $opts{o};
my $pkg_config_pkg_names = $opts{p} // "";
my $extra_gccgo_flags = $opts{f} // "";

say "output: $output";
say "pkg-config pkg_names: $pkg_config_pkg_names";
my $gccgo_L = get_part_gccgo_flags($pkg_config_pkg_names);
my $gccgoflags = "-Wl,--dynamic-linker=/lib/ld-linux.so.2 $gccgo_L $extra_gccgo_flags";

my @cmdline_args = ($gobin, "build", "-v", "-o", $output, "-compiler", "gccgo", "-gccgoflags", $gccgoflags);
push @cmdline_args, @ARGV;
say '$ ' . join(" ", @cmdline_args);
my $gobuild_ret = system(@cmdline_args);
if ($gobuild_ret != 0) {
    die "go build failed: $!";
}
my $chrpath_ret = system("chrpath", "-d", $output);
if ($chrpath_ret != 0) {
    die "chrpath failed: %!";
}
