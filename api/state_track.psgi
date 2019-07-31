use strict;
use warnings;
use JSON;
use Plack::Builder;
use Plack::Request;
use Plack::App::EventSource;
use Couchbase::Bucket;

BEGIN {
    if( not defined($ENV{'STATE_TRACK_CFG'}) )
    {
        die('missing STATE_TRACK_CFG environment variable');
    }

    if( not -r $ENV{'STATE_TRACK_CFG'} )
    {
        die('Cannot access ' . $ENV{'STATE_TRACK_CFG'});
    }

    $CFG::dbhost = '127.0.0.1';
    $CFG::bucket = 'state_track';
    $CFG::dbuser = 'Administrator';
    $CFG::dbpw = 'password';
    $CFG::apiprefix = '/strack/';
    
    do $ENV{'STATE_TRACK_CFG'};
    die($@) if($@);
    die($!) if($!);
};


my $json = JSON->new()->canonical();

sub iterate_and_push
{
    my $env = shift;
    my $cb = shift;
    my $rv = $cb->query_iterator(@_);

    return sub {
        my $responder = shift;
        my $writer = $responder->
            (
             [
              200,
              [
               'Content-Type' => 'text/event-stream; charset=UTF-8',
               'Cache-Control' => 'no-store, no-cache, must-revalidate, max-age=0',
              ]
             ]
            );

        while( (my $row = $rv->next()) )
        {
            my $event = "event: row\x0d\x0a";
            if( defined($row->{'id'}) )
            {
                $event .= 'id: ' . $row->{'id'} . "\x0d\x0a";
            }

            $event .= 'data: ' . $json->encode({%{$row}}) .  "\x0d\x0a";
            $writer->write($event . "\x0d\x0a");
        }

        $writer->write("event: end\x0d\x0a");
        $writer->close();
    };
}
         

my $cb = Couchbase::Bucket->new('couchbase://' . $CFG::dbhost . '/' . $CFG::bucket,
                                {'username' => $CFG::dbuser, 'password' => $CFG::dbpw});




my $builder = Plack::Builder->new;

$builder->mount
    ($CFG::apiprefix . 'networks' => sub {
         my $env = shift;
         my $req = Plack::Request->new($env);
         
         return iterate_and_push
             ($env, $cb,
              'SELECT META().id,block_num,block_time,irreversible,network ' .
              'FROM ' . $CFG::bucket . ' WHERE type=\'sync\'');
     });

$builder->to_app;



# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 4
# cperl-continued-statement-offset: 4
# cperl-continued-brace-offset: -4
# cperl-brace-offset: 0
# cperl-label-offset: -2
# End:
