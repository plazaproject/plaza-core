%%% @doc
%%% REST endpoint to get available connection points
%%% @end

-module(automate_rest_api_connections_established_root).
-export([init/2]).
-export([ allowed_methods/2
        , options/2
        , is_authorized/2
        , content_types_provided/2
        , resource_exists/2
        ]).

-export([ to_json/2
        ]).


-include("./records.hrl").
-include("../../automate_service_port_engine/src/records.hrl").
-define(FORMATTING, automate_rest_api_utils_formatting).

-record(state, { user_id }).

-spec init(_,_) -> {'cowboy_rest',_,_}.
init(Req, _Opts) ->
    UserId = cowboy_req:binding(user_id, Req),
    {cowboy_rest, Req
    , #state{ user_id=UserId }}.

resource_exists(Req, State) ->
    case cowboy_req:method(Req) of
        <<"POST">> ->
            { false, Req, State };
        _ ->
            { true, Req, State}
    end.

%% CORS
options(Req, State) ->
    Req1 = automate_rest_api_cors:set_headers(Req),
    {ok, Req1, State}.

%% Authentication
-spec allowed_methods(cowboy_req:req(),_) -> {[binary()], cowboy_req:req(),_}.
allowed_methods(Req, State) ->
    {[<<"GET">>, <<"OPTIONS">>], Req, State}.

is_authorized(Req, State) ->
    Req1 = automate_rest_api_cors:set_headers(Req),
    case cowboy_req:method(Req1) of
        %% Don't do authentication if it's just asking for options
        <<"OPTIONS">> ->
            { true, Req1, State };
        _ ->
            case cowboy_req:header(<<"authorization">>, Req, undefined) of
                undefined ->
                    { {false, <<"Authorization header not found">>} , Req1, State };
                X ->
                    #state{user_id=UserId} = State,
                    case automate_rest_api_backend:is_valid_token_uid(X) of
                        {true, UserId} ->
                            { true, Req1, State };
                        {true, _} -> %% Non matching user_id
                            { { false, <<"Unauthorized here">>}, Req1, State };
                        false ->
                            { { false, <<"Authorization not correct">>}, Req1, State }
                    end
            end
    end.

%% GET handler
content_types_provided(Req, State) ->
    {[{{<<"application">>, <<"json">>, []}, to_json}],
     Req, State}.

-spec to_json(cowboy_req:req(), #state{})
             -> {binary(),cowboy_req:req(), #state{}}.
to_json(Req, State) ->
    #state{user_id=UserId} = State,
    case automate_rest_api_backend:list_established_connections(UserId) of
        { ok, Connections } ->

            Output = jiffy:encode(lists:filtermap(fun to_map/1, Connections)),
            Res1 = cowboy_req:delete_resp_header(<<"content-type">>, Req),
            Res2 = cowboy_req:set_resp_header(<<"content-type">>, <<"application/json">>, Res1),

            { Output, Res2, State }
    end.

to_map(#user_to_bridge_connection_entry{ id=Id
                                       , bridge_id=BridgeId
                                       , user_id=_
                                       , channel_id=_
                                       , name=Name
                                       , creation_time=_CreationTime
                                       }) ->
    case automate_service_port_engine:get_bridge_info(BridgeId) of
        {ok, #service_port_metadata{ name=BridgeName, icon=Icon }} ->
            {true, #{ <<"connection_id">> => Id
                    , <<"name">> => serialize_string_or_undefined(Name)
                    , <<"bridge_id">> => BridgeId
                    , <<"bridge_name">> => serialize_string_or_undefined(BridgeName)
                    , <<"icon">> => ?FORMATTING:serialize_icon(Icon)
                    } };
        {error, _Reason} ->
            false
    end.

serialize_string_or_undefined(undefined) ->
    null;
serialize_string_or_undefined(String) ->
    String.
