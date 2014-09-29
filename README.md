[![Build Status](https://travis-ci.org/PowerMeMobile/smppload.png?branch=master)](https://travis-ci.org/PowerMeMobile/smppload)

## Prerequisites

In order to compile **smppload** you need to have [Erlang](http://www.erlang.org/) and [GNU Make](http://www.gnu.org/software/make/) installed.

## Compilation

<pre>
$ git clone https://github.com/PowerMeMobile/smppload.git
$ cd smppload
$ make
</pre>

## Usage

Now it's possible to launch **smppload** as an escript, which is faster, but Erlang needs to be installed:

<pre>
$ ./smppload
</pre>

or as a release, which is slower, but has greater portability:

<pre>
$ ./rel/smppload/smppload
</pre>

* Help message

<pre>
$ ./smppload
SMPP Loader from Power Alley Gateway Suite (1.1.0)
Usage: /home/ten0s/bin/smppload [-h] [-H [<host>]] [-P [<port>]]
                                [-B [<bind_type>]] [-i [<system_id>]]
                                [-p [<password>]] [-t [<system_type>]]
                                [-r [<rps>]] [-s [<source>]]
                                [-d <destination>] [-b <body>]
                                [-l [<length>]] [-c [<count>]]
                                [-D [<delivery>]] [-C [<data_coding>]]
                                [-f <file>] [-v [<verbosity>]]
                                [-T [<thread_count>]]
                                [--bind_timeout [<bind_timeout>]]
                                [--unbind_timeout [<unbind_timeout>]]
                                [--submit_timeout [<submit_timeout>]]
                                [--delivery_timeout [<delivery_timeout>]]

  -h, --help          Show this message
  -H, --host          SMSC server host name or IP address [default:
                      127.0.0.1]
  -P, --port          SMSC server port [default: 2775]
  -B, --bind_type     SMSC bind type: tx | trx [default: trx]
  -i, --system_id     SMSC system_id [default: user]
  -p, --password      SMSC password [default: password]
  -t, --system_type   SMSC service_type [default: ]
  -r, --rps           Number of requests per second [default: 1000]
  -s, --source        SMS source address Addr[:Len][,Ton=1,Npi=1]
                      [default: ]
  -d, --destination   SMS destination address Addr[:Len][,Ton=1,Npi=1]
  -b, --body          SMS body, randomly generated by default
  -l, --length        Randomly generated body length [default: 140]
  -c, --count         Count of SMS to send with given or random body
                      [default: 1]
  -D, --delivery      Delivery receipt [default: 0]
  -C, --data_coding   Data coding [default: 3]
  -f, --file          Send messages from file
  -v, --verbosity     Verbosity level [default: 0]
  -T, --thread_count  Thread/process count [default: 10]
  --bind_timeout      Bind timeout, sec [default: 10]
  --unbind_timeout    Unbind timeout, sec [default: 5]
  --submit_timeout    Submit timeout, sec [default: 20]
  --delivery_timeout  Delivery timeout, sec [default: 80]
</pre>

* Send a message with the body 'Hello there!' to localhost and the standard SMPP port
<pre>
$ ./smppload --source 375296660002 --destination 375293332211 --body 'Hello there!'
OR short
$ ./smppload -s 375296660002 -d 375293332211 -b 'Hello there!'
</pre>


* The above is the same as
<pre>
$ ./smppload --host 127.0.0.1 --port 2775 --bind_type trx --system_type '' --system_id user --password password --source 375296660002 --destination 375293332211 --body 'Hello there!'
OR short
$ ./smppload -H 127.0.0.1 -P 2775 -B trx -t '' -i user -p password -s 375296660002 -d 375293332211 -b 'Hello there!'
</pre>

* Send a message as TX
<pre>
$ ./smppload --bind_type tx --source 375296660002 --destination 375293332211 --body 'Hello there!'
</pre>

* Send a message with defined TON and NPI
<pre>
$ ./smppload --source FromBank,5,0 --destination 375293332211,1,1 --body 'Return our money, looser!'
</pre>

* Send a message with random trailing 4 and 7 digits respectively
<pre>
$ ./smppload --source 37529000:4 --destination 37529:7 --body 'Hi!'
</pre>

* Send a message with empty source
<pre>
$ ./smppload --source "" --destination 375293332211 --body 'Hi!'
OR
$ ./smppload --destination 375293332211 --body 'Hi!'
</pre>

* Send a message with empty source but defined TON and NPI
<pre>
$ ./smppload --source ",5,0" --destination 375293332211 --body 'Hi!'
</pre>

* Send a message with a random body
<pre>
$ ./smppload --source 375296660002 --destination 375293332211
</pre>

* Send a message with a random body and length 25
<pre>
$ ./smppload --source 375296660002 --destination 375293332211 --length 25
</pre>

* Send a multipart message with a random body and length 160
<pre>
$ ./smppload --source 375296660002 --destination 375293332211 --length 160
</pre>

* Send 100 messages with random bodies
<pre>
$ ./smppload --source 375296660002 --destination 375293332211 --count 100
</pre>

* Send a message in data_coding 8 (UCS2-BE)
<pre>
$ ./smppload --source 375296660002 --destination 375293332211 --body "Привет" --data_coding 8
</pre>

* Send messages from file test/messages.txt
<pre>
$ cat test/messages.txt
# source;destination;body;delivery
# where
#   source      :: address
#   destination :: address
#   address     :: addr[,ton,npi]
#   body        :: string, use double semicolon (;;) in the body
#   delivery    :: true | false | 1 | 0
#   data_coding :: integer
375296660002,1,1;375291112231,1,1;Message #1;true;3
375296660002,1,1;375291112232,1,1;Message #2;true;3
375296660002,1,1;375291112233,1,1;Message #3;true;3
375296660002,1,1;375291112234,1,1;Message #4;true;3
375296660002,1,1;375291112235,1,1;Message #5;true;3
$ ./smppload --file test/messages.txt
</pre>

* Send messages from standard input
<pre>
$ cat test/messages.txt | ./smppload --file -
</pre>

* Send dynamically generated messages from standard input
<pre>
$ for i in `seq 1 100`; do printf "375296660002,1,1;37529%07d,1,1;Message #%d;false;3\n" $i $i; done | ./smppload --file -
</pre>

* Send a message with ERROR (default) log level
<pre>
$ ./smppload --source 375296660002 --destination 375293332211 --body 'Hello there!'
</pre>

* Send a message with INFO log level
<pre>
$ ./smppload --source 375296660002 --destination 375293332211 --body 'Hello there!' -v
INFO:  Connected to 127.0.0.1:2775
INFO:  Bound to Funnel
INFO:  Stats:
INFO:     Send success:     1
INFO:     Delivery success: 0
INFO:     Send fail:        0
INFO:     Delivery fail:    0
INFO:     Errors:           0
INFO:     Avg Rps:          20 mps
INFO:  Unbound
</pre>

* Send a message with DEBUG log level
<pre>
$ ./smppload --source 375296660002 --destination 375293332211 --body 'Hello there!' -vv
DEBUG: Options: [{source,"375296660002"},
                 {destination,"375293332211"},
                 {body,"Hello there!"},
                 {verbosity,2},
                 {host,"127.0.0.1"},
                 {port,2775},
                 {bind_type,"trx"},
                 {system_id,"user"},
                 {password,"password"},
                 {system_type,[]},
                 {rps,1000},
                 {length,140},
                 {count,1},
                 {delivery,0},
                 {data_coding,3},
                 {thread_count,10},
                 {bind_timeout,10},
                 {unbind_timeout,5},
                 {submit_timeout,20},
                 {delivery_timeout,80}]
DEBUG: Module: lazy_messages_body
INFO:  Connected to 127.0.0.1:2775
DEBUG: Request: {bind_transceiver,[{system_type,[]},
                                   {system_id,"user"},
                                   {password,"password"},
                                   {bind_timeout,10000}]}
DEBUG: Response: {bind_transceiver_resp,0,1,[{system_id,"Funnel"}]}
INFO:  Bound to Funnel
DEBUG: Request: {submit_sm,[{source_addr_ton,1},
                            {source_addr_npi,1},
                            {source_addr,"375296660002"},
                            {dest_addr_ton,1},
                            {dest_addr_npi,1},
                            {destination_addr,"375293332211"},
                            {short_message,"Hello there"},
                            {esm_class, 0},
                            {data_coding,3},
                            {registered_delivery,0},
                            {submit_timeout,20000},
                            {delivery_timeout,80000}]}
DEBUG: Response: {submit_sm_resp,0,2,[{message_id,"190602"}]}
INFO:  Stats:
INFO:     Send success:     1
INFO:     Delivery success: 0
INFO:     Send fail:        0
INFO:     Delivery fail:    0
INFO:     Errors:           0
INFO:     Avg Rps:          23 mps
DEBUG: Request: {unbind,[]}
DEBUG: Response: {unbind_resp,0,3,[]}
INFO:  Unbound
</pre>

## Known issues and limitations

* Randomly generated message body encoding is Latin1.
* Message body encoding from files or command line is expected to be in UTF-8.
* Thread count is 1 by default until the https://github.com/iamaleksey/oserl/issues/1 issue is fixed.