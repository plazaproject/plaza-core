-module(automate_rest_api_backend).

%% API exports
-export([ register_user/1
        , login_user/1
        , is_valid_token/1
        , create_monitor/2
        , lists_monitors_from_username/1
        , create_program/1
        , get_program/2
        , lists_programs_from_username/1
        , update_program/3
        , list_services_from_username/1
        , get_service_enable_how_to/2
        , list_chats_from_username/1

        , update_program_metadata/3
        , delete_program/2
        ]).

%% Definitions
-include("./records.hrl").
-include("../../automate_storage/src/records.hrl").
-include("../../automate_chat_registry/src/records.hrl").

%%====================================================================
%% API functions
%%====================================================================
register_user(#registration_rec{ email=Email
                               , password=Password
                               , username=Username
                               }) ->
    case automate_storage:create_user(Username, Password, Email) of
        { ok, UserId } ->
            Url = generate_url_from_userid(UserId),
            io:format("Url: ~p~n", [Url]),
            { ok, Url };
        { error, Reason } ->
            { error, Reason }
    end.

login_user(#login_rec{ password=Password
                     , username=Username
                     }) ->
    case automate_storage:login_user(Username, Password) of
        { ok, Token } ->
            { ok, Token };
        { error, Reason } ->
            { error, Reason }
    end.

is_valid_token(Token) when is_binary(Token) ->
    case automate_storage:get_session_username(Token) of
        { ok, Username } ->
            {true, Username};
        { error, session_not_found } ->
            false;
        { error, Reason } ->
            io:format("Error getting session: ~p~n", [Reason]),
            false
    end.

