%%% @doc
%%% Automate service port shared resource management tests.
%%% @end

-module(automate_service_port_engine_shared_resource_tests).
-include_lib("eunit/include/eunit.hrl").
-include("../src/records.hrl").
-include("../../automate_storage/src/records.hrl").
-include("../../automate_bot_engine/src/instructions.hrl").
-include("../../automate_bot_engine/src/program_records.hrl").


%% Test data
-define(TEST_NODES, [node()]).
-define(TEST_ID_PREFIX, "automate_service_port_engine_shared_resource_tests").
-define(RECEIVE_TIMEOUT, 100).

-define(APPLICATION, automate_service_port_engine).
-define(BACKEND, automate_service_port_engine_mnesia_backend).
-define(UTILS, automate_service_port_engine_test_utils).
-define(BOT_UTILS, automate_bot_engine_test_utils).
-define(ROUTER, automate_service_port_engine_router).

%%====================================================================
%% Test API
%%====================================================================

session_manager_test_() ->
    {setup
    , fun setup/0
    , fun stop/1
    , fun tests/1
    }.

%% @doc App infrastructure setup.
%% @end
setup() ->
    NodeName = node(),

    %% Use a custom node name to avoid overwriting the actual databases
    net_kernel:start([testing, shortnames]),

    {ok, _Pid} = application:ensure_all_started(?APPLICATION),

    {NodeName}.

%% @doc App infrastructure teardown.
%% @end
stop({_NodeName}) ->
    %% ?BACKEND:uninstall(),
    ok = application:stop(?APPLICATION),

    ok.

tests(_SetupResult) ->
    %% Custom blocks
    [ { "[Bridge - Shared resources] Allow to share resources, blocks that require a shared resource do appear"
      , fun blocks_with_shared_resources_appear/0
      }
    , { "[Bridge - Shared resources] Allow to share resources, blocks that require a non-shared resource don't appear"
      , fun non_shared_resources_negate_custom_blocks/0
      }
      %% TODO: Should it show blocks with NO required resources?
      %% Execution test
    , { "[Bridge - Shared resources] Allow to make calls on shared resource values"
      , fun allow_to_make_calls_on_shared_resource_values/0
      }
    , { "[Bridge - Shared resources] Don't to make calls on non-shared resource values"
      , fun disallow_calls_on_non_shared_resource_values/0
      }
    ].


