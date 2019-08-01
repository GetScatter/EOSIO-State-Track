# EOSIO State Track API

The API is storing table rows and transaction traces for a number of
smart contracts and provides a way for searching and retrieving the
data.


The API accepts HTTP GET and POST requests, so it's up to you to choose
the right one. Many SSE libraies are not allowing to send anything but
GET requests.

The API output is a stream of [Server-Sent
Events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events)
(SSE). It allows transporting large chunks of data without much
overhead, and there's support in browsers and javascript libraries.

The output is a number of events, such as `row`, `rowupd`, `tx`,
followed by `end` event.

Presence of `end` event indicates that the whole output has been
delivered. The event also contains the total count of events preceding
it.

Each event data field is a JSON object.

`block_num` and `block_timestamp` attributes in most of the output are
informational and indicate the latest block that updated a specific data
element (in case of `contracts` request, they indicate the moment when
the contract was added to the database).



## Networks and contracts

* `https://HOST/strack/networks` lists the EOSIO blockchains known to
  the API, their actual head block status and irreversible block number.


* `https://HOST/strack/contracts?network=NETWORK` lists smart contract
  accounts that are being tracked by the API. The following attributes
  are of importance:

  * `account_name` specifies the EOSIO account name;
  
  * `contract_type` specifies the type of contract. It is used in other
    queries.

  * `track_tables`: if present and set to `true`, contract table
    contents are tracked and returned by the API.

  * `track_tx`: if present and set to `true`, transaction history of
    this account is stored and retyurned by the API.


## Contract tables


* `https://HOST/strack/contract_tables?network=NETWORK&code=ACCOUNT`
  lists names of tables in the smart contract, in `tblname` attribute.


* `https://HOST/strack/table_scopes?network=NETWORK&code=ACCOUNT&table=TABLE`
  lists the scopes of a table in `scope` attribute.


* `https://HOST//strack/table_rows?network=NETWORK&code=ACCOUNT&table=TABLE&scope=SCOPE`
  lists table rows. First come rows that are updated by irreversible
  transactions, in `row` events in undefined order. Then `rowupd` events
  follow in chronological order. They have an additional attribute
  `added` which is set to `true` if the row is added or modified, and
  `false` of a row is deleted. Attributes in every event are as follows:

  * `primary_key` is the table primary index value in numeric notation;

  * `rowval` is the value of a row as a JSON object.


* `https://HOST//strack/table_row_by_pk?network=NETWORK&code=ACCOUNT&table=TABLE&scope=SCOPE&pk=N'
  returns a single or none `row` event comprising of one table row value.


* `https://HOST//strack/table_rows_by_scope?network=NETWORK&table=TABLE&scope=SCOPE&contract_type=CTYPE`
  allows searching for a specific scope in tables across multiple smart
  contracts. This is useful if you need to find all NFT tokens belonging
  to an account. The result is in the same format as for `table_rows`
  request.


## Account history

`https://HOST//strack/account_history?network=NETWORK&account=ACCOUNT`
returns transaction traces relevant for the account in reverse
order. Without additional parameters, it returns 100 latest
transactions.

Additional HTTP request parameters:

* `maxrows` indicates the maximum entries to return. The output length
  may potentially be double of this number if there are so many
  speculative transactions.

* `start_block` indicates the lowest block number in the output.

* `end_block` indicates the highest block in the output.


The result is a number of `tx` events with the following attributes:

* `id` is a concatenation of the word 'tx', network name, and
  transaction ID, separated by colons.

* `block_num` and `block_timestamp` indicate the block of transaction.

* `irreversible`: `true` or `false` indicates whether the transaction is
  found in an irreversible or speculative block.

* `trace` contains a full transaction trace object as returned by
  Chronicle.



# Data collection

There are two ways how accounts are marked for tracking: by manual
insertion in the database, and by having an entry in
[`tokenconfigs`](https://github.com/eosio-standards-wg/tokenconfigs)
table.




# Souce code, license and copyright

Source code repository: https://github.com/cc32d9/eosio_state_track

Copyright 2019 cc32d9@gmail.com

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.


