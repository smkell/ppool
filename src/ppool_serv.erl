%%%-------------------------------------------------------------------
%%% @author skell
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 21. Sep 2015 3:26 PM
%%%-------------------------------------------------------------------
-module(ppool_serv).
-author("skell").

-behaviour(gen_server).

%% API
-export([start/4, start_link/4, run/2, sync_queue/2, async_queue/2, stop/1]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

%% The friendly supervisor is started dynamically!
-define(SPEC(MFA),
  {worker_sup,
    {ppool_worker_sup, start_link, [MFA]},
    temporary,
    10000,
    supervisor,
    [ppool_worker_sup]}).

-record(state, {limit=0,
                sup,
                refs,
                queue=queue:new()}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start(Name :: atom(), Limit :: integer(), Sup :: atom(), MFA :: tuple()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start(Name, Limit, Sup, MFA) when is_atom(Name), is_integer(Limit) ->
  gen_server:start({local, Name}, ?MODULE, {Limit, MFA, Sup}, []).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(Name :: atom(), Limit :: integer(), Sup :: atom(), MFA :: tuple()) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Name, Limit, Sup, MFA) ->
  gen_server:start_link({local, Name}, ?MODULE, {Limit, MFA, Sup}, []).

run(Name, Args) ->
  gen_server:call(Name, {run, Args}).

sync_queue(Name, Args) ->
  gen_server:call(Name, {sync, Args}, infinity).

async_queue(Name, Args) ->
  gen_server:cast(Name, {async, Args}).

stop(Name) ->
  gen_server:call(Name, stop).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init({Limit, MFA, Sup}) ->
  %% We need to find the Pid of the worker supervisor from here,
  %% but alas this would be calling the supervisor while it waits for us to start!
  self() ! {start_worker_supervisor, Sup, MFA},
  {ok, #state{limit=Limit, refs=gb_sets:empty()}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% == Protocols ==
%%
%% === run ===
%% Message: {run, Args}
%% Runs a new worker in the pool if there is capacity, otherwise
%% it rejects the incoming request with 'noalloc'
%%
%% === sync ===
%% Message: {sync, Args}
%% Runs a new worker in the pool if there is capacity, otherwise
%% it adds the job to the queue and continues without replying to the
%% caller (since the caller has indicated that this should be a
%% synchronous operation).
%%
%% === stop ===
%% Message: stop
%% Stops the server cleanly.
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_call({run, Args}, _From, S=#state{limit=N, sup=Sup, refs=R}) when N > 0 ->
  {ok, Pid} = supervisor:start_child(Sup, Args),
  Ref = erlang:monitor(process, Pid),
  {reply, {ok,Pid}, S#state{limit=N-1, refs=gb_sets:add(Ref,R)}};
handle_call({run, _Args}, _From, S=#state{limit=N}) when N =< 0 ->
  {reply, noalloc, S};

handle_call({sync, Args}, _From, S = #state{limit=N, sup=Sup, refs=R}) when N > 0 ->
  {ok, Pid} = supervisor:start_child(Sup, Args),
  Ref = erlang:monitor(process, Pid),
  {reply, {ok,Pid}, S#state{limit=N-1, refs=gb_sets:add(Ref,R)}};
handle_call({sync, Args},  From, S = #state{queue=Q}) ->
  {noreply, S#state{queue=queue:in({From, Args}, Q)}};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast({async, Args}, S=#state{limit=N, sup = Sup, refs = R}) when N > 0 ->
  {ok, Pid} = supervisor:start_child(Sup, Args),
  Ref = erlang:monitor(process, Pid),
  {noreply, S#state{limit = N-1, refs=gb_sets:add(Ref, R)}};
handle_cast({async, Args}, S=#state{limit=N, queue=Q}) when N =< 0 ->
  {noreply, S#state{queue = queue:in(Args,Q)}};
%% Not going to explain this one!
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_info({'DOWN', Ref, process, _Pid, _}, S = #state{refs=Refs}) ->
  io:format("received down msg~n"),
  case gb_sets:is_element(Ref, Refs) of
    true ->
      handle_down_worker(Ref, S);
    false -> %% not our problem
      {noreply, S}
  end;
handle_info({start_worker_supervisor, Sup, MFA}, S=#state{}) ->
  {ok, Pid} = supervisor:start_child(Sup, ?SPEC(MFA)),
  link(Pid),
  {noreply, S#state{sup=Pid}};
handle_info(Msg, State) ->
  io:format("Unknown msg: ~p~n", [Msg]),
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

handle_down_worker(Ref, S=#state{limit=L, sup=Sup, refs=Refs}) ->
  case queue:out(S#state.queue) of
    {{value, {From, Args}}, Q} ->
      {ok, Pid} = supervisor:start_child(Sup, Args),
      NewRef = erlang:monitor(process, Pid),
      NewRefs = gb_sets:insert(NewRef, gb_sets:delete(Ref, Refs)),
      gen_server:reply(From, {ok, Pid}),
      {noreply, S#state{refs = NewRefs, queue = Q}};
    {{value, Args}, Q} ->
      {ok, Pid} = supervisor:start_child(Sup, Args),
      NewRef = erlang:monitor(process, Pid),
      NewRefs = gb_sets:insert(NewRef, gb_sets:delete(Ref,Refs)),
      {noreply, S#state{refs = NewRefs, queue = Q}};
    {empty, _} ->
      {noreply, S#state{limit = L+1, refs = gb_sets:delete(Ref, Refs)}}
  end.