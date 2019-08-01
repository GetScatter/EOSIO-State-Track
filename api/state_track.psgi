use strict;
use warnings;
use JSON;
use Plack::Builder;
use Plack::Request;
use Plack::App::EventSource;
use Couchbase::Bucket;
#use Data::Dumper;

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


sub get_writer
{
    my $responder = shift;
    return $responder->
        (
         [
          200,
          [
           'Content-Type' => 'text/event-stream; charset=UTF-8',
           'Cache-Control' => 'no-store, no-cache, must-revalidate, max-age=0',
          ]
         ]
        );
}


sub send_event
{
    my $writer = shift;
    my $event = shift;

    my @lines;
    while( scalar(@{$event}) > 0 )
    {
        push(@lines, shift(@{$event}) . ': ' . shift(@{$event}));
    }
    
    $writer->write(join("\x0d\x0a", @lines) . "\x0d\x0a\x0d\x0a");
}

sub iterate_and_push
{
    my $cb = shift;
    my @queries = @_;

    return sub {
        my $responder = shift;
        my $writer = get_writer($responder);
        my $count = 0;
        
        foreach my $q (@queries)
        {
            my $eventtype = shift(@{$q});
            my $rv = $cb->query_iterator(@{$q});

            while( (my $row = $rv->next()) )
            {
                my $event = ['event', $eventtype];
                if( defined($row->{'id'}) )
                {
                    push(@{$event}, 'id', $row->{'id'});
                }
                
                push(@{$event}, 'data', $json->encode({%{$row}}));
                send_event($writer, $event);
                $count++;
            }
        }
        
        send_event($writer, ['event', 'end', 'data', $json->encode({'count' => $count})]);
        $writer->close();
    };
}
         

sub push_one_or_nothing
{
    my $val = shift;
    
    return sub {
        my $responder = shift;
        my $writer = get_writer($responder);
        my $count = 0;
        if( defined($val) )
        {
            send_event($writer, ['event', 'row', 'data', $json->encode({%{$val}})]);
            $count++;
        }
        send_event($writer, ['event', 'end', 'data', $json->encode({'count' => $count})]);
        $writer->close();
    }
}


sub error
{
    my $req = shift;
    my $msg = shift;
    my $res = $req->new_response(400);
    $res->content_type('text/plain');
    $res->body($msg . "\x0d\x0a");
    return $res->finalize;
}

    

my $cb = Couchbase::Bucket->new('couchbase://' . $CFG::dbhost . '/' . $CFG::bucket,
                                {'username' => $CFG::dbuser, 'password' => $CFG::dbpw});




my $builder = Plack::Builder->new;

$builder->mount
    ($CFG::apiprefix . 'networks' => sub {
         my $env = shift;
         my $req = Plack::Request->new($env);
         
         return iterate_and_push
             ($cb,
              ['row', 'SELECT META().id,block_num,block_time,irreversible,network ' .
               'FROM ' . $CFG::bucket . ' WHERE type=\'sync\'']);
     });


$builder->mount
    ($CFG::apiprefix . 'contracts' => sub {
         my $env = shift;
         my $req = Plack::Request->new($env);
         my $p = $req->parameters();
         my $network = $p->{'network'};
         return(error($req, "'network' is not specified")) unless defined($network);
         return(error($req, "invalid network")) unless ($network =~ /^\w+$/);

         my $ctype_filter = '';
         my $ctype = $p->{'contract_type'};
         if( defined($ctype) )
         {
             return(error($req, "invalid contract_type")) unless ($ctype =~ /^[a-z0-9:_]+$/);
             $ctype_filter = ' AND contract_type=\'' . $ctype . '\' ';
         }
         
         return iterate_and_push
             ($cb,
              ['row',
               'SELECT META().id, account_name, contract_type, track_tables, ' .
               'track_tx, block_timestamp, block_num ' .
               'FROM ' . $CFG::bucket . ' WHERE type=\'contract\' AND network=\'' . $network . '\'' .
               $ctype_filter]);
     });


$builder->mount
    ($CFG::apiprefix . 'contract_tables' => sub {
         my $env = shift;
         my $req = Plack::Request->new($env);
         my $p = $req->parameters();
         my $network = $p->{'network'};
         return(error($req, "'network' is not specified")) unless defined($network);
         return(error($req, "invalid network")) unless ($network =~ /^\w+$/);

         my $code = $p->{'code'};
         return(error($req, "'code' is not specified")) unless defined($code);
         return(error($req, "invalid code")) unless ($code =~ /^[1-5a-z.]{1,13}$/);
         
         return iterate_and_push
             ($cb,
              ['row',
               'SELECT distinct tblname ' .
               'FROM ' . $CFG::bucket . ' WHERE (type=\'table_row\' OR type=\'table_upd\') ' .
               ' AND network=\'' . $network . '\' AND code=\'' . $code . '\'']);
     });


