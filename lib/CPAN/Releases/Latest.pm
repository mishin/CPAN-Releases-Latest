package CPAN::Releases::Latest;

use 5.006;
use Moo;
use File::HomeDir;
use File::Spec::Functions 'catfile';
use MetaCPAN::Client 1.001000;
use CPAN::DistnameInfo;
use Carp;
use autodie;

my $FORMAT_REVISION = 1;

has 'max_age'    => (is => 'ro', default => sub { '1 day' });
has 'cache_path' => (is => 'rw');
has 'basename'   => (is => 'ro', default => sub { 'latest-releases.txt' });
has 'path'       => (is => 'ro');

sub BUILD
{
    my $self = shift;

    if ($self->path) {
        if (-f $self->path) {
            return;
        }
        else {
            croak "the file you specified with 'path' doesn't exist";
        }
    }

    if (not $self->cache_path) {
        my $classid = __PACKAGE__;
           $classid =~ s/::/-/g;

        $self->cache_path(
            catfile(File::HomeDir->my_dist_data($classid, { create => 1 }),
                    $self->basename)
        );
    }

    if (-f $self->cache_path) {
        require Time::Duration::Parse;
        my $max_age_in_seconds = Time::Duration::Parse::parse_duration(
                                     $self->max_age
                                 );
        return unless time() - $max_age_in_seconds
                      > (stat($self->cache_path))[9];
    }

    $self->_build_cached_index();
}

sub _build_cached_index
{
    my $self = shift;

    my $client     = MetaCPAN::Client->new();
    my $query      = {
                        either => [
                                      { all => [
                                          { status   => 'latest'    },
                                          { maturity => 'released'  },
                                      ]},

                                      { all => [
                                          { status   => 'cpan'      },
                                          { maturity => 'developer' },
                                      ]},
                                   ]
                     };
    my $params     = {
                         fields => [qw(name version date status maturity stat download_url)]
                     };
    my $result_set = $client->release($query, $params);
    my $scroller   = $result_set->scroller;
    my $distdata   = {
                         released  => {},
                         developer => {},
                     };
    my %seen;

    while (my $result = $scroller->next) {
        my $release  = $result->{fields};
        my $maturity = $release->{maturity};
        my $slice    = $distdata->{$maturity};
        my $path     = $release->{download_url};
           $path     =~ s!^.*/authors/id/!!;
        my $distinfo = CPAN::DistnameInfo->new($path);
        my $distname = defined($distinfo) && defined($distinfo->dist)
                       ? $distinfo->dist
                       : $release->{metadata}->{name};

        next unless !exists($slice->{ $distname })
                 || $release->{stat}->{mtime} > $slice->{$distname}->{time};
        $seen{ $distname }++;
        $slice->{ $distname } = {
                                    path => $path,
                                    time => $release->{stat}->{mtime},
                                    size => $release->{stat}->{size},
                                };
    }

    open(my $fh, '>', $self->cache_path);
    print $fh "#FORMAT: $FORMAT_REVISION\n";
    foreach my $distname (sort { lc($a) cmp lc($b) } keys %seen) {
        my ($stable_release, $developer_release);

        if (defined($stable_release = $distdata->{released}->{$distname})) {
            printf $fh "%s %s %d %d\n",
                       $distname,
                       $stable_release->{path},
                       $stable_release->{time},
                       $stable_release->{size};
        }

        if (   defined($developer_release = $distdata->{developer}->{$distname})
            && (   !defined($stable_release)
                || $developer_release->{time} > $stable_release->{time}
               )
           )
        {
            printf $fh "%s %s %d %d\n",
                       $distname,
                       $developer_release->{path},
                       $developer_release->{time},
                       $developer_release->{size};
        }

    }
    close($fh);
}

sub release_iterator
{
    my $self = shift;

    require CPAN::Releases::Latest::ReleaseIterator;
    return CPAN::Releases::Latest::ReleaseIterator->new( latest => $self, @_ );
}

1;

=head1 NAME

CPAN::Releases::Latest - a list of the latest release(s) of all dists on CPAN, including dev releases

=head1 SYNOPSIS

 use CPAN::Releases::Latest;
 
 my $latest   = CPAN::Releases::Latest->new();
 my $iterator = $latest->release_iterator();
 
 while (my $release = $iterator->next_release) {
     printf "%s path=%s  time=%d  size=%d\n",
            $release->distname,
            $release->path,
            $release->timestamp,
            $release->size;
 }

=head1 DESCRIPTION

VERY MUCH AN ALPHA. ALL THINGS MAY CHANGE.

This module uses the MetaCPAN API to construct a list of all dists on CPAN.
It will let you iterate across these, returning the latest release of the dist.
If the latest release is a developer release, then you'll first get back the
non-developer release (if there is one), and then you'll get back the developer release.

=head1 REPOSITORY

L<https://github.com/neilbowers/CPAN-Releases-Latest>

=head1 AUTHOR

Neil Bowers E<lt>neilb@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Neil Bowers <neilb@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
