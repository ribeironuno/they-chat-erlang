-module(client).
-export([start/2, exit/1, send_msg/2, get_servers/1, connect_server/3, disconnect_server/1]).

start(Client, RouterNode) ->
  case net_adm:ping(RouterNode) of
    pang ->
      io:format("Router is down. Aborting ...~n", []);
    pong ->
      register(Client, spawn(
        fun() ->
          process_flag(trap_exit, true),
          loop(RouterNode, empty)
        end))
  end.

%% Chat interaction functions

send_msg(Client, Message) ->
  Client ! {send_message, Message}.

get_servers(Client) ->
  Client ! {get_servers}.

connect_server(Client, Topic, Username) ->
  Client ! {connect, Topic, Username}.

disconnect_server(Client) ->
  Client ! {disconnect}.

exit(Client) ->
  Client ! {exit}.

%% Loop function to be called recursively.
%%
%% RouterNode : The node of the router (because by design the process is always atom router)
%% ChatNode : The node of the chat (is initialized with the atom empty by the start fun)
loop(RouterNode, ChatNode) ->
  receive

    {get_servers} ->
      {router, RouterNode} ! {self(), get_servers},
      receive
        {server_map, Reply} ->
          print_servers(Reply)
      after 5000 ->
        io:format("Router did not respond~n", [])
      end,
      loop(RouterNode, ChatNode);

    {connect, Topic, Username} ->
      %% Calls the router to obtain the Pid of topic's chat
      {router, RouterNode} ! {self(), Topic, get},
      receive
        {server, ChatNodeReply} ->
          case ChatNodeReply of
            not_found ->
              io:format("Topic ~p do not exists~n", [Topic]),
              loop(RouterNode, ChatNode);

            _ ->
              %% Calls the chat requesting to enter
              {server_chat, ChatNodeReply} ! {self(), Username, enter},
              receive
                {Reply} ->
                  case Reply of
                    fail ->
                      io:format("Operation failed~n", []),
                      loop(RouterNode, ChatNode);
                    ok ->
                      io:format("Success! You are inside of the chat~n", []),
                      loop(RouterNode, ChatNodeReply)
                  end
              after 5000 ->
                io:format("Router did not responded~n", []),
                loop(RouterNode, ChatNode)
              end
          end
      after 5000 ->
        io:format("Router did not responded~n", []),
        loop(RouterNode, ChatNode)
      end;

    {disconnect} ->
      case ChatNode of
        empty ->
          io:format("The client is not connected to any server~n", []),
          loop(RouterNode, empty);
        _ ->
          %% Sends the leave intent to the server
          {server_chat, ChatNode} ! {self(), leave},
          receive
            {_} ->
              io:format("Client disconnected~n", []),
              loop(RouterNode, empty)
          after 5000 ->
            io:format("Client disconnected~n", []),
            loop(RouterNode, empty)
          end

      end;

    {send_message, Message} ->
      {server_chat, ChatNode} ! {self(), send_message, Message},
      loop(RouterNode, ChatNode);

    {receive_message, {SenderPid, SenderUsername}, Message} ->
      io:format("[~p~p] : ~p~n", [SenderPid, SenderUsername, Message]),
      loop(RouterNode, ChatNode);

    {exit} ->
      io:format("Exiting ...");

  %% --- Link API ---

  %% Handle logic if the chat went down
    {'EXIT', _, _} ->
      io:format("Server chat went down. Waiting recover ...~n", []),
      receive
        {From, ping} ->
          From ! {{self(), node()}, pong},
          link(From),
          io:format("Chat is back~n", []),
          loop(RouterNode, ChatNode)
      after 5000 ->
        io:format("Leaving chat... ~nYou can try connect to the same or another topic~n", [])
      end,
      loop(RouterNode, empty)

  end.

%% Helper functions

print_servers(ReplyMap) ->
  Keys = maps:keys(ReplyMap),
  StringList = [io_lib:format("~p~n", [Key]) || Key <- Keys],
  io:format("Servers online by topic:~n", []),
  io:format("~s~n", [lists:flatten(StringList)]).


