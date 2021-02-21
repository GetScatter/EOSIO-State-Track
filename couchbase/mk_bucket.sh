. ./chkvars.sh

couchbase-cli bucket-create --username $COUCH_USER --password $COUCH_PW  --cluster couchbase://localhost --bucket $COUCH_BUCKET --bucket-eviction-policy fullEviction --bucket-type couchbase --bucket-ramsize 10000

