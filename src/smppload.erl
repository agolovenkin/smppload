-module(smppload).

-export([
    main/0,
    main/1
]).

-include("message.hrl").
-include("smppload.hrl").
-include_lib("oserl/include/smpp_globals.hrl").

%% Purely empirical values
-define(MAX_OUTSTANDING_SUBMITS, 100).
-define(FIRST_REPLY_TIMEOUT, 150000).
-define(REST_REPLIES_TIMEOUT, 30000).

%% ===================================================================
%% API
%% ===================================================================

-spec main() -> no_return().
main() ->
    PlainArgs = init:get_plain_arguments(),
    case PlainArgs of
        ["--", Args] ->
            main(Args);
        _ ->
            main([])
    end.

-spec main([string()]) -> no_return().
main([]) ->
    AppName = app_name(),
    OptSpecs = opt_specs(),
    print_usage(AppName, OptSpecs);
main("--") ->
    main([]);
main(Args) ->
    AppName = app_name(),
    OptSpecs = opt_specs(),

    case getopt:parse(OptSpecs, Args) of
        {ok, {Opts, _NonOptArgs}} ->
            process_opts(AppName, Opts, OptSpecs);
        {error, {Reason, Data}} ->
            ?ABORT("Parse data ~p failed with: ~s~n", [Data, Reason])
    end.

%% ===================================================================
%% Internal
%% ===================================================================

opt_specs() ->
    DC = ?ENCODING_SCHEME_LATIN_1,
    {MaxMsgLen, _} = smppload_utils:max_msg_seg(DC),
    [
        %% {Name, ShortOpt, LongOpt, ArgSpec, HelpMsg}
        {help, $h, "help", undefined, "Show this message"},
        {host, $H, "host", {string, "127.0.0.1"}, "SMSC server host name or IP address"},
        {port, $P, "port", {integer, 2775}, "SMSC server port"},
        {bind_type, $B, "bind_type", {string, "trx"}, "SMSC bind type: tx | trx"},
        {system_id, $i, "system_id", {string, "user"}, "SMSC system_id"},
        {password, $p, "password", {string, "password"}, "SMSC password"},
        {system_type, $t, "system_type", {string, ""}, "SMSC service_type"},
        {rps, $r, "rps", {integer, 1000}, "Number of requests per second"},
        {source, $s, "source", {string, ""}, "SMS source address Addr[:Len][,Ton=1,Npi=1]"},
        {destination , $d, "destination", string, "SMS destination address Addr[:Len][,Ton=1,Npi=1]"},
        {body, $b, "body", string, "SMS body, randomly generated by default"},
        {length, $l, "length", {integer, MaxMsgLen}, "Randomly generated body length"},
        {count, $c, "count", {integer, 1}, "Count of SMS to send with given or random body"},
        {delivery, $D, "delivery", {integer, 0}, "Delivery receipt"},
        {data_coding, $C, "data_coding", {integer, DC}, "Data coding"},
        {file, $f, "file", string, "Send messages from file"},
        {sequentially, $S, "sequentially", undefined, "Send messages sequentially, parallel by default"},
        {verbosity, $v, "verbosity", {integer, 0}, "Verbosity level"}
    ].

process_opts(AppName, Opts, OptSpecs) ->
    case ?gv(help, Opts, false) of
        true ->
            print_usage(AppName, OptSpecs);
        false ->
            %% initialize the logger.
            smppload_log:init(?gv(verbosity, Opts)),
            ?DEBUG("Options: ~p~n", [Opts]),

            BindTypeFun = get_bind_type_fun(Opts),
            ?DEBUG("BindTypeFun: ~p~n", [BindTypeFun]),

            MessagesModule = get_lazy_messages_module(Opts),
            ?DEBUG("MessagesModule: ~p~n", [MessagesModule]),

            %% start needed applications.
            error_logger:tty(false),
            application:start(common_lib),
            application:start(smppload),

            {ok, _} = smppload_esme:start(),

            Host = ?gv(host, Opts),
            Port = ?gv(port, Opts),
            Peer = format_peer(Host, Port),
            case smppload_esme:connect(Host, Port) of
                ok ->
                    ?INFO("Connected to ~s~n", [Peer]);
                {error, Reason1} ->
                    ?ABORT("Connect to ~s failed with: ~s~n", [Peer, Reason1])
            end,

            SystemType = ?gv(system_type, Opts),
            SystemId = ?gv(system_id, Opts),
            Password = ?gv(password, Opts),
            BindParams = [
                {system_type, SystemType},
                {system_id, SystemId},
                {password, Password}
            ],
            case apply(smppload_esme, BindTypeFun, [BindParams]) of
                {ok, RemoteSystemId} ->
                    ?INFO("Bound to ~s~n", [RemoteSystemId]);
                {error, Reason2} ->
                    ?ABORT("Bind failed with: ~p~n", [Reason2])
            end,

            Rps = ?gv(rps, Opts),
            ok = smppload_esme:set_max_rps(Rps),

            Sequentially = ?gv(sequentially, Opts, false),
            {ok, Stats} = send_messages(MessagesModule, Opts, Sequentially),

            ?INFO("Stats:~n", []),
            ?INFO("   Send success:     ~p~n", [smppload_stats:send_succ(Stats)]),
            ?INFO("   Delivery success: ~p~n", [smppload_stats:dlr_succ(Stats)]),
            ?INFO("   Send fail:        ~p~n", [smppload_stats:send_fail(Stats)]),
            ?INFO("   Delivery fail:    ~p~n", [smppload_stats:dlr_fail(Stats)]),
            ?INFO("   Errors:           ~p~n", [smppload_stats:errors(Stats)]),
            ?INFO("   Avg Rps:          ~p mps~n", [smppload_stats:rps(Stats)]),

            smppload_esme:unbind(),
            ?INFO("Unbound~n", []),

            %% stop applications.
            error_logger:tty(false),
            application:stop(smppload),
            application:stop(common_lib)
    end.