%%====================================================================
%% Custom block tests
%%====================================================================
blocks_with_shared_resources_appear() ->
    OwnerUser = {user, <<?TEST_ID_PREFIX, "-test-1-owner">>},
    ReaderUserId = <<?TEST_ID_PREFIX, "-test-1-reader">>,
    ReaderUser = {user, ReaderUserId},
    GroupName = <<?TEST_ID_PREFIX, "-test-1-group">>,
    ResourceName = <<"channels">>,
    SharedValue = <<"shared-val-id">>,
    SharedValueName = <<"shared-val-name">>,

    {ok, #user_group_entry{ id=GroupId }} = automate_storage:create_group(GroupName, OwnerUser, false),
    ok = automate_storage:add_collaborators({ group, GroupId }, [{ReaderUserId, editor}]),

    BridgeName = <<?TEST_ID_PREFIX, "-test-1-service-port">>,
    {ok, BridgeId} = ?APPLICATION:create_service_port(OwnerUser, BridgeName),

    Configuration = #{ <<"is_public">> => false
                     , <<"service_name">> => BridgeName
                     , <<"blocks">> => [ get_test_block([{resource, ResourceName}]) ]
                     },
    ok = ?APPLICATION:from_service_port(BridgeId, OwnerUser,
                                        jiffy:encode(#{ <<"type">> => <<"CONFIGURATION">>
                                                      , <<"value">> => Configuration
                                                      })),

    {ok, ConnectionId} = ?UTILS:establish_connection(BridgeId, OwnerUser),
    ok = automate_service_port_engine:set_shared_resource(ConnectionId
                                                         , ResourceName
                                                         , #{ SharedValue =>
                                                                  #{ <<"name">> => SharedValueName
                                                                   , <<"shared_with">> => [ #{ <<"id">> => GroupId
                                                                                             , <<"type">> => <<"group">>
                                                                                             }
                                                                                          ] } }),

    {ok, #{ BridgeId := [CustomBlock] } } = automate_service_port_engine:list_custom_blocks({group, GroupId}),
    check_test_block(CustomBlock).

non_shared_resources_negate_custom_blocks() ->
    OwnerUser = {user, <<?TEST_ID_PREFIX, "-test-2-owner">>},
    ReaderUserId = <<?TEST_ID_PREFIX, "-test-2-reader">>,
    ReaderUser = {user, ReaderUserId},
    GroupName = <<?TEST_ID_PREFIX, "-test-2-group">>,
    ResourceNameShared = <<"channels">>,
    ResourceNameNotShared = <<"non-channels">>,

    SharedValue = <<"shared-val-id">>,
    SharedValueName = <<"shared-val-name">>,

    {ok, #user_group_entry{ id=GroupId }} = automate_storage:create_group(GroupName, OwnerUser, false),
    ok = automate_storage:add_collaborators({ group, GroupId }, [{ReaderUserId, editor}]),

    BridgeName = <<?TEST_ID_PREFIX, "-test-2-service-port">>,
    {ok, BridgeId} = ?APPLICATION:create_service_port(OwnerUser, BridgeName),

    Configuration = #{ <<"is_public">> => false
                     , <<"service_name">> => BridgeName
                     , <<"blocks">> => [ get_test_block([{resource, ResourceNameNotShared}]) ]
                     },
    ok = ?APPLICATION:from_service_port(BridgeId, OwnerUser,
                                        jiffy:encode(#{ <<"type">> => <<"CONFIGURATION">>
                                                      , <<"value">> => Configuration
                                                      })),

    {ok, ConnectionId} = ?UTILS:establish_connection(BridgeId, OwnerUser),
    ok = automate_service_port_engine:set_shared_resource(ConnectionId
                                                         , ResourceNameShared
                                                         , #{ SharedValue =>
                                                                  #{ <<"name">> => SharedValueName
                                                                   , <<"shared_with">> => [ #{ <<"id">> => GroupId
                                                                                             , <<"type">> => <<"group">>
                                                                                             }
                                                                                          ] } }),

    ?assertMatch({ok, #{ BridgeId := [] } }, automate_service_port_engine:list_custom_blocks({group, GroupId})).


allow_to_make_calls_on_shared_resource_values() ->
    OwnerUser = {user, <<?TEST_ID_PREFIX, "-test-3-owner">>},
    ReaderUserId = <<?TEST_ID_PREFIX, "-test-3-reader">>,
    ReaderUser = {user, ReaderUserId},
    GroupName = <<?TEST_ID_PREFIX, "-test-3-group">>,
    ResourceName = <<"channels">>,
    SharedValue = <<"shared-val-id">>,
    SharedValueName = <<"shared-val-name">>,
    ReturnMessage = #{ <<"result">> => <<"ok">>} ,

    {ok, #user_group_entry{ id=GroupId }} = automate_storage:create_group(GroupName, OwnerUser, false),
    ok = automate_storage:add_collaborators({ group, GroupId }, [{ReaderUserId, editor}]),

    BridgeName = <<?TEST_ID_PREFIX, "-test-3-service-port">>,
    {ok, BridgeId} = ?APPLICATION:create_service_port(OwnerUser, BridgeName),

    Configuration = #{ <<"is_public">> => false
                     , <<"service_name">> => BridgeName
                     , <<"blocks">> => [ get_test_block([{resource, ResourceName}]) ]
                     },
    ok = ?APPLICATION:from_service_port(BridgeId, OwnerUser,
                                        jiffy:encode(#{ <<"type">> => <<"CONFIGURATION">>
                                                      , <<"value">> => Configuration
                                                      })),

    {ok, ConnectionId} = ?UTILS:establish_connection(BridgeId, OwnerUser),

    Orig = self(),
    Bridge = spawn(fun() ->
                           ok = ?ROUTER:connect_bridge(BridgeId),
                           Orig ! ready,
                           receive
                               { automate_service_port_engine_router
                               , _ %% From
                               , { data, MessageId, RecvMessage }} ->
                                   ?assertMatch(#{ <<"value">> := #{ <<"arguments">> := [SharedValue] } },
                                                RecvMessage),
                                   io:fwrite("Answering...~n", []),
                                   ok = ?ROUTER:answer_message(MessageId, ReturnMessage);
                               _ ->
                                   ct:fail(timeout)
                           end
                   end),
    receive ready -> ok end,

    ok = automate_service_port_engine:set_shared_resource(ConnectionId
                                                         , ResourceName
                                                         , #{ SharedValue =>
                                                                  #{ <<"name">> => SharedValueName
                                                                   , <<"shared_with">> => [ #{ <<"id">> => GroupId
                                                                                             , <<"type">> => <<"group">>
                                                                                             }
                                                                                          ] } }),

    {ok, ProgramId} =  ?BOT_UTILS:create_user_program({group, GroupId}),
    Thread = #program_thread{ position = [1]
                            , program=[ #{ ?TYPE => ?COMMAND_CALL_SERVICE
                                         , ?ARGUMENTS => #{ ?SERVICE_ID => BridgeId
                                                          , ?SERVICE_ACTION => get_function_id()
                                                          , ?SERVICE_CALL_VALUES => [#{ ?TYPE => ?VARIABLE_CONSTANT
                                                                                      , ?VALUE => SharedValue
                                                                                      }]
                                                          }
                                         }
                                      ]
                            , global_memory=#{}
                            , instruction_memory=#{}
                            , program_id=ProgramId
                            , thread_id=undefined
                            },

    {ran_this_tick, NewThreadState} = automate_bot_engine_operations:run_thread(Thread, {?SIGNAL_PROGRAM_TICK, none}, undefined).