$builder->mount
    ($CFG::apiprefix . 'table_scopes' => sub {
         my $env = shift;
         my $req = Plack::Request->new($env);
         my $p = $req->parameters();
         my $network = $p->{'network'};
         return(error($req, "'network' is not specified")) unless defined($network);
         return(error($req, "invalid network")) unless ($network =~ /^\w+$/);

         my $code = $p->{'code'};
         return(error($req, "'code' is not specified")) unless defined($code);
         return(error($req, "invalid code")) unless ($code =~ /^[1-5a-z.]{1,13}$/);

         my $table = $p->{'table'};
         return(error($req, "'table' is not specified")) unless defined($table);
         return(error($req, "invalid table")) unless ($table =~ /^[1-5a-z.]{1,13}$/);
         
         return iterate_and_push
             ($cb,
              ['row',
               'SELECT distinct scope ' .
               'FROM ' . $CFG::bucket . ' WHERE (type=\'table_row\' OR type=\'table_upd\') ' .
               ' AND network=\'' . $network . '\' AND code=\'' . $code . '\' ' .
               ' AND tblname=\'' . $table . '\'']);
     });


$builder->mount
    ($CFG::apiprefix . 'table_rows' => sub {
         my $env = shift;
         my $req = Plack::Request->new($env);
         my $p = $req->parameters();
         my $network = $p->{'network'};
         return(error($req, "'network' is not specified")) unless defined($network);
         return(error($req, "invalid network")) unless ($network =~ /^\w+$/);

         my $code = $p->{'code'};
         return(error($req, "'code' is not specified")) unless defined($code);
         return(error($req, "invalid code")) unless ($code =~ /^[1-5a-z.]{1,13}$/);

         my $table = $p->{'table'};
         return(error($req, "'table' is not specified")) unless defined($table);
         return(error($req, "invalid table")) unless ($table =~ /^[1-5a-z.]{1,13}$/);

         my $scope = $p->{'scope'};
         return(error($req, "'scope' is not specified")) unless defined($scope);
         return(error($req, "invalid scope")) unless ($scope =~ /^[1-5a-z.]{1,13}$/);
         
         return iterate_and_push
             ($cb,
              ['row',
               'SELECT META().id,block_num,primary_key,rowval ' .
               'FROM ' . $CFG::bucket . ' WHERE type=\'table_row\' ' .
               ' AND network=\'' . $network . '\' AND code=\'' . $code . '\' ' .
               ' AND tblname=\'' . $table . '\' AND scope=\'' . $scope . '\''],
              ['rowupd',
               'SELECT META().id,block_num,primary_key,added,rowval ' .
               'FROM ' . $CFG::bucket . ' WHERE type=\'table_upd\' ' .
               ' AND network=\'' . $network . '\' AND code=\'' . $code . '\' ' .
               ' AND tblname=\'' . $table . '\' AND scope=\'' . $scope . '\' ' .
               'ORDER BY TONUM(block_num_x)']);
     });


$builder->mount
    ($CFG::apiprefix . 'table_row_by_pk' => sub {
         my $env = shift;
         my $req = Plack::Request->new($env);
         my $p = $req->parameters();
         my $network = $p->{'network'};
         return(error($req, "'network' is not specified")) unless defined($network);
         return(error($req, "invalid network")) unless ($network =~ /^\w+$/);

         my $code = $p->{'code'};
         return(error($req, "'code' is not specified")) unless defined($code);
         return(error($req, "invalid code")) unless ($code =~ /^[1-5a-z.]{1,13}$/);

         my $table = $p->{'table'};
         return(error($req, "'table' is not specified")) unless defined($table);
         return(error($req, "invalid table")) unless ($table =~ /^[1-5a-z.]{1,13}$/);

         my $scope = $p->{'scope'};
         return(error($req, "'scope' is not specified")) unless defined($scope);
         return(error($req, "invalid scope")) unless ($scope =~ /^[1-5a-z.]{1,13}$/);

         my $pk = $p->{'pk'};
         return(error($req, "'pk' is not specified")) unless defined($pk);
         return(error($req, "invalid pk")) unless ($pk =~ /^\d+$/);

         my $ret = undef;
         my $rv = $cb->query_slurp
             ('SELECT block_num,primary_key,rowval ' .
              'FROM ' . $CFG::bucket . ' WHERE type=\'table_row\' ' .
              ' AND network=\'' . $network . '\' AND code=\'' . $code . '\' ' .
              ' AND tblname=\'' . $table . '\' AND scope=\'' . $scope . '\' ' .
              ' AND primary_key=\'' . $pk . '\'');

         # there's only one or zero rows
         foreach my $row (@{$rv->rows})
         {
             $ret = $row;
         }

         # process updates
         $rv = $cb->query_slurp
             ('SELECT added,block_num,primary_key,rowval ' .
              'FROM ' . $CFG::bucket . ' WHERE type=\'table_upd\' ' .
              ' AND network=\'' . $network . '\' AND code=\'' . $code . '\' ' .
              ' AND tblname=\'' . $table . '\' AND scope=\'' . $scope . '\' ' .
              ' AND primary_key=\'' . $pk . '\' ORDER BY TONUM(block_num_x)');

         foreach my $row (@{$rv->rows})
         {
             if( $row->{'added'} eq 'true' )
             {
                 delete $row->{'added'};
                 $ret = $row;
             }
             else
             {
                 $ret = undef;
             }
         }
         
         return push_one_or_nothing($ret);
     });




