use strict;
use warnings;
use Test::More;

use Digest::SHA;

use Plack::Test;
use Plack::Builder;
use HTTP::Request::Common;
use Mojo::Server::PSGI;

my $content = [qw/hello world/];
my $sha = Digest::SHA->new->add(@$content)->hexdigest;

my $handler = builder {
    enable "Plack::Middleware::ETag";
    sub { [ '200', [ 'Content-Type' => 'text/html' ], $content ] };
};

my $second_handler = builder {
    enable "Plack::Middleware::ETag";
    sub {
        [
            '200', [ 'Content-Type' => 'text/html', 'ETag' => '123' ],
            $content
        ];
    };
};

my $unmodified_handler = builder {
    enable "Plack::Middleware::ConditionalGET";
    enable "Plack::Middleware::ETag";
    sub { [ '200', [ 'Content-Type' => 'text/html' ], $content ] };
};

my $file_handler = builder {
   enable "Plack::Middleware::ETag";
   open my $fh, 'README';
   sub {[200, ['Content-Type' => 'text/html', ], $fh]};
};

my $mojo_handler = builder {
   enable "Plack::Middleware::ETag";
   my $psgi = Mojo::Server::PSGI->new;
   $psgi->unsubscribe('request');
   $psgi->on(request => sub {
    my ($psgi, $tx) = @_;
    $tx->res->code(200);
    $tx->res->headers->content_type('text/plain');
    $tx->res->body(join ' ', @$content);
    $tx->resume;
   });
   $psgi->to_psgi_app;
};

my $cache_control = builder {
    enable "Plack::Middleware::ETag", cache_control => 1;
    sub { [ '200', [ 'Content-Type' => 'text/html' ], $content ] };
};

my $cache_control_array = builder {
    enable "Plack::Middleware::ETag",
      cache_control => [ 'must-revalidate', 'max-age=3600', 'no-store' ];
    sub { [ '200', [ 'Content-Type' => 'text/html' ], $content ] };
};

test_psgi
    app    => $handler,
    client => sub {
    my $cb = shift;
    {
        my $req = GET "http://localhost/";
        my $res = $cb->($req);
        ok $res->header('ETag');
        is $res->header('ETag'), $sha;
    }
};

test_psgi
    app    => $second_handler,
    client => sub {
    my $cb = shift;
    {
        my $req = GET "http://localhost/";
        my $res = $cb->($req);
        ok $res->header('ETag');
        is $res->header('ETag'), '123';
    }
};

test_psgi
    app    => $unmodified_handler,
    client => sub {
    my $cb = shift;
    {
        my $req = GET "http://localhost/", 'If-None-Match' => $sha;
        my $res = $cb->($req);
        ok $res->header('ETag');
	is $res->code, 304;
	ok !$res->content;
    }
};

test_psgi
    app    => $file_handler,
    client => sub {
    my $cb = shift;
    {
        my $req = GET "http://localhost/";
        my $res = $cb->($req);
        ok $res->header('ETag');
	is $res->code, 200;
	ok $res->content;
    }
};

test_psgi
    app    => $mojo_handler,
    client => sub {
    my $cb = shift;
    {
        my $req = GET "http://localhost/";
        my $res = $cb->($req);
        ok $res->header('ETag');
	is $res->code, 200;
	ok $res->content;
    }
};

test_psgi
  app    => $cache_control,
  client => sub {
    my $cb = shift;
    {
        my $req = GET "http://localhost/";
        my $res = $cb->($req);
        ok $res->header('ETag');
        is $res->header('ETag'),          $sha;
        is $res->header('Cache-Control'), 'must-revalidate';
    }
  };

test_psgi
  app    => $cache_control_array,
  client => sub {
    my $cb = shift;
    {
        my $req = GET "http://localhost/";
        my $res = $cb->($req);
        ok $res->header('ETag');
        is $res->header('ETag'), $sha;
        is $res->header('Cache-Control'),
          'must-revalidate, max-age=3600, no-store';
    }
  };

done_testing;