format_peer({A, B, C, D}, Port) ->
    io_lib:format("~p.~p.~p.~p:~p", [A, B, C, D, Port]);
format_peer(Host, Port) when is_list(Host) ->
    io_lib:format("~s:~p", [Host, Port]).

get_bind_type_fun(Opts) ->
    BindType = ?gv(bind_type, Opts),
    case string:to_lower(BindType) of
        "tx" ->
            bind_transmitter;
        "trx" ->
            bind_transceiver;
        _ ->
            ?ABORT("Unknown bind type: ~p~n", [BindType])
    end.

get_lazy_messages_module(Opts) ->
    case ?gv(file, Opts) of
        undefined ->
            case ?gv(body, Opts) of
                undefined ->
                    check_destination(Opts),
                    smppload_lazy_messages_random;
                _ ->
                    check_destination(Opts),
                    smppload_lazy_messages_body
            end;
        _ ->
            smppload_lazy_messages_file
    end.

check_destination(Opts) ->
    case ?gv(destination, Opts) of
        undefined ->
            ?ABORT("Destination address is not provided~n", []);
        _ ->
            ok
    end.

send_messages(Module, Config, Sequentially) ->
    {ok, State0} = smppload_lazy_messages:init(Module, Config),
        Fun = case Sequentially of
                true ->
                    fun send_seq_messages/1;
                false ->
                    fun send_par_messages/1
              end,
    {ok, State1, Stats} = Fun(State0),
    ok = smppload_lazy_messages:deinit(State1),
    {ok, Stats}.

send_seq_messages(State0) ->
    send_seq_messages(State0, smppload_stats:new()).

send_seq_messages(State0, Stats0) ->
    case smppload_lazy_messages:get_next(State0) of
        {ok, Submit, State1} ->
            Stats = send_message(Submit),
            send_seq_messages(State1, smppload_stats:add(Stats0, Stats));
        {no_more, State1} ->
            Stats1 =
                case smppload_esme:get_avg_rps() of
                    {ok, AvgRps} ->
                        smppload_stats:inc_rps(Stats0, AvgRps);
                    {error, _} ->
                        Stats0
                end,
            {ok, State1, Stats1}
    end.

