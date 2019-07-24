use strict;
use warnings;
use JSON;
use Getopt::Long;
use Digest::SHA qw(sha256_hex);
use Time::HiRes qw (time sleep);

use Couchbase::Bucket;
use Couchbase::Document;

use Net::WebSocket::Server;
use Protocol::WebSocket::Frame;

$Protocol::WebSocket::Frame::MAX_PAYLOAD_SIZE = 100*1024*1024;
$Protocol::WebSocket::Frame::MAX_FRAGMENTS_AMOUNT = 102400;

$| = 1;


my $network;
my $track_tokenconfigs = 1;

my $port = 8100;
my $ack_every = 120;

my $dbhost = '127.0.0.1';
my $bucket = 'state_track';
my $dbuser = 'Administrator';
my $dbpw = 'password';


my $ok = GetOptions
    (
     'network=s' => \$network,
     'tkcfg'     => \$track_tokenconfigs, 
     'port=i'    => \$port,
     'ack=i'     => \$ack_every,     
     'dbhost=s'  => \$dbhost,
     'bucket=s'  => \$bucket,
     'dbuser=s'  => \$dbuser,
     'dbpw=s'    => \$dbpw,
     );


if( not $ok or scalar(@ARGV) > 0 or not $network )
{
    print STDERR "Usage: $0 --network=eos [options...]\n",
        "The utility opens a WS port for Chronicle to send data to.\n",
        "Options:\n",
        "  --port=N           \[$port\] TCP port to listen to websocket connection\n",
        "  --ack=N            \[$ack_every\] Send acknowledgements every N blocks\n",
        "  --network=NAME     name of EOS network\n",
        "  --notkcfg          skip looking up tokenconfigs table\n",
        "  --dbhost=HOST      \[$dbhost] Couchbase host\n",
        "  --bucket=NAME      \[$bucket] Couchbase bucket\n",
        "  --dbuser=USER      \[$dbuser\] Couchbase user\n",
        "  --dbpw=PW          \[$dbpw\] Couchbase password\n";
    exit 1;
}
     
my $cb = Couchbase::Bucket->new('couchbase://' . $dbhost . '/' . $bucket,
                                {'username' => $dbuser, 'password' => $dbpw});

my $json = JSON->new->canonical;

my $confirmed_block = 0;
my $unconfirmed_block = 0;
my $irreversible = 0;

my %acc_store_deltas;
my %acc_store_traces;
my %acc_contract_type;

# set them to nonzero to process all leftovers on first run
my $has_upd_tables = 1;
my $has_upd_tx = 1;
    
my $contracts_last_fetched = 0;
refresh_contracts();

{
    my $doc = Couchbase::Document->new('sync:' . $network);
    $cb->get($doc);
    if( $doc->is_ok() )
    {
        $confirmed_block = $doc->value()->{'block_num'};
        $unconfirmed_block = $confirmed_block; 
        $irreversible = $doc->value()->{'irreversible'};
        print STDERR "Last confirmed block: $confirmed_block, Irreversible: $irreversible\n";
    }
}


Net::WebSocket::Server->new(
    listen => $port,
    on_connect => sub {
        my ($serv, $conn) = @_;
        $conn->on(
            'binary' => sub {
                my ($conn, $msg) = @_;
                my ($msgtype, $opts, $js) = unpack('VVa*', $msg);
                my $data = eval {$json->decode($js)};
                if( $@ )
                {
                    print STDERR $@, "\n\n";
                    print STDERR $js, "\n";
                    exit;
                } 
                
                my $ack = process_data($msgtype, $data, \$js);
                if( $ack > 0 )
                {
                    $conn->send_binary(sprintf("%d", $ack));
                    print STDERR "ack $ack\n";
                }
            },
            'disconnect' => sub {
                print STDERR "Disconnected\n";
            },
            
            );
    },
    )->start;


