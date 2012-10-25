-module(ecomponent_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("exmpp/include/exmpp.hrl").
-include_lib("exmpp/include/exmpp_client.hrl").
-include("../include/ecomponent.hrl").

-export([all/0]).
-export([init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    config_test/1, ping_test/1, disco_test/1,
    forward_response_module_test/1,forward_ns_in_set_test/1
]).

all() -> 
    [
        config_test, ping_test, disco_test, forward_response_module_test,
        forward_ns_in_set_test
    ].

init_per_suite(Config) ->
    mnesia:start(),
    meck:new(lager, [no_link]),
    meck:expect(lager, info, fun(X,Y) -> error_logger:info_msg(X,Y) end),
    meck:expect(lager, info, fun(X) -> error_logger:info_msg(X) end),
    meck:expect(lager, dispatch_log, fun(_Severity, _Metadata, Format, Args, _Size) ->
        error_logger:info_msg(Format, Args)
    end),
    
    error_logger:info_msg("INIT SUITE"),
    
    meck:new(syslog, [no_link]),
    meck:expect(syslog, open, fun(_Name, _Opts, _Facility) -> ok end),
    
    meck:new(confetti, [no_link]),
    meck:expect(confetti, fetch, fun(_) -> [
        {syslog_name, "ecomponent" },
        {jid, "ecomponent.test" },
        {server, "localhost" },
        {port, 8899},
        {pass, "secret"},
        {whitelist, [] }, %% throttle whitelist
        {access_list_get, []},
        {access_list_set, [
            {'com.yuilop.push/message', [<<"bob.localhost">>]},
            {'com.yuilop.push/jingle-initiate', [<<"bob.localhost">>]},
            {'com.yuilop.push/jingle-terminate', [<<"bob.localhost">>]},
            {'com.yuilop.push/multimedia/files', [<<"bob.localhost">>]},
            {'com.yuilop.push/multimedia/location', [<<"bob.localhost">>]},
            {'com.yuilop.push/contacts', [<<"bob.localhost">>]}
        ]},
        {max_per_period, 15},
        {period_seconds, 8},
        {processors, [
            {default, {mod, dummy}}
        ]}
    ] end),
    
    meck:new(exmpp_component, [no_link]),
    meck:expect(exmpp_component, start, fun() -> self() end),
    meck:expect(exmpp_component, stop, fun(_) -> ok end),
    meck:expect(exmpp_component, auth, fun(_Pid, _JID, _Pass) -> ok end),
    meck:expect(exmpp_component, connect, fun(_Pid, _Server, _Port) -> "1234" end),
    meck:expect(exmpp_component, handshake, fun(_Pid) -> ok end),
    
    Config.

end_per_suite(_Config) ->
    error_logger:info_msg("END SUITE"),
    
    meck:unload(syslog),
    meck:unload(confetti),
    meck:unload(exmpp_component),
    meck:unload(lager),
    mnesia:stop(),
    ok.

init_per_testcase(config_test, Config) ->
    Config;
init_per_testcase(save_id_expired_test, Config) ->
    meck:expect(confetti, fetch, fun(_) -> [
        {syslog_name, "ecomponent" },
        {jid, "ecomponent.test" },
        {server, "localhost" },
        {port, 8899},
        {pass, "secret"},
        {whitelist, [] }, %% throttle whitelist
        {access_list_get, []},
        {access_list_set, [
            {'com.yuilop.push/message', [<<"bob.localhost">>]},
            {'com.yuilop.push/jingle-initiate', [<<"bob.localhost">>]},
            {'com.yuilop.push/jingle-terminate', [<<"bob.localhost">>]},
            {'com.yuilop.push/multimedia/files', [<<"bob.localhost">>]},
            {'com.yuilop.push/multimedia/location', [<<"bob.localhost">>]},
            {'com.yuilop.push/contacts', [<<"bob.localhost">>]}
        ]},
        {max_per_period, 15},
        {period_seconds, 8},
        {processors, [
            {default, {mod, dummy}}
        ]},
        {request_timeout, 2}
    ] end),
    {ok, _Pid} = ecomponent:start_link(),
    Config;
init_per_testcase(_, Config) ->
    error_logger:info_msg("INIT GENERIC TESTCASE"),
    {ok, _Pid} = ecomponent:start_link(),
    Config.

end_per_testcase(config_test, _Config) ->
    ok;
end_per_testcase(_, _Config) ->
    error_logger:info_msg("END GENERIC TESTCASE"),
    ok = ecomponent:stop().

config_test(_Config) ->
    {ok, State} = ecomponent:init([]),
    lager:info("~p~n", [State]),
    Pid = self(),
    {state, 
        Pid, "ecomponent.test", "secret",
        "localhost", 8899, [], 15, 8, [{default, {mod, dummy}}],
        3, 100, 10, [
            {'com.yuilop.push/message', [<<"bob.localhost">>]},
            {'com.yuilop.push/jingle-initiate', [<<"bob.localhost">>]},
            {'com.yuilop.push/jingle-terminate', [<<"bob.localhost">>]},
            {'com.yuilop.push/multimedia/files', [<<"bob.localhost">>]},
            {'com.yuilop.push/multimedia/location', [<<"bob.localhost">>]},
            {'com.yuilop.push/contacts', [<<"bob.localhost">>]}
        ], [], local7, "ecomponent", _Timestamp} = State,
    ok.

ping_test(_Config) ->
    Packet = #received_packet{
        packet_type=iq, type_attr="get", raw_packet=
            {xmlel, 'jabber:client', none, 'iq',[
                {<<"type">>,"get"},
                {<<"to">>,"alice.localhost"},
                {<<"id">>,"test_bot"}
            ], [
                {xmlel, 'urn:xmpp:ping', none, 'ping', [],[]}
            ]},
        from={"bob","localhost",undefined}
    },
    Pid = self(),
    meck:expect(exmpp_component, send_packet, fun(_XmppCom, P) ->
        error_logger:info_msg("Sending Packet: ~p", [P]),
        Pid ! P
    end),
    ecomponent ! Packet,
    receive
        {xmlel,'jabber:client',[],iq,[
            {<<"type">>,"result"},
            {<<"id">>,"test_bot"},
            {<<"from">>,"alice.localhost"}
        ],[]} -> 
            ok;
        Any ->
            throw(Any)
    after 1000 ->
        throw("ERROR timeout")
    end.

