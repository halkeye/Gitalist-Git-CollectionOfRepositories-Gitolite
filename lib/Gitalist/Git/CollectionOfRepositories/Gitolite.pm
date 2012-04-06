use MooseX::Declare;
#use IPC::System::Simple ();
use warnings;
use strict;
use Data::Dumper;
use File::Basename;

# ABSTRACT: Adds support for gitolite to gitalist

# GL_RC=/home/git/.gitolite.rc GL_BINDIR=/home/git/bin HOME=/home/git perl -I /home/git/bin -Mgitolite_env -Mgitolite -e 'print gitolite::report_basic("^","halkeye");'
$ENV{GL_RC}||="/home/git/.gitolite.rc";
$ENV{GL_BINDIR}||="/home/git/bin";

class Gitalist::Git::CollectionOfRepositories::Gitolite
    with Gitalist::Git::CollectionOfRepositoriesWithRequestState 
{
    use MooseX::Types::Common::String qw/NonEmptySimpleStr/;    
    use Gitalist::Git::Types qw/ ArrayRefOfDirs Dir DirOrUndef /;
    use MooseX::Types::Path::Class qw/Dir/;

    # Simple directory of repositories (for list)
    has repo_dir => (
        is => 'ro',
        isa => DirOrUndef,
        coerce => 1,
        builder => '_build_repo_dir',
        lazy => 1,
    );
    
    method implementation_class { 'Gitalist::Git::CollectionOfRepositories::GitoliteImpl' }
    method debug_string { 'Chose ' . ref($self) }

    method extract_request_state ($ctx) {
        return (
            remote_user => $ctx->request->remote_user || $ENV{REMOTE_USR} || 'guest',
            repo_dir => $self->repo_dir
        );
    }
}

class Gitalist::Git::CollectionOfRepositories::GitoliteImpl
    extends Gitalist::Git::CollectionOfRepositories::FromDirectory {
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
            Gitalist::Git::CollectionOfRepositories::GitoliteImpl::Collection->new(%$self);
        },
        lazy => 1,
    );

}

class Gitalist::Git::CollectionOfRepositories::GitoliteImpl::Collection
    extends Gitalist::Git::CollectionOfRepositories::FromDirectory {
    use MooseX::Types::Common::String qw/NonEmptySimpleStr/;    
    
    has remote_user => (
        is => 'ro',
        isa => NonEmptySimpleStr,
        required => 1,
    );
    method _build_repositories { 
        my $ret = [];
        my $user = ($self->remote_user || 'guest');
        $user =~ s/\@.*$//; # trim off exchange domain
        $user = lc $user;

warn "here $user";
        local $ENV{HOME} = File::Basename::dirname($ENV{GL_RC});

        # Gitolite does a lot of messing with envs so only load at runtime once everything is setup right (better for local)
        unless ($INC{'gitolite'})
        {
            no warnings;
            require "$ENV{GL_BINDIR}/gitolite_env.pm";
        }

        my @repos;
        eval {
            {
                no warnings;
                @repos = gitolite::list_phy_repos();
            }
            $self->repo_dir($ENV{GL_REPO_BASE_ABS});

            foreach my $repo ( sort { lc $a cmp lc $b } @repos )
            {
                my $dir = $self->repo_dir->subdir($repo . '.git');
                next unless -d $dir; 
                next unless gitolite::can_read( $repo, $user);
                push @$ret, Gitalist::Git::Repository->new($dir),
            }
        };
        warn $@ if $@;
        return $ret;
    }
}
