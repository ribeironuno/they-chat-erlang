-module(server_monitor).
-export([start/2, start_by_router/3]).

%% The entry point of Server Node
%% It starts the server_monitor and the server_chat process and stabilize a monitoring reference between both
%% and between server_monitor and router
start(Topic, RouterNode) ->
  register(server_monitor, spawn(
    fun() ->
      % Tries to connect with router
      case net_adm:ping(RouterNode) of
        pang ->
          io:format("[server_monitor] Router is down. Aborting ...~n", []);
        pong ->
          catch {router, RouterNode} ! {{self(), node()}, Topic, sub},
          receive
            {RemoteRouter, server_accepted} ->
              io:format("[server_monitor] Server monitor is now register on ~p ~n", [self()]),
              monitor(process, RemoteRouter),
              ChatPid = element(1, spawn_monitor(server_chat, start, [self()])),
              register(server_chat, ChatPid),
              io:format("[server_monitor] Monitoring the server chat of pid ~p ~n", [ChatPid]),
              loop(Topic, ChatPid, RouterNode);

            {_, topic_exists} ->
              io:format("[server_monitor] The topic is already registered on the Router. Aborting ... ~n", [])

          after 2000 ->
            io:format("[server_monitor] No response from Router within 2 seconds. Aborting ...~n")
          end
      end
    end)
  ).

%% Fun to be called by the router to start the process
%% It will check if the chat process are still alive by sending a ping to the registered process with server_chat atom
start_by_router(Topic, RouterPid, RouterNode) ->
  register(server_monitor, spawn(
    fun() ->
      monitor(process, RouterPid),
      %% Pings the server chat in order to know if the process is still alive or not
      Result = {server_chat, node()} ! {self(), ping},
      try Result of
        _ ->
          receive
            {From, pong} ->
              io:format("[server_monitor] Received pong from server chat at ~p in monitor ~p~n", [From, self()]),
              monitor(process, From),
              loop(Topic, From, RouterNode)

          after 5000 ->
            io:format("[server_monitor] Timeout the server chat did not respond to ping~n", [])
          end
      catch
        _:_ ->
          io:format("[server_monitor] Failed to send ping to server chat~n", [])
      end,
      %% The logic in case of non response from the server_chat
      io:format("[server_monitor] Server monitor is now register on ~p~n", [self()]),
      ChatPid = element(1, spawn_monitor(node(), server_chat, start, [self()])),
      register(server_chat, ChatPid),
      io:format("[server_monitor] Monitoring the server chat of pid ~p ~n", [ChatPid]),
      loop(Topic, ChatPid, RouterNode)
    end)).

%% Loop server_monitor function to be called recursively.
%%
%% Topic : The topic that is registered this Server Node
%% ChatPid : the Pid of the server_chat
%% RouterMachine : The node address of the Router
loop(Topic, ChatPid, RouterMachine) ->
  receive

    {'DOWN', Ref, process, _Pid, _} ->
      case _Pid of

      %% If the server_chat went down
        ChatPid ->
          demonitor(Ref),
          io:format("[server_monitor] Server chat went down~n", []),
          NewChatPid = element(1, spawn_monitor(server_chat, start, [self()])),
          register(server_chat, NewChatPid),
          loop(Topic, NewChatPid, RouterMachine);

        %% If it was the router
        _ ->
          io:format("[server_monitor] Router went down. Waiting that recovers ...~n", []),
          demonitor(Ref),
          %% Waits for the ping from the router to recover
          receive
            {From, ping} ->
              From ! {{self(), node()}, pong},
              monitor(process, From),
              io:format("[server_monitor] Router is back. Continue operating ...~n", []),
              loop(Topic, ChatPid, RouterMachine)
          after 50000 ->
            io:format("[server_monitor] Router did not responded. Exiting ...~n", [])
          end

      end

  end.
