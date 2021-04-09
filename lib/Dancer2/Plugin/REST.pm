package Dancer2::Plugin::REST;
# ABSTRACT: A plugin for writing RESTful apps with Dancer2

use 5.12.0;  # for the sub attributes

use strict;
use warnings;

use Carp;

use Dancer2::Plugin;

use Dancer2::Core::HTTP 0.203000;
use List::Util qw/ pairmap pairgrep /;

my %content_types = (
    yaml => 'text/x-yaml',
    yml  => 'text/x-yaml',
    json => 'application/json',
    dump => 'text/x-data-dumper',
    ''   => 'text/html',
);

# TODO check if we use the handles
has '+app' => (
    handles => [qw/
        add_hook
        add_route
        response
        request
    /],
);

sub prepare_serializer_for_format :PluginKeyword { 
    my $self = shift;

    my $conf = $self->app->config;
    if( my $serializer = $conf->{serializer} ) {
        warn "serializer '$serializer' specified in config file, overrode by Dancer2::Plugin::REST\n";
    }

    $conf->{serializer} = 'Mutable::REST';

    ## laod content_types from dancer config
    if( exists( $conf->{plugins}{REST}{content_types} ) ) {
      while( my ( $k, $v ) = each( %{ $conf->{plugins}{REST}{content_types} } ) ) {
	warn( qq{loading content_types "$v" from config\n} );
	$content_types{ $k } = $v;
      }
    }

    $self->add_hook( Dancer2::Core::Hook->new(
        name => 'before',
        code => sub {
            my $format = $self->request->params->{'format'}
                         || eval { $self->request->captures->{'format'} };

            my $content_type = lc $content_types{$format||''} or return;

            $self->request->headers->header( 'Content-Type' => $content_type );

        }
    ) );
}

sub resource :PluginKeyword {
    my ($self, $resource, %triggers) = @_;

    my %actions = (
        update => 'put',
        create => 'post',
        map { $_ => $_ } qw/ get delete /
    );

    croak "resource should be given with triggers"
      unless defined $resource
             and grep { $triggers{$_} } keys %actions;

    while( my( $action, $code ) = each %triggers ) {
            $self->add_route( 
                method => $actions{$action},
                regexp => $_,
                code   => $code,
            ) for map { sprintf $_, '/:id' x ($action ne 'create') }
                        "/${resource}%s.:format", "/${resource}%s";
    }
};

sub send_entity :PluginKeyword {
    my ($self, $entity, $http_code) = @_;

    $self->response->status($http_code || 200);
    $entity;
};

sub _status_helpers {
    return 
                # see https://github.com/PerlDancer/Dancer2/pull/1235
           pairmap { ( $a =~ /\d.*_/ ? (split '_', $a, 2 )[1] : $a ), $b  }
           pairmap  { $a =~ /^\d+$/ ? ( $a => $a ) : ( $a => $b ) }
           pairgrep { $a !~ /[A-Z]/ } 
                    Dancer2::Core::HTTP->all_mappings;
}

plugin_keywords pairmap {
    { # inner scope because of the pairmap closure bug <:-P
        my( $helper_name, $code ) = ( $a, $b );
        $helper_name = "status_${helper_name}";

        $helper_name => sub {
            $_[0]->send_entity(
                ( ( $code >= 400 && ! ref $_[1] ) ? {error => $_[1]} : $_[1] ),
                $code
            );
        };
    }
} _status_helpers();

1;

package 
    Dancer2::Serializer::Mutable::REST;

# TODO write patch for D2:S:M to provide our own mapping
# and then we'll be able to preserce the 'text/html'

use Moo;

extends 'Dancer2::Serializer::Mutable';

around _get_content_type => sub {
    my( $orig, $self, $entity ) = @_;

    $self->has_request or return;

    my $ct = $self->request->header( 'content_type' );

    if( $ct eq 'text/html' or $ct eq '' ) {
        $self->set_content_type( 'text/html' );
        return;
    }

    $orig->($self,$entity);
};

1;

__END__

=pod


=head1 SYNOPSIS

    package MyWebService;

    use Dancer2;
    use Dancer2::Plugin::REST;

    prepare_serializer_for_format;

    get '/user/:id.:format' => sub {
        User->find(params->{id});
    };

    get qr{^/user/(?<id>\d+)\.(?<format>\w+)} => sub {
        User->find(captures->{id});
    };

    # curl http://mywebservice/user/42.json
    { "id": 42, "name": "John Foo", email: "john.foo@example.com"}

    # curl http://mywebservice/user/42.yml
    --
    id: 42
    name: "John Foo"
    email: "john.foo@example.com"

=head1 DESCRIPTION

This plugin helps you write a RESTful webservice with Dancer2.

=head1 CONFIGURATION

=head2 serializers

The default format serializer hash which maps a given C<:format> to 
a C<Dancer2::Serializer::*> serializer. Unless overriden in the 
configuration, it defaults to:

    serializers:
      json: JSON
      yml:  YAML
      dump: Dumper

