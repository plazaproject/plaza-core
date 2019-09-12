%%% @doc
%%% Automate bot engine tests.
%%% @end

-module(automate_bot_engine_thread_stopping_tests).
-include_lib("eunit/include/eunit.hrl").

%% Data structures
-include("../../automate_storage/src/records.hrl").
-include("../src/program_records.hrl").
-include("../src/instructions.hrl").
-include("../../automate_channel_engine/src/records.hrl").

%% Test data
-include("just_wait_program.hrl").

-define(APPLICATION, automate_bot_engine).
-define(TEST_NODES, [node()]).
-define(TEST_MONITOR, <<"__test_monitor__">>).
-define(TEST_SERVICE, automate_service_registry_test_service:get_uuid()).
-define(TEST_SERVICE_ACTION, test_action).

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
    application:stop(?APPLICATION),

    ok.


tests(_SetupResult) ->
    [ { "[Bot runner - Stop threads] Start a thread and stop it, the program must continue running"
      , fun start_thread_and_stop_threads_continues/0 }
    , { "[Bot runner - Stop threads] Create a program and stop it's threads (none). Nothing happens"
      , fun start_program_and_stop_threads_nothing/0 }
    ].


%%%% Bot runner
start_thread_and_stop_threads_continues() ->
    %% Sequence
    %%
    %% Test (this)  *---+--------------+.............+-----+---------+...........+---------+----------------+
    %%                  ↓              ↓             ↑     ↓         ↓           ↑         ↓                ↓
    %%                 Creates    Sends trigger  Confirms  ↓      Stop threads  Confirms  Check alive     Check alive
    %%                  ↓              ↓             ↑     ↓         ↓           ↑         ↓                ↓
    %% Program          *..............+-+-----------+....( )........+-+---------+.........YES.............( )...
    %%                                   ↓                 ↓           ↓                                    ↓
    %%                                Creates        Check alive     Stop                                 Check alive
    %%                                   ↓                 ↓           ↓                                    ↓
    %% Thread                            *-- wait ........YES..........X                                    NO

    %% Program creation
    TriggerMonitorSignal = { ?TRIGGERED_BY_MONITOR
                           , { ?JUST_WAIT_MONITOR_ID, #{ ?CHANNEL_MESSAGE_CONTENT => start }}},

    {Username, ProgramName, ProgramId} = create_anonymous_program(),

    Program = #program_state{ program_id=?JUST_WAIT_PROGRAM_ID
                            , variables=?JUST_WAIT_PROGRAM_VARIABLES
                            , triggers=[#program_trigger{ condition=?JUST_WAIT_PROGRAM_TRIGGER
                                                        , subprogram=?JUST_WAIT_PROGRAM_INSTRUCTIONS
                                                        }
                                       ]
                            },

    %% Launch program
    ?assertMatch({ok, ProgramId},
                 automate_storage:update_program(
                   Username, ProgramName,
                   #stored_program_content{ type=?JUST_WAIT_PROGRAM_TYPE
                                          , parsed=#{ <<"blocks">> => [[ ?JUST_WAIT_PROGRAM_TRIGGER
                                                                         | ?JUST_WAIT_PROGRAM_INSTRUCTIONS ]]
                                                    , <<"variables">> => ?JUST_WAIT_PROGRAM_VARIABLES
                                                    }
                                          , orig=?JUST_WAIT_PROGRAM_ORIG
                                          })),

    ?assertMatch(ok, automate_bot_engine_launcher:update_program(ProgramId)),

    %% Check that program id alive
    ?assertMatch(ok, wait_for_program_alive(ProgramId, 10, 100)),

    {ok, ProgramPid} = automate_storage:get_program_pid(ProgramId),
    ?assert(is_process_alive(ProgramPid)),

    %% Trigger sent, thread is spawned
    ?assertMatch({ok, [_Thread]}, automate_bot_engine_triggers:get_triggered_threads(Program, TriggerMonitorSignal)),

    %% %% Check that thread is alive
    %% @TODO: Get program threads has yet to be implemented
    %% [{Pid, ThreadId}] = automate_storage:get_program_threads(ProgramId),
    %% ?assert(is_process_alive(ThreadId)),

    %% Stop threads
    ok = automate_rest_api_backend:stop_program_threads(undefined, ProgramId),

    %% Check that program is alive
    {ok, ProgramPid2} = automate_storage:get_program_pid(ProgramId),
    ?assert(is_process_alive(ProgramPid2)),

    %% %% Check that thread is dead
    %% @TODO: Get program threads has yet to be implemented
    %% ?assert(length(automate_storage:get_program_thread(ProgramId)) == 0),

    ok.

