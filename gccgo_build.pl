#!/usr/bin/perl
use strict;
use warnings;
use 5.018;

use Getopt::Std;
use Data::Dumper;

my $use_new_gccgo = 0;
my $go_bin = "go";

if (defined $ENV{GCCGO_BUILD_GCCGO_VERSION}) {
    my $version = $ENV{GCCGO_BUILD_GCCGO_VERSION};
    if ($version == "7") {
        $use_new_gccgo = 1;
    }
} else {
    # detected by kernel version
    my $kernel_release=qx(uname -r);
    if ($kernel_release =~ /-aere-/) {
        $use_new_gccgo = 1;
    }
}

if ($use_new_gccgo) {
    $go_bin = "/usr/sw/swgcc720-standard/usr/bin/go";
    $ENV{LD_LIBRARY_PAT}="/usr/sw/swgcc720-standard/usr/lib";
    $ENV{C_INCLUDE_PATH}="/usr/include";
    $ENV{PKG_CONFIG_ALLOW_SYSTEM_LIBS} = '1';
}

say "use new gccgo: ". ($use_new_gccgo ? "yes" : "no");

sub get_libs_L {
	my $pkgnames = shift;
	my $opt_L = qx(pkg-config --libs-only-L --static $pkgnames);
	chomp $opt_L;
	return $opt_L;
}

sub get_libs_l {
    my $pkgnames = shift;
    my $opt_l = qx(pkg-config --libs-only-l $pkgnames);
    chomp $opt_l;
    return $opt_l;
}

my $arch = qx(arch);
chomp $arch;
say "arch: $arch";

# get part of gccgo flags from pkg-config
sub get_part_gccgo_flags {
    my $pkgnames = shift;
    if ($use_new_gccgo) {
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
    } else {
        my $opt_l = get_libs_l($pkgnames);
        return $opt_l;
    }
}

my %opts;

# -o output name
# -p pkg-config pkgnames
# -f extra gccgoflags
# -l extra link libs, only for old version gccgo
getopts('o:p:f:l:', \%opts);

if (!defined $opts{o}) {
    die "no set output";
}
my $output = $opts{o};
my $pkg_config_pkg_names = $opts{p} // "";
my $extra_gccgo_flags = $opts{f} // "";
my $extra_gccgo_libs = $opts{l} // "";

say "output: $output";
say "pkg-config pkg_names: $pkg_config_pkg_names";

my $gccgoflags = "";
my $part_gccgo_flags = get_part_gccgo_flags($pkg_config_pkg_names);

if ($use_new_gccgo) {
    $gccgoflags = "-Wl,--dynamic-linker=/lib/ld-linux.so.2 $part_gccgo_flags $extra_gccgo_flags";
} else {
	my @libs = split /\s/, $extra_gccgo_libs;
	my $extra_gccgo_libs_flags = join(" ", map { "-l".$_ } @libs);
    $gccgoflags = "$part_gccgo_flags $extra_gccgo_flags $extra_gccgo_libs_flags";
}

# run go build command
my @cmdline_args = ($go_bin, "build", "-v", "-o", $output, "-compiler", "gccgo",
 "-gccgoflags", $gccgoflags);
push @cmdline_args, @ARGV;
say '$ ' . join(" ", @cmdline_args);
my $gobuild_ret = system(@cmdline_args);
if ($gobuild_ret != 0) {
    die "go build failed: $!";
}

if ($use_new_gccgo) {
    # delete rpath setting
    my $chrpath_ret = system("chrpath", "-d", $output);
    if ($chrpath_ret != 0) {
        die "chrpath failed: %!";
    }
}