=head1 KEYWORDS

=head2 prepare_serializer_for_format

When this pragma is used, a before filter is set by the plugin to automatically
change the serializer when a format is detected in the URI.

That means that each route you define with a B<:format> param or captures token 
will trigger a serializer definition, if the format is known.

This lets you define all the REST actions you like as regular Dancer2 route
handlers, without explicitly handling the outgoing data format.

Regexp routes will use the file-extension from captures->{'format'} to determine
the serialization format.

=head2 content_type

it's possible to override the context_type definition for the format detected in the URI.

For that use the Dancer2 configuration file with:

    plugins:
      REST:
        content_types:
          yaml: 'text/x-yaml'
          yml: 'text/x-yaml'
          json: 'application/json'
          dump: 'text/x-data-dumper'
          xml: 'text/xml'

=head2 resource

This keyword lets you declare a resource your application will handle.

    resource user =>
        get    => sub { # return user where id = params->{id}   },
        create => sub { # create a new user with params->{user} },
        delete => sub { # delete user where id = params->{id}   },
        update => sub { # update user with params->{user}       };

    # this defines the following routes:
    # GET /user/:id
    # GET /user/:id.:format
    # POST /user
    # POST /user.:format
    # DELETE /user/:id
    # DELETE /user/:id.:format
    # PUT /user/:id
    # PUT /user/:id.:format

=head2 helpers

Helpers are available for all HTTP codes as recognized by L<Dancer2::Core::HTTP>:

    status_100    status_continue
    status_101    status_switching_protocols
    status_102    status_processing

    status_200    status_ok
    status_201    status_created
    status_202    status_accepted
    status_203    status_non_authoritative_information
    status_204    status_no_content
    status_205    status_reset_content
    status_206    status_partial_content
    status_207    status_multi_status
    status_208    status_already_reported

    status_301    status_moved_permanently
    status_302    status_found
    status_303    status_see_other
    status_304    status_not_modified
    status_305    status_use_proxy
    status_306    status_switch_proxy
    status_307    status_temporary_redirect

    status_400    status_bad_request
    status_401    status_unauthorized
    status_402    status_payment_required
    status_403    status_forbidden
    status_404    status_not_found
    status_405    status_method_not_allowed
    status_406    status_not_acceptable
    status_407    status_proxy_authentication_required
    status_408    status_request_timeout
    status_409    status_conflict
    status_410    status_gone
    status_411    status_length_required
    status_412    status_precondition_failed
    status_413    status_request_entity_too_large
    status_414    status_request_uri_too_long
    status_415    status_unsupported_media_type
    status_416    status_requested_range_not_satisfiable
    status_417    status_expectation_failed
    status_418    status_i_m_a_teapot
    status_420    status_enhance_your_calm
    status_422    status_unprocessable_entity
    status_423    status_locked
    status_424    status_failed_dependency
    status_425    status_unordered_collection
    status_426    status_upgrade_required
    status_428    status_precondition_required
    status_429    status_too_many_requests
    status_431    status_request_header_fields_too_large
    status_444    status_no_response
    status_449    status_retry_with
    status_450    status_blocked_by_windows_parental_controls
    status_451    status_redirect
    status_494    status_request_header_too_large
    status_495    status_cert_error
    status_496    status_no_cert
    status_497    status_http_to_https
    status_499    status_client_closed_request

    status_500    status_error, status_internal_server_error
    status_501    status_not_implemented
    status_502    status_bad_gateway
    status_503    status_service_unavailable
    status_504    status_gateway_timeout
    status_505    status_http_version_not_supported
    status_506    status_variant_also_negotiates
    status_507    status_insufficient_storage
    status_508    status_loop_detected
    status_509    status_bandwidth_limit_exceeded
    status_510    status_not_extended
    status_511    status_network_authentication_required
    status_598    status_network_read_timeout_error
    status_599    status_network_connect_timeout_error

All 1xx, 2xx and 3xx status helpers will set the response status to the right value
and serves its argument as the response, serialized.

    status_ok({users => {...}});
    # set status to 200, serves the serialized format of { users => {... } }

    status_200({users => {...}});
    # ditto

    status_created({users => {...}});
    # set status to 201, serves the serialized format of { users => {... } }

For error statuses ( 4xx and 5xx ), there is an additional dash of
syntaxic sugar: if the argument is a simple string, it'll
be converted to C<{ error => $error }>.

    status_not_found({ error => "file $name not found" } );
    # send 404 with serialization of { error => "file blah not found" }

    status_not_found("file $name not found");
    # ditto


=head1 LICENCE

This module is released under the same terms as Perl itself.

=head1 AUTHORS

This module has been written by Alexis Sukrieh C<< <sukria@sukria.net> >> and Franck
Cuny.

=head1 SEE ALSO

L<Dancer2> L<http://en.wikipedia.org/wiki/Representational_State_Transfer>

=cut