start_program_and_stop_threads_nothing() ->
    %% Sequence
    %%
    %% Test (this)  *---+-----------+...........+---------+--→ OK
    %%                  ↓           ↓           ↑         ↓
    %%                 Creates   Stop threads  Confirms  Check alive
    %%                  ↓           ↓           ↑         ↓
    %% Program          *...........+-----------+.........YES

    %% Program creation
    TriggerMonitorSignal = { ?TRIGGERED_BY_MONITOR
                           , { ?JUST_WAIT_MONITOR_ID, #{ ?CHANNEL_MESSAGE_CONTENT => start }}},

    {Username, ProgramName, ProgramId} = create_anonymous_program(),

    Program = #program_state{ program_id=?JUST_WAIT_PROGRAM_ID
                            , variables=?JUST_WAIT_PROGRAM_VARIABLES
                            , triggers=[#program_trigger{ condition=?JUST_WAIT_PROGRAM_TRIGGER
                                                        , subprogram=?JUST_WAIT_PROGRAM_INSTRUCTIONS
                                                        }
                                       ]
                            },

    %% Launch program
    ?assertMatch({ok, ProgramId},
                 automate_storage:update_program(
                   Username, ProgramName,
                   #stored_program_content{ type=?JUST_WAIT_PROGRAM_TYPE
                                          , parsed=#{ <<"blocks">> => [[ ?JUST_WAIT_PROGRAM_TRIGGER
                                                                         | ?JUST_WAIT_PROGRAM_INSTRUCTIONS ]]
                                                    , <<"variables">> => ?JUST_WAIT_PROGRAM_VARIABLES
                                                    }
                                          , orig=?JUST_WAIT_PROGRAM_ORIG
                                          })),

    ?assertMatch(ok, automate_bot_engine_launcher:update_program(ProgramId)),

    %% Check that program id alive
    ?assertMatch(ok, wait_for_program_alive(ProgramId, 10, 100)),

    {ok, ProgramPid} = automate_storage:get_program_pid(ProgramId),
    ?assert(is_process_alive(ProgramPid)),

    %% Stop threads
    ok = automate_rest_api_backend:stop_program_threads(undefined, ProgramId),

    %% Check that program is alive
    {ok, ProgramPid2} = automate_storage:get_program_pid(ProgramId),
    ?assert(is_process_alive(ProgramPid2)),

    ok.


%%====================================================================
%% Util functions
%%====================================================================
create_anonymous_program() ->

    {Username, UserId} = create_random_user(),

    ProgramName = binary:list_to_bin(uuid:to_string(uuid:uuid4())),
    {ok, ProgramId} = automate_storage:create_program(Username, ProgramName),
    {Username, ProgramName, ProgramId}.


create_random_user() ->
    Username = binary:list_to_bin(uuid:to_string(uuid:uuid4())),
    Password = undefined,
    Email = binary:list_to_bin(uuid:to_string(uuid:uuid4())),

    {ok, UserId} = automate_storage:create_user(Username, Password, Email),
    {Username, UserId}.

wait_for_program_alive(Pid, 0, SleepTime) ->
    {error, timeout};

wait_for_program_alive(ProgramId, TestTimes, SleepTime) ->
    case automate_storage:get_program_pid(ProgramId) of
        {ok, _} ->
            ok;
        {error, not_running} ->
            timer:sleep(SleepTime),
            wait_for_program_alive(ProgramId, TestTimes - 1, SleepTime)
    end.