disallow_calls_on_non_shared_resource_values() ->
    OwnerUser = {user, <<?TEST_ID_PREFIX, "-test-4-owner">>},
    ReaderUserId = <<?TEST_ID_PREFIX, "-test-4-reader">>,
    ReaderUser = {user, ReaderUserId},
    GroupName = <<?TEST_ID_PREFIX, "-test-4-group">>,
    ResourceName = <<"channels">>,
    SharedValue = <<"shared-val-id">>,
    NonSharedValue = <<"non-shared-val-id">>,
    SharedValueName = <<"shared-val-name">>,

    {ok, #user_group_entry{ id=GroupId }} = automate_storage:create_group(GroupName, OwnerUser, false),
    ok = automate_storage:add_collaborators({ group, GroupId }, [{ReaderUserId, editor}]),

    BridgeName = <<?TEST_ID_PREFIX, "-test-4-service-port">>,
    {ok, BridgeId} = ?APPLICATION:create_service_port(OwnerUser, BridgeName),

    Configuration = #{ <<"is_public">> => false
                     , <<"service_name">> => BridgeName
                     , <<"blocks">> => [ get_test_block([{resource, ResourceName}]) ]
                     },
    ok = ?APPLICATION:from_service_port(BridgeId, OwnerUser,
                                        jiffy:encode(#{ <<"type">> => <<"CONFIGURATION">>
                                                      , <<"value">> => Configuration
                                                      })),

    {ok, ConnectionId} = ?UTILS:establish_connection(BridgeId, OwnerUser),

    Orig = self(),
    Bridge = spawn(fun() ->
                           ok = ?ROUTER:connect_bridge(BridgeId),
                           Orig ! ready,
                           receive
                               { automate_service_port_engine_router
                               , _ %% From
                               , { data, _MessageId, _RecvMessage }} ->
                                   Orig ! { fail, "Should not have called the bridge"};
                               done ->
                                   ok
                           end
                   end),
    receive ready -> ok end,

    ok = automate_service_port_engine:set_shared_resource(ConnectionId
                                                         , ResourceName
                                                         , #{ SharedValue =>
                                                                  #{ <<"name">> => SharedValueName
                                                                   , <<"shared_with">> => [ #{ <<"id">> => GroupId
                                                                                             , <<"type">> => <<"group">>
                                                                                             }
                                                                                          ] } }),

    {ok, ProgramId} =  ?BOT_UTILS:create_user_program({group, GroupId}),
    Thread = #program_thread{ position = [1]
                            , program=[ #{ ?TYPE => ?COMMAND_CALL_SERVICE
                                         , ?ARGUMENTS => #{ ?SERVICE_ID => BridgeId
                                                          , ?SERVICE_ACTION => get_function_id()
                                                          , ?SERVICE_CALL_VALUES => [#{ ?TYPE => ?VARIABLE_CONSTANT
                                                                                      , ?VALUE => NonSharedValue
                                                                                      }]
                                                          }
                                         }
                                      ]
                            , global_memory=#{}
                            , instruction_memory=#{}
                            , program_id=ProgramId
                            , thread_id=undefined
                            },

    spawn(fun() ->
                  try automate_bot_engine_operations:run_thread(Thread, {?SIGNAL_PROGRAM_TICK, none}, undefined) of
                      {ran_this_tick, NewThreadState} ->
                          Orig ! {fail, "Should not have run"}
                  catch ErrorNs:Error:StackTrace ->
                          Orig ! pass
                  end
          end
         ),
    receive
        pass ->
            Bridge ! done;
        {fail, Reason} ->
            Bridge ! done,
            ct:fail(Reason)
    end.


%%====================================================================
%% Custom block tests - Internal functions
%%====================================================================
-define(FunctionName, <<"first_function_name">>).
-define(FunctionId, <<"first_function_id">>).
-define(FunctionMessage, <<"sample message">>).
-define(BlockType, <<"str">>).
-define(BlockResultType, null).
-define(SaveTo, undefined).

get_function_id() ->
    ?FunctionId.

build_arguments(Args) ->
    lists:map(fun(Arg) ->
                      case Arg of
                          {resource, Name} ->
                              #{ type => string
                               , values => #{ collection => Name }
                               };
                          Num when is_number(Num) ->
                              #{ type => integer
                               , default => integer_to_binary(Num)
                               }
                      end
              end, Args).

get_test_block(Arguments) ->
    #{ <<"arguments">> => build_arguments(Arguments)
     , <<"function_name">> => ?FunctionName
     , <<"message">> => ?FunctionMessage
     , <<"id">> => ?FunctionId
     , <<"block_type">> => ?BlockType
     , <<"block_result_type">> => ?BlockResultType
     }.

check_test_block(Block) ->
    ?assertMatch(#service_port_block{ block_id=?FunctionId
                                    , function_name=?FunctionName
                                    , message=?FunctionMessage
                                    , arguments=_
                                    , block_type=?BlockType
                                    , block_result_type=?BlockResultType
                                    , save_to=?SaveTo
                                    }, Block).
-undef(Arguments).
-undef(FunctionName).
-undef(FunctionId).
-undef(FunctionMessage).
-undef(BlockType).
-undef(BlockResultType).
-undef(SaveTo).
