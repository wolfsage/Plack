package Plack::Server::Mojo;
use strict;
use warnings;
use base qw(Mojo::Base);
use Plack::Util;
use URI;
use URI::Escape;

__PACKAGE__->attr([ 'host', 'port' ]);

my $mojo_daemon;

sub mojo_daemon_class { 'Mojo::Server::Daemon' }

sub run {
    my($self, $app) = @_;

    my $mojo_app = Plack::Server::Mojo::App->new(psgi_app => $app);

    my $class = $self->mojo_daemon_class;
    Plack::Util::load_class($class);

    $mojo_daemon = $class->new;
    $mojo_daemon->port($self->port)    if $self->port;
    $mojo_daemon->address($self->host) if defined $self->host;
    $mojo_daemon->app($mojo_app);
    $mojo_daemon->run;
}

package Plack::Server::Mojo::App;
use base qw(Mojo);

__PACKAGE__->attr([ 'psgi_app' ]);

sub is_multiprocess { Plack::Util::FALSE }

sub handler {
    my($self, $tx) = @_;

    my %env;
    $env{REQUEST_METHOD} = $tx->req->method;
    $env{SCRIPT_NAME}    = "";
    $env{REQUEST_URI}    = URI->new($tx->req->url)->path_query;
    $env{PATH_INFO}      = URI::Escape::uri_unescape($tx->req->url->path);
    $env{QUERY_STRING}   = $tx->req->url->query->to_string;
    $env{SERVER_NAME}    = $mojo_daemon->address;
    $env{SERVER_PORT}    = $mojo_daemon->port;
    $env{SERVER_PROTOCOL} = "HTTP/" . $tx->req->version;

    for my $name (@{ $tx->req->headers->names }) {
        (my $header = $name) =~ tr/-/_/;
        $env{"HTTP_" . uc($header)} = $tx->req->headers->header($name);
    }

    $env{CONTENT_TYPE}   = $tx->req->headers->content_type;
    $env{CONTENT_LENGTH} = $tx->req->headers->content_length;

    # FIXME: use IO::Handle-ish API
    my $content = $tx->req->content->asset->slurp;
    open my $input, "<", \$content;

    $env{'psgi.version'}    = [1,0];
    $env{'psgi.url_scheme'} = 'http';
    $env{'psgi.input'}      = $input;
    $env{'psgi.errors'}     = *STDERR;

    $env{'psgi.multithread'}  = Plack::Util::FALSE;
    $env{'psgi.multiprocess'} = $self->is_multiprocess;
    $env{'psgi.run_once'}     = Plack::Util::FALSE;

    my $res = Plack::Util::run_app $self->psgi_app, \%env;

    $tx->res->code($res->[0]);
    my $headers = $res->[1];
    while (my ($k, $v) = splice(@$headers, 0, 2)) {
        $tx->res->headers->header($k => $v);
    }

    my $body = $res->[2];

    my $response_content;
    Plack::Util::foreach($body, sub { $response_content .= $_[0] });
    $tx->res->body($response_content);
}

package Plack::Server::Mojo;

1;

__END__

=head1 NAME

Plack::Server::Mojo - Mojo daemon based PSGI handler

=head1 SYNOPSIS

  use Plack::Server::Mojo;

  my $server = Plack::Server::Mojo->new(
      host => $host,
      port => $port,
  );
  $server->run($app);

=head1 DESCRIPTION

This implementation is considered highly experimental.

=cut
