use strict;
package Plack::App::GitHub::WebHook;
#ABSTRACT: GitHub WebHook receiver as Plack application
our $VERSION = '0.4'; #VERSION
use v5.10;
use JSON qw(decode_json);

use parent 'Plack::Component';
use Plack::Util::Accessor qw(hook access app);
use Plack::Request;
use Plack::Middleware::Access;
use Carp qw(croak);

sub prepare_app {
    my $self = shift;

    if ($self->hook) {
        if ( (ref $self->hook // '') eq 'CODE' ) {
            $self->hook( [ $self->hook ] );
        } elsif ( (ref $self->hook // '') ne 'ARRAY' ) {
            croak "hook must be a CODEREF or ARRAYREF";
        }
    } else {
        $self->hook([]);
    }

    $self->access([
        allow => "204.232.175.64/27",
        allow => "192.30.252.0/22",
        deny  => "all"
    ]) unless $self->access;

    $self->app(
        Plack::Middleware::Access->wrap(
            sub { $self->call_granted(shift) },
            rules => $self->access
        )
    );

    $self->init;
}

sub init { }

sub call {
    my ($self, $env) = @_;
    $self->app->($env);
}

sub call_granted {
    my ($self, $env) = @_;

    if ( $env->{REQUEST_METHOD} ne 'POST' ) {
        return [405,['Content-Type'=>'text/plain','Content-Length'=>18],['Method Not Allowed']];
    }

    my $req = Plack::Request->new($env);

    my $json = eval { decode_json $req->body_parameters->{payload} };

    if (!$json) {
        return [400,['Content-Type'=>'text/plain','Content-Length'=>11],['Bad Request']];
    }

    if ( $self->receive($json) ) {
        return [200,['Content-Type'=>'text/plain','Content-Length'=>2],['OK']];
    } else {
        return [202,['Content-Type'=>'text/plain','Content-Length'=>8],['Accepted']];
    }
}

sub receive {
    my ($self, $payload) = @_;

    my $ok;
    foreach my $hook (@{$self->{hook}}) {
        return unless $hook->($payload);
        $ok++;
    } 
    return $ok;
}


1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Plack::App::GitHub::WebHook - GitHub WebHook receiver as Plack application

=head1 VERSION

version 0.4

=head1 SYNOPSIS

    use Plack::App::GitHub::WebHook;

    Plack::App::GitHub::WebHook->new(
        hook => sub {
            my $payload = shift;
            ...
        }
    )->to_app;

=head2 Multiple hooks

If multiple hooks are provided, they get called one by one until
a hook returns a false value.

    use Plack::App::GitHub::WebHook;
    use IPC::Run3;

    Plack::App::GitHub::WebHook->new(
        hook => [
            sub { $_[0]->{repository}{name} eq 'foo' }, # filter
            sub { my ($payload) = @_; ...  }, # some action
            sub { run3 \@cmd ... }, # some more action
        ]
    )->to_app;

=head2 Access restriction    

By default access is restricted to known GitHub WebHook IPs.

    Plack::App::GitHub::WebHook->new(
        hook => sub { ... },
        access => [
            allow => "204.232.175.64/27",
            allow => "192.30.252.0/22",
            deny  => 'all'
        ]
    )->to_app;

    # this is equivalent to
    use Plack::Builder;
    builder {
        mount 'notify' => builder {
            enable 'Access', rules => [
                allow => "204.232.175.64/27",
                allow => "192.30.252.0/22",
                deny  => 'all'
            ]
            Plack::App::GitHub::WebHook->new(
                hook => sub { ... }
            );
        }
    };

=head1 DESCRIPTION

This L<PSGI> application receives HTTP POST requests with body parameter
C<payload> set to a JSON object. The default use case is to receive
L<GitHub WebHooks|https://help.github.com/articles/post-receive-hooks>.

The response of a HTTP request to this application is one of:

=over 4

=item HTTP 403 Forbidden

If access was not granted (for instance because it did not origin from GitHub).

=item HTTP 405 Method Not Allowed

If the request was no HTTP POST.

=item HTTP 400 Bad Request

If the payload was no well-formed JSON. A later version of this module may add
further validation.

=item HTTP 200 OK

Otherwise, if the hook was called and returned a true value.

=item HTTP 202 Accepted

Otherwise, if the hook was called and returned a false value.

=back

This module requires at least Perl 5.10.

=head1 CONFIGURATION

=over 4

=item hook

A code reference or an array reference of code references with multiple tasks.
Each task gets passed the encoded payload. If the task returns a true value,
next the task is called or HTTP status code 200 is returned. Information can be
passed from one task to the next by modifying the payload. 

If a task fails or no task was given, HTTP status code 202 is returned
immediately. This mechanism can be used for conditional hooks or to detect
hooks that were called successfully but failed to execute for some reason.

=item access

Access restrictions, as passed to L<Plack::Middleware::Access>. See SYNOPSIS
for the default value. A recent list of official GitHub WebHook IPs is vailable
at L<https://api.github.com/meta>. One should only set the access value on
instantiation, or manually call C<prepare_app> after modification.

=back

=head1 SEE ALSO

L<WWW::GitHub::PostReceiveHook> uses L<Web::Simple> to receive GitHub web
hooks. L<Net::GitHub> and L<Pithub> provide access to GitHub APIs.

=head1 AUTHOR

Jakob Voß

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Jakob Voß.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
