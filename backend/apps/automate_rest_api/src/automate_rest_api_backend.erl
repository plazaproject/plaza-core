-module(automate_rest_api_backend).

%% API exports
-export([ register_user/1
        , login_user/1
        , is_valid_token/1
        ]).

%% Definitions
-include("./records.hrl").

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

%%====================================================================
%% Internal functions
%%====================================================================
generate_url_from_userid(UserId) ->
    binary:list_to_bin(lists:flatten(io_lib:format("/api/v0/users/~s", [UserId]))).
