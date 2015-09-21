%%%-------------------------------------------------------------------
%%% @author skell
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 21. Sep 2015 2:45 PM
%%%-------------------------------------------------------------------
-module(ppool_supersup).
-author("skell").

-behaviour(supervisor).

%% API
-export([start_link/0, stop/0, start_pool/3, stop_pool/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ppool).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%--------------------------------------------------------------------
%% @doc
%% Stops the supervisor for ppool supervisors.
%%
%% @end
%%--------------------------------------------------------------------
stop() ->
  case whereis(ppool) of
    P when is_pid(P) ->
      exit(P, kill);
    _ -> ok
  end.

%%--------------------------------------------------------------------
%% @doc
%% Starts a new pool.
%%
%% @end
%%--------------------------------------------------------------------
start_pool(Name, Limit, MFA) ->
  ChildSpec = {Name,
    {ppool_sup, start_link, [Name, Limit, MFA]},
    permanent, 10500, supervisor, [ppool_sup]},
  supervisor:start_child(ppool, ChildSpec).

%%--------------------------------------------------------------------
%% @doc
%% Stps a running pool.
%%
%% @end
%%--------------------------------------------------------------------
stop_pool(Name) ->
  supervisor:terminate_child(ppool, Name),
  supervisor:delete_child(ppool, Name).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, {SupFlags :: {RestartStrategy :: supervisor:strategy(),
    MaxR :: non_neg_integer(), MaxT :: non_neg_integer()},
    [ChildSpec :: supervisor:child_spec()]
  }} |
  ignore |
  {error, Reason :: term()}).
init([]) ->
  MaxRestart = 6,
  MaxTime = 3600,
  {ok, {{one_for_one, MaxRestart, MaxTime}, []}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