$builder->mount
    ($CFG::apiprefix . 'table_rows_by_scope' => sub {
         my $env = shift;
         my $req = Plack::Request->new($env);
         my $p = $req->parameters();
         my $network = $p->{'network'};
         return(error($req, "'network' is not specified")) unless defined($network);
         return(error($req, "invalid network")) unless ($network =~ /^\w+$/);

         my $ctype = $p->{'contract_type'};
         return(error($req, "'contract_type' is not specified")) unless defined($ctype);
         return(error($req, "invalid contract_type")) unless ($ctype =~ /^[a-z0-9:_]+$/);

         my $table = $p->{'table'};
         return(error($req, "'table' is not specified")) unless defined($table);
         return(error($req, "invalid table")) unless ($table =~ /^[1-5a-z.]{1,13}$/);

         my $scope = $p->{'scope'};
         return(error($req, "'scope' is not specified")) unless defined($scope);
         return(error($req, "invalid scope")) unless ($scope =~ /^[1-5a-z.]{1,13}$/);
         
         return iterate_and_push
             ($cb,
              ['row',
               'SELECT META().id,block_num,code,primary_key,rowval ' .
               'FROM ' . $CFG::bucket . ' WHERE type=\'table_row\' ' .
               ' AND network=\'' . $network . '\' AND contract_type=\'' . $ctype . '\' ' .
               ' AND tblname=\'' . $table . '\' AND scope=\'' . $scope . '\''],
              ['rowupd',
               'SELECT META().id,block_num,added,code,primary_key,rowval ' .
               'FROM ' . $CFG::bucket . ' WHERE type=\'table_upd\' ' .
               ' AND network=\'' . $network . '\' AND contract_type=\'' . $ctype . '\' ' .
               ' AND tblname=\'' . $table . '\' AND scope=\'' . $scope . '\'' .
               'ORDER BY TONUM(block_num_x)']);
     });



$builder->mount
    ($CFG::apiprefix . 'account_history' => sub {
         my $env = shift;
         my $req = Plack::Request->new($env);
         my $p = $req->parameters();
         my $network = $p->{'network'};
         return(error($req, "'network' is not specified")) unless defined($network);
         return(error($req, "invalid network")) unless ($network =~ /^\w+$/);

         my $account = $p->{'account'};
         return(error($req, "'account' is not specified")) unless defined($account);
         return(error($req, "invalid account")) unless ($account =~ /^[1-5a-z.]{1,13}$/);

         my $maxrows = $p->{'maxrows'};
         $maxrows = 100 unless defined($maxrows);

         my $filter = '';
         my $block_order = '';
         my $start_block = $p->{'start_block'};
         if( defined($start_block) )
         {
             return(error($req, "invalid start_block")) unless ($start_block =~ /^\d+$/);
             $filter .= ' AND TONUM(block_num) >= ' . $start_block;
         }

         my $end_block = $p->{'end_block'};
         if( defined($end_block) )
         {
             return(error($req, "invalid end_block")) unless ($end_block =~ /^\d+$/);
             $filter .= ' AND TONUM(block_num) <= ' . $end_block;
         }

         if( $filter ne '' )
         {
             $block_order = 'TONUM(block_num) DESC,';
         }

         return iterate_and_push
             ($cb,
              ['tx',
               'SELECT META().id,block_num,block_timestamp,trace, \'false\' as irreversible ' .
               'FROM ' . $CFG::bucket . ' WHERE type=\'transaction_upd\' ' .
               ' AND ANY acc IN tx_accounts SATISFIES acc=\'' . $account . '\' END ' .
               $filter .
               ' ORDER BY ' . $block_order . 'TONUM(trace.action_traces[0].receipt.global_sequence) DESC ' .
               ' LIMIT ' . $maxrows],
              ['tx',
               'SELECT META().id,block_num,block_timestamp,trace, \'true\' as irreversible ' .
               'FROM ' . $CFG::bucket . ' WHERE type=\'transaction\' ' .
               ' AND ANY acc IN tx_accounts SATISFIES acc=\'' . $account . '\' END ' .
               $filter .
               ' ORDER BY ' . $block_order . 'TONUM(trace.action_traces[0].receipt.global_sequence) DESC ' .
               ' LIMIT ' . $maxrows]);
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
