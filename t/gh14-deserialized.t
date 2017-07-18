use strict;
use warnings;
use Test::More;# tests=>3;
use Plack::Test;
use HTTP::Request::Common;
use Test::JSON::More;
use JSON;

{
    package App;
    use Dancer2;
    set serializer => 'JSON';

    post '/namecheck.:format' => sub {
        my $post_params = params('body');
	return $post_params;
    };

}
{
    package RESTApp;
    use Dancer2;
    use Dancer2::Plugin::REST;
    prepare_serializer_for_format;

    post '/namecheck.:format' => sub {
        my $post_params = params('body');
	return $post_params;
    };

}
my $req = HTTP::Request->new(POST => "/namecheck.json");
$req->header("Content-Type"=>"application/json");
my $json='{"item":1,"type":"test"}';
$req->content($json);
ok_json($json, "JSON Seems wellformed");

my $app = App->to_app;
my $restapp = RESTApp->to_app;

test_app( '$app', $app );
test_app( '$restapp', $restapp );

sub test_app {
    my( $desc, $app) = @_;

    subtest $desc => sub {
        is( ref $restapp, 'CODE', 'Got app' );
        my $test = Plack::Test->create($app);
        my $res=$test->request($req);
        is( $res->code, 200, '[POST: Check Name  ] ' )or BAIL_OUT("checking of a name  is necessary for testing to proceed.");
        cmp_json($res->content,$json,"Check If response JSON matches Input");
    };
}


done_testing;
