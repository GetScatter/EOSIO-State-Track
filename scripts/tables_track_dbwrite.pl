use strict;
use warnings;
use JSON;
use Getopt::Long;
use Digest::SHA qw(sha256_hex);

use Couchbase::Bucket;
use Couchbase::Document;

use Net::WebSocket::Server;
use Protocol::WebSocket::Frame;

$Protocol::WebSocket::Frame::MAX_PAYLOAD_SIZE = 100*1024*1024;
$Protocol::WebSocket::Frame::MAX_FRAGMENTS_AMOUNT = 102400;

$| = 1;

my $port = 8100;
my $ack_every = 120;

my $network;
my $dbhost = '10.0.3.41';
my $bucket = 'eosio_tables';


my $ok = GetOptions
    ('network=s' => \$network,
     'port=i'    => \$port,
     'ack=i'     => \$ack_every,     
     'dbhost=s'  => \$dbhost,
     'bucket=s'  => \$bucket);


if( not $ok or scalar(@ARGV) > 0 or not $network )
{
    print STDERR "Usage: $0 --network=eos [options...]\n",
    "The utility opens a WS port for Chronicle to send data to.\n",
    "Options:\n",
    "  --port=N           \[$port\] TCP port to listen to websocket connection\n",
    "  --ack=N            \[$ack_every\] Send acknowledgements every N blocks\n",
    "  --network=NAME     name of EOS network\n",
    "  --dbhost=HOST      \[$dbhost]\n",
    "  --bucket=NAME      \[$bucket]\n";
    exit 1;
}

my $cb = Couchbase::Bucket->new('couchbase://' . $dbhost . '/' . $bucket,
                                {'username' => 'Administrator', 'password' => 'password'});

my $json = JSON->new->canonical;

my $confirmed_block = 0;
my $unconfirmed_block = 0;
my $irreversible = 0;

my %contracts_include;
my %contracts_skip;
my $last_skip_flush = 0;
my $flush_skip_every = 7200;


{
    my $doc = Couchbase::Document->new('sync:' . $network);
    $cb->get($doc);
    if( $doc->is_ok() )
    {
        $confirmed_block = $doc->value()->{'block_num'};
        $irreversible = $doc->value()->{'irreversible'};
        $last_skip_flush = $confirmed_block;
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
                         'AND network=\'' . $network . '\' AND TONUM(block_num)>=' . $block_num);
            
        $confirmed_block = $block_num;
        $unconfirmed_block = $block_num;
        return $block_num;
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
            
            if( $table eq 'tokenconfigs' and defined($kvo->{'value'}{'standard'}) )
            {
                %contracts_skip = ();
                my $type = 'token:' . $kvo->{'value'}{'standard'};
                $contracts_include{$contract} = $type;

                my $doc = Couchbase::Document->new(
                    'contract:' . $contract, {
                        'type' => 'contract',
                        'account_name' => $contract,
                        'contract_type' => $type,
                        'block_timestamp' => $block_time,
                        'block_num' => $block_num,
                    });
                $cb->upsert($doc);
                if (!$doc->is_ok)
                {
                    die("Could not store document: " . $doc->errstr);
                }
            }

            my $ofinterest;
            if( defined($contracts_include{$contract}) )
            {
                $ofinterest = 1;
            }
            elsif( not $contracts_skip{$contract} )
            {
                my $doc = Couchbase::Document->new('contract:' . $contract);
                $cb->get($doc);
                if( $doc->is_ok() )
                {
                    $contracts_include{$contract} = $doc->value->{'contract_type'};
                    $ofinterest = 1;
                }
            }

            if( $ofinterest )
            {
                my $rowid = sha256_hex(
                    join(':', $network, $contract, $table, $kvo->{'scope'}, $kvo->{'primary_key'}));
                
                my $id = join(':', 'table_upd', $block_num, $rowid, $data->{'added'});
                my $doc = Couchbase::Document->new(
                    $id,
                    {
                        'type' => 'table_upd',
                        'contract_type' => $contracts_include{$contract},
                        'rowid' => $rowid,
                        'network' => $network,
                        'code' => $contract,
                        'tblname' => $table,
                        'added' => $data->{'added'},
                        'scope' => $kvo->{'scope'},
                        'value' => $kvo->{'value'},
                        'block_timestamp' => $block_time,
                        'block_num' => $block_num,
                        'block_num_x' => $block_num * 10 + ($data->{'added'} eq 'true' ? 1:0),
                    });
                $cb->insert($doc);
                if( not $doc->is_ok)
                {
                    die("Could not store document: " . $doc->errstr);
                }                
            }
            else
            {
                $contracts_skip{$contract} = 1;
            }
        }
    }
    elsif( $msgtype == 1003 ) # CHRONICLE_MSGTYPE_TX_TRACE
    {
        my $trace = $data->{'trace'};
        if( $trace->{'status'} eq 'executed' )
        {
            my $block_num = $data->{'block_num'};
            my $block_time = $data->{'block_timestamp'};
        }
    }
    elsif( $msgtype == 1009 ) # CHRONICLE_MSGTYPE_RCVR_PAUSE
    {
        if( $unconfirmed_block > $confirmed_block )
        {
            $confirmed_block = $unconfirmed_block;
            return $confirmed_block;
        }
    }
    elsif( $msgtype == 1010 ) # CHRONICLE_MSGTYPE_BLOCK_COMPLETED
    {
        my $block_num = $data->{'block_num'};
        my $block_time = $data->{'block_timestamp'};
        my $last_irreversible = $data->{'last_irreversible'};

        if( $block_num > $unconfirmed_block+1 )
        {
            printf STDERR ("WARNING: missing blocks %d to %d\n", $unconfirmed_block+1, $block_num-1);
        }                           

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
        }

        if( $block_num <= $last_irreversible or $last_irreversible > $irreversible )
        {
            ## process updates
            my $rv = $cb->query_iterator
                ('SELECT META().id,* FROM ' . $bucket . ' WHERE type=\'table_upd\' ' .
                 'AND network=\'' . $network . '\' AND TONUM(block_num)<=' . $last_irreversible .
                 ' ORDER BY TONUM(block_num_x)');

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
            
            $irreversible = $last_irreversible;
        }                   

        if( $block_num >= $last_skip_flush + $flush_skip_every )
        {
            %contracts_skip = ();
            $last_skip_flush = $block_num;
        }

        $unconfirmed_block = $block_num;
        if( $unconfirmed_block - $confirmed_block >= $ack_every )
        {
            $confirmed_block = $unconfirmed_block;
            return $confirmed_block;
        }
    }
    return 0;
}


