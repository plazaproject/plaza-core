%%%-------------------------------------------------------------------
%% @doc automate_service_registry API.
%% @end
%%%-------------------------------------------------------------------

-module(automate_service_registry_query).

%% API
-export([ is_enabled_for_user/2
        , get_how_to_enable/2
        , call/5
        , get_monitor_id/2
        ]).

-define(SERVER, ?MODULE).
-include("records.hrl").

%%====================================================================
%% API functions
%%====================================================================
is_enabled_for_user({Module, Params}, Username) ->
    Module:is_enabled_for_user(Username, Params);

is_enabled_for_user(Module, Username) ->
    Module:is_enabled_for_user(Username).

get_how_to_enable({Module, Params}, UserInfo) ->
    Module:get_how_to_enable(UserInfo, Params);

get_how_to_enable(Module, UserInfo) ->
    Module:get_how_to_enable(UserInfo).

call({Module, Params}, Action, Values, Thread, UserId) ->
    Module:call(Action, Values, Thread, UserId, Params);

call(Module, Action, Values, Thread, UserId) ->
    Module:call(Action, Values, Thread, UserId).

get_monitor_id({Module, Params}, UserId) ->
    Module:get_monitor_id(UserId, Params);

get_monitor_id(Module, UserId) ->
    Module:get_monitor_id(UserId).
