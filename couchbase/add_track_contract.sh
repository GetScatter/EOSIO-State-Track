. ./chkvars.sh

if [ $# -ne 5 ]; then
    echo "Usage: $0 NEWORK ACCOUNT TYPE TRACKTABLES TRACKTX" 1>&2;
    exit 1;
fi

NETWORK=$1
ACC=$2
TYPE=$3
TRACKTABLES=$4
TRACKTX=$5


cbc create contract:${NETWORK}:${ACC} -V \
'{"type":"contract", "network":"'${NETWORK}'", "account_name":"'${ACC}'", "contract_type":"'${TYPE}'", "track_tables":"'${TRACKTABLES}'", "track_tx":"'${TRACKTX}'"}' \
-M upsert -u $COUCH_USER -P $COUCH_PW -U couchbase://localhost/$COUCH_BUCKET
