use MooseX::Declare;
use IPC::System::Simple ();
use warnings;
use strict;
use Data::Dumper;
use File::Basename;

# GL_RC=/home/git/.gitolite.rc GL_BINDIR=/home/git/bin HOME=/home/git perl -I /home/git/bin -Mgitolite_env -Mgitolite -e 'print gitolite::report_basic("^","halkeye");'
$ENV{GL_RC}||="/home/git/.gitolite.rc";
$ENV{GL_BINDIR}||="/home/git/bin";

class Gitalist::Git::CollectionOfRepositories::Gitolite
    with Gitalist::Git::CollectionOfRepositoriesWithRequestState {

    use MooseX::Types::Moose qw/HashRef/;
    sub BUILDARGS {
        my ($class, @args) = @_;
        my $args = $class->next::method(@args);
        my %collections = %{ delete $args->{collections} };
        foreach my $name (keys %collections) {
            my %args = %{$collections{$name}};
            my $class = delete $args{class};
            Class::MOP::load_class($class);
            $collections{$name} = $class->new(%args);
        }
        my $ret = { %$args, collections => \%collections };
        return $ret;
    }

    has remote_user_dispatch => (
        isa => HashRef,
        traits => ['Hash'],
        required => 1,
        handles => {
            _get_collection_name_for_remote_user => 'get',
        },
    );
    method implementation_class { 'Gitalist::Git::CollectionOfRepositories::GitoliteImpl' }

    method extract_request_state ($ctx) {
        return (remote_user => $ctx->request->remote_user);
    }
}
class Gitalist::Git::CollectionOfRepositories::GitoliteImpl
    extends Gitalist::Git::CollectionOfRepositories {
    use MooseX::Types::Moose qw/ HashRef Str /;
    use MooseX::Types::Common::String qw/NonEmptySimpleStr/;
    use MooseX::Types::Path::Class qw/Dir/;
    use Moose::Util::TypeConstraints;

    has remote_user_dispatch => (
        isa => HashRef,
        traits => ['Hash'],
        required => 1,
        handles => {
            _get_collection_name_for_vhost => 'get',
        },
    );

    has collections => (
        isa => HashRef,
        traits => ['Hash'],
        required => 1,
        handles => {
            _get_collection => 'get',
        }
    );

    has remote_user => (
        is => 'ro',
        isa => Str,
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
            my $ret = [];
            my $user = ($self->remote_user || 'guest');
            $user =~ s/\@.*$//; # trim off exchange domain
            $user = lc $user;

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
        },
        lazy => 1,
    );
}