send_message(Msg) ->
    SourceAddr =
        case Msg#message.source of
            [] ->
                [];
            _ ->
                [
                    {source_addr_ton , Msg#message.source#address.ton},
                    {source_addr_npi , Msg#message.source#address.npi},
                    {source_addr     , Msg#message.source#address.addr}
                ]
        end,
    RegDlr =
        case Msg#message.delivery of
            true  ->
                1;
            false ->
                0;
            Int when is_integer(Int), Int > 0 ->
                1;
            _Other ->
                0
        end,
    Params = SourceAddr ++ [
        {dest_addr_ton      , Msg#message.destination#address.ton},
        {dest_addr_npi      , Msg#message.destination#address.npi},
        {destination_addr   , Msg#message.destination#address.addr},
        {short_message      , Msg#message.body},
        {esm_class          , Msg#message.esm_class},
        {data_coding        , Msg#message.data_coding},
        {registered_delivery, RegDlr}
    ],

    case smppload_esme:submit_sm(Params) of
        {ok, _OutMsgId, no_delivery} ->
            smppload_stats:inc_send_succ(smppload_stats:new());
        {ok, _OutMsgId, delivery_timeout} ->
            smppload_stats:inc_dlr_fail(smppload_stats:inc_send_succ(smppload_stats:new()));
        {ok, _OutMsgId, _DlrRes} ->
            smppload_stats:inc_dlr_succ(smppload_stats:inc_send_succ(smppload_stats:new()));
        {error, _Reason} ->
            smppload_stats:inc_send_fail(smppload_stats:new())
    end.

send_par_messages(State0) ->
    process_flag(trap_exit, true),
    ReplyTo = self(),
    ReplyRef = make_ref(),
    {ok, MsgSent, State1} = send_par_init_messages(
        ReplyTo, ReplyRef, ?MAX_OUTSTANDING_SUBMITS, 0, State0
    ),
    send_par_messages_and_collect_replies(
        ReplyTo, ReplyRef, ?FIRST_REPLY_TIMEOUT, MsgSent, State1, smppload_stats:new()
    ).

%% start phase
send_par_init_messages(_ReplyTo, _ReplyRef, MaxMsgCnt, MaxMsgCnt, State0) ->
    {ok, MaxMsgCnt, State0};
send_par_init_messages(ReplyTo, ReplyRef, MaxMsgCnt, MsgCnt, State0) ->
    case smppload_lazy_messages:get_next(State0) of
        {ok, Submit, State1} ->
            spawn_link(
                fun() ->
                    send_message_and_reply(ReplyTo, ReplyRef, Submit)
                end
            ),
            send_par_init_messages(
                ReplyTo, ReplyRef, MaxMsgCnt, MsgCnt + 1, State1
            );
        {no_more, State1} ->
            {ok, MsgCnt, State1}
    end.

%% collect and send new messages phase.
send_par_messages_and_collect_replies(
    _ReplyTo, _ReplyRef, _Timeout, 0, State0, Stats0
) ->
    Stats1 =
        case smppload_esme:get_avg_rps() of
            {ok, AvgRps} ->
                smppload_stats:inc_rps(Stats0, AvgRps);
            {error, _} ->
                Stats0
        end,
    {ok, State0, Stats1};
send_par_messages_and_collect_replies(
    ReplyTo, ReplyRef, Timeout, MsgSent, State0, Stats0
) ->
    receive
        {ReplyRef, Stats} ->
            send_par_messages_and_collect_replies(
                ReplyTo, ReplyRef, ?REST_REPLIES_TIMEOUT,
                MsgSent, State0, smppload_stats:add(Stats0, Stats)
            );

        {'EXIT', _Pid, Reason} ->
            Stats1 =
                case Reason of
                        normal ->
                            Stats0;
                        _Other ->
                            ?ERROR("Submit failed with: ~p~n", [Reason]),
                            smppload_stats:inc_errors(Stats0)
                end,
            case smppload_lazy_messages:get_next(State0) of
                {ok, Submit, State1} ->
                    spawn_link(
                        fun() ->
                            send_message_and_reply(ReplyTo, ReplyRef, Submit)
                        end
                    ),
                    send_par_messages_and_collect_replies(
                        ReplyTo, ReplyRef, ?REST_REPLIES_TIMEOUT,
                        MsgSent - 1 + 1, State1, Stats1
                    );
                {no_more, State1} ->
                    send_par_messages_and_collect_replies(
                        ReplyTo, ReplyRef, ?REST_REPLIES_TIMEOUT,
                        MsgSent - 1, State1, Stats0
                    )
            end
    after
        Timeout ->
            Stats1 =
                case smppload_esme:get_avg_rps() of
                    {ok, AvgRps} ->
                        smppload_stats:inc_rps(Stats0, AvgRps);
                    {error, _} ->
                        Stats0
                end,
            {ok, State0, Stats1}
    end.

send_message_and_reply(ReplyTo, ReplyRef, Submit) ->
    Stats = send_message(Submit),
    ReplyTo ! {ReplyRef, Stats}.

print_usage(AppName, OptSpecs) ->
    print_description_vsn(AppName),
    getopt:usage(OptSpecs, AppName).

print_description_vsn(AppName) ->
    case description_vsn(AppName) of
        {Description, Vsn} ->
            io:format("~s (~s)~n", [Description, Vsn]);
        _ ->
            ok
    end.

description_vsn(AppName) ->
    case app_options(AppName) of
        undefined ->
            undefined;
        Options ->
            Description = ?gv(description, Options),
            Vsn = ?gv(vsn, Options),
            {Description, Vsn}
    end.

is_escript() ->
    case init:get_argument(mode) of
        {ok, [["embedded"]]} ->
            false;
        _ ->
            true
    end.

app_name() ->
    case is_escript() of
        true ->
            escript:script_name();
        false ->
            {ok, [[AppName]]} = init:get_argument(progname),
            AppName
    end.

app_options(AppName) ->
    case is_escript() of
        true ->
            escript_options(AppName);
        false ->
            application_options(AppName)
    end.

escript_options(ScriptName) ->
    {ok, Sections} = escript:extract(ScriptName, []),
    Zip = ?gv(archive, Sections),
    AppName = lists:flatten(io_lib:format("~p.app", [?MODULE])),
    case zip:extract(Zip, [{file_list, [AppName]}, memory]) of
        {ok, [{AppName, Binary}]} ->
            {ok, Tokens, _} = erl_scan:string(binary_to_list(Binary)),
            {ok, {application, ?MODULE, Options}} = erl_parse:parse_term(Tokens),
            Options;
        _ ->
            undefined
    end.

application_options(_AppName) ->
    case application:get_all_key(?MODULE) of
        undefined ->
            undefined;
        {ok, Options} ->
            Options
    end.
