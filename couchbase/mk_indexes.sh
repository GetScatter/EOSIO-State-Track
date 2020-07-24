. ./chkvars.sh

alias q="cbc-n1ql -u $COUCH_USER -P $COUCH_PW -U couchbase://localhost/$COUCH_BUCKET"

q "CREATE INDEX sync_01 ON $COUCH_BUCKET(head_reached) WHERE type = 'sync'"

q "CREATE INDEX contract_01 ON $COUCH_BUCKET(network,contract_type,account_name) WHERE type = 'contract'"



q "CREATE INDEX tbl_upd_01 ON $COUCH_BUCKET(network,TONUM(block_num)) WHERE type = 'table_upd'"

q "CREATE INDEX tbl_upd_02 ON $COUCH_BUCKET(network,code,tblname,scope,primary_key,added) WHERE type = 'table_upd'"

q "CREATE INDEX tbl_upd_03 ON $COUCH_BUCKET(network,contract_type,tblname,scope,added) WHERE type = 'table_upd'"

q "CREATE INDEX tbl_upd_04 ON $COUCH_BUCKET(network,rowval.owner,added) WHERE type = 'table_upd' AND contract_type='token:dgoods' AND tblname='dgood' AND scope=code"

q "CREATE INDEX tbl_upd_05 ON $COUCH_BUCKET(network,code,scope,rowval.schema_name) WHERE type = 'table_upd' AND contract_type='token:atomicassets' AND tblname='schemas' USING GSI WITH {'defer_build':true}"

q "CREATE INDEX tbl_upd_06 ON $COUCH_BUCKET(network,code,scope,rowval.template_id) WHERE type = 'table_upd' AND contract_type='token:atomicassets' AND tblname='templates' USING GSI WITH {'defer_build':true}"



q "CREATE INDEX tbl_row_02 ON $COUCH_BUCKET(network,code,tblname,scope,primary_key) WHERE type = 'table_row'"

q "CREATE INDEX tbl_row_03 ON $COUCH_BUCKET(network,contract_type,tblname,scope) WHERE type = 'table_row'"

q "CREATE INDEX tbl_row_04 ON $COUCH_BUCKET(network,rowval.owner) WHERE type = 'table_row' AND contract_type='token:dgoods' AND tblname='dgood' AND scope=code"

q "CREATE INDEX tbl_row_05 ON $COUCH_BUCKET(network,code,scope,rowval.schema_name) WHERE type = 'table_row' AND contract_type='token:atomicassets' AND tblname='schemas' USING GSI WITH {'defer_build':true}"

q "CREATE INDEX tbl_row_06 ON $COUCH_BUCKET(network,code,scope,rowval.template_id) WHERE type = 'table_row' AND contract_type='token:atomicassets' AND tblname='templates' USING GSI WITH {'defer_build':true}"


q "BUILD INDEX ON $COUCH_BUCKET ('tbl_upd_05', 'tbl_upd_06', 'tbl_row_05', 'tbl_row_06')"



q "CREATE INDEX tx_01 ON $COUCH_BUCKET(network, DISTINCT ARRAY acc FOR acc IN tx_accounts END, TONUM(trace.action_traces[0].receipt.global_sequence) DESC) WHERE type = 'transaction'"

q "CREATE INDEX tx_02 ON $COUCH_BUCKET(network, DISTINCT ARRAY acc FOR acc IN tx_accounts END, TONUM(block_num) DESC, TONUM(trace.action_traces[0].receipt.global_sequence) DESC) WHERE type = 'transaction'"


q "CREATE INDEX tx_upd_01 ON $COUCH_BUCKET(network,TONUM(block_num)) WHERE type = 'transaction_upd'"

q "CREATE INDEX tx_upd_02 ON $COUCH_BUCKET(network, DISTINCT ARRAY acc FOR acc IN tx_accounts END, TONUM(block_num),TONUM(trace.action_traces[0].receipt.global_sequence)) WHERE type = 'transaction_upd'"