sub process_data
{
    my $msgtype = shift;
    my $data = shift;
    my $jsptr = shift;

    if( $msgtype == 1001 ) # CHRONICLE_MSGTYPE_FORK
    {
        my $block_num = $data->{'block_num'};
        print STDERR "fork at $block_num\n";

        $cb->query_slurp('DELETE FROM ' . $bucket . ' WHERE type=\'table_upd\' ' .
                         'AND network=\'' . $network . '\' AND TONUM(block_num)>=' . $block_num,
                         {}, {'scan_consistency' => '"request_plus"'});
            
        $cb->query_slurp('DELETE FROM ' . $bucket . ' WHERE type=\'transaction_upd\' ' .
                         'AND network=\'' . $network . '\' AND TONUM(block_num)>=' . $block_num,
                         {}, {'scan_consistency' => '"request_plus"'});

        $confirmed_block = $block_num-1;
        $unconfirmed_block = $block_num-1;
        return $confirmed_block;
    }
    elsif( $msgtype == 1007 ) # CHRONICLE_MSGTYPE_TBL_ROW
    {
        my $kvo = $data->{'kvo'};
        if( ref($kvo->{'value'}) eq 'HASH' )
        {
            my $contract = $kvo->{'code'};
            my $table = $kvo->{'table'};
            my $block_num = $data->{'block_num'};
            my $block_time = $data->{'block_timestamp'};
            
            if( $track_tokenconfigs and
                $table eq 'tokenconfigs' and defined($kvo->{'value'}{'standard'}) )
            {
                my $type = 'token:' . $kvo->{'value'}{'standard'};
                $acc_store_deltas{$contract} = 1;
                $acc_contract_type{$contract} = $type;

                my $doc = Couchbase::Document->new(
                    'contract:' . $network . ':' . $contract,  {
                        'type' => 'contract',
                        'network' => $network,
                        'account_name' => $contract,
                        'contract_type' => $type,
                        'track_tables' => 'true',
                        'block_timestamp' => $block_time,
                        'block_num' => $block_num,
                    });
                $cb->upsert($doc);
                if (!$doc->is_ok)
                {
                    die("Could not store document: " . $doc->errstr);
                }
                print STDERR '.';
            }

            if( $acc_store_deltas{$contract} )
            {
                my $rowid = sha256_hex(
                    join(':', $network, $contract, $table, $kvo->{'scope'}, $kvo->{'primary_key'}));
                
                my $id = join(':', 'table_upd', $block_num, $rowid, $data->{'added'});
                my $type = $acc_contract_type{$contract};
                $type = 'unnclassified' unless defined($type);
                
                my $doc = Couchbase::Document->new(
                    $id,
                    {
                        'type' => 'table_upd',
                        'contract_type' => $type,
                        'rowid' => $rowid,
                        'network' => $network,
                        'code' => $contract,
                        'tblname' => $table,
                        'added' => $data->{'added'},
                        'scope' => $kvo->{'scope'},
                        'primary_key' => $kvo->{'primary_key'},    
                        'rowval' => $kvo->{'value'},
                        'block_timestamp' => $block_time,
                        'block_num' => $block_num,
                        'block_num_x' => $block_num * 10 + ($data->{'added'} eq 'true' ? 1:0),
                    });
                $cb->insert($doc);
                if( not $doc->is_ok)
                {
                    die("Could not store document: " . $doc->errstr);
                }                
                $has_upd_tables = $block_num;
                print STDERR '+';
            }
        }
    }
    elsif( $msgtype == 1003 ) # CHRONICLE_MSGTYPE_TX_TRACE
    {
        my $trace = $data->{'trace'};
        if( $trace->{'status'} eq 'executed' )
        {
            my %accounts;
            foreach my $atrace ( @{$trace->{'action_traces'}} )
            {
                my $act = $atrace->{'act'};                
                $accounts{$atrace->{'receipt'}{'receiver'}} = 1;
                $accounts{$act->{'account'}} = 1;
            }

            my %accounts_matched;
            foreach my $acc (keys %accounts)
            {
                if( $acc_store_traces{$acc} )
                {
                    $accounts_matched{$acc} = 1;
                }
            }

            if( scalar(keys %accounts_matched) > 0 )
            {
                $data->{'type'} = 'transaction_upd';
                $data->{'network'} = $network;
                $data->{'tx_accounts'} = [sort keys %accounts_matched];
                
                my $doc = Couchbase::Document->new(
                    'tx:' . $network . ':' . $trace->{'id'}, $data);
                $cb->insert($doc);
                if (!$doc->is_ok)
                {
                    die("Could not store document: " . $doc->errstr);
                }
                $has_upd_tx = $data->{'block_num'};
                print STDERR '*';
            }
        }
    }
    elsif( $msgtype == 1009 ) # CHRONICLE_MSGTYPE_RCVR_PAUSE
    {
        refresh_contracts();
        if( $unconfirmed_block > $confirmed_block )
        {
            $confirmed_block = $unconfirmed_block;
            return $confirmed_block;
        }
    }
    elsif( $msgtype == 1010 ) # CHRONICLE_MSGTYPE_BLOCK_COMPLETED
    {
        refresh_contracts();
        my $block_num = $data->{'block_num'};
        my $block_time = $data->{'block_timestamp'};
        my $last_irreversible = $data->{'last_irreversible'};

        if( $block_num > $unconfirmed_block+1 )
        {
            printf STDERR ("WARNING: missing blocks %d to %d\n", $unconfirmed_block+1, $block_num-1);
        }                           

        if( $block_num <= $last_irreversible or $last_irreversible > $irreversible )
        {
            if( $has_upd_tables > 0 )
            {                
                ## process updates
                my $rv = $cb->query_iterator
                    ('SELECT META().id,* FROM ' . $bucket . ' WHERE type=\'table_upd\' ' .
                     'AND network=\'' . $network . '\' AND TONUM(block_num)<=' . $last_irreversible .
                     ' ORDER BY TONUM(block_num_x)',
                    {}, {'scan_consistency' => '"request_plus"'});
                
                while((my $row = $rv->next))
                {                
                    my $obj = $row->{$bucket};
                    my $tbl_id = join(':', 'table_row', $obj->{'rowid'});
                    
                    if( $obj->{'added'} eq 'true' )
                    {
                        delete $obj->{'added'};
                        delete $obj->{'rowid'};
                        delete $obj->{'block_num_x'};
                        $obj->{'type'} = 'table_row';
                        
                        my $doc = Couchbase::Document->new($tbl_id, $obj);
                        $cb->upsert($doc);
                        if( not $doc->is_ok)
                        {
                            die("Could not store document: " . $doc->errstr);
                        }
                    }
                    else
                    {
                        my $doc = Couchbase::Document->new($tbl_id);
                        $cb->remove($doc);
                        if( not $doc->is_ok and not $doc->is_not_found )
                        {
                            die("Could not remove document: " . $doc->errstr);
                        }
                    }
                    
                    {
                        my $doc = Couchbase::Document->new($row->{'id'});
                        $cb->remove($doc);
                        if( not $doc->is_ok )
                        {
                            die("Could not remove document: " . $doc->errstr);
                        }
                    }
                }

                if( $has_upd_tables <= $last_irreversible )
                {
                    $has_upd_tables = 0;
                }
            }

            if( $has_upd_tx > 0 )
            {
                $cb->query_slurp('UPDATE ' . $bucket . ' SET type=\'transaction\' WHERE type=\'transaction_upd\' ' .
                                 'AND network=\'' . $network . '\' AND TONUM(block_num)<=' . $last_irreversible,
                                 {}, {'scan_consistency' => '"request_plus"'});

                if( $has_upd_tx <= $last_irreversible )
                {
                    $has_upd_tx= 0;
                }
            }

            $irreversible = $last_irreversible;
        }                   

        $unconfirmed_block = $block_num;
        if( $unconfirmed_block - $confirmed_block >= $ack_every )
        {
            my $doc = Couchbase::Document->new(
                'sync:' . $network, {
                    'type' => 'sync',
                    'network' => $network,
                    'block_num' => $block_num,
                    'block_time' => $block_time,
                    'irreversible' => $last_irreversible
                });
            $cb->upsert($doc);
            if( not $doc->is_ok)
            {
                die("Could not store document: " . $doc->errstr);
            }

            $confirmed_block = $unconfirmed_block;
            return $confirmed_block;
        }
    }
    return 0;
}



sub refresh_contracts
{
    if( time() - $contracts_last_fetched < 10 )
    {
        return;
    }
        
    %acc_store_deltas = ();
    %acc_store_traces = ();
    %acc_contract_type = ();

    my $rv = $cb->query_iterator('SELECT * FROM ' . $bucket . ' WHERE type=\'contract\' ' .
                                 'AND network=\'' . $network  . '\'');

    while((my $row = $rv->next))
    {
        my $acc = $row->{$bucket}{'account_name'};
        next unless defined $acc;
        
        if( defined($row->{$bucket}{'track_tables'}) and $row->{$bucket}{'track_tables'} eq 'true' )
        {
            $acc_store_deltas{$acc} = 1;
        }
        if( defined($row->{$bucket}{'track_tx'}) and $row->{$bucket}{'track_tx'} eq 'true' )
        {
            $acc_store_traces{$acc} = 1;
        }
        if( defined($row->{$bucket}{'contract_type'}) )
        {
            $acc_contract_type{$acc} = $row->{$bucket}{'contract_type'};
        }
    }
    $contracts_last_fetched = time();
}
