use MooseX::Declare;
use namespace::autoclean;
#use warnings;
#use strict;
#use File::Basename;

# ABSTRACT: Adds support for gitolite to gitalist

class Gitalist::Git::CollectionOfRepositories::Gitolite
    with Gitalist::Git::CollectionOfRepositoriesWithRequestState 
{
    use MooseX::Types::Common::String qw/NonEmptySimpleStr/;    
    use Gitalist::Git::Types qw/DirOrUndef /;

    has gitolite_conf => (
        is       => 'ro',
        isa      => NonEmptySimpleStr,
        default  => '/home/git/.gitolite.rc',
        required => 0,
    );

    has gitolite_bin_dir => (
        is       => 'ro',
        isa      => DirOrUndef,
        default  => '/home/git/bin',
        required => 0,
        coerce   => 1,
        lazy     => 1,
    );
    
    method implementation_class { 'Gitalist::Git::CollectionOfRepositories::Gitolite::Impl' }
    method debug_string { 'Chose ' . ref($self) }

    method extract_request_state ($ctx) {
        return (
            remote_user => $ctx->request->remote_user || $ENV{REMOTE_USER} || 'gitweb',
        );
    }
}

class Gitalist::Git::CollectionOfRepositories::Gitolite::Impl
{
    use MooseX::Types::Common::String qw/NonEmptySimpleStr/;    
    use MooseX::Types::Path::Class qw/Dir/;
    use Moose::Util::TypeConstraints;

    has remote_user => (
        is => 'ro',
        isa => NonEmptySimpleStr,
        required => 1,
    );

    method debug_string { 'chosen collection ' . ref($self->chosen_collection) . " " . $self->chosen_collection->debug_string }

    role_type 'Gitalist::Git::CollectionOfRepositories';
    has chosen_collection => (
        is => 'ro',
        does => 'Gitalist::Git::CollectionOfRepositories',
        handles => [qw/
            _get_repo_from_name
            _build_repositories
            /],
        default => sub {
            my $self = shift;
            Gitalist::Git::CollectionOfRepositories::Gitolite::Collection->new(%$self);
        },
        lazy => 1,
    );

}

class Gitalist::Git::CollectionOfRepositories::Gitolite::Collection
    extends Gitalist::Git::CollectionOfRepositories::FromListOfDirectories {
    use MooseX::Types::Common::String qw/NonEmptySimpleStr/;    
    use Gitalist::Git::Types qw/DirOrUndef ArrayRefOfDirs /;
    
    has remote_user => (
        is => 'ro',
        isa => NonEmptySimpleStr,
        required => 1,
    );

    has gitolite_conf => (
        is       => 'ro',
        isa      => NonEmptySimpleStr,
        default  => '/home/git/.gitolite.rc',
        required => 0,
    );

    has gitolite_bin_dir => (
        is       => 'ro',
        isa      => DirOrUndef,
        default  => '/home/git/bin',
        required => 0,
        coerce   => 1,
        lazy     => 1,
    );
    
    has repo_dir => (
        isa      => DirOrUndef,
        is       => 'ro',
        required => 1,
        coerce   => 1,
        default  => sub {
            my $self = shift;
            # GL_RC=/home/git/.gitolite.rc GL_BINDIR=/home/git/bin HOME=/home/git perl -I /home/git/bin -Mgitolite_env -Mgitolite -e 'print gitolite::report_basic("^","halkeye");'
            $ENV{GL_RC}     ||= $self->gitolite_conf . "";
            $ENV{GL_BINDIR} ||= $self->gitolite_bin_dir . "";

            local $ENV{HOME} = File::Basename::dirname($ENV{GL_RC});

            # Gitolite does a lot of messing with envs so only load at runtime once everything is setup right (better for local)
            unless ($INC{'gitolite'})
            {
                no warnings;

                our $REPO_BASE;
                require "$ENV{GL_BINDIR}/gitolite_env.pm";
                require gitolite_rc;    gitolite_rc -> import;
                require gitolite;       gitolite    -> import;
                $ENV{GL_REPO_BASE_ABS} = ( $REPO_BASE =~ m(^/) ? $REPO_BASE : "$ENV{HOME}/$REPO_BASE" );
            }
            return $ENV{GL_REPO_BASE_ABS};
        },
    );

    has repos => (
        isa      => ArrayRefOfDirs,
        is       => 'ro',
        coerce   => 1,
        required => 1,
        default  => sub {
            my $self = shift;
            my $ret = [];

            my $user = ($self->remote_user || 'guest');
            $user =~ s/\@.*$//; # trim off exchange domain
            $user = lc $user;

            # Lazy, so this forces git config to be loaded by calling repo_dir
            $self->repo_dir->resolve();

            my @repos;
            eval {
                {
                    no warnings;
                    @repos = gitolite::list_phy_repos();
                }

                foreach my $repo ( sort { lc $a cmp lc $b } @repos )
                {
                    my $dir = $self->repo_dir->subdir($repo . '.git');
                    next unless -d $dir; 
                    next unless gitolite::can_read( $repo, $user);
                    push @$ret, $dir; #Gitalist::Git::Repository->new($dir),
                }
            };
            warn 'Error (', ref($self), '): ', $@ if $@;
            return $ret;
        }
    );
}

