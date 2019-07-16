. ./chkvars.sh

if [ $# -ne 2 ]; then
    echo "Usage: $0 NEWORK ACCOUNT" 1>&2;
    exit 1;
fi

NETWORK=$1
ACC=$2


cbc create contract:${NETWORK}:${ACC} -V \
'{"type":"contract", "network":"'${NETWORK}'", "account_name":"'${ACC}'", "contract_type":"marketplace", "track_tables":"true", "track_tx":"true"}' \
-M upsert -u $COUCH_USER -P $COUCH_PW -U couchbase://localhost/$COUCH_BUCKET
