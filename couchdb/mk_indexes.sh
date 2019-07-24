. ./chkvars.sh

alias q="cbc-n1ql -u $COUCH_USER -P $COUCH_PW -U couchbase://localhost/$COUCH_BUCKET"

q "CREATE PRIMARY INDEX ON $COUCH_BUCKET"

q "CREATE INDEX tbl_upd_01 ON $COUCH_BUCKET(network,TONUM(block_num)) WHERE type = 'table_upd'"

q "CREATE INDEX tbl_upd_02 ON $COUCH_BUCKET(network,code,tblname,scope) WHERE type = 'table_upd'"


q "CREATE INDEX contract_01 ON $COUCH_BUCKET(network,contract_type,account_name) WHERE type = 'contract'"

q "CREATE INDEX tbl_row_01 ON $COUCH_BUCKET(network,contract_type,code) WHERE type = 'table_row'"

q "CREATE INDEX tbl_row_02 ON $COUCH_BUCKET(network,code,tblname,scope) WHERE type = 'table_row'"

q "CREATE INDEX tbl_row_03 ON $COUCH_BUCKET(network,contract_type,tblname,scope) WHERE type = 'table_row'"

q "CREATE INDEX tbl_row_04 ON $COUCH_BUCKET(network,scope) WHERE type = 'table_row'"

q "CREATE INDEX tbl_row_05 ON $COUCH_BUCKET(network,code,scope,primary_key) WHERE type = 'table_row'"

q "CREATE INDEX tx_01 ON $COUCH_BUCKET(network, DISTINCT ARRAY acc FOR acc IN tx_accounts END, TONUM(block_num)) WHERE type = 'transaction'"

q "CREATE INDEX tx_upd_01 ON $COUCH_BUCKET(network,TONUM(block_num)) WHERE type = 'transaction_upd'"