disco_test(_Config) ->
    Packet = #received_packet{
        packet_type=iq, type_attr="get", raw_packet=
            {xmlel, 'jabber:client', none, 'iq',[
                {<<"type">>,"get"},
                {<<"to">>,"alice.localhost"},
                {<<"id">>,"test_bot"}
            ], [
                {xmlel, 'http://jabber.org/protocol/disco#info', none, 'query', [],[]}
            ]},
        from={"bob","localhost",undefined}
    },
    Pid = self(),
    meck:expect(exmpp_component, send_packet, fun(_XmppCom, P) ->
        error_logger:info_msg("Sending Packet: ~p", [P]),
        Pid ! P
    end),
    ecomponent ! Packet,
    receive
        {xmlel,'jabber:client',[],iq,[
            {<<"type">>,"result"},
            {<<"id">>,"test_bot"},
            {<<"from">>,"alice.localhost"}
        ],[
            {xmlel, 'http://jabber.org/protocol/disco#info', [], 'query', [], []}
        ]} -> 
            ok;
        Any ->
            throw(Any)
    after 1000 ->
        throw("ERROR timeout")
    end.

forward_response_module_test(_Config) ->
    Id = <<"forward_response_module_test">>,
    Packet = #received_packet{
        packet_type=iq, type_attr="error", raw_packet=
            {xmlel, 'jabber:client', none, 'iq',[
                {<<"type">>,"error"},
                {<<"to">>,"alice.localhost"},
                {<<"id">>,binary_to_list(Id)}
            ], [
                {xmlel, 'urn:itself', none, 'error', [],[]}
            ]},
        from={"bob","localhost",undefined}
    },
    timem:insert(Id, #matching{id="test_bot", ns='urn:itself', processor=self()}),
    ecomponent ! Packet,
    receive
        #response{ns='urn:itself', params=Params} when is_record(Params,params) ->
            error_logger:info_msg("Params: ~p~n", [Params]),
            ok;
        Any ->
            throw(Any)
    after 1000 ->
        throw("ERROR timeout")
    end.

forward_ns_in_set_test(_Config) ->
    Packet = #received_packet{
        packet_type=iq, type_attr="set", raw_packet=
            {xmlel, 'jabber:client', none, 'iq', [
                {<<"type">>, "set"},
                {<<"to">>, "alice.localhost"},
                {<<"id">>, "test_fwns_set"}
            ], [
                {xmlel, 'urn:itself', none, 'data', [], []}
            ]},
        from={"bob", "localhost", undefined}
    },
    Pid = self(),
    meck:new(dummy),
    meck:expect(dummy, process_iq, fun(Params) ->
        error_logger:info_msg("Received params: ~p~n", [Params]),
        Pid ! Params
    end),
    ecomponent ! Packet,
    receive
        #params{type="set",ns='urn:itself'}=Params ->
            error_logger:info_msg("Params: ~p~n", [Params]),
            ok;
        Any ->
            throw(Any)
    after 1000 ->
        throw("ERROR timeout")
    end.

save_id_expired_test(_Config) ->
    Id = ecomponent:gen_id(),
    Id_l = binary_to_list(Id),
    Packet = #received_packet{
        packet_type=iq, type_attr="set", raw_packet=
            {xmlel, 'jabber:client', none, 'iq', [
                {<<"type">>, "set"},
                {<<"to">>, "alice.localhost"},
                {<<"id">>, Id_l}
            ], [
                {xmlel, 'urn:itself', none, 'data', [], []}
            ]},
        from={"bob", "localhost", undefined}
    },
    Pid = self(),
    meck:expect(exmpp_component, send_packet, fun(_XmppCom, P) ->
        error_logger:info_msg("Sending Packet: ~p", [P]),
        Pid ! P
    end),
    ecomponent:save_id(Id, 'urn:itself', Packet, dummy),
    receive
        {xmlel, 'jabber:client', none, 'iq', [
            {<<"type">>, "set"},
            {<<"to">>, "alice.localhost"},
            {<<"id">>, Id_l}
        ], [
            {xmlel, 'urn:itself', none, 'data', [], []}
        ]} ->
            ok;
        Any ->
            throw(Any)
    after 3000 ->
        throw("Timeout error")
    end.