-spec create_monitor(binary(), #monitor_descriptor{}) -> {ok, {binary(), binary()}}.
create_monitor(Username, #monitor_descriptor{ type=Type, name=Name, value=Value }) ->
    case automate_storage:create_monitor(Username, #monitor_entry{ type=Type
                                                                 , name=Name
                                                                 , value=Value
                                                                 , id=none %% ID generated by the storage
                                                                 , user_id=none
                                                                 }) of
        { ok, MonitorId } ->
            { ok, { MonitorId, Name } }
    end.

-spec lists_monitors_from_username(binary()) -> {'ok', [ #monitor_metadata{} ] }.
lists_monitors_from_username(Username) ->
    case automate_storage:lists_monitors_from_username(Username) of
        {ok, Monitors} ->
            {ok, [#monitor_metadata{ id=Id
                                   , name=Name
                                   , link=generate_url_for_monitor_name(Username, Name)
                                   }
                  || {Id, Name} <- Monitors]}
    end.

create_program(Username) ->
    ProgramName = generate_program_name(),
    case automate_storage:create_program(Username, ProgramName) of
        { ok, ProgramId } ->
            { ok, { ProgramId
                  , ProgramName
                  , generate_url_for_program_name(Username, ProgramName) } }
    end.

get_program(Username, ProgramName) ->
    case automate_storage:get_program(Username, ProgramName) of
        {ok, ProgramData} ->
            {ok, program_entry_to_program(ProgramData)};
        X ->
            X
    end.

-spec lists_programs_from_username(binary()) -> {'ok', [ #program_metadata{} ] }.
lists_programs_from_username(Username) ->
    case automate_storage:lists_programs_from_username(Username) of
        {ok, Programs} ->
            {ok, [#program_metadata{ id=ProgramId
                                   , name=ProgramName
                                   , link=generate_url_for_program_name(Username, ProgramName)
                                   }
                  || {ProgramId, ProgramName} <- Programs]}
    end.

update_program(Username, ProgramName,
               #program_content{ orig=Orig
                               , parsed=Parsed
                               , type=Type }) ->

    {ok, UserId} = automate_storage:get_userid_from_username(Username),
    {ok, Linked} = automate_program_linker:link_program(Parsed, UserId),
    io:fwrite("Linked program: ~p~n", [Linked]),
    case automate_storage:update_program(Username, ProgramName,
                                         #stored_program_content{ orig=Orig
                                                                , parsed=Linked
                                                                , type=Type }) of
        { ok, ProgramId } ->
            automate_bot_engine_launcher:update_program(ProgramId);
        { error, Reason } ->
            {error, Reason}
    end.

update_program_metadata(Username, ProgramName,
                        Metadata=#editable_user_program_metadata{program_name=NewProgramName}) ->

    case automate_storage:update_program_metadata(Username,
                                                  ProgramName,
                                                  Metadata) of
        { ok, _ProgramId } ->
            {ok, #{ <<"link">> => generate_url_for_program_name(Username, NewProgramName) }};
        { error, Reason } ->
            {error, Reason}
    end.


delete_program(Username, ProgramName) ->
    automate_storage:delete_program(Username, ProgramName).

-spec list_services_from_username(binary()) -> {'ok', [ #service_metadata{} ]} | {error, term(), binary()}.
list_services_from_username(Username) ->
    {ok, UserId} = automate_storage:get_userid_from_username(Username),
    case  automate_service_registry:get_all_services_for_user(UserId) of
        {ok, Services} ->
            {ok, get_services_metadata(Services, Username)};
        E = {error, _, _} ->
            E
    end.


-spec get_service_enable_how_to(binary(), binary()) -> {ok, binary() | none} | {error, not_found}.
get_service_enable_how_to(Username, ServiceId) ->
    case get_platform_service_how_to(Username, ServiceId) of
        {ok, HowTo} ->
            {ok, HowTo};
        {error, not_found} ->
            %% TODO: Implement user-defined services
            io:format("[Error] Non platform service required~n"),
            {error, not_found}
    end.


-spec list_chats_from_username(binary()) -> {'ok', [ #chat_entry{} ]} | {error, term(), binary()}.
list_chats_from_username(Username) ->
    {ok, UserId} = automate_storage:get_userid_from_username(Username),
    automate_chat_registry:get_all_chats_for_user(UserId).

%%====================================================================
%% Internal functions
%%====================================================================
get_services_metadata(Services, Username) ->
    lists:map(fun ({K, V}) -> get_service_metadata(K, V, Username) end,
              maps:to_list(Services)).

get_service_metadata(Id
                    , #{ name := Name
                       , description := _Description
                       , module := Module
                       }
                    , Username) ->
    try Module:is_enabled_for_user(Username) of
        {ok, Enabled} ->
            #service_metadata{ id=Id
                             , name=Name
                             , link=generate_url_for_service_id(Username, Id)
                             , enabled=Enabled
                             }
    catch X:Y ->
            io:fwrite("Error: ~p:~p~n", [X, Y]),
            none
    end.

generate_url_for_service_id(Username, ServiceId) ->
    binary:list_to_bin(lists:flatten(io_lib:format("/api/v0/users/~s/services/id/~s", [Username, ServiceId]))).

generate_url_from_userid(UserId) ->
    binary:list_to_bin(lists:flatten(io_lib:format("/api/v0/users/~s", [UserId]))).

%% *TODO* generate more interesting names.
generate_program_name() ->
    binary:list_to_bin(uuid:to_string(uuid:uuid4())).

generate_url_for_program_name(Username, ProgramName) ->
    binary:list_to_bin(lists:flatten(io_lib:format("/api/v0/users/~s/programs/~s", [Username, ProgramName]))).

generate_url_for_monitor_name(Username, MonitorName) ->
    binary:list_to_bin(lists:flatten(io_lib:format("/api/v0/users/~s/monitors/~s", [Username, MonitorName]))).

program_entry_to_program(#user_program_entry{ id=Id
                                            , user_id=UserId
                                            , program_name=ProgramName
                                            , program_type=ProgramType
                                            , program_parsed=ProgramParsed
                                            , program_orig=ProgramOrig
                                            }) ->
    #user_program{ id=Id
                 , user_id=UserId
                 , program_name=ProgramName
                 , program_type=ProgramType
                 , program_parsed=ProgramParsed
                 , program_orig=ProgramOrig
                 }.

-spec get_platform_service_how_to(binary(), binary()) -> {ok, binary() | none} | {error, not_found}.
get_platform_service_how_to(Username, ServiceId)  ->
    {ok, UserId} = automate_storage:get_userid_from_username(Username),
    case automate_service_registry:get_service_by_id(ServiceId, UserId) of
        E = {error, not_found} ->
            E;
        {ok, #{ module := Module }} ->
            Module:get_how_to_enable(#{ user_id => UserId, user_name => Username})
    end.
