# EOSIO State Track API

The API is storing table rows and transaction traces for a number of
smart contracts and provides a way for searching and retrieving the
data.


The API accepts HTTP GET and POST requests, so it's up to you to
choose the right one. Many SSE libraries are not allowing to send
anything but GET requests.

The API output is a stream of [Server-Sent
Events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events)
(SSE). It allows transporting large chunks of data without much
overhead, and there's support in browsers and javascript libraries.

The output is a number of events, such as `row`, `rowupd`, `tx`,
followed by `end` event.

Presence of `end` event indicates that the whole output has been
delivered. The event also contains the total count of events preceding
it.

Data field in each event is a JSON object.

`block_num` and `block_timestamp` attributes in most of the output are
informational and indicate the latest block that updated a specific data
element (in case of `contracts` request, they indicate the moment when
the contract was added to the database).



## Networks

* `https://HOST/strack/networks` lists the EOSIO blockchains known to
  the API, their actual head block status and irreversible block number.


## NFT Assets

* `https://HOST/strack/tokens?network=NETWORK&account=ACCOUNT` lists
  all NFT assets belonging to the account. The `rowval` field in the
  data JSON represents a table row in corresponding smart contract.
  `contract_type` field indicates the type of a smart contract, such
  as "token:simpleassets" or "token:dgoods", and the client software
  has to interpret the row contents according to the type of a
  contract.



## Contracts

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


# Public API endpoints

A list of public API endpoints is served by IPFS. It shares the same
endpoints JSON as
[LightAPI](https://github.com/cc32d9/eosio_light_api), listing the
endpoints under "state-track-endpoints" section. The list is available
with the following links:

* https://endpoints.light.xeos.me/endpoints.json (served by Cloudflare)

* https://ipfs.io/ipns/QmTuBHRokSuiLBiqE1HySfK1BFiT2pmuDTuJKXNganE52N/endpoints.json


Also [`apidirectory`](https://github.com/cc32d9/eos.apidirectory)
smart contract in EOS is listing the endpoints under "statetrack"
type.


# Project sponsors

* [GetScatter](https://get-scatter.com/): funding the software
  development;

* [EOS Amsterdam](https://eosamsterdam.net/): hosting of public
  endpoints.




# Souce code, license and copyright

Source code repository: https://github.com/GetScatter/EOSIO-State-Track

Copyright (c) 2019 GetScatter Ltd.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

