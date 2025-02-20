-module(router).

-export([start/0, start_by_monitor/2]).

%% The entry point of Router Node
%% It starts the router and the router_monitor process and stabilize a monitoring reference between both
start() ->
  register(router, spawn(
    fun() ->
      io:format("[router] Router is up on ~p ~n", [self()]),
      MonitorPid = element(1, spawn_monitor(router_monitor, start, [maps:new(), self()])),
      register(router_monitor, MonitorPid),
      loop(maps:new(), MonitorPid)
    end)
  ).

%% Function to be called by the monitor to restart the router after it has stopped
start_by_monitor(BackupMap, MonitorPid) ->
  io:format("[router] Router is up by monitor call on pid ~p ~n", [self()]),
  monitor(process, MonitorPid),
  UpdatedMap = ping_servers(BackupMap, MonitorPid),
  loop(UpdatedMap, MonitorPid).

%% Loop router function to be called recursively
%%
%% TopicMap : Structure that maps #{Topic -> ServerInfo}
%% MonitorPid : Pid of the monitor
loop(TopicMap, MonitorPid) ->
  receive
  %% --- API Server Monitor ---

    {{RemotePid, RemoteNode}, Topic, sub} ->
      case topic_exists(TopicMap, Topic) of
        true ->
          RemotePid ! {self(), topic_exists},
          loop(TopicMap, MonitorPid);
        false ->
          monitor(process, {server_monitor, RemoteNode}),
          RemotePid ! {self(), server_accepted},
          NewMap = server_add(Topic, RemoteNode, TopicMap, MonitorPid),
          loop(NewMap, MonitorPid)
      end;

    {{RemotePid, RemoteNode}, Topic, unsub} ->
      case topic_exists(TopicMap, Topic) of
        true ->
          RemotePid ! {"Topic not found"},
          loop(TopicMap, MonitorPid);
        false ->
          demonitor(process, {server_monitor, RemoteNode}),
          NewMap = server_remove(Topic, TopicMap, MonitorPid),
          RemotePid ! {"Topic removed successfully"},
          loop(NewMap, MonitorPid)
      end;

  %% --- API Client ---

    {From, get_servers} ->
      From ! {server_map, TopicMap},
      loop(TopicMap, MonitorPid);

    {From, Topic, get} ->
      case topic_exists(TopicMap, Topic) of
        true ->
          From ! {server, get_server(TopicMap, Topic)},
          loop(TopicMap, MonitorPid);
        false ->
          From ! {server, not_found},
          loop(TopicMap, MonitorPid)
      end;

  %% --- Monitor Handle ---

    {'DOWN', Ref, process, _Pid, _Reason} ->
      case _Pid of
        %% If the router_monitor went down
        MonitorPid ->
          demonitor(Ref),
          io:format("[router] Router monitor ~p went down~n", [_Pid]),
          NewRouterMonitor = element(1, spawn_monitor(router_monitor, start, [TopicMap, self()])),
          register(router_monitor, NewRouterMonitor),
          loop(TopicMap, NewRouterMonitor);

        %% If it was a server_monitor
        {server_monitor, RemoteNode} ->
          demonitor(Ref),
          io:format("[router] Server monitor ~p went down~n", [_Pid]),
          %% Needs a rpc call to start the process on a remote machine
          rpc:call(RemoteNode, server_monitor, start_by_router, [get_topic_by_node(TopicMap, RemoteNode), self(), node()]),
          monitor(process, {server_monitor, RemoteNode}),
          loop(TopicMap, MonitorPid);

        _ ->
          demonitor(Ref),
          io:format("[router] Received a unknown monitor DOWN message ~p~n", [_Pid]),
          loop(TopicMap, MonitorPid)

      end

  end.

%% Helper functions

topic_exists(ServerMap, Topic) ->
  maps:is_key(Topic, ServerMap).

server_add(Topic, RemoteNode, ServerMap, MonitorPid) ->
  NewMap = maps:put(Topic, RemoteNode, ServerMap),
  MonitorPid ! {Topic, RemoteNode, add},
  NewMap.

server_remove(ServerMap, TopicToRemove, MonitorPid) ->
  NewMap = maps:remove(TopicToRemove, ServerMap),
  MonitorPid ! {TopicToRemove, remove},
  NewMap.

get_topic_by_node(ServerMap, NodeToSearch) ->
  maps:fold(
    fun(Topic, RemoteNode, Acc) ->
      case RemoteNode == NodeToSearch of
        true -> Topic;
        false -> Acc
      end
    end, not_found, ServerMap).

get_server(ServerMap, Topic) ->
  try
    maps:get(Topic, ServerMap)
  catch
    _:_ -> not_found
  end.

%% Iterates over the servers and do a ping to filter out servers that may have crashed in the meantime
ping_servers(ServerMap, MonitorPid) ->
  io:format("[router] Servers to ping ~p~n", [ServerMap]),
  maps:fold(
    fun(Topic, RemoteNode, Acc) ->
      io:format("[router] Pinging ~p => ~p ...~n", [Topic, RemoteNode]),
      Result = {server_monitor, RemoteNode} ! {self(), ping},
      try Result of
        _ ->
          receive
            {{_, RemoteNode}, pong} ->
              io:format("[router] Received pong ~p => ~p~n", [Topic, RemoteNode]),
              monitor(process, {server_monitor, RemoteNode}),
              maps:put(Topic, RemoteNode, Acc)
          after 5000 ->
            io:format("[router] Timeout ~p => ~p~n", [Topic, RemoteNode]),
            MonitorPid ! {Topic, remove},
            Acc
          end
      catch
        _:_ ->
          io:format("[router] Failed to send ping to ~p => ~p~n", [Topic, RemoteNode]),
          MonitorPid ! {Topic, remove},
          Acc
      end
    end, maps:new(), ServerMap).
